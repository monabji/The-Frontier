defmodule FrontierWeb.ReaderHTML do
  @moduledoc """
  The reader's own pages: onboarding, your paper, and what is stored.
  """

  use FrontierWeb, :html

  embed_templates "reader_html/*"

  defp thumb_count(counts, key), do: Map.get(counts, key, 0)
end
