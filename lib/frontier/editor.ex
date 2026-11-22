defmodule Frontier.Editor do
  @moduledoc """
  The editor: rank the pool, write the edition, and prove it before printing.

  One run reads the day's candidate stories, asks the model for a structured
  edition, validates its shape against the paper's furniture, grounds every
  entry against the source text it was given, and gives the failures exactly one
  chance to be rewritten. Whatever still fails is dropped and logged. The run
  records its tokens and cost; an edition can be shorter than a full paper, but
  it can never print a quote the source does not contain or a link that does
  not resolve.

  The model chooses and writes. It does not place: `Frontier.Editor.Plan` owns
  caps, positions and the lead. It does not ground: `Frontier.Editor.Grounding`
  owns that. This module is only the order the steps happen in.
  """

  require Logger

  alias Frontier.Editions
  alias Frontier.Editor.{Candidates, Client, Cost, Grounding, Plan, Prompt, Reply, Sections}
  alias Frontier.Newsroom.Pool
  alias Frontier.Sources.Run
  alias Frontier.Repo

  @stage "edit"
  @source "editor"

  @type report :: %{
          candidates: non_neg_integer(),
          printed: non_neg_integer(),
          tickers: non_neg_integer(),
          rejected: non_neg_integer(),
          excluded: [map()],
          read_minutes: pos_integer(),
          word_count: non_neg_integer(),
          model: String.t() | nil,
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cost_micros: non_neg_integer(),
          issues: [term()]
        }

  @doc """
  Edits an edition day and leaves it as a draft.

  Options: `:client` (module or function), `:candidates` (tests), `:fetcher`
  for source text, `:link_checker`, `:repair` (default true), `:limit`.
  """
  @spec edit(Date.t(), keyword()) ::
          {:ok, %{edition: Frontier.Editions.Edition.t(), plan: Plan.t(), report: report()}}
          | {:error, term()}
  def edit(day, opts \\ []) do
    started = System.monotonic_time(:millisecond)
    run = start_run(day)
    pool = prepare(day, opts)

    case pool.candidates do
      [] ->
        reason = {:no_candidates, pool.excluded}
        fail_run(run, reason, started, nil)
        {:error, reason}

      candidates ->
        run_editor(day, run, candidates, pool, opts, started)
    end
  end

  defp prepare(day, opts) do
    case Keyword.get(opts, :candidates) do
      nil ->
        Pool.paper_stories(day: day)
        |> Candidates.build(opts)

      candidates ->
        %{candidates: candidates, excluded: []}
    end
  end

  defp run_editor(day, run, candidates, pool, opts, started) do
    context = %{
      day: day,
      candidates: candidates,
      client: Keyword.get(opts, :client, Client.configured()),
      link_checker: Keyword.get(opts, :link_checker, &Grounding.resolve_link/1),
      opts: opts
    }

    case ask(context, repair: false) do
      {:ok, payload, usage, model} ->
        plan = Plan.validate(payload, candidates)
        verdict = ground(plan, context)
        verdict = %{verdict | usage: usage, model: model}
        verdict = maybe_repair(context, payload, plan, verdict)

        finalise(day, run, candidates, pool, verdict, verdict.usage, verdict.model, started, opts)

      {:error, reason} ->
        reason = {:editor_client, reason}
        fail_run(run, reason, started, nil)
        {:error, reason}
    end
  end

  defp maybe_repair(context, payload, plan, verdict) do
    if repair?(plan, verdict) and Keyword.get(context.opts, :repair, true) do
      problem = problem(plan, verdict)

      case repair(context, problem) do
        {:ok, repaired, repair_usage, repair_model} ->
          merged = merge(payload, repaired)
          plan = Plan.validate(merged, context.candidates)
          usage = add_usage(verdict.usage, repair_usage)
          model = verdict.model || repair_model
          verdict = ground(plan, context)

          %{verdict | usage: usage, model: model}

        {:error, reason} ->
          Logger.warning(
            "[editor] repair pass failed, keeping the first reply: #{inspect(reason)}"
          )

          verdict
      end
    else
      verdict
    end
  end

  # A dead link cannot be repaired by rewriting copy: the entry would fail the
  # same check again and the repair call would be wasted. Those entries drop
  # straight away; everything else gets the one repair.
  defp repair?(plan, verdict) do
    repairable = repairable_failures(verdict)
    repairable != [] or too_short(plan) != nil or desk_note_problem(plan) != nil
  end

  defp repairable_failures(verdict) do
    Enum.filter(verdict.failures, fn %{reasons: reasons} ->
      Enum.all?(reasons, &repairable?/1)
    end)
  end

  defp repairable?({:unresolved_link, _reason}), do: false
  defp repairable?(_reason), do: true

  defp problem(plan, verdict) do
    %{
      failures: repairable_failures(verdict),
      too_short: too_short(plan),
      desk_note: desk_note_problem(plan),
      chosen_ids: MapSet.new(Enum.map(plan.entries ++ plan.tickers, & &1.story_id))
    }
  end

  defp too_short(%{issues: issues}) do
    Enum.find_value(issues, fn
      {:too_short, chosen, target} -> {chosen, target}
      _issue -> nil
    end)
  end

  defp desk_note_problem(%{issues: issues}) do
    Enum.find_value(issues, fn
      {:desk_note, reason} -> reason
      _issue -> nil
    end)
  end

  defp repair(context, problem) do
    messages = Prompt.repair_messages(context.day, context.candidates, problem, context.opts)
    ask_with(context.client, messages, Keyword.put(context.opts, :repair, true))
  end

  # The repair reply is a patch: corrected entries replace the originals by
  # story id, new entries are appended, and an absent desk note leaves the
  # first one alone.
  defp merge(payload, repaired) do
    %{
      "desk_note" => Reply.get(repaired, "desk_note") || Reply.get(payload, "desk_note"),
      "entries" => merge_list(Reply.list(payload, "entries"), Reply.list(repaired, "entries")),
      "also_today" =>
        merge_list(Reply.list(payload, "also_today"), Reply.list(repaired, "also_today"))
    }
  end

  defp merge_list(original, repaired) do
    by_id = Map.new(repaired, &{Reply.get(&1, "story_id"), &1})
    known = MapSet.new(Enum.map(original, &Reply.get(&1, "story_id")))

    replaced =
      Enum.map(original, fn item -> Map.get(by_id, Reply.get(item, "story_id"), item) end)

    additions = Enum.reject(repaired, &MapSet.member?(known, Reply.get(&1, "story_id")))

    replaced ++ additions
  end

  defp ask(context, extra) do
    call_opts = Keyword.merge(context.opts, extra)
    messages = Prompt.messages(context.day, context.candidates, call_opts)
    ask_with(context.client, messages, call_opts)
  end

  defp ask_with(client, messages, opts) do
    case Client.complete(client, messages, opts) do
      {:ok, reply} ->
        with {:ok, content} <- content(reply),
             {:ok, payload} <- decode(content) do
          {:ok, payload, Client.usage(reply), Client.model(reply)}
        end

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_reply, other}}
    end
  end

  defp content(%{content: content}) when is_binary(content), do: {:ok, content}
  defp content(%{"content" => content}) when is_binary(content), do: {:ok, content}
  defp content(reply), do: {:error, {:missing_content, reply}}

  defp decode(content) do
    content =
      content
      |> String.trim()
      |> String.replace(~r/\A```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```\z/, "")

    case Jason.decode(content) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, other} -> {:error, {:not_a_json_object, other}}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  # The model's reply, checked against the text it was given. A story that
  # fails a check is not dropped yet: it is handed back once.
  defp ground(plan, context) do
    by_id = Map.new(context.candidates, &{&1.id, &1})

    {entries, entry_failures} =
      Enum.map_reduce(plan.entries, [], fn entry, failures ->
        case grounded(entry, by_id[entry.story_id], context.link_checker) do
          {:ok, entry} -> {entry, failures}
          {:error, reasons} -> {nil, [%{entry: entry, reasons: reasons} | failures]}
        end
      end)

    {tickers, ticker_failures} =
      Enum.map_reduce(plan.tickers, [], fn ticker, failures ->
        case grounded(ticker, by_id[ticker.story_id], context.link_checker) do
          {:ok, ticker} -> {ticker, failures}
          {:error, reasons} -> {nil, [%{entry: ticker, reasons: reasons} | failures]}
        end
      end)

    %{
      plan: plan,
      desk_note: plan.desk_note,
      entries: Enum.reject(entries, &is_nil/1),
      tickers: Enum.reject(tickers, &is_nil/1),
      failures: entry_failures ++ ticker_failures,
      issues: plan.issues,
      usage: %{input_tokens: 0, output_tokens: 0},
      model: nil
    }
  end

  defp grounded(_entry, nil, _link_checker), do: {:error, [:unknown_story]}

  defp grounded(entry, candidate, link_checker) do
    quote = Grounding.choose_quote(quote_options(entry), candidate.text)

    reasons =
      [
        Grounding.check_entities(entry.headline, candidate.text),
        Grounding.check_words(entry.summary, entry.kind),
        link_check(entry.url, link_checker)
      ]
      |> Enum.flat_map(fn
        :ok -> []
        {:ok, _final} -> []
        {:error, reason} -> [reason]
      end)

    case {quote, reasons} do
      {{:ok, chosen}, []} -> {:ok, %{entry | quote: chosen}}
      {{:ok, _chosen}, reasons} -> {:error, reasons}
      {{:error, reason}, reasons} -> {:error, [reason | reasons]}
    end
  end

  defp quote_options(entry) do
    [entry.quote | Map.get(entry, :quote_candidates, [])]
    |> Enum.filter(&is_binary/1)
  end

  defp link_check(url, checker) do
    Grounding.check_link(url, checker)
  end

  defp finalise(day, run, candidates, pool, verdict, usage, model, started, opts) do
    plan = final_plan(verdict, candidates)

    cond do
      plan.entries == [] ->
        rejections = rejections(verdict, pool)
        :ok = Editions.record_rejections(day, rejections)

        reason = {:nothing_printed, Enum.map(verdict.failures, & &1.reasons)}
        fail_run(run, reason, started, %{usage: usage, model: model})
        {:error, reason}

      desk_note_issue = Enum.find(plan.issues, &match?({:desk_note, _}, &1)) ->
        rejections = rejections(verdict, pool)
        :ok = Editions.record_rejections(day, rejections)

        reason = {:desk_note_invalid, elem(desk_note_issue, 1)}
        fail_run(run, reason, started, %{usage: usage, model: model})
        {:error, reason}

      plan.desk_note == nil ->
        rejections = rejections(verdict, pool)
        :ok = Editions.record_rejections(day, rejections)

        reason = {:desk_note_invalid, :missing}
        fail_run(run, reason, started, %{usage: usage, model: model})
        {:error, reason}

      true ->
        save(day, run, pool, plan, verdict, usage, model, started, opts)
    end
  end

  defp save(day, run, pool, plan, verdict, usage, model, started, opts) do
    case Editions.save_draft(day, plan, opts) do
      {:ok, edition} ->
        rejections = rejections(verdict, pool)
        :ok = Editions.record_rejections(day, rejections)

        report = report(pool, plan, rejections, usage, model)

        finish_run(run, report, started)
        log_report(report)
        {:ok, %{edition: edition, plan: plan, report: report}}

      {:error, reason} ->
        fail_run(run, reason, started, %{usage: usage, model: model})
        {:error, reason}
    end
  end

  # Anything still failing after the one repair is removed here; re-validating
  # re-places what is left and keeps positions gapless.
  defp final_plan(verdict, candidates) do
    Plan.validate(
      %{
        "desk_note" => verdict.desk_note,
        "entries" => Enum.map(verdict.entries, &raw_entry/1),
        "also_today" => Enum.map(verdict.tickers, &raw_ticker/1)
      },
      candidates
    )
  end

  defp raw_entry(entry) do
    %{
      "story_id" => entry.story_id,
      "section" => entry.section,
      "headline" => entry.headline,
      "dek" => entry.dek,
      "summary" => entry.summary,
      "quote" => entry.quote,
      "quote_candidates" => entry.quote_candidates
    }
  end

  defp raw_ticker(ticker) do
    %{
      "story_id" => ticker.story_id,
      "headline" => ticker.headline,
      "summary" => ticker.summary,
      "quote" => ticker.quote,
      "quote_candidates" => ticker.quote_candidates
    }
  end

  defp report(pool, plan, rejections, usage, model) do
    %{
      candidates: length(pool.candidates),
      printed: plan.story_count,
      tickers: length(plan.tickers),
      rejected: length(rejections),
      excluded: pool.excluded,
      read_minutes: Sections.read_minutes(plan.word_count),
      word_count: plan.word_count,
      model: model,
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cost_micros: Cost.micros(usage),
      issues: plan.issues
    }
  end

  defp rejections(verdict, pool) do
    headlines = Map.new(pool.candidates, &{&1.id, &1.headline})

    plan_drops =
      Enum.flat_map(verdict.issues, fn
        {:dropped, story_id, reason} ->
          [
            %{
              story_id: story_id,
              headline: Map.get(headlines, story_id),
              reason: reason_code(reason),
              detail: inspect(reason)
            }
          ]

        _issue ->
          []
      end)

    failures =
      Enum.map(verdict.failures, fn %{entry: entry, reasons: reasons} ->
        %{
          story_id: entry.story_id,
          headline: entry.headline,
          reason: reason_code(first_reason(reasons)),
          detail: inspect(reasons)
        }
      end)

    plan_drops ++ failures
  end

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code({tag, _value}) when is_atom(tag), do: Atom.to_string(tag)
  defp reason_code(reason), do: inspect(reason)

  defp first_reason([reason | _rest]), do: reason
  defp first_reason([]), do: :unknown

  defp log_report(report) do
    Logger.info(
      "[editor] #{report.printed} stories + #{report.tickers} tickers, " <>
        "#{report.rejected} rejected, #{report.read_minutes} min, " <>
        "#{report.model || "unknown model"}: #{report.input_tokens} in / " <>
        "#{report.output_tokens} out, #{Cost.format(report.cost_micros)}"
    )
  end

  @doc false
  def run_stage, do: @stage

  defp start_run(day) do
    %Run{}
    |> Run.changeset(%{
      stage: @stage,
      source: @source,
      edition_day: day,
      status: "running",
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp finish_run(run, report, started) do
    run
    |> Run.changeset(%{
      status: "ok",
      fetched: report.candidates,
      inserted: report.printed + report.tickers,
      rejected: report.rejected,
      model: report.model,
      input_tokens: report.input_tokens,
      output_tokens: report.output_tokens,
      cost_micros: report.cost_micros,
      duration_ms: elapsed(started)
    })
    |> Repo.update!()
  end

  defp fail_run(run, reason, started, meta) do
    error = format_reason(reason)
    Logger.error("[editor] failed after #{elapsed(started)}ms: #{error}")

    usage = (meta && meta[:usage]) || %{input_tokens: 0, output_tokens: 0}

    run
    |> Run.changeset(%{
      status: "error",
      error: error,
      model: meta && meta[:model],
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cost_micros: Cost.micros(usage),
      duration_ms: elapsed(started)
    })
    |> Repo.update!()

    :ok
  end

  defp add_usage(a, b) do
    %{
      input_tokens: a.input_tokens + b.input_tokens,
      output_tokens: a.output_tokens + b.output_tokens
    }
  end

  defp elapsed(started), do: System.monotonic_time(:millisecond) - started

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
