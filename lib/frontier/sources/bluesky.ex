defmodule Frontier.Sources.Bluesky do
  @moduledoc """
  Bluesky, read through its public AppView API.

  The paper wants the conversation, not a firehose, so it reads a short list of
  accounts rather than the whole network: no auth, no scraping, one request per
  account per run. An account that fails is left out of the batch and reported;
  the others still contribute.

  A post's headline is its first line, trimmed — a social post has no title —
  and its link is the bsky.app permalink a reader can open. Reposts and replies
  are skipped: they are other people's words or half a conversation, and phase
  3's discourse quotes need posts that stand on their own.
  """

  @behaviour Frontier.Sources.Adapter

  alias Frontier.Sources.{Adapter, Item, Text}

  @endpoint "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed"

  # People who write about AI and software in public. Adding an account here is
  # the whole cost of adding a voice.
  @actors [
    "simonwillison.net",
    "karpathy.bsky.social"
  ]

  @limit 30
  @headline_length 180

  @impl true
  def key, do: "bsky"

  @impl true
  def label, do: "Bluesky"

  @doc "The accounts the paper reads."
  def actors, do: @actors

  @doc "The request made for one account."
  @spec url(String.t()) :: String.t()
  def url(actor) do
    @endpoint <> "?" <> URI.encode_query(%{"actor" => actor, "limit" => @limit})
  end

  @impl true
  def fetch(opts \\ []) do
    client = Adapter.client(opts)

    results =
      Enum.map(@actors, fn actor -> {actor, client.(url(actor))} end)

    case for {actor, {:ok, payload}} <- results, do: {actor, payload} do
      [] -> {:error, {:every_account_failed, Enum.map(results, fn {a, r} -> {a, r} end)}}
      feeds -> {:ok, feeds}
    end
  end

  @impl true
  def normalize(feeds) when is_list(feeds) do
    items =
      feeds
      |> Enum.flat_map(fn {_actor, payload} -> posts(payload) end)
      |> Enum.flat_map(&item/1)
      |> Enum.with_index(1)
      |> Enum.map(fn {item, position} -> %{item | position: position} end)

    {:ok, items}
  end

  def normalize(_payload), do: {:error, :unexpected_payload}

  defp posts(%{"feed" => feed}) when is_list(feed), do: feed
  defp posts(_payload), do: []

  defp item(%{"post" => _post, "reply" => _reply}), do: []
  defp item(%{"reason" => _repost}), do: []
  defp item(%{"post" => post}), do: item(post)

  defp item(%{"uri" => uri, "author" => author, "record" => record} = post)
       when is_binary(uri) and is_map(author) and is_map(record) do
    text = Text.plain(record["text"])
    headline = headline(text)
    handle = author["handle"]

    if headline && is_binary(handle) && handle != "" do
      permalink = permalink(handle, uri)

      [
        %Item{
          external_id: uri,
          title: headline,
          url: permalink,
          discussion_url: permalink,
          author: handle,
          text: text,
          kind: :post,
          score: post["likeCount"],
          comments_count: post["replyCount"],
          published_at: datetime(record["createdAt"])
        }
      ]
    else
      []
    end
  end

  defp item(_post), do: []

  defp permalink(handle, uri) do
    rkey = uri |> String.split("/") |> List.last()
    "https://bsky.app/profile/#{handle}/post/#{rkey}"
  end

  defp headline(nil), do: nil

  defp headline(text) do
    text
    |> String.split("\n", trim: true)
    |> List.first()
    |> case do
      nil -> nil
      line -> String.slice(line, 0, @headline_length)
    end
  end

  defp datetime(nil), do: nil

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  defp datetime(_value), do: nil
end
