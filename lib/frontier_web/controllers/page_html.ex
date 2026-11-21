defmodule FrontierWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FrontierWeb, :html

  embed_templates "page_html/*"

  # The band tells the reader how much is on the page. Stories, now that the
  # pool exists: a story is one event, however many sources carried it.
  defp kicker([]), do: "Nothing on the page"

  defp kicker(stories) do
    sources =
      stories
      |> Enum.flat_map(& &1.story_items)
      |> Enum.map(& &1.raw_item.source)
      |> Enum.uniq()
      |> length()

    "#{stories(length(stories))} · #{sources(sources)}"
  end

  defp stories(1), do: "1 story"
  defp stories(count), do: "#{count} stories"

  defp sources(1), do: "1 source"
  defp sources(count), do: "#{count} sources"
end
