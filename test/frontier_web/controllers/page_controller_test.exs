defmodule FrontierWeb.PageControllerTest do
  use FrontierWeb.ConnCase

  alias Frontier.Newsroom.Dateline
  alias Frontier.Sources
  alias Frontier.Sources.{HN, RSS}

  # The page prints an edition day, and only keeps a week. These adapters serve
  # the recorded payloads with their dates moved to "just now", so the tests are
  # about the page and not about the day they happen to run on.
  defmodule HNFixture do
    @behaviour Frontier.Sources.Adapter
    def key, do: "hn"
    def label, do: "Hacker News"
    def fetch(_opts), do: {:ok, :fixture}

    def normalize(_payload) do
      {:ok, items} = HN.normalize(Frontier.Fixtures.hn_front_page())
      {:ok, Enum.map(items, &%{&1 | published_at: recent()})}
    end

    def recent, do: DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defmodule BlogFixture do
    @behaviour Frontier.Sources.Adapter
    def key, do: "rss:test"
    def label, do: "Test Blog"
    def fetch(_opts), do: {:ok, :fixture}

    def normalize(_payload) do
      {:ok, items} = RSS.normalize(Frontier.Fixtures.rss_fixture("google-ai.xml"))
      {:ok, Enum.map(items, &%{&1 | published_at: HNFixture.recent()})}
    end
  end

  setup do
    reports = Sources.run(adapters: [HNFixture, BlogFixture], day: Dateline.edition_date())
    assert [_hn, _blog] = reports

    %{items: Sources.front_page_items(day: Dateline.edition_date())}
  end

  describe "GET / with today's fetch stored" do
    test "prints the front page", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "The Frontier"
      assert html =~ "Front Page"
      assert html =~ "2 sources"
      assert items != []
    end

    test "has a heading outline: paper, section, stories", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query("h1") |> LazyHTML.text() |> String.contains?("The Frontier")
      assert doc |> LazyHTML.query("h2") |> LazyHTML.text() |> String.contains?("Front Page")
      stories = doc |> LazyHTML.query("article, ol.items > li") |> count()
      headlines = doc |> LazyHTML.query("h3") |> count()

      assert headlines == stories
    end

    test "gives every story on the page a working link", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      links =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("article h3 a, ol.items h3 a")
        |> LazyHTML.attribute("href")

      assert length(links) == length(items)

      for item <- items do
        assert item.url in links, "missing link for #{item.title}"
      end
    end

    test "prints each article once, however many sources carried it", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      hrefs =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("article h3 a, ol.items h3 a")
        |> LazyHTML.attribute("href")

      assert length(hrefs) == length(Enum.uniq(hrefs))
    end

    test "gives every story a source line, in IST", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      doc = LazyHTML.from_document(html)
      sources = doc |> LazyHTML.query(".item-source__host") |> LazyHTML.text()

      assert doc |> LazyHTML.query(".item-source__host") |> count() == length(items)
      assert sources =~ "math216.wordpress.com"

      lead = hd(items)

      assert html =~
               ~s(datetime="#{DateTime.to_iso8601(lead.published_at)}")

      assert html =~ Dateline.format_short(lead.published_at)
    end

    test "sends the reader to the discussion too", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      lead = Enum.find(items, & &1.discussion_url)

      assert html =~ ~s(href="#{lead.discussion_url}")
    end

    test "the date line is the edition date in IST", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      date = Dateline.edition_date()
      assert html =~ Dateline.format(date)
      assert html =~ ~s(datetime="#{Date.to_iso8601(date)}")
    end
  end

  describe "GET / before the press has run" do
    setup do
      Frontier.Repo.delete_all(Frontier.Sources.RawItem)
      Frontier.Repo.delete_all(Frontier.Sources.Run)
      :ok
    end

    test "says so plainly instead of printing an empty sheet", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "No stories yet"
      assert html =~ "mix frontier.fetch"
    end
  end

  defp count(nodes), do: nodes |> LazyHTML.attribute("class") |> length()

  test "the page preloads both faces and loads the paper's stylesheet", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    assert html =~ ~s(href="/fonts/fraunces-latin.woff2")
    assert html =~ ~s(href="/fonts/newsreader-latin.woff2")
    assert html =~ ~s(href="/assets/css/app.css")
  end

  test "the paper asks nothing of a third party", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    refute html =~ "fonts.googleapis.com"
    refute html =~ "fonts.gstatic.com"
    refute html =~ "cdn.jsdelivr"
  end

  test "the page ships no JavaScript", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    refute html =~ "<script"
  end
end
