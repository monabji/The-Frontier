defmodule Frontier.Editions.AssembleTest do
  use Frontier.DataCase, async: false

  alias Frontier.ClusteringFixtures
  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Editions.Store
  alias Frontier.Newsroom.Pool
  alias Frontier.Repo
  alias Frontier.Sources
  alias Frontier.Sources.{Item, RawItem}

  @day ~D[2026-11-22]

  setup do
    EditionStorage.tmp!(%{})
    ClusteringFixtures.seed!(@day)

    {:ok, _} =
      Sources.upsert_items(
        "rss:openai",
        [
          %Item{
            external_id: "second-story",
            title: "A bakery in Lisbon is teaching machines to smell bread",
            url: "https://example.com/bread",
            kind: :post,
            published_at: ~U[2026-11-22 04:00:00Z]
          },
          %Item{
            external_id: "third-story",
            title: "Zebra migration patterns in the Serengeti puzzle researchers",
            url: "https://example.com/zebras",
            kind: :post,
            published_at: ~U[2026-11-22 03:00:00Z]
          }
        ],
        day: @day
      )

    Pool.rebuild(@day, items: Repo.all(RawItem))
    %{stories: Pool.list_stories(day: @day)}
  end

  defp plan(stories, opts \\ []) do
    [first, second, third] = Enum.take(stories, 3)

    entry = fn story, section, position, kind ->
      %{
        story_id: story.id,
        url: story.primary_url,
        canonical_url: story.canonical_url,
        section: section,
        kind: kind,
        position: position,
        headline: if(kind == :lead, do: "The lead", else: "Story #{story.id}"),
        dek: "The day's dek.",
        summary: String.duplicate("word ", 70),
        quote: "A verified sentence from the source.",
        primary_source: story.primary_source,
        source_label: "OpenAI",
        discussion_url: nil,
        score: nil,
        comments_count: nil,
        published_at: story.first_published_at,
        word_count: 70
      }
    end

    %{
      desk_note:
        Keyword.get(
          opts,
          :desk_note,
          "A quiet morning, honestly told, with the paper shorter than usual."
        ),
      entries: [entry.(first, "Front Page", 1, :lead), entry.(second, "Research", 1, :standard)],
      tickers: [
        entry.(third, "Also Today", 1, :ticker)
        |> Map.put(:headline, "A minor item")
        |> Map.put(:summary, "A short ticker line of twelve words or so.")
      ],
      issues: [],
      story_count: 2,
      word_count: 900
    }
  end

  describe "assemble/2" do
    test "writes the artifact, stores its files and records the version", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))

      assert {:ok, %{artifact: artifact, stored: stored, edition: edition}} =
               Editions.assemble(@day)

      assert artifact.status == "draft"
      assert artifact.stats["stories"] == 2
      assert artifact.stats["tickers"] == 1
      assert File.exists?(stored.json_path)
      assert File.exists?(stored.html_path)
      assert edition.artifact_hash == artifact.hash
      assert edition.artifact_path == stored.json_path
      assert edition.built_at
      assert Store.read(@day).hash == artifact.hash
    end

    test "the HTML snapshot is the paper, rendered from the artifact", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, _} = Editions.assemble(@day)

      {:ok, html} = Store.html(@day)
      assert html =~ "The Frontier"
      assert html =~ "The lead"
      assert html =~ "From the desk"
      assert html =~ "A verified sentence from the source."
    end

    test "the same inputs produce the same hash, however often it is rebuilt", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, %{artifact: first}} = Editions.assemble(@day)
      {:ok, %{artifact: second}} = Editions.assemble(@day)

      assert first.hash == second.hash
      assert Store.read(@day).hash == first.hash
    end

    test "a changed edition is a new version, and the old one stays", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, %{artifact: first}} = Editions.assemble(@day)

      {:ok, _} =
        Editions.save_draft(
          @day,
          plan(stories, desk_note: "A different desk note, still honest and still short.")
        )

      {:ok, %{artifact: second}} = Editions.assemble(@day)

      refute first.hash == second.hash
      assert Store.read(@day).hash == second.hash
      assert File.exists?(Path.join(Store.day_dir(@day), first.hash <> ".json"))
    end

    test "a day with no edition has nothing to assemble" do
      assert {:error, :no_edition} = Editions.assemble(@day)
    end
  end

  describe "publish/2" do
    test "publishes a draft as a dated artifact", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))

      assert {:ok, edition} = Editions.publish(@day, now: ~U[2026-11-22 00:30:00Z])
      assert edition.status == "published"
      assert edition.published_at == ~U[2026-11-22 00:30:00Z]
      assert edition.artifact_hash

      artifact = Store.read(@day)
      assert artifact.status == "published"
      assert artifact.published_at == ~U[2026-11-22 00:30:00Z]
      assert artifact.stats["stories"] == 2
    end

    test "a published edition cannot be assembled over, unless republishing", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, published} = Editions.publish(@day)

      assert {:error, :edition_is_published} = Editions.assemble(@day)
      assert Store.read(@day).hash == published.artifact_hash

      assert {:ok, %{artifact: artifact}} = Editions.assemble(@day, republish: true)
      assert artifact.hash == published.artifact_hash
    end

    test "a published edition rebuilds a missing artifact instead of lying", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, published} = Editions.publish(@day)
      File.rm_rf!(Store.day_dir(@day))

      assert {:ok, rebuilt} = Editions.publish(@day)
      assert rebuilt.artifact_hash == published.artifact_hash
      assert Store.read(@day).hash == published.artifact_hash
    end

    test "publishing twice does not move the edition", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, first} = Editions.publish(@day)
      {:ok, second} = Editions.publish(@day)

      assert first.artifact_hash == second.artifact_hash
      assert Store.read(@day).hash == first.artifact_hash
    end
  end

  describe "freeze/2" do
    test "a frozen day cannot be edited, assembled or rewritten", %{stories: stories} do
      {:ok, _} = Editions.save_draft(@day, plan(stories))
      {:ok, published} = Editions.publish(@day)
      {:ok, frozen} = Editions.freeze(@day)

      assert frozen.status == "frozen"
      assert frozen.frozen_at
      assert Store.frozen?(@day)
      assert Store.read(@day).hash == published.artifact_hash

      assert {:error, :edition_is_frozen} = Editions.assemble(@day)
      assert {:error, :edition_is_frozen} = Editions.save_draft(@day, plan(stories))
      assert {:error, :edition_is_frozen} = Editions.publish(@day)
      assert Store.read(@day).hash == published.artifact_hash
    end

    test "freezing a day with no artifact is refused" do
      assert {:error, :no_artifact} = Editions.freeze(@day)
    end
  end
end
