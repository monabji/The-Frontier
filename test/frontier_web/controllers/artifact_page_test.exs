defmodule FrontierWeb.ArtifactPageTest do
  use FrontierWeb.ConnCase, async: false

  import Ecto.Query

  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Editions.{Artifact, Edition, Entry, Store}
  alias Frontier.Editor
  alias Frontier.EditorFixtures
  alias Frontier.Newsroom.Dateline
  alias Frontier.Repo

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

    {:ok, edition} = Editions.publish(day)

    %{day: day, edition: edition, candidate_ids: Enum.map(candidates, & &1.id)}
  end

  defp watch_queries do
    id = "artifact-query-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      id,
      [:frontier, :repo, :query],
      fn _event, _measure, meta, _config ->
        send(parent, {:query, meta[:source]})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    id
  end

  defp no_queries! do
    refute_received {:query, _source}
  end

  describe "the front page is a projection of the artifact" do
    test "reads a published edition", %{conn: conn, day: day} do
      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ Dateline.format(day)
      assert html =~ "From the desk"
      assert html =~ "min read"
      assert html =~ "Quokka1 Zephyr1 opens a bakery"
    end

    test "the front page touches no database", %{conn: conn} do
      watch_queries()
      assert get(conn, ~p"/") |> html_response(200)
      no_queries!()
    end

    test "a dated URL prints the same paper", %{conn: conn, day: day} do
      watch_queries()
      html = get(conn, edition_path(day)) |> html_response(200)

      assert html =~ "Quokka1 Zephyr1 opens a bakery"
      assert html =~ Dateline.format(day)
      no_queries!()
    end

    test "a day that was never printed is a 404" do
      assert get(build_conn(), "/2026/11/23") |> response(404) =~ "No edition"
    end

    test "the page still prints with its database rows gone", %{conn: conn, day: day} do
      Repo.delete_all(from(entry in Frontier.Editions.Entry))
      Repo.delete_all(from(edition in Edition))
      Repo.delete_all(from(item in Frontier.Newsroom.StoryItem))
      Repo.delete_all(from(story in Frontier.Newsroom.Story))

      watch_queries()

      assert get(conn, ~p"/") |> html_response(200) =~ "Quokka1 Zephyr1 opens a bakery"

      assert get(conn, edition_path(day)) |> html_response(200) =~
               "Quokka1 Zephyr1 opens a bakery"

      assert get(conn, ~p"/archive") |> html_response(200) =~ Dateline.format(day)
      no_queries!()
    end
  end

  describe "the archive" do
    test "lists every published day, newest first", %{conn: conn, day: day} do
      previous = Date.add(day, -1)
      write_artifact(previous, "published", "The previous day's desk note.")

      html = get(conn, ~p"/archive") |> html_response(200)

      assert html =~ Dateline.format(day)
      assert html =~ Dateline.format(previous)
      assert index_of(html, edition_path(day)) < index_of(html, edition_path(previous))
      assert html =~ "Past editions"
    end

    test "a draft is not in the archive", %{conn: conn, day: day} do
      draft_day = Date.add(day, -1)
      write_artifact(draft_day, "draft", "Not published yet.")

      html = get(conn, ~p"/archive") |> html_response(200)

      refute html =~ Dateline.format(draft_day)
      assert html =~ Dateline.format(day)
    end

    test "the archive touches no database", %{conn: conn, day: day} do
      write_artifact(Date.add(day, -1), "published", "An older edition.")

      watch_queries()
      assert get(conn, ~p"/archive") |> html_response(200) =~ Dateline.format(day)
      no_queries!()
    end
  end

  describe "the stored HTML snapshot" do
    test "contains the paper, built from the artifact alone", %{day: day} do
      {:ok, html} = Store.html(day)

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "Quokka1 Zephyr1 opens a bakery"
      assert html =~ "The Frontier"
      assert html =~ "From the desk"
    end
  end

  defp write_artifact(day, status, desk_note) do
    entry = %Entry{
      section: "Front Page",
      position: 1,
      kind: "lead",
      headline: "A previous headline",
      dek: "A previous dek.",
      summary: "A previous summary.",
      quote: "A previous quote.",
      url: "https://example.com/previous",
      canonical_url: "https://example.com/previous",
      source_label: "OpenAI",
      word_count: 3
    }

    artifact =
      Artifact.build(%Edition{
        day: day,
        status: status,
        desk_note: desk_note,
        read_minutes: 2,
        word_count: 100,
        story_count: 1,
        entries: [entry]
      })

    {:ok, _stored} = Store.write(artifact, "<h1>A previous headline</h1>")
    artifact
  end

  defp edition_path(%Date{} = day), do: "/#{day.year}/#{day.month}/#{day.day}"

  defp index_of(html, needle) do
    case :binary.match(html, needle) do
      {index, _length} -> index
      :nomatch -> -1
    end
  end
end
