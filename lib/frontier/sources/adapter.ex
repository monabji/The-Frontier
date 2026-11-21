defmodule Frontier.Sources.Adapter do
  @moduledoc """
  What every source must implement to join the paper.

  Sources are peers: Hacker News, a blog's feed, arXiv and Bluesky all look
  like this to the newsroom. Fetching and normalizing are separate calls so a
  recorded payload can be replayed in a test without a client at all.

      key/0        the source's stable name, as stored on every raw item
      fetch/1      ask the source for one page of its items
      normalize/1  turn that payload into `Frontier.Sources.Item`s

  `fetch/1` takes options; adapters must accept a `:client` function, which is
  how tests replace the network with a fixture. An adapter never raises for a
  bad response: it returns `{:error, reason}` so one broken source cannot take
  the run down with it.
  """

  alias Frontier.Sources.Item

  @typedoc "Whatever an adapter's API returns, decoded."
  @type payload :: term()

  @typedoc "Why a fetch or a normalization could not produce items."
  @type reason :: term()

  @callback key() :: String.t()
  @callback fetch(keyword()) :: {:ok, payload()} | {:error, reason()}
  @callback normalize(payload()) :: {:ok, [Item.t()]} | {:error, reason()}

  @doc "The client option an adapter should use, defaulting to real HTTP."
  @spec client(keyword()) :: (String.t() -> {:ok, term()} | {:error, term()})
  def client(opts), do: Keyword.get(opts, :client, &Frontier.HTTP.get_json/1)
end
