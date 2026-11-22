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

      assert {:ok, %{text: text, image_url: nil}} =
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

      assert {:ok, %{text: text, image_url: image_url}} =
               SourceText.for_item(raw, fetcher: fetcher)

      assert text =~ "A real sentence from the article"
      assert image_url == nil
      assert_received {:fetched, "https://example.com/story-2"}
    end

    test "a page that cannot be read refuses rather than inventing text" do
      fetcher = fn _url -> {:error, {:http_status, 404, "Not Found"}} end
      raw = hd(story(3, nil).story_items).raw_item

      assert {:error, {:http_status, 404, "Not Found"}} =
               SourceText.for_item(raw, fetcher: fetcher)
    end

    test "the article body wins over the page's navigation" do
      html = """
      <html><body>
      <nav>Models Datasets Pricing Enterprise Login Sign Up</nav>
      <article><h1>Bread &amp; butter</h1><p>#{String.duplicate("The bakery opens before dawn. ", 20)}</p></article>
      <footer>Terms Privacy Cookies</footer>
      </body></html>
      """

      text = SourceText.from_html(html)
      assert text =~ "The bakery opens before dawn."
      refute text =~ "Datasets"
      refute text =~ "Privacy"
    end

    test "a tiny article teaser falls back to the page body" do
      html = """
      <html><body><article>A 30-second teaser.</article>
      <div>#{String.duplicate("The real report begins with a sentence of substance. ", 12)}</div>
      </body></html>
      """

      assert SourceText.from_html(html) =~ "The real report begins"
    end

    test "the article's Open Graph image comes back with its text" do
      fetcher = fn _url ->
        {:ok,
         """
         <html><head>
         <meta property="og:image" content="https://cdn.example.com/lead.jpg">
         </head><body><article>#{String.duplicate("A real sentence from the article. ", 20)}</article></body></html>
         """, "text/html"}
      end

      raw = hd(story(2, "Too short.").story_items).raw_item

      assert {:ok, %{image_url: "https://cdn.example.com/lead.jpg"}} =
               SourceText.for_item(raw, fetcher: fetcher)
    end

    test "an escaped ampersand in an image URL is decoded" do
      html =
        ~s(<html><head><meta property="og:image" content="https://cdn.example.com/lead.jpg?w=1600&amp;h=900"></head><body>#{String.duplicate("A sentence. ", 40)}</body></html>)

      assert SourceText.image_from(html, "text/html", "https://example.com/story") ==
               "https://cdn.example.com/lead.jpg?w=1600&h=900"
    end

    test "a relative Open Graph image resolves against the article" do
      html =
        ~s(<html><head><meta property="og:image" content="/images/lead.jpg"></head><body>#{String.duplicate("A sentence. ", 40)}</body></html>)

      assert SourceText.image_from(html, "text/html", "https://example.com/story") ==
               "https://example.com/images/lead.jpg"
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

    test "a story with no publication is not quotable" do
      story = %Story{
        id: 9,
        headline: "A social post about something",
        primary_url: "https://bsky.app/profile/x/post/1",
        canonical_url: "https://bsky.app/profile/x/post/1",
        story_items: [
          %StoryItem{
            role: "discussion",
            raw_item: %RawItem{source: "bsky", url: "https://bsky.app/profile/x/post/1"}
          }
        ]
      }

      assert %{candidates: [], excluded: [excluded]} = Candidates.build([story])
      assert excluded.reason == :no_primary_item
    end

    test "the list is capped and keeps the paper's order" do
      stories = Enum.map(1..5, &story(&1, @stored))
      %{candidates: candidates} = Candidates.build(stories, limit: 3)
      assert Enum.map(candidates, & &1.id) == [1, 2, 3]
    end
  end
end
