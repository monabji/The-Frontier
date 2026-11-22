defmodule Frontier.EditionsTest do
  use Frontier.DataCase, async: false

  alias Frontier.ClusteringFixtures
  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Newsroom.Pool
  alias Frontier.Repo
  alias Frontier.Sources
  alias Frontier.Sources.{Item, RawItem}

  @day ~D[2026-11-22]

  setup do
    EditionStorage.tmp!(%{})
    ClusteringFixtures.seed!(@day)

    {:ok, _} =
      Sources.upsert_items(
        "rss:openai",
        [
          %Item{
            external_id: "bread-1",
            title: "A bakery in Lisbon is teaching machines to smell bread",
            url: "https://example.com/bread",
            kind: :post,
            published_at: ~U[2026-11-22 04:00:00Z]
          }
        ],
        day: @day
      )

    Pool.rebuild(@day, items: Repo.all(RawItem))
    %{stories: Pool.list_stories(day: @day)}
  end

  defp plan(stories) do
    entries =
      stories
      |> Enum.take(2)
      |> Enum.with_index(1)
      |> Enum.map(fn {story, index} ->
        %{
          story_id: story.id,
          url: story.primary_url,
          canonical_url: story.canonical_url,
          section: "Front Page",
          kind: if(index == 1, do: :lead, else: :standard),
          position: index,
          headline: "Headline #{index}",
          dek: "A dek.",
          summary: String.duplicate("word ", 70),
          quote: "A real quote from the source.",
          primary_source: story.primary_source,
          source_label: "OpenAI",
          discussion_url: nil,
          score: nil,
          comments_count: nil,
          published_at: story.first_published_at,
          word_count: 70
        }
      end)

    %{
      desk_note: "A quiet morning, with one launch worth the front page and little else.",
      entries: entries,
      tickers: [],
      issues: [],
      story_count: length(entries),
      word_count: 900
    }
  end

  describe "a draft edition" do
    test "stores the desk note, read time and placed entries", %{stories: stories} do
      assert {:ok, edition} = Editions.save_draft(@day, plan(stories))

      assert edition.status == "draft"
      assert edition.story_count == 2
      assert edition.read_minutes == Editions.get(@day).read_minutes
      assert [%{section: "Front Page", kind: "lead", position: 1} | _] = edition.entries
      assert Editions.get(@day).desk_note =~ "quiet morning"
    end

    test "replacing a draft replaces its entries, not appends them", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, edition} = Editions.save_draft(@day, plan(stories))

      assert length(edition.entries) == 2
      assert length(Editions.get(@day).entries) == 2
    end

    test "a published edition is never overwritten", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, _} = Editions.publish(@day)

      assert {:error, {:edition_is_published, "published"}} =
               Editions.save_draft(@day, plan(stories))

      assert Editions.get(@day).status == "published"
    end
  end

  describe "the drop log" do
    test "records why an editor choice did not print" do
      Editions.record_rejections(@day, [
        %{story_id: 7, headline: "A made-up quote", reason: :quote_not_in_source}
      ])

      assert [rejection] = Editions.rejections(@day)
      assert rejection.story_id == 7
      assert rejection.reason == "quote_not_in_source"
    end
  end
end
