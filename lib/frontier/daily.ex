defmodule Frontier.Daily do
  @moduledoc """
  One morning's work: fetch, cluster, edit, assemble.

  The run is a sequence of stages, each of which already records its own row.
  This module owns the order and the decision that a morning with nothing to
  print is a failure rather than an empty paper. It never publishes: the 06:00
  publish job does that, after the run has had time to finish.

  Options are for the operator and for tests: `:adapters`, `:fetch_client`,
  `:editor_client`, `:link_checker`, `:renderer`, `:candidates`.
  """

  alias Frontier.{Editions, Runs}
  alias Frontier.Editor
  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  @stage "daily"

  @type report :: %{
          day: Date.t(),
          fetch: [Sources.report()],
          stories: non_neg_integer(),
          printed: non_neg_integer(),
          tickers: non_neg_integer(),
          rejected: non_neg_integer(),
          read_minutes: pos_integer(),
          word_count: non_neg_integer(),
          model: String.t() | nil,
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cost_micros: non_neg_integer(),
          artifact: Editions.Artifact.t()
        }

  @doc """
  Runs the morning for a day and leaves an assembled draft.

  `{:ok, report}` means the paper is ready to publish. `{:error, reason}` means
  no draft was written (or it could not be assembled), and the caller — the
  job — alerts and retries.
  """
  @spec run(Date.t() | nil, keyword()) :: {:ok, report()} | {:error, term()}
  def run(day \\ nil, opts \\ []) do
    day = day || Dateline.edition_date()
    run = Runs.start(@stage, day)

    cond do
      not Editions.writable?(day) ->
        reason = :edition_is_locked
        Runs.fail(run, reason)
        {:error, reason}

      true ->
        execute(day, run, opts)
    end
  end

  defp execute(day, run, opts) do
    reports = fetch(day, opts)

    if Enum.all?(reports, &(&1.status == :error)) and
         Enum.sum(Enum.map(reports, & &1.fetched)) == 0 do
      reason = :every_source_failed
      Runs.fail(run, reason, fetched: 0)
      {:error, reason}
    else
      pool = Pool.rebuild(day)

      if pool.items == 0 do
        reason = :nothing_in_the_pool
        Runs.fail(run, reason)
        {:error, reason}
      else
        edit(day, run, reports, pool, opts)
      end
    end
  end

  defp edit(day, run, reports, pool, opts) do
    editor_opts = Keyword.take(opts, [:link_checker, :candidates])
    editor_opts = maybe_put(editor_opts, :client, Keyword.get(opts, :editor_client))

    case Editor.edit(day, editor_opts) do
      {:ok, %{report: editor_report}} ->
        assemble(day, run, reports, pool, editor_report, opts)

      {:error, reason} ->
        Runs.fail(run, reason, fetched: total_fetched(reports))
        {:error, reason}
    end
  end

  defp assemble(day, run, reports, pool, editor_report, opts) do
    renderer_opts =
      case Keyword.get(opts, :renderer) do
        nil -> []
        renderer -> [renderer: renderer]
      end

    case Editions.assemble(day, renderer_opts) do
      {:ok, %{artifact: artifact}} ->
        report = %{
          day: day,
          fetch: reports,
          stories: pool.stories,
          printed: editor_report.printed,
          tickers: editor_report.tickers,
          rejected: editor_report.rejected,
          read_minutes: editor_report.read_minutes,
          word_count: artifact.stats["words"] || 0,
          model: editor_report.model,
          input_tokens: editor_report.input_tokens,
          output_tokens: editor_report.output_tokens,
          cost_micros: editor_report.cost_micros,
          artifact: artifact
        }

        Runs.finish(run,
          fetched: total_fetched(reports),
          inserted: editor_report.printed,
          updated: pool.stories,
          rejected: editor_report.rejected,
          model: editor_report.model,
          input_tokens: editor_report.input_tokens,
          output_tokens: editor_report.output_tokens,
          cost_micros: editor_report.cost_micros
        )

        {:ok, report}

      {:error, reason} ->
        Runs.fail(run, reason, fetched: total_fetched(reports))
        {:error, reason}
    end
  end

  defp fetch(day, opts) do
    adapters = Keyword.get(opts, :adapters, Sources.adapters())

    source_opts =
      [day: day, adapters: adapters]
      |> maybe_put(:client, Keyword.get(opts, :fetch_client))
      |> maybe_put(:redirect_resolver, Keyword.get(opts, :redirect_resolver))

    Sources.run(source_opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp total_fetched(reports), do: reports |> Enum.map(& &1.fetched) |> Enum.sum()
end
