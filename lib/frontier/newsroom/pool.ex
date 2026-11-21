defmodule Frontier.Newsroom.Pool do
  @moduledoc """
  The day's candidate pool: every fetched item, clustered into stories.

  The pool is rebuilt, not appended to. A rebuild reads the day's items from
  each source's latest successful run, clusters them, and leaves the database
  holding exactly the stories those items make. Running it twice over the same
  pool produces the same stories with the same ids, so a scheduled re-run is
  safe.

  Job ads are not stories and never enter the pool.
  """

  import Ecto.Query

  alias Frontier.Newsroom.{Clusters, Story, StoryItem}
  alias Frontier.Repo
  alias Frontier.Sources

  @doc """
  Rebuilds an edition day's pool and reports what it found.

  Options: `:items` to cluster an explicit list instead of reading the day
  (tests and replays).
  """
  @spec rebuild(Date.t(), keyword()) :: %{
          stories: non_neg_integer(),
          items: non_neg_integer(),
          merged: non_neg_integer()
        }
  def rebuild(day, opts \\ []) do
    started = System.monotonic_time(:millisecond)
    items = Keyword.get_lazy(opts, :items, fn -> Sources.day_items(day: day) end)
    clusters = Clusters.cluster(items)

    report =
      if items == [] do
        # An empty pool is not evidence that the day had no stories: it is
        # usually a past day whose items have since been re-fetched. Leave the
        # stories standing rather than deleting a day.
        %{stories: 0, items: 0, merged: 0}
      else
        case Repo.transaction(fn -> sync(day, clusters) end) do
          {:ok, _result} ->
            %{
              stories: length(clusters),
              items: length(items),
              merged: Enum.sum(Enum.map(clusters, & &1.item_count)) - length(clusters)
            }

          {:error, reason} ->
            raise "clustering #{day} failed; nothing was written: #{inspect(reason)}"
        end
      end

    record_run(day, report, System.monotonic_time(:millisecond) - started)
    report
  end

  # The cluster stage is a run like any other: phase 6's log and phase 10's
  # admin page read `runs`, and a rebuild that leaves no trace is invisible.
  defp record_run(day, report, duration_ms) do
    %Frontier.Sources.Run{}
    |> Frontier.Sources.Run.changeset(%{
      stage: "cluster",
      source: "pool",
      edition_day: day,
      status: "ok",
      fetched: report.items,
      inserted: report.stories,
      updated: report.merged,
      duration_ms: duration_ms,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  @doc """
  The day's stories as the paper prints them: interleaved by each source's own
  order, the way the pool was built, with their items loaded.
  """
  @spec paper_stories(keyword()) :: [Story.t()]
  def paper_stories(opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Frontier.Newsroom.Dateline.edition_date/0)
    limit = Keyword.get(opts, :limit)

    query =
      from story in Story,
        where: story.edition_day == ^day,
        preload: [story_items: :raw_item]

    query
    |> Repo.all()
    |> Enum.sort_by(fn story ->
      {story.sort_position || 9_999, Frontier.Sources.source_rank(story.primary_source || ""),
       story.id}
    end)
    |> then(fn stories -> if limit, do: Enum.take(stories, limit), else: stories end)
  end

  @doc """
  The day's stories, biggest cluster first, with their items loaded.
  """
  @spec list_stories(keyword()) :: [Story.t()]
  def list_stories(opts \\ []) do
    day = Keyword.get_lazy(opts, :day, &Frontier.Newsroom.Dateline.edition_date/0)
    limit = Keyword.get(opts, :limit)

    query =
      from story in Story,
        where: story.edition_day == ^day,
        order_by: [desc: story.item_count, asc: story.cluster_key],
        preload: [story_items: :raw_item]

    query
    |> then(fn query -> if limit, do: limit(query, ^limit), else: query end)
    |> Repo.all()
  end

  defp sync(day, clusters) do
    keys = Enum.map(clusters, & &1.cluster_key)

    # A story whose key no longer exists is stale: its event changed or its
    # primary moved. Stale stories go first so the canonical-URL index cannot
    # collide with the replacement.
    Repo.delete_all(
      from story in Story, where: story.edition_day == ^day and story.cluster_key not in ^keys
    )

    existing =
      Repo.all(from story in Story, where: story.edition_day == ^day)
      |> Map.new(&{&1.cluster_key, &1})

    Enum.each(clusters, fn cluster ->
      story = upsert_story(cluster, day, existing[cluster.cluster_key])
      Repo.delete_all(from item in StoryItem, where: item.story_id == ^story.id)

      Repo.insert_all(
        StoryItem,
        Enum.map(cluster.items, fn item ->
          %{
            story_id: story.id,
            raw_item_id: raw_item_id(item),
            role: to_string(item.role),
            inserted_at: now(),
            updated_at: now()
          }
        end)
      )
    end)
  end

  defp upsert_story(cluster, day, existing) do
    attrs = %{
      edition_day: day,
      cluster_key: cluster.cluster_key,
      headline: cluster.headline,
      canonical_url: cluster.canonical_url,
      primary_url: cluster.primary_url,
      kind: cluster.kind,
      item_count: cluster.item_count,
      source_count: cluster.source_count,
      first_published_at: cluster.first_published_at,
      last_published_at: cluster.last_published_at,
      sort_position: cluster.sort_position,
      primary_source: cluster.primary_source,
      inserted_at: now(),
      updated_at: now()
    }

    case existing do
      nil ->
        %Story{} |> Story.changeset(attrs) |> Repo.insert!()

      story ->
        story |> Story.changeset(attrs) |> Repo.update!()
    end
  end

  # Clusters carry the row id of what they clustered; the JSON fixtures used in
  # tests do not, so the item's stored identity is looked up by its URL.
  defp raw_item_id(%{raw: %{id: id}}) when is_integer(id), do: id

  defp raw_item_id(%{raw: raw}) do
    external_id = Map.get(raw, :external_id) || Map.get(raw, "external_id")
    source = Map.get(raw, :source) || Map.get(raw, "source")

    Repo.one!(
      from item in Frontier.Sources.RawItem,
        where: item.source == ^source and item.external_id == ^external_id,
        select: item.id
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
