defmodule FrontierWeb.PageController do
  use FrontierWeb, :controller

  alias Frontier.Newsroom.Dateline
  alias Frontier.Newsroom.DemoEdition

  def home(conn, _params) do
    date = Dateline.edition_date()

    conn
    |> assign(:page_title, "The Frontier — #{Dateline.format(date)}")
    |> assign(
      :page_description,
      "The day in AI and technology, edited to be read in ten minutes. " <>
        "Edition of #{Dateline.format(date)}."
    )
    |> render(:home, date: date, edition: DemoEdition.current())
  end
end
