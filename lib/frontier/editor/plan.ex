defmodule Frontier.Editor.Plan do
  @moduledoc """
  Turns the editor's structured reply into the paper's placement.

  The model may choose and write, but it does not get to break the furniture:
  an entry must name a story that exists, a section that exists, appear once,
  and fit the section's cap. The first Front Page entry is the lead whatever
  the reply called it. Anything that cannot be placed is dropped with a reason
  the run log can show, never quietly moved to a section it does not belong in.
  """

  alias Frontier.Editor.{Reply, Sections}

  @target_stories 22
  @desk_note_words 20..60

  @type issue ::
          {:dropped, term(), term()}
          | {:too_short, non_neg_integer(), non_neg_integer()}
          | {:desk_note, term()}

  @type entry :: %{
          story_id: term(),
          url: String.t(),
          canonical_url: String.t(),
          section: String.t(),
          kind: :lead | :standard | :ticker,
          position: pos_integer(),
          headline: String.t(),
          dek: String.t() | nil,
          summary: String.t(),
          quote: String.t() | nil,
          quote_candidates: [String.t()],
          primary_source: String.t() | nil,
          source_label: String.t() | nil,
          discussion_url: String.t() | nil,
          score: non_neg_integer() | nil,
          comments_count: non_neg_integer() | nil,
          published_at: DateTime.t() | nil,
          word_count: non_neg_integer()
        }

  @type t :: %{
          desk_note: String.t() | nil,
          entries: [entry()],
          tickers: [entry()],
          issues: [issue()],
          story_count: non_neg_integer(),
          word_count: non_neg_integer()
        }

  @doc """
  Validates and places a decoded reply against the day's candidates.

  `candidates` are plain maps with `:id`, `:url`, `:canonical_url`,
  `:primary_source`, `:source_label`, `:discussion_url`, `:score`,
  `:comments_count` and `:published_at`; see `Frontier.Editor.Candidates`.
  """
  @spec validate(map(), [map()]) :: t()
  def validate(payload, candidates) when is_map(payload) do
    by_id = Map.new(candidates, &{&1.id, &1})
    seen = MapSet.new()

    {entries, issues, seen} =
      payload
      |> Reply.list("entries")
      |> Enum.reduce({[], [], seen}, fn raw, {kept, issues, seen} ->
        case place(raw, by_id, seen) do
          {:ok, entry, seen} -> {[entry | kept], issues, seen}
          {:drop, id, reason} -> {kept, [{:dropped, id, reason} | issues], seen}
        end
      end)

    {entries, issues} = apply_caps(Enum.reverse(entries), issues)

    {tickers, issues, _seen} =
      payload
      |> Reply.list("also_today")
      |> Enum.reduce({[], issues, seen}, fn raw, {kept, issues, seen} ->
        case place_ticker(raw, by_id, seen) do
          {:ok, ticker, seen} -> {[ticker | kept], issues, seen}
          {:drop, id, reason} -> {kept, [{:dropped, id, reason} | issues], seen}
        end
      end)

    tickers = Enum.reverse(tickers)
    {tickers, issues} = cap_tickers(tickers, issues)
    {desk_note, issues} = desk_note(payload, issues)
    issues = too_short(entries, candidates, issues)

    %{
      desk_note: desk_note,
      entries: entries,
      tickers: tickers,
      issues: issues,
      story_count: length(entries),
      word_count: word_count(desk_note, entries, tickers)
    }
  end

  @doc "The paper's placement, with positions assigned inside each section."
  @spec ordered(t()) :: [{String.t(), [entry()]}]
  def ordered(%{entries: entries}) do
    entries
    |> Enum.group_by(& &1.section)
    |> then(fn grouped ->
      Sections.names()
      |> Enum.map(fn section -> {section, Map.get(grouped, section, [])} end)
      |> Enum.reject(fn {_section, entries} -> entries == [] end)
    end)
  end

  defp place(raw, by_id, seen) do
    id = Reply.get(raw, "story_id")
    section = Reply.get(raw, "section")

    cond do
      id == nil ->
        {:drop, nil, :missing_story}

      not is_binary(section) or not Sections.section?(section) ->
        {:drop, id, {:unknown_section, section}}

      MapSet.member?(seen, id) ->
        {:drop, id, :duplicate}

      not Map.has_key?(by_id, id) ->
        {:drop, id, :unknown_story}

      true ->
        {:ok, entry(raw, by_id[id], section), MapSet.put(seen, id)}
    end
  end

  defp place_ticker(raw, by_id, seen) do
    id = Reply.get(raw, "story_id")

    cond do
      id == nil -> {:drop, nil, :missing_story}
      MapSet.member?(seen, id) -> {:drop, id, :duplicate}
      not Map.has_key?(by_id, id) -> {:drop, id, :unknown_story}
      true -> {:ok, entry(raw, by_id[id], "Also Today"), MapSet.put(seen, id)}
    end
  end

  defp entry(raw, story, section) do
    %{
      story_id: story.id,
      url: story.url,
      canonical_url: story.canonical_url,
      section: section,
      kind: :standard,
      position: 0,
      headline: copy(raw, "headline", story.headline),
      dek: blank_to_nil(Reply.get(raw, "dek")),
      summary: copy(raw, "summary", ""),
      quote: blank_to_nil(Reply.get(raw, "quote")),
      quote_candidates: quote_candidates(raw),
      primary_source: Map.get(story, :primary_source),
      source_label: Map.get(story, :source_label),
      discussion_url: Map.get(story, :discussion_url),
      score: Map.get(story, :score),
      comments_count: Map.get(story, :comments_count),
      published_at: Map.get(story, :published_at),
      word_count: Sections.word_count(copy(raw, "summary", ""))
    }
  end

  defp apply_caps(entries, issues) do
    {kept, issues} =
      entries
      |> Enum.group_by(& &1.section)
      |> then(fn grouped ->
        Sections.names()
        |> Enum.reduce({[], issues}, fn section, {kept, issues} ->
          candidates = Map.get(grouped, section, [])
          cap = Sections.cap(section)
          {inside, outside} = Enum.split(candidates, cap)

          outside =
            Enum.map(outside, fn entry -> {:dropped, entry.story_id, :section_over_cap} end)

          {kept ++ inside, issues ++ outside}
        end)
      end)

    {placed, _} =
      kept
      |> Enum.group_by(& &1.section)
      |> then(fn grouped ->
        Sections.names()
        |> Enum.reduce({[], 0}, fn section, {placed, _count} ->
          entries = Map.get(grouped, section, [])

          positioned =
            entries
            |> Enum.with_index(1)
            |> Enum.map(fn {entry, position} ->
              %{entry | position: position, kind: Sections.kind(section, position)}
            end)

          {placed ++ positioned, length(entries)}
        end)
      end)

    {placed, issues}
  end

  defp cap_tickers(tickers, issues) do
    {inside, outside} = Enum.split(tickers, Sections.ticker_cap())

    outside = Enum.map(outside, fn ticker -> {:dropped, ticker.story_id, :ticker_over_cap} end)

    inside =
      inside
      |> Enum.with_index(1)
      |> Enum.map(fn {ticker, position} ->
        %{ticker | position: position, kind: :ticker, section: "Also Today"}
      end)

    {inside, issues ++ outside}
  end

  defp desk_note(payload, issues) do
    note = payload |> Reply.get("desk_note") |> blank_to_nil()
    count = Sections.word_count(note)

    cond do
      note == nil -> {nil, [{:desk_note, :missing} | issues]}
      count < @desk_note_words.first -> {note, [{:desk_note, :too_short} | issues]}
      count > @desk_note_words.last -> {note, [{:desk_note, :too_long} | issues]}
      true -> {note, issues}
    end
  end

  defp too_short(entries, candidates, issues) do
    count = length(entries)

    if count < @target_stories and length(candidates) >= @target_stories do
      [{:too_short, count, @target_stories} | issues]
    else
      issues
    end
  end

  # Read time counts the prose the plan budgets: the desk note, each story's
  # summary, and the ticker lines. Headlines are labels and quotes are evidence
  # set beside the prose, so neither is part of the advertised length. PLAN's
  # 1,800–2,000 words for a full paper is this number.
  defp word_count(desk_note, entries, tickers) do
    main =
      Enum.reduce(entries, Sections.word_count(desk_note), fn entry, total ->
        total + entry.word_count
      end)

    Enum.reduce(tickers, main, fn ticker, total -> total + ticker.word_count end)
  end

  defp copy(raw, key, fallback) do
    case blank_to_nil(Reply.get(raw, key)) do
      nil -> fallback
      text -> text
    end
  end

  defp quote_candidates(raw) do
    case Reply.get(raw, "quote_candidates") do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      _other -> []
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp blank_to_nil(_value), do: nil
end
