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
  @near_identical 0.7
  @guarded_name_similarity 0.25
  # A rare word is one only a few of the day's stories used. Two headlines that
  # share a rare two-word phrase ("lead azide") are about the same thing,
  # however they are worded.
  @rare_document_frequency 3

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
    @type t :: %__MODULE__{
            cluster_key: String.t(),
            headline: String.t(),
            canonical_url: String.t(),
            primary_url: String.t(),
            kind: String.t() | nil,
            first_published_at: DateTime.t() | nil,
            last_published_at: DateTime.t() | nil,
            item_count: non_neg_integer(),
            source_count: non_neg_integer(),
            sort_position: pos_integer() | nil,
            primary_source: String.t() | nil,
            items: [map()]
          }

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
      :sort_position,
      :primary_source,
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

    # Rarity is read off the day's pool: a word only a few stories used is what
    # tells two of them apart from the rest. The clustering stays deterministic
    # because the pool is the input.
    frequencies = document_frequencies(prepared)
    prepared = Enum.map(prepared, &Map.put(&1, :frequencies, frequencies))

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

  # Chaining is bounded: a new item must relate to a publication already in
  # the cluster, not to whatever linked chain reached it. A cluster of
  # aggregator posts has no publication, so it compares against its members.
  defp related_to_cluster?(item, cluster) do
    anchors = Enum.reject(cluster.items, &Frontier.Sources.aggregator?(&1.source))
    anchors = if anchors == [], do: cluster.items, else: anchors

    Enum.any?(anchors, &related?(item, &1))
  end

  defp related?(a, b) do
    cond do
      a.canonical == b.canonical -> true
      one_word_apart?(a, b) -> false
      version_conflict?(a, b) -> false
      not within_window?(a.published_at, b.published_at) -> false
      a.content_hash == b.content_hash -> true
      shared_name?(a, b) -> true
      subset?(a.tokens, b.tokens) or subset?(b.tokens, a.tokens) -> true
      title_similarity(a.tokens, b.tokens) >= @near_identical -> true
      true -> rare_phrase?(a, b)
    end
  end

  # "Gemini 4 Neon for developers" and "Gemini 4 Argon for developers" differ by
  # exactly one word: that word is the product, and the two are different
  # products. Event verbs are stopwords, so "releases" vs "launches" does not
  # trip this.
  defp one_word_apart?(a, b) do
    differing =
      MapSet.difference(a.tokens, b.tokens)
      |> MapSet.union(MapSet.difference(b.tokens, a.tokens))

    MapSet.size(differing) == 2 and MapSet.size(a.tokens) == MapSet.size(b.tokens) and
      MapSet.size(a.tokens) >= 3
  end

  # Two headlines that name different versions of the same line ("Gemini 4
  # Neon" and "Gemini 5 Neon") are two releases, however alike they read. The
  # version is the one thing a title must never let clustering throw away.
  defp version_conflict?(a, b) do
    MapSet.size(a.versions) > 0 and MapSet.size(b.versions) > 0 and
      not MapSet.equal?(a.versions, b.versions)
  end

  # A headline that is nothing but the name ("Inkling 2 Mini") sits inside the
  # fuller headline that reports it.
  defp subset?(small, big) do
    MapSet.size(small) >= 2 and MapSet.subset?(small, big)
  end

  # A shared name only merges when it is the whole name in both headlines: if
  # either title has a longer name built on it ("Gemini 4" vs "Gemini 4 Neon"),
  # the two are talking about different things. The titles must also agree on
  # something beyond the name, so two announcements about one product family
  # stay two stories.
  defp shared_name?(a, b) do
    shared =
      a.entities
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(b.entities)))
      |> Enum.reject(&(not Entities.distinctive?(a.entities[&1])))
      |> Enum.reject(&extended?(&1, a.entities))
      |> Enum.reject(&extended?(&1, b.entities))

    shared != [] and
      title_similarity(a.tokens, b.tokens) >= @guarded_name_similarity
  end

  # Sentence-case headlines never yield a capitalised name ("lead azide"), so
  # the last signal is a shared rare phrase: two adjacent words that only a few
  # of the day's stories used. Generic company and product words are common in
  # the pool and so cannot qualify.
  defp rare_phrase?(a, b) do
    shared_rare =
      a.tokens
      |> MapSet.intersection(b.tokens)
      |> Enum.filter(&rare?(&1, a.frequencies))

    shared_phrase? =
      a.phrases
      |> MapSet.intersection(b.phrases)
      |> Enum.any?(fn {left, right} ->
        rare?(left, a.frequencies) and rare?(right, a.frequencies)
      end)

    # One shared phrase is not enough on its own: "Hugging Face", "Google
    # Cloud" are two-word names that would merge every story mentioning one.
    # The headlines must agree on more than the phrase itself.
    shared_phrase? and length(shared_rare) >= 3
  end

  defp rare?(token, frequencies) do
    Map.get(frequencies, token, 0) <= @rare_document_frequency
  end

  defp document_frequencies(items) do
    frequencies =
      Enum.reduce(items, %{}, fn item, acc ->
        Enum.reduce(item.tokens, acc, fn token, acc ->
          Map.update(acc, token, 1, &(&1 + 1))
        end)
      end)

    Map.put(frequencies, :documents, max(length(items), 1))
  end

  defp extended?(key, entities) do
    Enum.any?(Map.keys(entities), fn other ->
      other != key and String.starts_with?(other, key)
    end)
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

  defp prepare(item) do
    url = field(item, :url)
    canonical = Canonical.normalize(url) || field(item, :canonical_url)
    title = field(item, :title) || ""
    entities = Map.new(Entities.from_title(title), fn name -> {Entities.key(name), name} end)

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
        position: field(item, :position),
        discussion_url: field(item, :discussion_url),
        content_hash: Canonical.utterance_hash(field(item, :title), field(item, :text)),
        published_at: datetime(field(item, :published_at)),
        tokens: content_tokens(title),
        phrases: content_phrases(title),
        entities: entities,
        versions: entity_versions(entities),
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
      sort_position: best_position(cluster.items),
      primary_source: primary.source,
      items: cluster.items |> Enum.map(&with_role(primary, &1)) |> sort_items()
    }
  end

  # The story is as well-placed as its best-placed item: a blog post carried by
  # HN enters the paper at HN's rank, not at the bottom.
  defp best_position(items) do
    items
    |> Enum.map(& &1.position)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp with_role(primary, item) do
    role =
      cond do
        item == primary -> :primary
        Frontier.Sources.aggregator?(item.source) -> :discussion
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
      :position,
      :discussion_url,
      :published_at,
      :raw
    ])
    |> Map.put(:role, role)
  end

  # The publication that broke the story leads; the aggregator that linked to
  # it follows. Earliest publication wins among publications, then the higher
  # score, then the URL, so the choice never depends on input order.
  # A publication beats an aggregator, and an aggregator that points at the
  # article beats one that points at itself: a social permalink is a place to
  # argue, not the story. Then the earliest, then the better score.
  defp primary(items) do
    Enum.min_by(items, fn item ->
      {
        if(Frontier.Sources.aggregator?(item.source), do: 1, else: 0),
        if(item.url == item.discussion_url, do: 1, else: 0),
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

  # Numbers are kept: a version is part of what the headline says, and dropping
  # it made "Gemini 4 Neon" and "Gemini 5 Neon" the same set of words.
  defp content_tokens(title) do
    title
    |> content_words()
    |> MapSet.new()
  end

  # Adjacent content words, in order. Numbers are left out: "gemini 4" is a
  # version, and two releases sharing one is exactly what must not merge.
  defp content_phrases(title) do
    title
    |> content_words()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reject(fn [left, right] -> numeric?(left) or numeric?(right) end)
    |> MapSet.new(fn [left, right] -> {left, right} end)
  end

  defp content_words(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split(" ", trim: true)
    |> Enum.reject(&(String.length(&1) < 2 or &1 in @stopwords))
  end

  defp numeric?(word), do: Regex.match?(~r/\A\d+\z/, word)

  # Only versions that sit inside a name count: a social post that mentions
  # "3.4B active parameters" is not claiming a different release.
  defp entity_versions(entities) do
    entities
    |> Map.values()
    |> Enum.flat_map(&Regex.scan(~r/\d+(?:[.\-]\d+)*/, &1))
    |> List.flatten()
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
    case Map.fetch(item, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(item, Atom.to_string(key))
    end
  end
end
