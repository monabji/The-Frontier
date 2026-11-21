defmodule FrontierWeb.PoolController do
  @moduledoc """
  The pool page: every story the clusterer made today, and what it made it from.

  Internal and unlinked. It exists so thresholds can be judged by reading real
  clusters — which items landed together, which roles they took — instead of by
  trusting a count.
  """
  use FrontierWeb, :controller

  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Sources

  def index(conn, _params) do
    day = Sources.current_edition_day()
    stories = Pool.list_stories(day: day)

    conn
    |> assign(:page_title, "Pool — #{Dateline.format(day)}")
    |> assign(:page_description, "Internal view of the day's clustered pool.")
    |> render(:index, day: day, stories: stories)
  end
end
