defmodule FrontierWeb.EditionPageTest do
  use FrontierWeb.ConnCase

  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Editor
  alias Frontier.EditorFixtures
  alias Frontier.Newsroom.Dateline

  setup do
    EditionStorage.tmp!(%{})
    day = Dateline.edition_date()
    stories = EditorFixtures.seed_stories(32, day)
    candidates = EditorFixtures.candidates(stories)
    payload = EditorFixtures.payload(candidates)

    client = fn _messages, _opts ->
      {:ok,
       %{
         content: Jason.encode!(payload),
         usage: %{input_tokens: 1_200, output_tokens: 400},
         model: "test-model"
       }}
    end

    {:ok, _} =
      Editor.edit(day,
        candidates: candidates,
        client: client,
        link_checker: fn _url -> {:ok, "https://example.com/final"} end
      )

    {:ok, _} = Editions.assemble(day)

    %{day: day, edition: Editions.get(day)}
  end

  describe "the edition page" do
    test "opens with the desk note, read time and date", %{conn: conn, day: day} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ Dateline.format(day)
      assert html =~ "From the desk"
      assert html =~ "machine-written"
      assert html =~ "busy morning in models"
      assert html =~ "min read"
      assert html =~ ~s(datetime="#{Date.to_iso8601(day)}")
    end

    test "prints every section in paper order", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      sections = doc |> LazyHTML.query(".section-band") |> LazyHTML.text()

      assert sections =~ "Front Page"
      assert sections =~ "Models & Releases"
      assert sections =~ "Research"
      assert sections =~ "Tooling & Dev"
      assert sections =~ "The Discourse"
      assert sections =~ "The Long Read"
      assert sections =~ "Back Page"
      assert sections =~ "Also Today"

      assert sections =~ ~r/Front Page.*Also Today/s
    end

    test "a story prints its headline, summary and verified quote", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      lead_summary =
        doc |> LazyHTML.query(".story--lead .story__summary") |> LazyHTML.text()

      assert String.split(lead_summary, ~r/\s+/, trim: true) |> length() == 135

      assert doc |> LazyHTML.query(".story--lead .story__quote p") |> LazyHTML.text() =~
               "Quokka1 Zephyr1 opens a bakery in Lisbon."
    end

    test "the lead links to the publication, with its source line", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc
             |> LazyHTML.query(".story--lead .story__headline a")
             |> LazyHTML.attribute("href") == ["https://example.com/story-1"]

      assert doc |> LazyHTML.query(".story--lead .item-source__host") |> LazyHTML.text() ==
               "example.com"
    end

    test "Also Today is a ticker of one-line items", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query(".ticker__item") |> Enum.count() == 10
      assert doc |> LazyHTML.query(".ticker__line") |> LazyHTML.text() =~ "word word"
    end

    test "the outline is still paper, section, story", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query("h1") |> LazyHTML.text() |> String.contains?("The Frontier")
      assert doc |> LazyHTML.query("h2") |> LazyHTML.text() |> String.contains?("Front Page")
      assert doc |> LazyHTML.query("h3.story__headline") |> Enum.count() == 22
    end

    test "no story is printed twice", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)

      links =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(".story__headline a, .ticker__headline a")
        |> LazyHTML.attribute("href")

      assert length(links) == 32
      assert length(links) == length(Enum.uniq(links))
    end
  end

  describe "the broadsheet layout" do
    test "the standard page carries both tabs and starts on Standard", %{conn: conn} do
      html = get(conn, ~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query(".sheet--reader") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".viewswitch__tab") |> Enum.count() == 2

      assert doc
             |> LazyHTML.query(".viewswitch__tab[aria-current='page']")
             |> LazyHTML.text()
             |> String.trim() == "Standard"

      assert html =~ ~s(href="/?layout=broadsheet")
    end

    test "?layout=broadsheet prints the page-one composition", %{conn: conn} do
      html = get(conn, ~p"/?layout=broadsheet") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query(".sheet--broadsheet") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".broadsheet__front") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".broadsheet__lead") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".broadsheet__rail") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".broadsheet__mosaic") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".broadsheet__inside") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".broadsheet .story__headline") |> Enum.count() == 22
      assert doc |> LazyHTML.query(".broadsheet .ticker__item") |> Enum.count() == 10

      assert doc
             |> LazyHTML.query(".viewswitch__tab[aria-current='page']")
             |> LazyHTML.text()
             |> String.trim() == "Broadsheet"

      assert html =~ "From the desk"
      assert html =~ "Inside today"
      refute html =~ "<script"
    end

    test "every story is printed once, in both layouts", %{conn: conn} do
      html = get(conn, ~p"/?layout=broadsheet") |> html_response(200)

      links =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(".broadsheet .story__headline a, .broadsheet .ticker__headline a")
        |> LazyHTML.attribute("href")

      assert length(links) == 32
      assert length(links) == length(Enum.uniq(links))
    end

    test "the choice is remembered in the session", %{conn: conn} do
      conn = get(conn, ~p"/?layout=broadsheet")
      assert html_response(conn, 200) =~ "sheet--broadsheet"

      html = get(recycle(conn), ~p"/") |> html_response(200)
      assert html =~ "sheet--broadsheet"
      assert html =~ "Inside today"
    end

    test "the reader can switch back", %{conn: conn} do
      conn = get(conn, ~p"/?layout=broadsheet")
      conn = get(recycle(conn), ~p"/?layout=reader")

      html = html_response(conn, 200)
      assert html =~ "sheet--reader"
      refute html =~ "broadsheet__front"
    end

    test "an unknown layout falls back to the standard page", %{conn: conn} do
      html = get(conn, ~p"/?layout=magazine") |> html_response(200)

      assert html =~ "sheet--reader"
      refute html =~ "sheet--broadsheet"
    end

    test "an unknown saved layout also falls back to the standard page", %{conn: conn} do
      html =
        conn
        |> init_test_session(%{paper_layout: "magazine"})
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "sheet--reader"
      refute html =~ "sheet--broadsheet"
    end

    test "a dated edition keeps the chosen layout in its tab links", %{conn: conn, day: day} do
      {:ok, _} = Editions.publish(day)
      path = edition_path(day)
      html = get(conn, path <> "?layout=broadsheet") |> html_response(200)

      assert html =~ "sheet--broadsheet"
      assert html =~ ~s(href="#{path}?layout=reader")
      assert html =~ ~s(href="#{path}?layout=broadsheet")
    end
  end

  describe "before an edition exists" do
    test "the clustered pool still prints", %{conn: conn} do
      File.rm_rf!(Frontier.Editions.Store.root())
      Frontier.Repo.delete_all(Frontier.Editions.Entry)
      Frontier.Repo.delete_all(Frontier.Editions.Edition)

      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "Quokka1 Zephyr1 opens a bakery"
      refute html =~ "From the desk"
    end

    test "the layout tabs wait for a printed edition", %{conn: conn} do
      File.rm_rf!(Frontier.Editions.Store.root())
      Frontier.Repo.delete_all(Frontier.Editions.Entry)
      Frontier.Repo.delete_all(Frontier.Editions.Edition)

      html = get(conn, ~p"/?layout=broadsheet") |> html_response(200)

      refute html =~ "viewswitch"
      assert html =~ "sheet--reader"
    end
  end

  defp edition_path(%Date{} = day) do
    "/#{day.year}/#{day.month}/#{day.day}"
  end
end
