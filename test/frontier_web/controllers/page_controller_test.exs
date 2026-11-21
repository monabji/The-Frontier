defmodule FrontierWeb.PageControllerTest do
  use FrontierWeb.ConnCase

  alias Frontier.Newsroom.Dateline
  alias Frontier.Newsroom.DemoEdition

  setup do
    %{conn: get(build_conn(), ~p"/")}
  end

  test "GET / prints the front page", %{conn: conn} do
    html = html_response(conn, 200)
    story = DemoEdition.current().story

    assert html =~ "The Frontier"
    assert html =~ story.headline
    assert html =~ story.dek
    assert html =~ "Front Page"
  end

  test "the date line is the edition date in IST", %{conn: conn} do
    html = html_response(conn, 200)

    date = Dateline.edition_date()
    assert html =~ Dateline.format(date)
    assert html =~ ~s(datetime="#{Date.to_iso8601(date)}")
  end

  test "the lead's summary and its source quote are both on the page", %{conn: conn} do
    html = html_response(conn, 200)
    story = DemoEdition.current().story

    for paragraph <- story.body do
      assert html =~ paragraph
    end

    assert html =~ story.quote.text
  end

  test "the story links to its single source over https", %{conn: conn} do
    html = html_response(conn, 200)
    url = DemoEdition.current().story.source.url

    assert html =~ ~s(href="#{url}")
    assert length(String.split(html, url)) == 2, "the source should be linked exactly once"
  end

  test "the page preloads both faces and loads the paper's stylesheet", %{conn: conn} do
    html = html_response(conn, 200)

    assert html =~ ~s(href="/fonts/fraunces-latin.woff2")
    assert html =~ ~s(href="/fonts/newsreader-latin.woff2")
    assert html =~ ~s(href="/assets/css/app.css")
  end

  test "the paper asks nothing of a third party", %{conn: conn} do
    html = html_response(conn, 200)

    refute html =~ "fonts.googleapis.com"
    refute html =~ "fonts.gstatic.com"
    refute html =~ "cdn.jsdelivr"
  end
end
