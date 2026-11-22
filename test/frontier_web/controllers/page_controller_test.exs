defmodule FrontierWeb.PageControllerTest do
  use FrontierWeb.ConnCase

  alias Frontier.ClusteringFixtures
  alias Frontier.EditionStorage
  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  setup do
    EditionStorage.tmp!(%{})
    day = Dateline.edition_date()
    items = ClusteringFixtures.seed!(day)
    Pool.rebuild(day, items: items)

    %{day: day, stories: Pool.paper_stories(day: day)}
  end

  describe "GET / with a clustered pool" do
    test "prints the front page", %{conn: conn, stories: stories} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "The Frontier"
      assert html =~ "Front Page"
      assert html =~ "1 story"
      assert html =~ "3 sources"
      assert length(stories) == 1
    end

    test "prints one story for the launch, not its three items", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      headlines =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("article h3 a, ol.items h3 a")

      assert headlines |> LazyHTML.attribute("href") |> length() == 1

      assert headlines
             |> LazyHTML.text()
             |> String.contains?("Welcome Inkling 2 Mini")
    end

    test "sends the reader to the publication, not the aggregator", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      [headline_link] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("h3 a")
        |> LazyHTML.attribute("href")

      assert headline_link == "https://huggingface.co/blog/inkling2mini"
    end

    test "prints the related discussion beside it", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ ~s(href="https://news.ycombinator.com/item?id=50581260")
      assert html =~ "Discussion"
    end

    test "has a heading outline: paper, section, story", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query("h1") |> LazyHTML.text() |> String.contains?("The Frontier")
      assert doc |> LazyHTML.query("h2") |> LazyHTML.text() |> String.contains?("Front Page")

      assert doc |> LazyHTML.query("h3") |> LazyHTML.attribute("class") |> length() == 1
    end

    test "the date line is the edition date in IST", %{conn: conn, day: day} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ Dateline.format(day)
      assert html =~ ~s(datetime="#{Date.to_iso8601(day)}")
    end

    test "no story's link appears twice", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      links =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("article h3 a, ol.items h3 a")
        |> LazyHTML.attribute("href")

      assert length(links) == length(Enum.uniq(links))
    end
  end

  describe "GET / before the press has clustered" do
    setup do
      Frontier.Repo.delete_all(Frontier.Newsroom.Story)
      :ok
    end

    test "says so plainly instead of printing an empty sheet", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "No stories yet"
      assert html =~ "mix frontier.fetch"
      assert html =~ "mix frontier.cluster"
    end
  end

  test "GET / shows the last edition before the day's first fetch", %{conn: conn} do
    yesterday = Date.add(Dateline.edition_date(), -1)
    Frontier.Repo.delete_all(Frontier.Newsroom.Story)

    items = ClusteringFixtures.seed!(yesterday)
    Pool.rebuild(yesterday, items: items)

    # A successful run on the old day, none today: the paper prints the old
    # edition with its own date rather than an empty page until 05:15.
    %Frontier.Sources.Run{}
    |> Frontier.Sources.Run.changeset(%{
      stage: "fetch",
      source: "hn",
      edition_day: yesterday,
      status: "ok",
      fetched: 1,
      inserted: 1,
      inserted_at: DateTime.utc_now()
    })
    |> Frontier.Repo.insert!()

    html = get(conn, ~p"/") |> html_response(200)

    assert Sources.current_edition_day() == yesterday
    assert html =~ Dateline.format(yesterday)
    assert html =~ "Welcome Inkling 2 Mini"
  end

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
