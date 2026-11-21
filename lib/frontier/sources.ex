defmodule Frontier.Sources do
  @moduledoc """
  The newsroom's front door: run an adapter, store what it found.

  A run is one adapter asked once. It fetches, normalizes and upserts, and it
  reports what happened — how many items it saw, how many were new, how many
  were refreshed, how long it took. Failures are logged and turned into a
  report, never raised: one broken source cannot stop the others.

  Storage is idempotent on `(source, external_id)`. Fetch the same front page
  ten times and `raw_items` holds it once.
  """

  require Logger

  import Ecto.Query

  alias Frontier.Newsroom.Dateline
  alias Frontier.Repo
  alias Frontier.Sources.{RawItem, HN}

  @type report :: %{
          source: String.t(),
          status: :ok | :error,
          duration_ms: non_neg_integer(),
          fetched: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer(),
          error: String.t() | nil
        }

  @doc "Every source the paper reads."
  @spec adapters() :: [module()]
  def adapters, do: [HN]

  @doc """
  Runs each adapter once and returns a report per adapter, in order.

  Options are passed through to the adapters; `:client` replaces the network in
  tests, `:adapters` narrows the run.
  """
  @spec run(keyword()) :: [report()]
  def run(opts \\ []) do
    opts
    |> Keyword.get(:adapters, adapters())
    |> Enum.map(&run_adapter(&1, opts))
  end

  @doc """
  Runs one adapter. A failure — a dead request, a payload that isn't what the
  adapter expects, or the adapter itself raising — becomes an error report.
  """
  @spec run_adapter(module(), keyword()) :: report()
  def run_adapter(adapter, opts \\ []) do
    source = adapter.key()
    started = System.monotonic_time(:millisecond)

    result =
      try do
        with {:ok, payload} <- adapter.fetch(opts),
             {:ok, items} <- adapter.normalize(payload),
             {:ok, counts} <- upsert_items(source, items) do
          {:ok, counts}
        end
      rescue
        exception -> {:error, Exception.message(exception)}
      end

    report(source, result, elapsed(started))
  end

  @doc """
  Stores a source's items, one row per `(source, external_id)`.

  Re-running refreshes the row instead of adding another, so the counts split
  into new and updated. An item without a title or a link is skipped and
  counted — the paper's first rule is no link, no story.
  """
  @spec upsert_items(String.t(), [Frontier.Sources.Item.t()]) ::
          {:ok,
           %{
             fetched: non_neg_integer(),
             inserted: non_neg_integer(),
             updated: non_neg_integer(),
             skipped: non_neg_integer()
           }}
  def upsert_items(source, items) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    printable =
      items
      |> Enum.filter(&printable?/1)
      |> Enum.uniq_by(& &1.external_id)

    skipped = length(items) - length(printable)
    ids = Enum.map(printable, & &1.external_id)
    known = known_ids(source, ids)

    rows = Enum.map(printable, &row(&1, source, now))

    if rows != [] do
      Repo.insert_all(RawItem, rows,
        on_conflict: {:replace, RawItem.refreshed_fields()},
        conflict_target: [:source, :external_id]
      )
    end

    {:ok,
     %{
       fetched: length(items),
       inserted: Enum.count(ids, &(not MapSet.member?(known, &1))),
       updated: Enum.count(ids, &MapSet.member?(known, &1)),
       skipped: skipped
     }}
  end

  @doc """
  One source's items for one edition day, in the order they were fetched.

  The day is IST, not UTC: after midnight the page has no front page until the
  next run, which is the truth about a daily paper.
  """
  @spec list_items(String.t(), keyword()) :: [RawItem.t()]
  def list_items(source, opts \\ []) do
    date = Keyword.get_lazy(opts, :date, &Dateline.edition_date/0)
    limit = Keyword.get(opts, :limit, 30)
    {start, close} = Dateline.day_bounds(date)

    Repo.all(
      from item in RawItem,
        where: item.source == ^source and item.fetched_at >= ^start and item.fetched_at < ^close,
        order_by: [asc: item.position, asc: item.id],
        limit: ^limit
    )
  end

  defp report(source, {:ok, counts}, duration_ms) do
    Logger.info(
      "[sources] #{source}: #{counts.fetched} fetched, #{counts.inserted} new, " <>
        "#{counts.updated} refreshed, #{counts.skipped} skipped in #{duration_ms}ms"
    )

    Map.merge(counts, %{source: source, status: :ok, duration_ms: duration_ms, error: nil})
  end

  defp report(source, {:error, reason}, duration_ms) do
    error = format_reason(reason)
    Logger.error("[sources] #{source} failed after #{duration_ms}ms: #{error}")

    %{
      source: source,
      status: :error,
      duration_ms: duration_ms,
      fetched: 0,
      inserted: 0,
      updated: 0,
      skipped: 0,
      error: error
    }
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp elapsed(started), do: System.monotonic_time(:millisecond) - started

  defp known_ids(_source, []), do: MapSet.new()

  defp known_ids(source, ids) do
    from(item in RawItem,
      where: item.source == ^source and item.external_id in ^ids,
      select: item.external_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp row(item, source, now) do
    %{
      source: source,
      external_id: item.external_id,
      title: item.title,
      url: item.url,
      discussion_url: item.discussion_url,
      author: item.author,
      text: item.text,
      points: item.points,
      comments_count: item.comments_count,
      position: item.position,
      published_at: item.published_at,
      fetched_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp printable?(%Frontier.Sources.Item{} = item) do
    present?(item.external_id) and present?(item.title) and link?(item.url)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp link?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  defp link?(_url), do: false
end
