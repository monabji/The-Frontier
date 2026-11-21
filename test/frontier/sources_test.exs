defmodule Frontier.SourcesTest do
  use Frontier.DataCase, async: false

  import ExUnit.CaptureLog

  alias Frontier.Fixtures
  alias Frontier.Sources
  alias Frontier.Sources.{HN, Item, RawItem}
  alias Frontier.Newsroom.Dateline

  defmodule BrokenAdapter do
    @behaviour Frontier.Sources.Adapter
    def key, do: "broken"
    def fetch(_opts), do: {:error, :timeout}
    def normalize(_payload), do: {:error, :unexpected_payload}
  end

  defmodule ExplodingAdapter do
    @behaviour Frontier.Sources.Adapter
    def key, do: "exploding"
    def fetch(_opts), do: raise("the source cannot even be asked")
    def normalize(_payload), do: []
  end

  defp fixture_client do
    payload = Fixtures.hn_front_page()

    fn url ->
      if url == HN.url(), do: {:ok, payload}, else: {:error, {:http_status, 404}}
    end
  end

  defp fixture_items do
    {:ok, items} = HN.normalize(Fixtures.hn_front_page())
    items
  end

  describe "upsert_items/2" do
    test "stores one row per item, scoped to its source" do
      assert {:ok, %{fetched: 30, inserted: 30, updated: 0}} =
               Sources.upsert_items("hn", fixture_items())

      assert Repo.aggregate(RawItem, :count) == 30

      assert %RawItem{source: "hn", title: "Hurried Announcement: Alessandro Masullo GRH"} =
               Repo.get_by!(RawItem, source: "hn", external_id: "50579568")
    end

    test "re-running adds nothing twice" do
      assert {:ok, %{inserted: 30}} = Sources.upsert_items("hn", fixture_items())

      assert {:ok, %{fetched: 30, inserted: 0, updated: 30}} =
               Sources.upsert_items("hn", fixture_items())

      assert Repo.aggregate(RawItem, :count) == 30
    end

    test "the same external id from two sources is two items" do
      {:ok, items} = HN.normalize(Fixtures.hn_front_page())
      one = Enum.take(items, 1)

      assert {:ok, _} = Sources.upsert_items("hn", one)
      assert {:ok, _} = Sources.upsert_items("hn-mirror", one)

      assert Repo.aggregate(RawItem, :count) == 2
      assert [_first] = Repo.all(from r in RawItem, where: r.source == "hn-mirror")
    end

    test "skips an item that cannot be printed rather than storing half of it" do
      item = %Item{external_id: "9", title: "No link", url: ""}

      assert {:ok, %{fetched: 1, inserted: 0, updated: 0, skipped: 1}} =
               Sources.upsert_items("hn", [item])

      assert Repo.aggregate(RawItem, :count) == 0
    end
  end

  describe "run/1" do
    test "fetches, normalizes and stores a source, reporting what it did" do
      assert [report] = Sources.run(adapters: [HN], client: fixture_client())

      assert report.source == "hn"
      assert report.status == :ok
      assert report.fetched == 30
      assert report.inserted == 30
      assert report.updated == 0
      assert is_integer(report.duration_ms)
      assert Repo.aggregate(RawItem, :count) == 30
    end

    test "a failing source is logged and the run carries on" do
      log =
        capture_log(fn ->
          reports = Sources.run(adapters: [BrokenAdapter, HN], client: fixture_client())

          assert [broken, hn] = reports
          assert broken.source == "broken"
          assert broken.status == :error
          assert broken.error == ":timeout"
          assert hn.status == :ok
          assert hn.inserted == 30
        end)

      assert log =~ "broken"
      assert log =~ "timeout"
      assert Repo.aggregate(RawItem, :count) == 30
    end

    test "an adapter that raises is contained too" do
      capture_log(fn ->
        assert [report] = Sources.run(adapters: [ExplodingAdapter], client: fixture_client())
        assert report.status == :error
        assert report.error =~ "the source cannot even be asked"
      end)
    end

    test "an unreadable payload is an error, not an empty success" do
      capture_log(fn ->
        assert [report] =
                 Sources.run(adapters: [HN], client: fn _url -> {:ok, %{"nope" => true}} end)

        assert report.status == :error
        assert report.error == ":unexpected_payload"
      end)
    end

    test "runs every registered adapter by default" do
      assert Sources.adapters() == [HN]
    end
  end

  describe "list_items/2" do
    test "returns a source's items in the order it fetched them" do
      {:ok, _} = Sources.upsert_items("hn", fixture_items())

      items = Sources.list_items("hn", date: Dateline.edition_date())

      assert length(items) == 30
      assert Enum.map(items, & &1.position) == Enum.to_list(1..30)
    end

    test "leaves yesterday's front page behind" do
      {:ok, _} = Sources.upsert_items("hn", fixture_items())
      Repo.update_all(RawItem, set: [fetched_at: ~U[2026-11-20 12:00:00Z]])

      assert Sources.list_items("hn", date: ~D[2026-11-22]) == []
    end

    test "takes a limit" do
      {:ok, _} = Sources.upsert_items("hn", fixture_items())

      assert length(Sources.list_items("hn", date: Dateline.edition_date(), limit: 5)) == 5
    end
  end
end
