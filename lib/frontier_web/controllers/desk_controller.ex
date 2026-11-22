defmodule FrontierWeb.DeskController do
  @moduledoc """
  The editing desk: a brief out to a chat window, a reply back in.

  This page exists because the paper must be able to close without an API key.
  It shows the exact prompt the editor would send, takes the JSON a person
  pasted back from ChatGPT, Gemini or Claude, and prints the result of the same
  grounding checks a live model's reply would face.

  It can write an edition, so it is behind `FRONTIER_DESK_TOKEN` (a query
  parameter on the page, a hidden field on its forms). With no token configured
  the route is simply not there.
  """

  use FrontierWeb, :controller

  alias Frontier.{Editions, Sources}
  alias Frontier.Editor.Desk
  alias Frontier.Editor.Sections
  alias Frontier.Newsroom.Dateline

  plug :require_desk

  def new(conn, _params) do
    day = Dateline.edition_date()

    conn
    |> assign_page(day)
    |> render_brief(day, nil, nil)
  end

  def create(conn, params) do
    day = day(params["day"])
    reply = params["reply"] || ""
    brief = params["brief"]

    conn = assign_page(conn, day)

    case Desk.submit(day, reply,
           assistant: params["assistant"] || "chat",
           link_checker: link_checker()
         ) do
      {:ok, %{edition: edition, report: report}} ->
        render_result(conn, day, edition, report, brief, nil)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_result(day, nil, nil, brief, Desk.explain(reason), reply)
    end
  end

  def publish(conn, params) do
    day = day(params["day"])

    case Editions.publish(day) do
      {:ok, _edition} ->
        redirect(conn, to: "/")

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> assign_page(day)
        |> render_result(day, Editions.get(day), nil, params["brief"], Desk.explain(reason), nil)
    end
  end

  # The brief is built once per view. A posted reply carries the brief back, so
  # a failed paste can be corrected without rebuilding (and re-fetching) the
  # whole candidate list.
  defp render_brief(conn, day, error, reply) do
    case safe_brief(day) do
      {:ok, brief} ->
        render(conn, :index,
          day: day,
          token: desk_token(),
          brief: brief.prompt,
          candidates: brief.candidates,
          excluded: brief.excluded,
          reply: reply,
          assistant: "chatgpt",
          error: error,
          result: nil
        )

      {:error, reason} ->
        render(conn, :index,
          day: day,
          token: desk_token(),
          brief: nil,
          candidates: 0,
          excluded: [],
          reply: reply,
          assistant: "chatgpt",
          error: "The brief could not be built: #{Desk.explain(reason)}",
          result: nil
        )
    end
  end

  defp render_result(conn, day, edition, report, brief, error, reply \\ nil) do
    sections = sections(edition)

    render(conn, :index,
      day: day,
      token: desk_token(),
      brief: brief,
      candidates: nil,
      excluded: [],
      reply: reply,
      assistant: "chatgpt",
      error: error,
      result: result(edition, report, sections)
    )
  end

  defp result(nil, nil, _sections), do: nil

  defp result(edition, report, sections) do
    %{
      edition: edition,
      report: report,
      sections: sections,
      tickers: Enum.filter(edition.entries, &(&1.section == "Also Today")),
      read_minutes: edition.read_minutes,
      printed: length(Enum.reject(edition.entries, &(&1.section == "Also Today")))
    }
  end

  defp sections(nil), do: []

  defp sections(edition) do
    edition.entries
    |> Enum.reject(&(&1.section == "Also Today"))
    |> Enum.group_by(& &1.section)
    |> then(fn grouped ->
      Sections.names()
      |> Enum.map(fn name -> {name, Map.get(grouped, name, [])} end)
      |> Enum.reject(fn {_name, entries} -> entries == [] end)
    end)
  end

  defp safe_brief(day) do
    {:ok, Desk.brief(day, limit: 100)}
  rescue
    exception -> {:error, {:brief_failed, Exception.message(exception)}}
  end

  defp assign_page(conn, day) do
    conn
    |> assign(:page_title, "Desk — #{Dateline.format(day)}")
    |> assign(:page_description, "The editing desk for #{Dateline.format(day)}.")
    |> assign(:csrf_token, get_csrf_token())
  end

  defp require_desk(conn, _opts) do
    expected = desk_token()
    given = conn.params["token"] || conn.query_params["token"]

    if is_binary(expected) and expected != "" and secure_equal?(given, expected) do
      conn
    else
      conn
      |> send_resp(404, "Not found")
      |> halt()
    end
  end

  defp secure_equal?(given, expected) when is_binary(given) do
    byte_size(given) == byte_size(expected) and Plug.Crypto.secure_compare(given, expected)
  end

  defp secure_equal?(_given, _expected), do: false

  defp desk_token, do: Application.get_env(:frontier, :desk_token)

  # The live checker is a network call per story; tests replace it through the
  # application environment, the same seam adapters use for their clients.
  defp link_checker do
    Application.get_env(:frontier, :desk_link_checker) ||
      (&Frontier.Editor.Grounding.resolve_link/1)
  end

  defp day(nil), do: Sources.current_edition_day() || Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Dateline.edition_date()
    end
  end
end
