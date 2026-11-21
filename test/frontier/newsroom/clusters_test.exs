defmodule Frontier.Newsroom.ClustersTest do
  use ExUnit.Case, async: true

  alias Frontier.Newsroom.Clusters

  setup do
    %{launch: launch()}
  end

  describe "one event, three sources" do
    test "the same launch from HN, a blog and a social post is one story", %{launch: launch} do
      assert [story] = Clusters.cluster(launch)

      assert story.headline ==
               "Welcome Inkling 2 Mini, Cutting-edge Performance for your Local Setup"

      assert story.item_count == 3
      assert story.source_count == 3
      assert story.canonical_url == "https://huggingface.co/blog/inkling2mini"
      assert story.first_published_at == ~U[2026-11-20 00:00:00Z]
      assert story.last_published_at == ~U[2026-11-20 20:12:19Z]
    end

    test "each carried item gets a role", %{launch: launch} do
      assert [story] = Clusters.cluster(launch)

      roles =
        Map.new(story.items, fn item ->
          {item.source, item.role}
        end)

      # The blog is where the story was published; HN and Bluesky carried the
      # conversation about it, so both are discussion.
      assert roles == %{
               "rss:huggingface" => :primary,
               "hn" => :discussion,
               "bsky" => :discussion
             }
    end
  end

  describe "what merges" do
    test "the same URL with campaign parameters is the same story" do
      items = [
        item("hn", "1", "A launch", "https://example.com/launch?utm_source=hn"),
        item("rss:blog", "2", "A launch, from the source", "https://example.com/launch")
      ]

      assert [story] = Clusters.cluster(items)
      assert story.item_count == 2
    end

    test "a rephrased headline about the same name is one story" do
      items = [
        item(
          "hn",
          "1",
          "Gemini 4 Neon is out",
          "https://example.com/a",
          ~U[2026-11-20 10:00:00Z]
        ),
        item(
          "rss:blog",
          "2",
          "Gemini 4 Neon: what changed for developers",
          "https://example.com/b",
          ~U[2026-11-20 15:00:00Z]
        )
      ]

      assert [_story] = Clusters.cluster(items)
    end
  end

  describe "what must not merge" do
    test "two different launches by the same company are two stories" do
      items = [
        item(
          "hn",
          "1",
          "OpenAI ships a new voice model",
          "https://example.com/voice",
          ~U[2026-11-20 10:00:00Z]
        ),
        item(
          "hn",
          "2",
          "OpenAI announces an enterprise tier",
          "https://example.com/tier",
          ~U[2026-11-20 14:00:00Z]
        )
      ]

      assert [_, _] = Clusters.cluster(items)
    end

    test "two versions of the same line are two stories, however alike they read" do
      items = [
        item(
          "hn",
          "1",
          "Gemini 4 Neon released",
          "https://example.com/4",
          ~U[2026-11-20 10:00:00Z]
        ),
        item(
          "hn",
          "2",
          "Gemini 5 Neon released",
          "https://example.com/5",
          ~U[2026-11-20 11:00:00Z]
        )
      ]

      assert [_, _] = Clusters.cluster(items)
    end

    test "parallel releases worded the same way are two stories" do
      items = [
        item(
          "hn",
          "1",
          "Google announces Gemini 4 Neon for developers",
          "https://example.com/neon",
          ~U[2026-11-20 10:00:00Z]
        ),
        item(
          "hn",
          "2",
          "Google announces Gemini 4 Argon for developers",
          "https://example.com/argon",
          ~U[2026-11-20 11:00:00Z]
        )
      ]

      assert [_, _] = Clusters.cluster(items)
    end

    test "the same event in sentence case, with no capitalised name, is one story" do
      items = [
        item(
          "hn",
          "1",
          "Detonating a pile of lead azide",
          "https://example.com/lead",
          ~U[2026-11-21 13:23:00Z]
        ),
        item(
          "rss:arstechnica",
          "2",
          "Army delays detonating \"catastrophically hazardous\" lead azide amid fear, anger",
          "https://example.com/delay",
          ~U[2026-11-20 19:21:00Z]
        )
      ]

      assert together?(
               with_filler(items),
               "Detonating a pile of lead azide",
               "Army delays detonating \"catastrophically hazardous\" lead azide amid fear, anger"
             )
    end

    test "a hyphenated name is the same product" do
      items = [
        item("hn", "1", "Inkling 2 Mini", "https://example.com/one", ~U[2026-11-20 10:00:00Z]),
        item(
          "hn",
          "2",
          "Inkling-2-Mini in 5.4 GB memory",
          "https://example.com/two",
          ~U[2026-11-20 18:00:00Z]
        )
      ]

      assert [_story] = Clusters.cluster(items)
    end

    test "two versions of a name are two stories" do
      items = [
        item(
          "hn",
          "1",
          "Gemini 4 Neon released",
          "https://example.com/neon",
          ~U[2026-11-20 10:00:00Z]
        ),
        item(
          "hn",
          "2",
          "Gemini Omni 1.2 Flash released",
          "https://example.com/omni",
          ~U[2026-11-20 12:00:00Z]
        )
      ]

      assert [_, _] = Clusters.cluster(items)
    end

    test "sharing only a company name does not merge two launches" do
      items = [
        item(
          "rss:huggingface",
          "1",
          "Decision models in Hugging Face",
          "https://example.com/a",
          ~U[2026-11-20 10:00:00Z]
        ),
        item(
          "rss:huggingface",
          "2",
          "Pay for Hugging Face Hub with your Google Cloud account",
          "https://example.com/b",
          ~U[2026-11-20 11:00:00Z]
        ),
        item(
          "rss:googleai",
          "3",
          "Google Cloud launches Gemini for healthcare",
          "https://example.com/c",
          ~U[2026-11-20 12:00:00Z]
        )
      ]

      assert [_, _, _] = Clusters.cluster(items)
    end

    test "the same headline more than a day apart is two stories" do
      items = [
        item(
          "hn",
          "1",
          "Inkling 2 Mini is here",
          "https://example.com/one",
          ~U[2026-11-19 10:00:00Z]
        ),
        item(
          "hn",
          "2",
          "Inkling 2 Mini is here",
          "https://example.com/two",
          ~U[2026-11-21 10:00:00Z]
        )
      ]

      assert [_, _] = Clusters.cluster(items)
    end

    test "an item with no date cannot be placed in a window, so it stands alone" do
      items = [
        item("hn", "1", "Inkling 2 Mini is here", "https://example.com/one", nil),
        item(
          "hn",
          "2",
          "Inkling 2 Mini is here",
          "https://example.com/two",
          ~U[2026-11-20 10:00:00Z]
        )
      ]

      assert [_, _] = Clusters.cluster(items)
    end
  end

  describe "the pool's invariants" do
    test "no canonical URL appears in two stories", %{launch: launch} do
      items = launch ++ [item("hn", "9", "Something else entirely", "https://example.com/z")]

      canonical =
        items
        |> Clusters.cluster()
        |> Enum.flat_map(fn story -> Enum.map(story.items, & &1.url) end)
        |> Enum.map(&Frontier.Sources.Canonical.normalize/1)

      assert length(canonical) == length(Enum.uniq(canonical))
    end

    test "clustering is deterministic: the same items in any order give the same stories",
         %{launch: launch} do
      items = launch ++ [item("hn", "9", "Something else entirely", "https://example.com/z")]

      forward = Clusters.cluster(items)
      backward = Clusters.cluster(Enum.reverse(items))

      assert snapshot(forward) == snapshot(backward)
    end

    test "every item lands in exactly one story", %{launch: launch} do
      clustered = Clusters.cluster(launch) |> Enum.flat_map(& &1.items)

      assert length(clustered) == length(launch)

      assert clustered |> Enum.map(& &1.external_id) |> Enum.sort() ==
               launch |> Enum.map(& &1["external_id"]) |> Enum.sort()
    end
  end

  defp together?(pool, title_a, title_b) do
    pool
    |> Clusters.cluster()
    |> Enum.any?(fn story ->
      titles = Enum.map(story.items, & &1.title)
      title_a in titles and title_b in titles
    end)
  end

  # A day's pool has more than two stories; rarity is read off it, and a pool
  # of two has no common words.
  defp with_filler(items) do
    fillers =
      ~w(rust gardening cooking awards cycling traffic weather music)
      |> Enum.with_index(1)
      |> Enum.map(fn {subject, n} ->
        item(
          "rss:filler-#{n}",
          "filler-#{n}",
          "Notes on #{subject} and its practitioners",
          "https://example.com/filler-#{n}",
          ~U[2026-11-20 08:00:00Z]
        )
      end)

    items ++ fillers
  end

  defp launch do
    "test/fixtures/clusters/inkling-launch.json"
    |> File.read!()
    |> Jason.decode!()
  end

  defp item(source, id, title, url, published_at \\ ~U[2026-11-20 10:00:00Z]) do
    %{
      "source" => source,
      "external_id" => id,
      "title" => title,
      "url" => url,
      "kind" => "story",
      "score" => nil,
      "published_at" => published_at && DateTime.to_iso8601(published_at)
    }
  end

  defp snapshot(stories) do
    Enum.map(stories, fn story ->
      {story.cluster_key, Enum.map(story.items, &{&1.source, &1.external_id, &1.role})}
    end)
  end
end
