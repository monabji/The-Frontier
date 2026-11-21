defmodule Frontier.Newsroom.PoolTest do
  use Frontier.DataCase, async: false

  alias Frontier.ClusteringFixtures
  alias Frontier.Newsroom.{Pool, Story, StoryItem}
  alias Frontier.Sources.{RawItem, Run}

  @day ~D[2026-11-22]

  describe "rebuild/2 with a three-source launch" do
    setup do
      %{items: ClusteringFixtures.seed!(@day)}
    end

    test "makes one story of the same launch from HN, a blog and a social post", %{
      items: items
    } do
      assert %{stories: 1, items: 3, merged: 2} = Pool.rebuild(@day, items: items)

      story = Repo.one!(Story) |> Repo.preload(story_items: :raw_item)

      assert story.headline ==
               "Welcome Inkling 2 Mini, Cutting-edge Performance for your Local Setup"

      assert story.canonical_url == "https://huggingface.co/blog/inkling2mini"
      assert story.item_count == 3
      assert story.source_count == 3
      assert story.edition_day == @day

      roles =
        story.story_items
        |> Repo.preload(:raw_item)
        |> Map.new(fn item -> {item.raw_item.source, item.role} end)

      assert roles == %{
               "rss:huggingface" => "primary",
               "hn" => "discussion",
               "bsky" => "duplicate"
             }
    end

    test "re-running is idempotent: same stories, same ids, same members", %{items: items} do
      Pool.rebuild(@day, items: items)
      first = snapshot()

      Pool.rebuild(@day, items: items)
      second = snapshot()

      assert first == second
      assert Repo.aggregate(Story, :count) == 1
      assert Repo.aggregate(StoryItem, :count) == 3
    end

    test "no canonical URL appears in two stories", %{items: items} do
      Pool.rebuild(@day, items: items)

      canonical = Repo.all(from story in Story, select: story.canonical_url)

      assert length(canonical) == length(Enum.uniq(canonical))
    end

    test "every item belongs to exactly one story", %{items: items} do
      Pool.rebuild(@day, items: items)

      memberships =
        Repo.all(from item in StoryItem, select: item.raw_item_id)

      assert length(memberships) == length(items)
      assert length(memberships) == length(Enum.uniq(memberships))
    end
  end

  describe "rebuild/2 when the pool changes" do
    setup do
      %{items: ClusteringFixtures.seed!(@day)}
    end

    test "a rotated pool leaves no stale stories behind", %{items: items} do
      Pool.rebuild(@day, items: items)
      assert Repo.aggregate(Story, :count) == 1

      # The next fetch brings different stories; yesterday's story is gone from
      # today's pool rather than lingering.
      old_ids = Repo.all(from item in RawItem, select: item.id)
      Repo.delete_all(from item in StoryItem, where: item.raw_item_id in ^old_ids)
      Repo.delete_all(RawItem)

      new_items = [
        %Frontier.Sources.Item{
          external_id: "new-1",
          title: "Kubernetes 2.0 ships with a smaller control plane",
          url: "https://example.com/new-1",
          kind: :post,
          published_at: ~U[2026-11-21 10:00:00Z]
        },
        %Frontier.Sources.Item{
          external_id: "new-2",
          title: "A field guide to soil microbes",
          url: "https://example.com/new-2",
          kind: :post,
          published_at: ~U[2026-11-21 11:00:00Z]
        }
      ]

      {:ok, _} = Frontier.Sources.upsert_items("hn", new_items, day: @day)
      rows = Repo.all(RawItem)

      assert %{stories: 2} = Pool.rebuild(@day, items: rows)

      keys = Repo.all(from story in Story, select: story.cluster_key)
      assert Enum.all?(keys, &String.starts_with?(&1, "url:https://example.com/new-"))
      assert Repo.aggregate(StoryItem, :count) == 2
    end

    test "a story whose primary moves is rewritten in place", %{items: items} do
      Pool.rebuild(@day, items: items)
      story = Repo.one!(Story)
      assert story.canonical_url == "https://huggingface.co/blog/inkling2mini"

      # The HN submission disappears; the social post is the earliest left.
      hn_item = Repo.get_by!(RawItem, source: "hn")
      Repo.delete_all(from item in StoryItem, where: item.raw_item_id == ^hn_item.id)
      Repo.delete!(hn_item)

      remaining = Repo.all(RawItem) |> Enum.reject(&(&1.source == "hn"))

      assert %{stories: 1} = Pool.rebuild(@day, items: remaining)

      updated = Repo.one!(Story)
      assert updated.item_count == 2
      assert updated.cluster_key == "url:https://huggingface.co/blog/inkling2mini"
      assert Repo.aggregate(StoryItem, :count) == 2
    end
  end

  describe "the pool's contents" do
    test "job ads never become stories" do
      {:ok, _} =
        Frontier.Sources.upsert_items(
          "hn",
          [
            %Frontier.Sources.Item{
              external_id: "job-1",
              title: "A company is hiring engineers",
              url: "https://example.com/jobs",
              kind: :job,
              published_at: ~U[2026-11-21 10:00:00Z]
            }
          ],
          day: @day
        )

      rows = Repo.all(RawItem)
      assert %{stories: 0} = Pool.rebuild(@day, items: rows)
      assert Repo.aggregate(Story, :count) == 0
    end

    test "the day's runs are what the pool is built from" do
      {:ok, _} =
        Frontier.Sources.upsert_items(
          "hn",
          [
            %Frontier.Sources.Item{
              external_id: "a",
              title: "A story",
              url: "https://example.com/a",
              kind: :post,
              published_at: ~U[2026-11-21 10:00:00Z]
            }
          ],
          day: @day
        )

      # Without a successful run, the item is not part of the day's pool.
      assert Frontier.Sources.day_items(day: @day) == []
      assert %{stories: 0} = Pool.rebuild(@day)

      run =
        %Run{}
        |> Run.changeset(%{
          stage: "fetch",
          source: "hn",
          edition_day: @day,
          status: "ok",
          fetched: 1,
          inserted_at: DateTime.utc_now()
        })
        |> Repo.insert!()

      Repo.update_all(RawItem, set: [run_id: run.id])

      assert length(Frontier.Sources.day_items(day: @day)) == 1
      assert %{stories: 1} = Pool.rebuild(@day)
    end
  end

  defp snapshot do
    stories =
      Story
      |> Repo.all()
      |> Enum.map(fn story ->
        members =
          StoryItem
          |> where([item], item.story_id == ^story.id)
          |> Repo.all()
          |> Enum.map(&{&1.raw_item_id, &1.role})
          |> Enum.sort()

        {story.id, story.cluster_key, story.headline, members}
      end)

    Enum.sort(stories)
  end
end
