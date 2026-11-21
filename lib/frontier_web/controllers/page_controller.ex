defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  def home(conn, _params) do
    day = Sources.current_edition_day()
    stories = Pool.paper_stories(day: day)

    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(day)}")
    |> assign(
      :page_description,
      "The day in AI and technology, edited to be read in ten minutes. " <>
        "Edition of #{Dateline.format(day)}."
    )
    |> render(:home, date: day, stories: stories)
  end
end
