defmodule FrontierWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FrontierWeb, :html

  embed_templates "page_html/*"

  # The band tells the reader how much is on the page and whose work it is.
  # "Items" until clusters make them stories in phase 3.
  defp kicker([]), do: "Nothing on the page"

  defp kicker(items) do
    sources = items |> Enum.map(& &1.source) |> Enum.uniq() |> length()

    "#{pluralize(sources, "source")} · #{pluralize(length(items), "item")}"
  end

  defp pluralize(1, noun), do: "1 #{noun}"
  defp pluralize(count, noun), do: "#{count} #{noun}s"
end
