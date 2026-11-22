defmodule Frontier.Editions.Artifact do
  @moduledoc """
  One day's paper, frozen into a single content-addressed object.

  The artifact is the record: a dated JSON document carrying every printed
  entry's copy, link and provenance, its section and position, the desk note
  and the stats. The hash is taken over a canonical encoding, so the same
  edition inputs always produce the same hash and the same bytes — no build
  time, no database ids, no map ordering. What a day said has one answer.

  The HTML snapshot is rendered from this object; the web page is a projection
  of it too, which is why a published day can be read with the database
  untouched.
  """

  alias Frontier.Editions.{Edition, Entry}
  alias Frontier.Editor.Sections

  # Bump this when the stored HTML template changes: the hash covers the
  # paper's content, so a schema bump is how an old snapshot is invalidated.
  @schema 1

  defstruct [
    :schema,
    :day,
    :status,
    :published_at,
    :desk_note,
    :read_minutes,
    :stats,
    :hash,
    sections: [],
    also_today: []
  ]

  @type t :: %__MODULE__{
          schema: pos_integer(),
          day: Date.t(),
          status: String.t(),
          published_at: DateTime.t() | nil,
          desk_note: String.t() | nil,
          read_minutes: pos_integer() | nil,
          stats: map(),
          hash: String.t(),
          sections: [{String.t(), [Entry.t()]}],
          also_today: [Entry.t()]
        }

  @doc "Builds the artifact for an edition and its entries."
  @spec build(Edition.t()) :: t()
  def build(%Edition{} = edition) do
    main = Enum.reject(edition.entries, &ticker?/1)
    tickers = Enum.filter(edition.entries, &ticker?/1)

    sections =
      Sections.names()
      |> Enum.map(fn name ->
        entries = main |> Enum.filter(&(&1.section == name)) |> Enum.sort_by(& &1.position)
        {name, entries}
      end)
      |> Enum.reject(fn {_name, entries} -> entries == [] end)

    artifact = %__MODULE__{
      schema: @schema,
      day: edition.day,
      status: edition.status,
      published_at: edition.published_at,
      desk_note: edition.desk_note,
      read_minutes: edition.read_minutes,
      stats: stats(sections, tickers, edition),
      sections: sections,
      also_today: Enum.sort_by(tickers, & &1.position),
      hash: nil
    }

    %{artifact | hash: hash(to_json(artifact))}
  end

  @doc "The canonical JSON document, without the hash (the filename carries it)."
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = artifact) do
    %{
      "schema" => artifact.schema,
      "day" => Date.to_iso8601(artifact.day),
      "status" => artifact.status,
      "published_at" => iso8601(artifact.published_at),
      "desk_note" => artifact.desk_note,
      "read_minutes" => artifact.read_minutes,
      "stats" => artifact.stats,
      "sections" =>
        Enum.map(artifact.sections, fn {name, entries} ->
          %{"name" => name, "entries" => Enum.map(entries, &entry_json/1)}
        end),
      "also_today" => Enum.map(artifact.also_today, &entry_json/1)
    }
  end

  @doc "Reads an artifact back from its stored JSON, recomputing its hash."
  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    artifact = %__MODULE__{
      schema: map["schema"],
      day: parse_day(map["day"]),
      status: map["status"],
      published_at: parse_datetime(map["published_at"]),
      desk_note: map["desk_note"],
      read_minutes: map["read_minutes"],
      stats: map["stats"] || %{},
      sections:
        map
        |> Map.get("sections", [])
        |> Enum.map(fn section ->
          {section["name"],
           Enum.map(section["entries"] || [], &entry_from_json(&1, section["name"]))}
        end),
      also_today:
        map
        |> Map.get("also_today", [])
        |> Enum.map(&entry_from_json(&1, "Also Today")),
      hash: nil
    }

    %{artifact | hash: hash(map)}
  end

  @doc """
  The SHA-256 of a canonical JSON encoding of a term.

  Keys are sorted at every level and lists keep their order, so the digest
  depends on what the paper says, not on how Elixir happened to build a map.
  """
  @spec hash(term()) :: String.t()
  def hash(term) do
    term
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "A canonical JSON encoding: sorted object keys, stable byte output."
  @spec canonical_json(term()) :: binary()
  def canonical_json(term), do: term |> encode() |> IO.iodata_to_binary()

  defp encode(map) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))

    [
      "{",
      Enum.map_intersperse(pairs, ",", fn {key, value} ->
        [Jason.encode!(key), ":", encode(value)]
      end),
      "}"
    ]
  end

  defp encode(list) when is_list(list), do: ["[", Enum.map_intersperse(list, ",", &encode/1), "]"]

  defp encode(value), do: Jason.encode!(value)

  defp stats(sections, tickers, edition) do
    stories = sections |> Enum.map(fn {_name, entries} -> length(entries) end) |> Enum.sum()

    sources =
      (Enum.flat_map(sections, fn {_name, entries} -> entries end) ++ tickers)
      |> Enum.map(& &1.source_label)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> length()

    %{
      "stories" => stories,
      "tickers" => length(tickers),
      "words" => edition.word_count,
      "sources" => sources,
      "sections" => length(sections)
    }
  end

  defp entry_json(%Entry{} = entry) do
    %{
      "kind" => entry.kind,
      "position" => entry.position,
      "headline" => entry.headline,
      "dek" => entry.dek,
      "summary" => entry.summary,
      "quote" => entry.quote,
      "url" => entry.url,
      "canonical_url" => entry.canonical_url,
      "source" => entry.primary_source,
      "source_label" => entry.source_label,
      "discussion_url" => entry.discussion_url,
      "score" => entry.score,
      "comments_count" => entry.comments_count,
      "published_at" => iso8601(entry.published_at),
      "word_count" => entry.word_count
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp entry_from_json(map, section) do
    %Entry{
      section: section,
      position: map["position"],
      kind: map["kind"],
      origin: map["origin"] || "edition",
      headline: map["headline"],
      dek: map["dek"],
      summary: map["summary"],
      quote: map["quote"],
      url: map["url"],
      canonical_url: map["canonical_url"],
      primary_source: map["source"],
      source_label: map["source_label"],
      discussion_url: map["discussion_url"],
      score: map["score"],
      comments_count: map["comments_count"],
      published_at: parse_datetime(map["published_at"]),
      word_count: map["word_count"] || 0
    }
  end

  defp ticker?(%Entry{section: "Also Today"}), do: true
  defp ticker?(%Entry{kind: "ticker"}), do: true
  defp ticker?(_entry), do: false

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp parse_day(day) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end
end
