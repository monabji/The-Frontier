defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Editions
  alias Frontier.Editions.Store
  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  # The two ways to read a printed edition. "reader" is the long-form page the
  # paper has always served; "broadsheet" is a dense page-one composition.
  @layouts ~w(reader broadsheet)

  @doc """
  The paper's front page.

  When an artifact exists it is the paper: the route reads the stored JSON and
  renders it, without touching the database. Until the first artifact is
  assembled, the clustered pool is shown so the press is never blank.
  """
  def home(conn, _params) do
    conn = assign_layout(conn)

    case Editions.current() do
      %{artifact: nil} -> render_pool(conn, Sources.current_edition_day())
      %{artifact: artifact, delayed: delayed} -> render_artifact(conn, artifact, delayed)
    end
  end

  @doc "A dated edition: `/2026/11/22`."
  def show(conn, %{"year" => year, "month" => month, "day" => day}) do
    conn = assign_layout(conn)

    with {:ok, date} <- date(year, month, day),
         artifact when not is_nil(artifact) <- Editions.artifact(date),
         true <- artifact.status in ["published", "late", "frozen"] do
      render_artifact(conn, artifact, false)
    else
      _ -> not_found(conn)
    end
  end

  @doc """
  Every published day, newest first. The archive reads storage only: it is the
  list of what the paper actually printed, not what the pool currently holds.
  """
  def archive(conn, _params) do
    editions =
      Store.days()
      |> Enum.reverse()
      |> Enum.map(fn day -> {day, Editions.artifact(day)} end)
      |> Enum.reject(fn {_day, artifact} -> is_nil(artifact) or artifact.status == "draft" end)

    conn
    |> assign(:page_title, "Archive — The Frontier")
    |> assign(:page_description, "Every published edition of The Frontier, kept as printed.")
    |> render(:archive, editions: editions)
  end

  defp render_artifact(conn, artifact, delayed) do
    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(artifact.day)}")
    |> assign(
      :page_description,
      artifact.desk_note ||
        "The day in AI and technology, edited to be read in ten minutes. " <>
          "Edition of #{Dateline.format(artifact.day)}."
    )
    |> assign(:delayed, delayed)
    |> assign(:delayed_date, artifact.day)
    |> assign(:noted, conn.params["noted"] == "thumb")
    |> render(:home,
      date: artifact.day,
      edition: FrontierWeb.ArtifactHTML.edition_view(artifact),
      sections: artifact.sections,
      tickers: artifact.also_today,
      stories: [],
      delayed: delayed,
      delayed_date: artifact.day,
      noted: conn.params["noted"] == "thumb",
      paper_layout: conn.assigns.paper_layout,
      layout_path: conn.request_path,
      thumbs: true,
      csrf_token: get_csrf_token(),
      return_to: conn.request_path
    )
  end

  defp render_pool(conn, day) do
    stories = Pool.paper_stories(day: day)

    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(day)}")
    |> assign(
      :page_description,
      "The day in AI and technology, edited to be read in ten minutes. " <>
        "Edition of #{Dateline.format(day)}."
    )
    |> render(:home,
      date: day,
      edition: nil,
      sections: [],
      tickers: [],
      stories: stories,
      delayed: false,
      delayed_date: day,
      noted: conn.params["noted"] == "thumb",
      paper_layout: "reader",
      layout_path: conn.request_path,
      thumbs: false,
      csrf_token: nil,
      return_to: "/"
    )
  end

  # A layout is chosen by the tab, remembered in the signed session, and
  # carried in the URL so a link can point at either view. The pool fallback
  # gets the same assign, but only a real edition shows the tabs.
  defp assign_layout(conn) do
    chosen = conn.params["layout"]

    layout =
      if chosen in @layouts do
        chosen
      else
        saved = get_session(conn, :paper_layout)
        if saved in @layouts, do: saved, else: "reader"
      end

    conn = if chosen in @layouts, do: put_session(conn, :paper_layout, layout), else: conn
    assign(conn, :paper_layout, layout)
  end

  defp date(year, month, day) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _ -> :error
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("No edition was printed for that day.")
  end
end
