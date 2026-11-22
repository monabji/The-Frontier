defmodule Frontier.Editor.Keyless do
  @moduledoc """
  The editor for a model with no key and a short reply: write the paper in
  parts, then let the ordinary plan and grounding decide what prints.

  A free keyless endpoint (Pollinations is the default shape) will answer, but
  its replies are capped at roughly fifteen hundred tokens and its model is
  small. Asking for twenty-one stories in one object returns a cut-off reply.
  So the desk is written two sections at a time: Front Page and Models, then
  Research and Security, and so on. Each part carries the same voice, caps,
  word budgets and quote rule, and each part only sees candidates routed to its
  sections by `Frontier.Editor.Beats`.

  The parts are merged into one payload and handed to `Frontier.Editor.edit/2`,
  which validates placement and grounds every entry exactly as it does for a
  live model. A part that cannot be decoded is skipped and logged; the paper is
  shorter, never invented.
  """

  require Logger

  alias Frontier.Editor
  alias Frontier.Editor.{Beats, Candidates, Client, Plain, Prompt, Reply, Sections}
  alias Frontier.Newsroom.Pool

  @default_group_tokens 4_000
  @note_tokens 400
  @desk_note_words 20..60

  # A small keyless model writes shorter summaries than the paper's ideal. The
  # floors are lower and the ceilings higher, and the read time is computed
  # from what prints, so the edition never claims a length it does not have.
  @word_ranges %{lead: 100..190, standard: 45..120, ticker: 12..18}

  @doc """
  Edits a day in parts and leaves a draft, the same contract as
  `Frontier.Editor.edit/2`.

  Options: `:client` (module or function), `:limit`, `:fetcher`,
  `:link_checker`, `:max_tokens`, `:now`.
  """
  @spec edit(Date.t(), keyword()) ::
          {:ok, %{edition: Frontier.Editions.Edition.t(), plan: map(), report: map()}}
          | {:error, term()}
  def edit(day, opts \\ []) do
    candidates = candidates(day, opts)
    client = Keyword.get(opts, :client, Client.configured())

    if candidates == [] do
      {:error, {:no_candidates, []}}
    else
      {entries, usage, model} = write_parts(day, candidates, client, opts)
      desk_note = desk_note(day, entries, client, opts)

      payload = %{
        "desk_note" => desk_note,
        "entries" => entries,
        "also_today" => []
      }

      reply = %{
        content: Jason.encode!(payload),
        usage: usage,
        model: model || "keyless"
      }

      Editor.edit(
        day,
        [
          candidates: candidates,
          client: fn _messages, _opts -> {:ok, reply} end,
          repair: false,
          word_ranges: Keyword.get(opts, :word_ranges, @word_ranges)
        ] ++ Keyword.take(opts, [:link_checker, :now])
      )
    end
  end

  defp candidates(day, opts) do
    %{candidates: candidates} =
      Pool.paper_stories(day: day)
      |> Candidates.build(Keyword.take(opts, [:limit, :fetcher]))

    candidates
  end

  defp write_parts(day, candidates, client, opts) do
    Beats.groups()
    |> Enum.reduce({[], %{input_tokens: 0, output_tokens: 0}, nil, MapSet.new()}, fn group,
                                                                                     {entries,
                                                                                      usage,
                                                                                      model, used} ->
      case write_part(day, group, candidates, used, client, opts) do
        {:ok, part_entries, part_usage, part_model} ->
          fresh =
            Enum.reject(part_entries, fn entry ->
              MapSet.member?(used, entry["story_id"])
            end)

          used = Enum.reduce(fresh, used, &MapSet.put(&2, &1["story_id"]))
          usage = add_usage(usage, part_usage)
          {entries ++ fresh, usage, model || part_model, used}

        {:error, reason} ->
          Logger.warning("[editor] keyless part #{inspect(group)} failed: #{inspect(reason)}")
          {entries, usage, model, used}
      end
    end)
    |> then(fn {entries, usage, model, _used} -> {entries, usage, model} end)
  end

  defp write_part(day, group, candidates, used, client, opts) do
    case Beats.group_candidates(group, candidates, used) do
      [] ->
        {:ok, [], %{input_tokens: 0, output_tokens: 0}, nil}

      usable ->
        messages = Prompt.group_text_messages(day, group, usable)

        case complete(client, messages, call_opts(opts)) do
          {:ok, reply} ->
            with {:ok, content} <- content(reply),
                 {:ok, payload} <- Plain.parse(content) do
              entries =
                payload
                |> Reply.list("entries")
                |> Enum.filter(&(Reply.get(&1, "story_id") != nil))
                |> Enum.map(&ground_quote(&1, candidates))

              {:ok, entries, Client.usage(reply), Client.model(reply)}
            end

          {:error, reason} ->
            {:error, reason}

          other ->
            {:error, {:unexpected_reply, other}}
        end
    end
  end

  # The paper's rule is a verbatim quote, not a particular quote. When a small
  # model paraphrases or copies the headline, fall back to the first clean
  # sentence in the source text so the story can still print, grounded.
  defp ground_quote(entry, candidates) do
    with id when not is_nil(id) <- Reply.get(entry, "story_id"),
         %{} = candidate <- Enum.find(candidates, &(&1.id == id)) do
      quote = Reply.get(entry, "quote")

      cond do
        is_binary(quote) and String.contains?(candidate.text, quote) ->
          entry

        alternate = find_quote(Reply.get(entry, "quote_candidates"), candidate.text) ->
          Map.put(entry, "quote", alternate)

        sentence = first_sentence(candidate.text) ->
          Map.put(entry, "quote", sentence)

        true ->
          entry
      end
    else
      _other -> entry
    end
  end

  defp find_quote(list, text) when is_list(list) do
    Enum.find(list, fn quote -> is_binary(quote) and String.contains?(text, quote) end)
  end

  defp find_quote(_list, _text), do: nil

  defp first_sentence(text) when is_binary(text) do
    text
    |> String.split(~r/(?<=[.!?])\s+/)
    |> Enum.map(&String.trim/1)
    |> Enum.find(fn sentence ->
      Sections.word_count(sentence) in 5..40 and not String.contains?(sentence, "[…]")
    end)
  end

  defp first_sentence(_text), do: nil

  defp desk_note(day, entries, client, opts) do
    headlines =
      entries
      |> Enum.map(&Reply.get(&1, "headline"))
      |> Enum.filter(&is_binary/1)
      |> Enum.map_join("\n", &"- #{&1}")

    prompt = """
    You are the editor of The Frontier, a daily newspaper for AI and technology. \
    One edition for #{Frontier.Newsroom.Dateline.format(day)} has just been placed. \
    Write its desk note: 20–60 words, one or two sentences, "From the desk" voice. \
    Read the shape of the day — what is busy, what is quiet — and be honest if the \
    paper is short. Do not greet the reader, do not address them, do not invent a \
    fact, do not use exclamation marks. Answer on one line in this exact format:

    DESK NOTE: one or two sentences

    The day's headlines:

    #{headlines}
    """

    messages = [
      %{role: "system", content: Prompt.system()},
      %{role: "user", content: prompt}
    ]

    case Client.complete(
           client,
           messages,
           Keyword.put(call_opts(opts), :max_tokens, @note_tokens)
         ) do
      {:ok, reply} ->
        note =
          case content(reply) do
            {:ok, content} -> Plain.desk_note(content)
            _other -> nil
          end

        valid_note(note)

      {:error, _reason} ->
        fallback_note()
    end
  end

  defp valid_note(note) when is_binary(note) do
    note = String.trim(note)

    if Sections.word_count(note) in @desk_note_words, do: note, else: fallback_note()
  end

  defp valid_note(_note), do: fallback_note()

  defp fallback_note do
    "A checked paper, shorter than a full day. Every story it prints is linked to its source and quoted from it."
  end

  # A free endpoint answers one caller at a time. A 402/429 is a queue, not a
  # failure: wait and ask again before giving the part up.
  defp complete(client, messages, opts, attempts \\ 3) do
    case Client.complete(client, messages, opts) do
      {:error, {:http_status, status, _body}} when status in [402, 429] and attempts > 1 ->
        Process.sleep(Keyword.get(opts, :retry_ms, 50_000))
        complete(client, messages, opts, attempts - 1)

      other ->
        other
    end
  end

  defp content(reply) do
    case Map.get(reply, :content) || Map.get(reply, "content") do
      content when is_binary(content) -> {:ok, content}
      _other -> {:error, :missing_content}
    end
  end

  defp call_opts(opts) do
    [
      max_tokens: Keyword.get(opts, :max_tokens, @default_group_tokens),
      temperature: 0.3,
      json_object: false
    ]
  end

  defp add_usage(a, b) do
    %{
      input_tokens: a.input_tokens + b.input_tokens,
      output_tokens: a.output_tokens + b.output_tokens
    }
  end
end
