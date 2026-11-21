defmodule Frontier.SourcesTest do
  use Frontier.DataCase, async: false

  import ExUnit.CaptureLog

  alias Frontier.Fixtures
  alias Frontier.Newsroom.Dateline
  alias Frontier.Sources
  alias Frontier.Sources.{Canonical, HN, Item, RawItem, Run}

  @day ~D[2026-11-22]

  defmodule BlogAdapter do
    @behaviour Frontier.Sources.Adapter
    alias Frontier.Sources.RSS

    def key, do: "rss:test"
    def label, do: "Test Blog"

    def fetch(opts) do
      client = Keyword.get(opts, :client, fn _url -> {:error, :no_client} end)
      client.("https://blog.test/feed")
    end

    def normalize(payload), do: RSS.normalize(payload)
  end

  defmodule BrokenAdapter do
    @behaviour Frontier.Sources.Adapter
    def key, do: "broken"
    def label, do: "Broken"
    def fetch(_opts), do: {:error, :timeout}
    def normalize(_payload), do: {:error, :unexpected_payload}
  end

  defmodule ExplodingAdapter do
    @behaviour Frontier.Sources.Adapter
    def key, do: "exploding"
    def label, do: "Exploding"
    def fetch(_opts), do: raise("the source cannot even be asked")
    def normalize(_payload), do: []
  end

  defmodule BadShapeAdapter do
    @behaviour Frontier.Sources.Adapter
    def key, do: "badshape"
    def label, do: "Bad shape"
    def fetch(_opts), do: {:ok, %{}}
    def normalize(_payload), do: []
  end

  defp client do
    hn = Fixtures.hn_front_page()
    xml = Fixtures.rss_fixture("google-ai.xml")

    fn
      "https://blog.test/feed" -> {:ok, xml}
      url -> if url == HN.url(), do: {:ok, hn}, else: {:error, {:http_status, 404, ""}}
    end
  end

  defp hn_items do
    {:ok, items} = HN.normalize(Fixtures.hn_front_page())
    items
  end

  defp blog_url do
    {:ok, [first | _]} = Frontier.Sources.RSS.normalize(Fixtures.rss_fixture("google-ai.xml"))
    first.url
  end

  defp hit(id, title, url, extra \\ %{}) do
    Map.merge(
      %{
        "objectID" => id,
        "title" => title,
        "url" => url,
        "author" => "someone",
        "points" => 10,
        "num_comments" => 1,
        "created_at" => "2026-11-21T10:00:00Z"
      },
      extra
    )
  end

  describe "upsert_items/3" do
    test "stores what the item is and where it lives" do
      assert {:ok, %{fetched: 30, inserted: 30, updated: 0}} =
               Sources.upsert_items("hn", hn_items(), day: @day)

      assert Repo.aggregate(RawItem, :count) == 30

      story = Repo.get_by!(RawItem, source: "hn", external_id: "50579568")

      assert story.title == "Hurried Announcement: Alessandro Masullo GRH"

      assert story.canonical_url ==
               "https://math216.wordpress.com/2026/11/20/hurried-announcement-alessandro-masullo-grh"

      assert story.content_hash =~ ~r/\A[0-9a-f]{64}\z/
      assert story.kind == "story"
      assert story.score == 2370
      assert story.edition_day == @day
      assert story.first_seen_at != nil
    end

    test "keeps what the source says the item is" do
      assert {:ok, _} = Sources.upsert_items("hn", hn_items(), day: @day)

      ask = Repo.get_by!(RawItem, source: "hn", external_id: "50583761")
      job = Repo.get_by!(RawItem, source: "hn", external_id: "50593679")

      assert ask.kind == "ask"
      assert job.kind == "job"
    end

    test "stores the canonical URL, not the campaign URL" do
      item = %Item{
        external_id: "1",
        title: "A launch",
        url: "https://example.com/launch/?utm_source=hn&utm_medium=social#top"
      }

      assert {:ok, _} = Sources.upsert_items("hn", [item], day: @day)

      assert %RawItem{canonical_url: "https://example.com/launch"} =
               Repo.get_by!(RawItem, source: "hn", external_id: "1")
    end

    test "re-running adds nothing twice and refreshes the story" do
      assert {:ok, %{inserted: 30}} = Sources.upsert_items("hn", hn_items(), day: @day)

      before = Repo.get_by!(RawItem, source: "hn", external_id: "50579568")
      Repo.update_all(RawItem, set: [score: 1, title: "stale"])

      assert {:ok, %{fetched: 30, inserted: 0, updated: 30}} =
               Sources.upsert_items("hn", hn_items(), day: @day)

      assert Repo.aggregate(RawItem, :count) == 30

      after_refresh = Repo.get_by!(RawItem, source: "hn", external_id: "50579568")

      assert after_refresh.score == 2370
      assert after_refresh.title == "Hurried Announcement: Alessandro Masullo GRH"
      assert after_refresh.inserted_at == before.inserted_at
    end

    test "the same external id from two sources is two items" do
      {:ok, items} = HN.normalize(Fixtures.hn_front_page())
      one = Enum.take(items, 1)

      assert {:ok, _} = Sources.upsert_items("hn", one, day: @day)
      assert {:ok, _} = Sources.upsert_items("hn-mirror", one, day: @day)

      assert Repo.aggregate(RawItem, :count) == 2
    end

    test "skips an item that cannot be printed rather than storing half of it" do
      items = [
        %Item{external_id: "9", title: "No link", url: ""},
        %Item{external_id: "10", title: "Not web", url: "javascript:alert(1)"},
        %Item{
          external_id: "11",
          title: "Unsafe discussion",
          url: "https://example.com/a",
          discussion_url: "javascript:alert(1)"
        }
      ]

      assert {:ok, %{fetched: 3, inserted: 0, updated: 0, skipped: 3}} =
               Sources.upsert_items("hn", items, day: @day)

      assert Repo.aggregate(RawItem, :count) == 0
    end
  end

  describe "run/1" do
    test "fetches, normalizes and stores a source, reporting what it did" do
      assert [report] = Sources.run(adapters: [HN], client: client(), day: @day)

      assert report.source == "hn"
      assert report.label == "Hacker News"
      assert report.status == :ok
      assert report.fetched == 30
      assert report.inserted == 30
      assert report.updated == 0
      assert is_integer(report.duration_ms)
      assert Repo.aggregate(RawItem, :count) == 30
    end

    test "writes a run for every source, with its counts" do
      reports = Sources.run(adapters: [HN], client: client(), day: @day)

      assert [%{status: :ok}] = reports

      run = Repo.one!(Run)

      assert run.source == "hn"
      assert run.stage == "fetch"
      assert run.edition_day == @day
      assert run.status == "ok"
      assert run.fetched == 30
      assert run.inserted == 30
      assert run.duration_ms >= 0
    end

    test "a failing source is logged, gets a failed run, and the run carries on" do
      log =
        capture_log(fn ->
          reports = Sources.run(adapters: [BrokenAdapter, HN], client: client(), day: @day)

          assert [broken, hn] = reports
          assert broken.source == "broken"
          assert broken.status == :error
          assert broken.error == ":timeout"
          assert hn.status == :ok
          assert hn.inserted == 30
        end)

      assert log =~ "broken"
      assert log =~ "timeout"

      assert %Run{status: "error", error: ":timeout"} =
               Repo.get_by!(Run, source: "broken")

      assert Repo.aggregate(RawItem, :count) == 30
    end

    test "an adapter that raises is contained too" do
      capture_log(fn ->
        assert [report] = Sources.run(adapters: [ExplodingAdapter], client: client(), day: @day)
        assert report.status == :error
        assert report.error =~ "the source cannot even be asked"
      end)
    end

    test "an adapter that breaks its contract is contained too" do
      capture_log(fn ->
        assert [report] = Sources.run(adapters: [BadShapeAdapter], client: client(), day: @day)
        assert report.status == :error
        assert report.error =~ "unexpected_result"
      end)
    end

    test "an unreadable payload is an error, not an empty success" do
      capture_log(fn ->
        assert [report] =
                 Sources.run(
                   adapters: [HN],
                   client: fn _url -> {:ok, %{"nope" => true}} end,
                   day: @day
                 )

        assert report.status == :error
        assert report.error == ":unexpected_payload"
      end)
    end

    test "one broken feed does not stop the others" do
      capture_log(fn ->
        reports = Sources.run(adapters: [HN, BlogAdapter], client: client(), day: @day)

        assert [hn, blog] = reports
        assert hn.status == :ok
        assert blog.status == :ok
        assert blog.inserted > 0
      end)

      assert Repo.aggregate(RawItem, :count) > 30
    end

    test "runs every registered adapter by default" do
      keys = Enum.map(Sources.adapters(), & &1.key())

      assert "hn" in keys
      assert "rss:openai" in keys
      assert "rss:arstechnica" in keys
      assert "bsky" in keys
      assert length(keys) == 8
    end
  end

  describe "list_items/2" do
    test "returns a source's latest batch, not a union of fetches" do
      first = %{"hits" => [hit("1", "First fetch story", "https://example.com/first")]}
      second = %{"hits" => [hit("2", "Second fetch story", "https://example.com/second")]}

      Sources.run(adapters: [HN], client: fn _url -> {:ok, first} end, day: @day)
      Sources.run(adapters: [HN], client: fn _url -> {:ok, second} end, day: @day)

      titles = Sources.list_items("hn", day: @day) |> Enum.map(& &1.title)

      assert titles == ["Second fetch story"]
    end

    test "keeps the source's order" do
      Sources.run(adapters: [HN], client: client(), day: @day)

      items = Sources.list_items("hn", day: @day)

      assert Enum.map(items, & &1.position) == Enum.to_list(1..30)
    end

    test "leaves yesterday's front page behind" do
      assert {:ok, _} = Sources.upsert_items("hn", hn_items(), day: @day)

      assert Sources.list_items("hn", day: ~D[2026-11-23]) == []
    end

    test "takes a limit" do
      Sources.run(adapters: [HN], client: client(), day: @day)

      assert length(Sources.list_items("hn", day: @day, limit: 5)) == 5
    end
  end

  describe "front_page_items/1" do
    test "prints one item per canonical URL, from every source" do
      Sources.run(adapters: [HN, BlogAdapter], client: client(), day: @day)

      items = Sources.front_page_items(day: @day)
      canonical = Enum.map(items, & &1.canonical_url)

      assert length(canonical) == length(Enum.uniq(canonical))
      assert Enum.any?(items, &(&1.source == "hn"))
      assert Enum.any?(items, &(&1.source == "rss:test"))
    end

    test "the same article from HN and a blog renders once, as the blog" do
      url = blog_url()

      hn_batch = %{
        "hits" => [
          hit("77", "Introducing Tool Retrieval in the Gemini API", url <> "?utm_source=hn")
        ]
      }

      Sources.run(adapters: [HN], client: fn _url -> {:ok, hn_batch} end, day: @day)
      Sources.run(adapters: [BlogAdapter], client: client(), day: @day)

      items = Sources.front_page_items(day: @day)
      matching = Enum.filter(items, &(&1.canonical_url == Canonical.normalize(url)))

      assert [story] = matching
      assert story.source == "rss:test"
    end

    test "leaves job ads off the page" do
      Sources.run(adapters: [HN], client: client(), day: @day)

      titles = Sources.front_page_items(day: @day) |> Enum.map(& &1.title)

      refute Enum.any?(titles, &String.contains?(&1, "Is Hiring"))
    end

    test "leaves anything older than a week off the page" do
      old = %{
        "hits" => [
          hit("90", "Ancient news", "https://example.com/ancient", %{
            "created_at" => "2026-11-01T10:00:00Z"
          })
        ]
      }

      Sources.run(adapters: [HN], client: fn _url -> {:ok, old} end, day: @day)

      assert Sources.front_page_items(day: @day) == []
    end

    test "interleaves the sources by their own order" do
      Sources.run(adapters: [HN, BlogAdapter], client: client(), day: @day)

      items = Sources.front_page_items(day: @day)
      firsts = Enum.take(items, 2)

      # Both sources' number-one items are on the page before either source's
      # second item: the page is a mix, not a source dumped after another.
      assert firsts |> Enum.map(& &1.position) |> Enum.sort() == [1, 1]
      assert firsts |> Enum.map(& &1.source) |> Enum.uniq() |> length() == 2
      assert hd(items).position == 1
    end

    test "prints at most a front page" do
      Sources.run(adapters: [HN], client: client(), day: @day)

      assert length(Sources.front_page_items(day: @day, limit: 12)) == 12
    end
  end

  describe "current_edition_day/1" do
    test "before the day's first fetch, the paper shows the last edition" do
      Sources.run(adapters: [HN], client: client(), day: ~D[2026-11-21])

      assert Sources.current_edition_day(~D[2026-11-22]) == ~D[2026-11-21]
    end

    test "once the day has a fetch, the paper shows today" do
      Sources.run(adapters: [HN], client: client(), day: ~D[2026-11-21])
      Sources.run(adapters: [HN], client: client(), day: ~D[2026-11-22])

      assert Sources.current_edition_day(~D[2026-11-22]) == ~D[2026-11-22]
    end

    test "a day whose only run fetched nothing does not count" do
      Sources.run(adapters: [HN], client: client(), day: ~D[2026-11-21])

      capture_log(fn ->
        Sources.run(
          adapters: [HN],
          client: fn _url -> {:ok, %{"hits" => []}} end,
          day: ~D[2026-11-22]
        )
      end)

      assert Sources.current_edition_day(~D[2026-11-22]) == ~D[2026-11-21]
    end
  end

  describe "label_for/1" do
    test "names a source the way the paper prints it" do
      assert Sources.label_for("hn") == "Hacker News"
      assert Sources.label_for("rss:openai") == "OpenAI"
      assert Sources.label_for("unknown") == "unknown"
    end
  end

  describe "the paper's clock" do
    test "an edition day is the IST day, and it is the one items are filed under" do
      assert {:ok, _} = Sources.upsert_items("hn", hn_items(), day: Dateline.edition_date())

      assert Repo.all(RawItem) |> Enum.all?(&(&1.edition_day == Dateline.edition_date()))
    end
  end
end
