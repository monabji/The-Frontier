defmodule Frontier.DailyTest do
  use Frontier.DataCase, async: false

  alias Frontier.Daily
  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Editions.Store
  alias Frontier.Editor.Cost
  alias Frontier.FixtureSource
  alias Frontier.Newsroom.{Dateline, Pool}
  alias Frontier.Runs
  alias Frontier.Sources

  @day ~D[2026-11-22]

  defmodule BrokenSource do
    @behaviour Frontier.Sources.Adapter
    @impl true
    def key, do: "broken"
    @impl true
    def label, do: "Broken"
    @impl true
    def fetch(_opts), do: {:error, :down}
    @impl true
    def normalize(_payload), do: {:error, :down}
  end

  setup do
    EditionStorage.tmp!()
    [_report] = Sources.run(day: @day, adapters: [FixtureSource])
    Pool.rebuild(@day)
    [story] = Pool.list_stories(day: @day)

    %{story: story}
  end

  defp payload(story) do
    %{
      "desk_note" =>
        "A quiet day with one compiler release, and the paper is shorter than usual because of it. " <>
          "The rest of the desk is quiet, and the paper says so.",
      "entries" => [
        %{
          "story_id" => story.id,
          "section" => "Research",
          "headline" => story.headline,
          "summary" => String.duplicate("word ", 85),
          "quote" => FixtureSource.quote()
        }
      ],
      "also_today" => []
    }
  end

  defp editor(payload) do
    fn _messages, _opts ->
      {:ok,
       %{
         content: Jason.encode!(payload),
         usage: %{input_tokens: 1_200, output_tokens: 400},
         model: "fixture-model"
       }}
    end
  end

  describe "a normal morning" do
    test "fetches, clusters, edits and assembles a draft", %{story: story} do
      assert {:ok, report} =
               Daily.run(@day,
                 adapters: [FixtureSource],
                 editor_client: editor(payload(story)),
                 link_checker: fn _url -> {:ok, "https://example.com/final"} end
               )

      assert report.printed == 1
      assert report.tickers == 0
      assert report.read_minutes == 1
      assert report.cost_micros == 420

      edition = Editions.get(@day)
      assert edition.status == "draft"
      assert edition.artifact_hash == report.artifact.hash
      assert Store.read(@day).hash == report.artifact.hash

      runs = Runs.list(@day)

      assert Enum.any?(
               runs,
               &(&1.stage == "fetch" and &1.source == "fixture" and &1.status == "ok")
             )

      assert Enum.any?(runs, &(&1.stage == "daily" and &1.status == "ok"))
      assert Enum.any?(runs, &(&1.stage == "edit" and &1.status == "ok"))
      assert Enum.any?(runs, &(&1.stage == "cluster" and &1.status == "ok"))

      daily = Enum.find(runs, &(&1.stage == "daily"))
      assert is_integer(daily.duration_ms)
      # The 05:15 run has until 06:00; a normal run is minutes, not the deadline.
      assert daily.duration_ms < 45 * 60 * 1000
    end

    test "the artifact is built from the run", %{story: story} do
      assert {:ok, %{artifact: artifact}} =
               Daily.run(@day,
                 adapters: [FixtureSource],
                 editor_client: editor(payload(story)),
                 link_checker: fn _url -> {:ok, "https://example.com/final"} end
               )

      assert artifact.status == "draft"
      assert artifact.stats["stories"] == 1

      assert artifact.sections |> List.first() |> elem(1) |> List.first() |> Map.get(:quote) ==
               FixtureSource.quote()
    end
  end

  describe "a failed morning" do
    test "an editor failure stops the run and leaves no artifact", %{story: _story} do
      assert {:error, {:editor_client, :boom}} =
               Daily.run(@day,
                 adapters: [FixtureSource],
                 editor_client: fn _messages, _opts -> {:error, :boom} end,
                 link_checker: fn _url -> {:ok, "https://example.com/final"} end
               )

      assert Store.read(@day) == nil

      [daily] = Enum.filter(Runs.list(@day), &(&1.stage == "daily"))
      assert daily.status == "error"
      assert daily.error =~ "boom"
    end

    test "every source failing is a failure, not an empty paper" do
      assert {:error, :every_source_failed} =
               Daily.run(@day, adapters: [BrokenSource])

      [daily] = Enum.filter(Runs.list(@day), &(&1.stage == "daily"))
      assert daily.status == "error"
    end
  end

  test "a published day is locked against a morning re-run", %{story: story} do
    assert {:ok, _} =
             Daily.run(@day,
               adapters: [FixtureSource],
               editor_client: editor(payload(story)),
               link_checker: fn _url -> {:ok, "https://example.com/final"} end
             )

    {:ok, _} = Editions.publish(@day)

    assert {:error, :edition_is_locked} =
             Daily.run(@day, adapters: [FixtureSource], editor_client: editor(payload(story)))

    [latest] = Runs.list(@day) |> Enum.filter(&(&1.stage == "daily")) |> Enum.take(-1)
    assert latest.status == "error"
  end

  test "the cost format used by the log is dollars" do
    assert Cost.format(420) == "$0.000420"
    assert Dateline.publish_hour() == 6
  end
end
