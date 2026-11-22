defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Editions
  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  def home(conn, _params) do
    day = Sources.current_edition_day()

    case Editions.get(day) || Editions.latest() do
      nil -> render_pool(conn, day)
      edition -> render_edition(conn, edition)
    end
  end

  defp render_edition(conn, edition) do
    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(edition.day)}")
    |> assign(
      :page_description,
      edition.desk_note ||
        "The day in AI and technology, edited to be read in ten minutes. " <>
          "Edition of #{Dateline.format(edition.day)}."
    )
    |> render(:home,
      date: edition.day,
      edition: edition,
      sections: Editions.sections(edition),
      tickers: Editions.tickers(edition),
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
end
