defmodule Frontier.Sources do
  @moduledoc """
  The newsroom's front door: run an adapter, store what it found.

  A run is one adapter asked once. It opens a `runs` row, fetches, normalizes
  and upserts, and closes the row with what it saw, how many items were new or
  refreshed, how long it took and why it failed if it did. Failures are logged
  and reported, never raised: one broken source cannot stop the others.

  Every stored item carries the run that last saw it. The page reads only the
  most recent successful run per source, so a front page that rotates between
  two fetches shows the second fetch, not a union of both.

  Storage is idempotent on `(source, external_id)`: fetch the same front page
  ten times and `raw_items` holds it once, refreshed.

  ## The page

  `front_page_items/1` is the paper's front page before the editor exists: each
  source's latest batch for one edition day, one entry per canonical URL, newest
  first. The same article submitted to HN and published by its own blog is two
  raw items and one story on the page; the publication wins over the aggregator,
  because the reader should be sent to the source.

  Two deterministic cuts stand in for editorial judgement until phase 4: job
  ads are not stories, and nothing older than a week is printed. Both are
  deliberately crude and both are cheap to change.
  """

  require Logger

  import Ecto.Query

  alias Frontier.Newsroom.Dateline
  alias Frontier.Repo
  alias Frontier.Sources.{Bluesky, Canonical, HN, RawItem, Run}

  @stage "fetch"

  # The paper prints 20–30 items. The pool is read wider so dedupe across
  # sources still leaves a full page.
  @front_page_size 30
  @pool_size 150

  # Until the editor ranks and dates stories, the paper keeps a week: daily
  # news plus the weekly blog post, and nothing older.
  @max_age_days 7

  # A source that only points at other sources' work is not the story's home:
  # an aggregator links out, a social feed talks about it.
  @aggregators ["hn", "bsky"]

  @doc """
  Whether a source is commentary on other people's work rather than a place a
  story was published. Aggregators never print as a story's link.
  """
  @spec aggregator?(String.t()) :: boolean()
  def aggregator?(source), do: source in @aggregators

  @type report :: %{
          source: String.t(),
          label: String.t(),
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
  def adapters, do: [HN | Frontier.Sources.RSS.feeds()] ++ [Bluesky]

  @doc """
  The paper's source order, best first. The lead is the first item of the first
  source until the editor ranks; it must not depend on alphabetical accident.
  """
  @spec source_rank(String.t()) :: non_neg_integer()
  def source_rank(source) do
    Enum.find_index(adapters(), &(&1.key() == source)) || 999
  end

  @doc "The name the paper prints for a source key."
  @spec label_for(String.t()) :: String.t()
  def label_for(key) do
    Enum.find_value(adapters(), key, fn adapter ->
      if adapter.key() == key, do: adapter.label()
    end)
  end

  @doc """
  Runs each adapter once and returns a report per adapter, in order.

  Options are passed through to the adapters; `:client` replaces the network in
  tests, `:adapters` narrows the run, `:redirect_resolver` replaces the
  redirect follower, `:day` sets the edition day.
  """
  @spec run(keyword()) :: [report()]
  def run(opts \\ []) do
    adapters = Keyword.get(opts, :adapters, adapters())
    day = Keyword.get_lazy(opts, :day, &Dateline.edition_date/0)

    Enum.map(adapters, &run_adapter(&1, Keyword.put(opts, :day, day)))
  end

  @doc """
  Runs one adapter and writes the run down.

  The run row is opened before the fetch, so an adapter that hangs or crashes
  leaves a row behind. A failure — a dead request, a payload that isn't what
  the adapter expects, or the adapter itself raising, throwing or exiting —
  closes the row as an error and returns a report instead of raising.
  """
  @spec run_adapter(module(), keyword()) :: report()
  def run_adapter(adapter, opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Dateline.edition_date/0)
    started = System.monotonic_time(:millisecond)
    source = source_of(adapter)
    run = start_run(source, day)

    result =
      try do
        with {:ok, payload} <- adapter.fetch(opts),
             {:ok, items} <- adapter.normalize(payload) do
          items = follow_redirects(items, opts)
          upsert_items(adapter.key(), items, day: day, run_id: run.id)
        else
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_result, other}}
        end
      rescue
        exception -> {:error, Exception.message(exception)}
      catch
        kind, reason -> {:error, {:caught, kind, reason}}
      end

    report = report(adapter, source, result, elapsed(started))
    finish_run(run, report)
    report
  end

  @doc """
  Stores a source's items, one row per `(source, external_id)`.

  Re-running refreshes the row instead of adding another, so the counts split
  into new and updated. An item without a title, a canonicalisable link or a
  safe discussion link is skipped — the paper's first rule is no link, no
  story. `first_seen_at` is kept; the day and run it was last seen in are
  overwritten.
  """
  @spec upsert_items(String.t(), [Frontier.Sources.Item.t()], keyword()) ::
          {:ok,
           %{
             fetched: non_neg_integer(),
             inserted: non_neg_integer(),
             updated: non_neg_integer(),
             skipped: non_neg_integer()
           }}
  def upsert_items(source, items, opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Dateline.edition_date/0)
    run_id = Keyword.get(opts, :run_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    printable =
      items
      |> Enum.map(&printable/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.external_id)

    skipped = length(items) - length(printable)
    ids = Enum.map(printable, & &1.external_id)
    known = known_ids(source, ids)

    rows = Enum.map(printable, &row(&1, source, day, run_id, now))

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
  The front page for an edition day: every source's latest batch, one entry per
  article, interleaved by each source's own order.

  No source is scored the way HN scores, so before the editor exists there is
  no shared rank. The page takes each source's first item, then its second, and
  so on: every source contributes its best work to the top of the page and none
  of them owns it. The same canonical URL from two sources appears once,
  preferring the publication over the aggregator.
  """
  @spec front_page_items(keyword()) :: [RawItem.t()]
  def front_page_items(opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Dateline.edition_date/0)
    limit = Keyword.get(opts, :limit, @front_page_size)

    day
    |> pool(limit: @pool_size)
    |> one_per_canonical_url()
    |> Enum.take(limit)
  end

  @doc """
  One source's items from its latest successful run on an edition day, in the
  order it fetched them.
  """
  @spec list_items(String.t(), keyword()) :: [RawItem.t()]
  def list_items(source, opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Dateline.edition_date/0)
    limit = Keyword.get(opts, :limit, @front_page_size)

    case latest_run_id(source, day) do
      nil ->
        []

      run_id ->
        Repo.all(
          from item in RawItem,
            where: item.run_id == ^run_id,
            order_by: [asc_nulls_last: item.position, asc: item.id],
            limit: ^limit
        )
    end
  end

  defp pool(day, opts) do
    limit = Keyword.get(opts, :limit, @pool_size)

    day
    |> day_items_for()
    |> Enum.take(limit)
  end

  @doc """
  The day the paper shows: today when it has a fetch, otherwise the most recent
  day that did.

  A daily paper does not go blank at midnight waiting for its 05:15 fetch; it
  shows the last edition and says which day it is.
  """
  @spec current_edition_day(Date.t() | nil) :: Date.t()
  def current_edition_day(today \\ nil) do
    today = today || Dateline.edition_date()

    if fetched_on?(today), do: today, else: latest_edition_day() || today
  end

  defp fetched_on?(day) do
    Repo.exists?(
      from run in Run,
        where:
          run.stage == ^@stage and run.edition_day == ^day and run.status == "ok" and
            run.inserted + run.updated > 0
    )
  end

  defp latest_edition_day do
    Repo.one(
      from run in Run,
        where: run.stage == ^@stage and run.status == "ok" and run.inserted + run.updated > 0,
        select: max(run.edition_day)
    )
  end

  defp day_items_for(day) do
    {day_start, _day_end} = Dateline.day_bounds(day)
    cutoff = DateTime.add(day_start, -@max_age_days * 86_400, :second)
    horizon = DateTime.add(day_start, 86_400, :second)

    case latest_run_ids(day) do
      [] ->
        []

      run_ids ->
        Repo.all(
          from item in RawItem,
            where:
              item.run_id in ^run_ids and item.kind != "job" and
                (is_nil(item.published_at) or
                   (item.published_at >= ^cutoff and item.published_at <= ^horizon))
        )
        |> Enum.sort_by(fn item ->
          {item.position || 9_999, source_rank(item.source), item.id}
        end)
    end
  end

  @doc """
  Every item from each source's latest successful run on an edition day, in
  each source's own order. The clustering pool reads this; job ads are already
  gone.
  """
  @spec day_items(keyword()) :: [RawItem.t()]
  def day_items(opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Dateline.edition_date/0)
    day_items_for(day)
  end

  # One entry per article: the publication beats the aggregator, and the
  # newest-first order of the pool survives the dedupe.
  defp one_per_canonical_url(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {item, index}, chosen ->
      Map.update(chosen, item.canonical_url, {item, index}, fn {current, current_index} ->
        if home_rank(item) < home_rank(current),
          do: {item, index},
          else: {current, current_index}
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(fn {_item, index} -> index end)
    |> Enum.map(fn {item, index} ->
      _ = index
      item
    end)
  end

  defp home_rank(item), do: if(aggregator?(item.source), do: 1, else: 0)

  defp latest_run_id(source, day) do
    Repo.one(
      from run in Run,
        where:
          run.stage == ^@stage and run.source == ^source and run.edition_day == ^day and
            run.status == "ok" and run.inserted + run.updated > 0,
        select: max(run.id)
    )
  end

  defp latest_run_ids(day) do
    Repo.all(
      from run in Run,
        where:
          run.stage == ^@stage and run.edition_day == ^day and run.status == "ok" and
            run.inserted + run.updated > 0,
        group_by: run.source,
        select: max(run.id)
    )
  end

  @doc """
  Follows shorteners and plain-`http` links before they are stored.
  """
  @spec follow_redirects([Frontier.Sources.Item.t()], keyword()) :: [
          Frontier.Sources.Item.t()
        ]
  def follow_redirects(items, opts) do
    resolver = Keyword.get(opts, :redirect_resolver, &Frontier.HTTP.final_url/1)
    Canonical.follow_redirects(items, resolver)
  end

  defp report(adapter, source, {:ok, counts}, duration_ms) do
    Logger.info(
      "[sources] #{source}: #{counts.fetched} fetched, #{counts.inserted} new, " <>
        "#{counts.updated} refreshed, #{counts.skipped} skipped in #{duration_ms}ms"
    )

    Map.merge(counts, %{
      source: source,
      label: label_of(adapter),
      status: :ok,
      duration_ms: duration_ms,
      error: nil
    })
  end

  defp report(adapter, source, {:error, reason}, duration_ms) do
    error = format_reason(reason)
    Logger.error("[sources] #{source} failed after #{duration_ms}ms: #{error}")

    %{
      source: source,
      label: label_of(adapter),
      status: :error,
      duration_ms: duration_ms,
      fetched: 0,
      inserted: 0,
      updated: 0,
      skipped: 0,
      error: error
    }
  end

  defp source_of(adapter) do
    adapter.key()
  rescue
    _ -> "unknown"
  end

  defp label_of(adapter) do
    adapter.label()
  rescue
    _ -> adapter.key()
  end

  defp start_run(source, day) do
    %Run{}
    |> Run.changeset(%{
      stage: @stage,
      source: source,
      edition_day: day,
      status: "running",
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp finish_run(run, report) do
    run
    |> Run.changeset(%{
      status: to_string(report.status),
      fetched: report.fetched,
      inserted: report.inserted,
      updated: report.updated,
      skipped: report.skipped,
      duration_ms: report.duration_ms,
      error: report.error
    })
    |> Repo.update!()
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

  defp row(item, source, day, run_id, now) do
    %{
      source: source,
      external_id: item.external_id,
      title: item.title,
      url: item.url,
      canonical_url: Canonical.normalize(item.url),
      content_hash: Canonical.content_hash(item),
      kind: to_string(item.kind),
      discussion_url: item.discussion_url,
      author: item.author,
      text: item.text,
      score: item.score,
      comments_count: item.comments_count,
      position: item.position,
      published_at: item.published_at,
      edition_day: day,
      run_id: run_id,
      first_seen_at: now,
      fetched_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp printable(%Frontier.Sources.Item{} = item) do
    if present?(item.external_id) and present?(item.title) and link?(item.url) and
         safe?(item.discussion_url) do
      item
    end
  end

  defp printable(_other), do: nil

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp link?(url) when is_binary(url), do: Canonical.normalize(url) != nil
  defp link?(_url), do: false

  # A discussion link is rendered straight into an href, so it is held to the
  # same standard as the story link: http(s) or nothing.
  defp safe?(nil), do: true
  defp safe?(url), do: link?(url)
end
