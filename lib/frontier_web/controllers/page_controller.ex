defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Newsroom.Dateline
  alias Frontier.Sources

  def home(conn, _params) do
    date = Sources.current_edition_day()
    items = Sources.front_page_items(day: date)

    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(date)}")
    |> assign(
      :page_description,
      "The day in AI and technology, edited to be read in ten minutes. " <>
        "Edition of #{Dateline.format(date)}."
    )
    |> render(:home, date: date, items: items)
  end
end
