defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Newsroom.Dateline
  alias Frontier.Newsroom.DemoEdition

  def home(conn, _params) do
    date = Dateline.edition_date()
    dateline = Dateline.format(date)
    edition = DemoEdition.current()

    conn
    |> assign(:page_title, "The Frontier — #{dateline}")
    |> assign(
      :page_description,
      "The day in AI and technology, edited to be read in ten minutes. Edition of #{dateline}."
    )
    |> render(:home, date: date, dateline: dateline, edition: edition)
  end
end
