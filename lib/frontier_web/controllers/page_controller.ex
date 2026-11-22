defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Editions
  alias Frontier.Editions.Store
  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  @doc """
  The paper's front page.

  When an artifact exists it is the paper: the route reads the stored JSON and
  renders it, without touching the database. Until the first artifact is
  assembled, the clustered pool is shown so the press is never blank.
  """
  def home(conn, _params) do
    case Editions.latest_artifact() do
      nil -> render_pool(conn, Sources.current_edition_day())
      artifact -> render_artifact(conn, artifact)
    end
  end

  @doc "A dated edition: `/2026/11/22`."
  def show(conn, %{"year" => year, "month" => month, "day" => day}) do
    with {:ok, date} <- date(year, month, day),
         artifact when not is_nil(artifact) <- Editions.artifact(date) do
      render_artifact(conn, artifact)
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

  defp render_artifact(conn, artifact) do
    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(artifact.day)}")
    |> assign(
      :page_description,
      artifact.desk_note ||
        "The day in AI and technology, edited to be read in ten minutes. " <>
          "Edition of #{Dateline.format(artifact.day)}."
    )
    |> render(:home,
      date: artifact.day,
      edition: FrontierWeb.ArtifactHTML.edition_view(artifact),
      sections: artifact.sections,
      tickers: artifact.also_today,
      stories: []
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
      stories: stories
    )
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
