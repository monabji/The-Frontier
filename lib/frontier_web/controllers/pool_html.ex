defmodule FrontierWeb.PoolHTML do
  @moduledoc """
  Templates for the internal pool page.
  """
  use FrontierWeb, :html

  embed_templates "pool_html/*"

  defp item_count(stories), do: stories |> Enum.map(& &1.item_count) |> Enum.sum()

  # The publication leads, then the conversation, then the repeats: the same
  # order the cluster put them in, restored after the database round trip.
  defp items_in_order(story) do
    Enum.sort_by(story.story_items, fn item -> {role_rank(item.role), item.id} end)
  end

  defp role_rank("primary"), do: 0
  defp role_rank("discussion"), do: 1
  defp role_rank(_other), do: 2
end
