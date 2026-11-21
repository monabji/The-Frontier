defmodule Frontier.Sources.HN do
  @moduledoc """
  Hacker News, read through Algolia's public search API.

  The front page is one search with the `front_page` tag; Algolia returns the
  stories in ranked order, which is the order the paper prints them in. No
  scraping: the API is public, documented and unauthenticated.

  A story that links somewhere else keeps its outbound URL; an Ask HN or a
  text post has no outbound URL, so its discussion link is the link the reader
  gets. Either way the item has a link, which is the paper's first rule.
  """

  @behaviour Frontier.Sources.Adapter

  alias Frontier.Sources.{Adapter, Item}

  @endpoint "https://hn.algolia.com/api/v1/search"
  # Ranked, not journalled: `front_page` is the tag the paper asks for, and 30
  # is the size the phase prints.
  @query "tags=front_page&hitsPerPage=30"
  @discussion "https://news.ycombinator.com/item?id="

  @impl true
  def key, do: "hn"

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
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {hit, position} -> item(hit, position) end)
      |> Enum.uniq_by(& &1.external_id)

    {:ok, items}
  end

  def normalize(_payload), do: {:error, :unexpected_payload}

  defp item(%{"objectID" => id, "title" => title} = hit, position)
       when is_binary(id) and id != "" and is_binary(title) and title != "" do
    discussion_url = @discussion <> id

    [
      %Item{
        external_id: id,
        title: String.trim(title),
        url: blank_to_nil(hit["url"]) || discussion_url,
        discussion_url: discussion_url,
        author: blank_to_nil(hit["author"]),
        text: plain_text(hit["story_text"]),
        points: hit["points"],
        comments_count: hit["num_comments"],
        published_at: parse_datetime(hit["created_at"]),
        position: position
      }
    ]
  end

  defp item(_hit, _position), do: []

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

  @doc """
  Algolia returns story text as HTML, entities and all. The paper stores text
  it could later quote verbatim, so tags go and entities become characters.
  """
  @spec plain_text(String.t() | nil) :: String.t() | nil
  def plain_text(nil), do: nil

  def plain_text(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/u, " ")
    |> decode_entities()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @named_entities %{
    "amp" => "&",
    "apos" => "'",
    "gt" => ">",
    "hellip" => "…",
    "ldquo" => "“",
    "lsquo" => "‘",
    "lt" => "<",
    "mdash" => "—",
    "nbsp" => " ",
    "ndash" => "–",
    "quot" => "\"",
    "rdquo" => "”",
    "rsquo" => "’"
  }

  defp decode_entities(text) do
    Regex.replace(~r/&(#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z]+);/, text, fn whole, entity ->
      entity(entity) || whole
    end)
  end

  defp entity("#x" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp entity("#" <> decimal), do: codepoint(String.to_integer(decimal))
  defp entity(name), do: Map.get(@named_entities, name)

  defp codepoint(value) do
    if value in 0..0x10FFFF and value not in 0xD800..0xDFFF do
      <<value::utf8>>
    end
  end
end
