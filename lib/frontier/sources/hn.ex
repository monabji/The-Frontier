defmodule Frontier.Sources.HN do
  @moduledoc """
  Hacker News, read through Algolia's public search API.

  The front page is one search with the `front_page` tag. Algolia returns the
  hits in its own relevance order — close to HN's ranking, not identical — and
  the paper keeps that order as the source's `position`, which is the only
  ordering the source offers. No scraping: the API is public and unauthenticated.

  A story that links somewhere else keeps its outbound URL; an Ask HN or a
  text post has no outbound URL, so its discussion link is the link the reader
  gets. Either way the item has a link, which is the paper's first rule.
  """

  @behaviour Frontier.Sources.Adapter

  alias Frontier.Sources.{Adapter, Item, Text}

  @endpoint "https://hn.algolia.com/api/v1/search"
  # Ranked, not journalled: `front_page` is the tag the paper asks for, and 30
  # is the size the phase prints.
  @query "tags=front_page&hitsPerPage=30"
  @discussion "https://news.ycombinator.com/item?id="

  @impl true
  def key, do: "hn"

  @impl true
  def label, do: "Hacker News"

  @impl true
  def fetch(opts \\ []) do
    Adapter.client(opts).(url())
  end

  @doc "The request a fetch makes; exposed so a test can assert it."
  @spec url() :: String.t()
  def url, do: @endpoint <> "?" <> @query

  @impl true
  def normalize(%{"hits" => hits}) when is_list(hits) do
    items =
      hits
      |> Enum.flat_map(&item/1)
      |> Enum.uniq_by(& &1.external_id)
      |> Enum.with_index(1)
      |> Enum.map(fn {item, position} -> %{item | position: position} end)

    {:ok, items}
  end

  def normalize(_payload), do: {:error, :unexpected_payload}

  defp item(%{"objectID" => id, "title" => title} = hit)
       when is_binary(id) and id != "" and is_binary(title) and title != "" do
    discussion_url = @discussion <> id

    [
      %Item{
        external_id: id,
        title: String.trim(title),
        url: blank_to_nil(hit["url"]) || discussion_url,
        discussion_url: discussion_url,
        author: blank_to_nil(hit["author"]),
        kind: kind(hit["_tags"]),
        text: Text.plain(hit["story_text"]),
        score: hit["points"],
        comments_count: hit["num_comments"],
        published_at: parse_datetime(hit["created_at"])
      }
    ]
  end

  defp item(_hit), do: []

  # HN says what a hit is in its tags; the paper keeps the distinction.
  defp kind(tags) when is_list(tags) do
    cond do
      "job" in tags -> :job
      "ask_hn" in tags -> :ask
      "show_hn" in tags -> :show
      true -> :story
    end
  end

  defp kind(_tags), do: :story

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end
end
