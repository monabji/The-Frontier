defmodule Frontier.Editions.ArtifactTest do
  use ExUnit.Case, async: true

  alias Frontier.Editions.{Artifact, Edition, Entry}

  @day ~D[2026-11-22]

  defp entry(attrs) do
    struct(
      %Entry{
        section: "Front Page",
        position: 1,
        kind: "lead",
        origin: "edition",
        headline: "A headline",
        dek: "A dek.",
        summary: "A summary of the thing that happened.",
        quote: "The thing happened.",
        image_url: "https://example.com/photo.jpg",
        url: "https://example.com/story",
        canonical_url: "https://example.com/story",
        primary_source: "rss:openai",
        source_label: "OpenAI",
        discussion_url: nil,
        score: nil,
        comments_count: nil,
        published_at: ~U[2026-11-22 04:00:00Z],
        word_count: 7
      },
      attrs
    )
  end

  defp edition(entries) do
    %Edition{
      day: @day,
      status: "draft",
      desk_note: "A quiet day, honestly told.",
      read_minutes: 9,
      word_count: 1_900,
      story_count: length(entries),
      entries: entries
    }
  end

  describe "the artifact's content" do
    test "packs the day, sections and ticker into one object" do
      artifact =
        Artifact.build(
          edition([
            entry(%{}),
            entry(%{section: "Research", kind: "standard", position: 1, headline: "A paper"}),
            entry(%{
              section: "Also Today",
              kind: "ticker",
              position: 1,
              headline: "A small thing"
            })
          ])
        )

      assert artifact.schema == 1
      assert artifact.day == @day
      assert artifact.status == "draft"
      assert artifact.desk_note =~ "quiet day"
      assert artifact.read_minutes == 9

      assert [{"Front Page", [_lead]}, {"Research", [_paper]}] = artifact.sections
      assert [%{headline: "A small thing"}] = artifact.also_today

      assert artifact.stats == %{
               "stories" => 2,
               "tickers" => 1,
               "words" => 1_900,
               "sources" => 1,
               "sections" => 2
             }
    end

    test "sections keep the paper's order, not alphabetical order" do
      artifact =
        Artifact.build(
          edition([
            entry(%{section: "Back Page", position: 1, kind: "standard"}),
            entry(%{section: "Front Page", position: 1, kind: "lead"}),
            entry(%{section: "Research", position: 1, kind: "standard"})
          ])
        )

      assert Enum.map(artifact.sections, &elem(&1, 0)) == ["Front Page", "Research", "Back Page"]
    end

    test "an entry carries its own link and provenance, not a story id" do
      json = Artifact.build(edition([entry(%{})])) |> Artifact.to_json()
      [section] = json["sections"]
      [lead] = section["entries"]

      assert lead["headline"] == "A headline"
      assert lead["quote"] == "The thing happened."
      assert lead["image_url"] == "https://example.com/photo.jpg"
      assert lead["url"] == "https://example.com/story"
      assert lead["canonical_url"] == "https://example.com/story"
      assert lead["source_label"] == "OpenAI"
      assert lead["kind"] == "lead"
      refute Map.has_key?(lead, "story_id")
    end
  end

  describe "content addressing" do
    test "the same inputs produce the same hash, byte for byte" do
      first = Artifact.build(edition([entry(%{})]))
      second = Artifact.build(edition([entry(%{})]))

      assert first.hash == second.hash
      assert Artifact.to_json(first) == Artifact.to_json(second)
      assert first.hash =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "a changed word changes the hash" do
      first = Artifact.build(edition([entry(%{})]))
      second = Artifact.build(edition([entry(%{headline: "Another headline"})]))

      refute first.hash == second.hash
    end

    test "key insertion order does not change the hash" do
      a = %{"b" => 1, "a" => %{"d" => 2, "c" => 3}}
      b = %{"a" => %{"c" => 3, "d" => 2}, "b" => 1}

      assert Artifact.hash(a) == Artifact.hash(b)
    end

    test "a stored JSON round-trips to the same artifact and hash" do
      artifact = Artifact.build(edition([entry(%{})]))
      json = artifact |> Artifact.to_json()

      restored = Artifact.from_json(json)

      assert restored.hash == artifact.hash
      assert restored.day == artifact.day
      assert restored.sections == artifact.sections
      assert Artifact.to_json(restored) == json
    end
  end

  describe "dates" do
    test "the day is a dated string and published_at is ISO 8601" do
      published = ~U[2026-11-22 00:30:00Z]

      artifact =
        Artifact.build(%{edition([entry(%{})]) | published_at: published, status: "published"})

      json = Artifact.to_json(artifact)

      assert json["day"] == "2026-11-22"
      assert json["published_at"] == "2026-11-22T00:30:00Z"
    end
  end
end
