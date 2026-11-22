defmodule Frontier.Editor.CandidatesTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.{Candidates, SourceText}
  alias Frontier.Newsroom.{Story, StoryItem}
  alias Frontier.Sources.RawItem

  defp story(id, text, overrides \\ %{}) do
    raw = %RawItem{
      id: id,
      source: "rss:openai",
      external_id: "ext-#{id}",
      title: "Quokka#{id} Zephyr#{id} opens a bakery",
      url: "https://example.com/story-#{id}",
      canonical_url: "https://example.com/story-#{id}",
      text: text,
      discussion_url: "https://news.ycombinator.com/item?id=#{id}",
      score: 100 + id,
      comments_count: id,
      published_at: ~U[2026-11-22 04:00:00Z]
    }

    struct(
      %Story{
        id: id,
        headline: raw.title,
        primary_url: raw.url,
        canonical_url: raw.canonical_url,
        primary_source: "rss:openai",
        first_published_at: raw.published_at,
        story_items: [%StoryItem{role: "primary", raw_item: raw}]
      },
      overrides
    )
  end

  @stored String.duplicate("The bakery opens before dawn and sells bread until noon. ", 8)

  describe "source text" do
    test "a substantial stored excerpt is used without a request" do
      fetcher = fn _url -> flunk("a stored excerpt must not be re-fetched") end

      assert {:ok, text} =
               SourceText.for_item(story(1, @stored).story_items |> hd() |> Map.get(:raw_item),
                 fetcher: fetcher
               )

      assert text =~ "bakery opens"
    end

    test "a thin excerpt is replaced by one article fetch" do
      fetcher = fn url ->
        send(self(), {:fetched, url})

        {:ok,
         "<html><body><p>#{String.duplicate("A real sentence from the article. ", 10)}</p></body></html>",
         "text/html"}
      end

      raw = hd(story(2, "Too short.").story_items).raw_item
      assert {:ok, text} = SourceText.for_item(raw, fetcher: fetcher)
      assert text =~ "A real sentence from the article"
      assert_received {:fetched, "https://example.com/story-2"}
    end

    test "a page that cannot be read refuses rather than inventing text" do
      fetcher = fn _url -> {:error, {:http_status, 404, "Not Found"}} end
      raw = hd(story(3, nil).story_items).raw_item

      assert {:error, {:http_status, 404, "Not Found"}} =
               SourceText.for_item(raw, fetcher: fetcher)
    end

    test "HTML machinery is stripped, entities decoded, text bounded" do
      html =
        "<html><script>tracker()</script><style>.a{}</style><p>Bread &amp; butter&nbsp;here</p></html>"

      text = SourceText.extract(html, "text/html")
      assert text == "Bread & butter here"
      refute text =~ "tracker"

      assert String.length(SourceText.extract(String.duplicate("word ", 3_000), "text/plain")) <=
               6_000
    end
  end

  describe "building candidates" do
    test "carries the link, provenance and source text" do
      %{candidates: [candidate], excluded: []} = Candidates.build([story(1, @stored)])

      assert candidate.id == 1
      assert candidate.url == "https://example.com/story-1"
      assert candidate.primary_source == "rss:openai"
      assert candidate.source_label == "OpenAI"
      assert candidate.discussion_url == "https://news.ycombinator.com/item?id=1"
      assert candidate.score == 101
      assert candidate.comments_count == 1
      assert candidate.text =~ "bakery opens"
    end

    test "a story whose text cannot be read is excluded and named" do
      fetcher = fn _url -> {:error, :timeout} end

      %{candidates: [], excluded: [excluded]} =
        Candidates.build([story(4, nil)], fetcher: fetcher)

      assert excluded.story_id == 4
      assert excluded.reason == :timeout
    end

    test "the list is capped and keeps the paper's order" do
      stories = Enum.map(1..5, &story(&1, @stored))
      %{candidates: candidates} = Candidates.build(stories, limit: 3)
      assert Enum.map(candidates, & &1.id) == [1, 2, 3]
    end
  end
end
