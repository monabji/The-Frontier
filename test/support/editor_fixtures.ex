defmodule Frontier.EditorFixtures do
  @moduledoc """
  A day's worth of candidates the editor can be tested against.

  The stories are deliberately unlike each other: shared product words would
  make the clusterer merge them, and a test about the editor should not also be
  a test about clustering.
  """

  import Ecto.Query

  alias Frontier.Newsroom.Pool
  alias Frontier.Repo
  alias Frontier.Sources.RawItem

  @day ~D[2026-11-22]
  @published_at ~U[2026-11-22 04:00:00Z]

  @placement [
    {"Front Page", 3},
    {"Models & Releases", 4},
    {"Research", 3},
    {"Tooling & Dev", 4},
    {"The Discourse", 3},
    {"The Long Read", 1},
    {"Back Page", 4}
  ]

  @doc "The section layout the plan's caps allow: 22 stories."
  def placement, do: @placement

  @doc "Stores `count` distinct raw items and clusters them into stories."
  def seed_stories(count \\ 32, day \\ @day) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(1..count, fn n ->
        url = "https://example.com/story-#{n}"

        %{
          source: "rss:openai",
          external_id: "story-#{n}",
          title: "Quokka#{n} Zephyr#{n} opens a bakery",
          url: url,
          canonical_url: url,
          content_hash: "hash-#{n}",
          kind: "post",
          text:
            "Quokka#{n} Zephyr#{n} opens a bakery in Lisbon. " <>
              "The shop said it will bake bread every morning for the neighbourhood. " <>
              "Its owner spent two years learning the trade in a small kitchen. " <>
              "The opening drew a queue down the street before sunrise. " <>
              "Bread will be sold until it runs out each day, the shop said. " <>
              "A second oven is planned for the spring, according to the owner.",
          published_at: @published_at,
          edition_day: day,
          position: n,
          first_seen_at: now,
          fetched_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(RawItem, rows)
    stories = Repo.all(from item in RawItem, order_by: item.id)
    Pool.rebuild(day, items: stories)
    Pool.paper_stories(day: day)
  end

  @doc "Candidates for the stored stories, in the paper's order."
  def candidates(stories) do
    %{candidates: candidates} = Frontier.Editor.Candidates.build(stories)
    candidates
  end

  @doc "A complete, valid structured reply for 22 stories and 10 tickers."
  def payload(candidates, opts \\ []) do
    main = Enum.take(candidates, 22)
    tickers = candidates |> Enum.drop(22) |> Enum.take(10)

    entries =
      main
      |> assign_sections()
      |> Enum.map(fn {candidate, section, position} ->
        kind = Frontier.Editor.Sections.kind(section, position)

        %{
          "story_id" => candidate.id,
          "section" => section,
          "headline" => candidate.headline,
          "dek" =>
            if(kind == :lead, do: "The day opens with a bakery and what it means.", else: nil),
          "summary" => summary(kind),
          "quote" => verbatim_quote(candidate)
        }
        |> reject_nil()
      end)

    also_today =
      Enum.map(tickers, fn candidate ->
        %{
          "story_id" => candidate.id,
          "headline" => candidate.headline,
          "summary" => summary(:ticker),
          "quote" => verbatim_quote(candidate)
        }
      end)

    %{
      "desk_note" => Keyword.get(opts, :desk_note, default_desk_note()),
      "entries" => Keyword.get(opts, :entries, entries),
      "also_today" => Keyword.get(opts, :also_today, also_today)
    }
  end

  @doc "The first sentence of a candidate's source text: a verbatim quote."
  def verbatim_quote(candidate) do
    candidate.text
    |> String.split(". ")
    |> List.first()
    |> then(fn sentence ->
      if String.ends_with?(sentence, "."), do: sentence, else: sentence <> "."
    end)
  end

  @doc "Summaries of the right length for a kind."
  def summary(:lead), do: words(135)
  def summary(:standard), do: words(70)
  def summary(:ticker), do: words(15)

  defp words(count), do: String.duplicate("word ", count) |> String.trim()

  defp default_desk_note do
    "A busy morning in models and a quieter afternoon in research. The paper is shorter than usual, and says so."
  end

  defp assign_sections(candidates) do
    {pairs, _rest} =
      Enum.map_reduce(@placement, candidates, fn {section, count}, remaining ->
        {slice, rest} = Enum.split(remaining, count)

        assigned =
          slice
          |> Enum.with_index(1)
          |> Enum.map(fn {candidate, position} -> {candidate, section, position} end)

        {assigned, rest}
      end)

    List.flatten(pairs)
  end

  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
