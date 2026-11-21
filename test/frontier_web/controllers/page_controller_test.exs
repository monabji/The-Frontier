defmodule FrontierWeb.PageControllerTest do
  use FrontierWeb.ConnCase

  alias Frontier.Fixtures
  alias Frontier.Newsroom.Dateline
  alias Frontier.Sources
  alias Frontier.Sources.HN

  setup do
    {:ok, items} = HN.normalize(Fixtures.hn_front_page())
    {:ok, _} = Sources.upsert_items(HN.key(), items)
    %{items: Sources.list_items(HN.key(), date: Dateline.edition_date())}
  end

  describe "GET / with today's fetch stored" do
    test "prints the front page", %{conn: conn, items: items} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ "The Frontier"
      assert html =~ "Front Page"
      assert html =~ "Hacker News"
      assert length(items) == 30
    end

    test "gives every story on the page a working link", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      for item <- items do
        assert html =~ ~s(href="#{item.url}"), "missing link for #{item.title}"
      end
    end

    test "gives every story a source line", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      for item <- items do
        assert html =~ Phoenix.HTML.html_escape(item.title) |> Phoenix.HTML.safe_to_string()
      end

      assert html =~ "math216.wordpress.com"
      assert html =~ "2,370 points"
    end

    test "prints every stored story once and only once", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)

      headlines = length(String.split(html, ~s(class="item__headline"))) - 1
      leads = length(String.split(html, ~s(class="lead-item__headline"))) - 1

      assert headlines + leads == length(items)
      assert leads == 1
    end

    test "sends the reader to the discussion too", %{conn: conn, items: items} do
      html = get(conn, ~p"/") |> html_response(200)
      lead = hd(items)

      assert html =~ ~s(href="#{lead.discussion_url}")
      assert html =~ "1,150 comments"
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
      :ok
    end

    test "says so plainly instead of printing an empty sheet", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "No stories yet"
      assert html =~ "mix frontier.fetch"
    end
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
