defmodule Frontier.Newsroom.Clusters do
  @moduledoc """
  Turning fetched items into events.

  A story is one thing that happened, however many sources carried it. The
  clustering is deterministic and offline: no embeddings, no model, no
  randomness. Two items join the same story when

    * they resolve to the same canonical URL, whatever the campaign string, or
    * they were published within a day of each other **and** either their
      titles say the same thing or they share a distinctive name.

  A name of one word is a company, and a company ships several things a week, so
  "OpenAI" alone never merges two stories; "Inkling 2 Mini" does. The 24-hour
  window keeps a launch from swallowing its follow-up coverage two days later.

  The story's identity is its primary item's canonical URL, and the primary is
  the publication that broke it — not the aggregator that linked to it — so
  re-running the clusterer over the same pool produces the same stories with
  the same keys.
  """

  alias Frontier.Newsroom.Entities
  alias Frontier.Sources.Canonical

  @window_seconds 24 * 3600
  @title_similarity 0.55
  # A two-word name is a company or a product family: "Hugging Face", "Google
  # Cloud". Sharing one is not enough. Three words, or a name carrying a
  # version, is an event: "Inkling 2 Mini", "Gemini 4 Argon".
  @distinctive_entity_tokens 3

  # Aggregators link to other people's work; the paper sends the reader to the
  # work. HN is the only one so far.
  @aggregators ["hn"]

  @stopwords ~w(
    a an the this that these those it its in on at for to of and but or is are was were be
    been being can could will would should may might must do does did has have had
    how why what when where who which with without from into over under about
    more most less least new now just here there we you they our your their
    says say said announces announced releases released launches launched
    update updates updated version
  )

  defmodule Story do
    @moduledoc """
    One event: a headline, a primary link and the items that carried it.
    """
    defstruct [
      :cluster_key,
      :headline,
      :canonical_url,
      :primary_url,
      :kind,
      :first_published_at,
      :last_published_at,
      :item_count,
      :source_count,
      items: []
    ]
  end

  @doc """
  Groups items into stories. Works on maps with atom or string keys, so the
  same function serves tests (recorded JSON) and the database (schemas).
  """
  @spec cluster([map()]) :: [Story.t()]
  def cluster(items) do
    prepared =
      items
      |> Enum.map(&prepare/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn item -> {item.canonical, item.source, item.external_id} end)

    prepared
    |> group()
    |> Enum.map(&story/1)
    |> Enum.sort_by(& &1.cluster_key)
  end

  defp group(items) do
    items
    |> Enum.reduce([], fn item, clusters ->
      {matching, rest} = Enum.split_with(clusters, &related_to_cluster?(item, &1))

      merged = %{items: [item | Enum.flat_map(matching, & &1.items)]}
      [merged | rest]
    end)
  end

  defp related_to_cluster?(item, cluster) do
    Enum.any?(cluster.items, &related?(item, &1))
  end

  defp related?(a, b) do
    cond do
      a.canonical == b.canonical -> true
      not within_window?(a.published_at, b.published_at) -> false
      title_similarity(a.tokens, b.tokens) >= @title_similarity -> true
      true -> shared_name?(a, b)
    end
  end

  defp shared_name?(a, b) do
    a.entities
    |> MapSet.intersection(b.entities)
    |> Enum.filter(&Entities.distinctive?/1)
    |> Enum.any?(&(count_tokens(&1) >= @distinctive_entity_tokens))
  end

  defp within_window?(nil, _other), do: false
  defp within_window?(_other, nil), do: false

  defp within_window?(a, b), do: abs(DateTime.diff(a, b, :second)) <= @window_seconds

  defp title_similarity(tokens_a, tokens_b) do
    union = MapSet.union(tokens_a, tokens_b)

    case MapSet.size(union) do
      0 -> 0.0
      size -> MapSet.size(MapSet.intersection(tokens_a, tokens_b)) / size
    end
  end

  defp count_tokens(name), do: name |> String.split(" ", trim: true) |> length()

  defp prepare(item) do
    url = field(item, :url)
    canonical = field(item, :canonical_url) || Canonical.normalize(url)
    title = field(item, :title) || ""

    if canonical == nil or field(item, :kind) == "job" or field(item, :kind) == :job do
      nil
    else
      %{
        source: field(item, :source),
        external_id: field(item, :external_id),
        title: title,
        url: url,
        canonical: canonical,
        kind: field(item, :kind) || "story",
        score: field(item, :score),
        published_at: datetime(field(item, :published_at)),
        tokens: content_tokens(title),
        entities: MapSet.new(Entities.from_title(title)),
        raw: item
      }
    end
  end

  defp story(cluster) do
    primary = primary(cluster.items)
    published = Enum.map(cluster.items, & &1.published_at) |> Enum.reject(&is_nil/1)

    %Story{
      cluster_key: "url:" <> primary.canonical,
      headline: primary.title,
      canonical_url: primary.canonical,
      primary_url: primary.url,
      kind: primary.kind,
      first_published_at: Enum.min(published, DateTime, fn -> nil end),
      last_published_at: Enum.max(published, DateTime, fn -> nil end),
      item_count: length(cluster.items),
      source_count: cluster.items |> Enum.map(& &1.source) |> Enum.uniq() |> length(),
      items: cluster.items |> Enum.map(&with_role(primary, &1)) |> sort_items()
    }
  end

  defp with_role(primary, item) do
    role =
      cond do
        item == primary -> :primary
        item.source in @aggregators -> :discussion
        true -> :duplicate
      end

    item
    |> Map.take([
      :source,
      :external_id,
      :title,
      :url,
      :canonical,
      :kind,
      :score,
      :published_at,
      :raw
    ])
    |> Map.put(:role, role)
  end

  # The publication that broke the story leads; the aggregator that linked to
  # it follows. Earliest publication wins among publications, then the higher
  # score, then the URL, so the choice never depends on input order.
  defp primary(items) do
    Enum.min_by(items, fn item ->
      {
        if(item.source in @aggregators, do: 1, else: 0),
        item.published_at || ~U[9999-12-31 00:00:00Z],
        -(item.score || 0),
        item.canonical,
        item.external_id
      }
    end)
  end

  defp sort_items(items) do
    Enum.sort_by(items, fn item ->
      {
        if(item.role == :primary, do: 0, else: 1),
        item.published_at || ~U[9999-12-31 00:00:00Z],
        item.source,
        item.external_id
      }
    end)
  end

  defp content_tokens(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split(" ", trim: true)
    |> Enum.reject(&(String.length(&1) < 2 or &1 in @stopwords or Regex.match?(~r/\A\d+\z/, &1)))
    |> MapSet.new()
  end

  defp datetime(%DateTime{} = value), do: DateTime.truncate(value, :second)
  defp datetime(nil), do: nil

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  defp datetime(_value), do: nil

  defp field(item, key) when is_map(item) do
    Map.get(item, key) || Map.get(item, Atom.to_string(key))
  end
end
