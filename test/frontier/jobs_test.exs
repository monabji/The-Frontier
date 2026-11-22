defmodule Frontier.JobsTest do
  use Frontier.DataCase, async: false

  alias Frontier.ClusteringFixtures
  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Jobs
  alias Frontier.Jobs.{DailyRun, FreezeEdition, PublishEdition}
  alias Frontier.Newsroom.Pool
  alias Frontier.Runs

  @day ~D[2026-11-22]

  setup do
    EditionStorage.tmp!()
    test = self()
    previous = Application.get_env(:frontier, :alert_adapter)

    Application.put_env(:frontier, :alert_adapter, fn level, title, body ->
      send(test, {:alert, level, title, body})
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:frontier, :alert_adapter, previous)
      else
        Application.delete_env(:frontier, :alert_adapter)
      end
    end)

    :ok
  end

  defp job(day) do
    %Oban.Job{
      args: %{"day" => Date.to_iso8601(day)},
      attempt: 1,
      max_attempts: 3
    }
  end

  defp draft!(day) do
    items = ClusteringFixtures.seed!(day)
    Pool.rebuild(day, items: items)
    [story] = Pool.list_stories(day: day)

    entry = %{
      story_id: story.id,
      url: story.primary_url,
      canonical_url: story.canonical_url,
      section: "Front Page",
      kind: :lead,
      position: 1,
      headline: "A headline",
      dek: "A dek.",
      summary: String.duplicate("word ", 130),
      quote: "A quote from the source.",
      primary_source: story.primary_source,
      source_label: "Hugging Face",
      discussion_url: nil,
      score: nil,
      comments_count: nil,
      published_at: story.first_published_at,
      word_count: 130
    }

    {:ok, _edition} =
      Editions.save_draft(day, %{
        desk_note: "A quiet morning, honestly told, with the paper shorter than usual.",
        entries: [entry],
        tickers: [],
        issues: [],
        story_count: 1,
        word_count: 900
      })

    :ok
  end

  describe "the 06:00 publish" do
    test "a missing draft fails, alerts, and leaves a readable run", %{} do
      assert {:error, :no_edition} = PublishEdition.perform(job(@day))

      assert_receive {:alert, :error, title, body}
      assert title =~ "late"
      assert body =~ "no_edition"
      assert body =~ Date.to_iso8601(@day)

      [run] = Enum.filter(Runs.list(@day), &(&1.stage == "publish"))
      assert run.status == "error"
      assert run.error =~ "no_edition"
    end

    test "a draft is published as the day's artifact", %{} do
      :ok = draft!(@day)

      assert :ok = PublishEdition.perform(job(@day))

      edition = Editions.get(@day)
      assert edition.status == "published"
      assert edition.artifact_hash
      assert Editions.artifact(@day).status == "published"

      [run] = Enum.filter(Runs.list(@day), &(&1.stage == "publish"))
      assert run.status == "ok"
      assert run.inserted == 1
    end
  end

  describe "the midnight freeze" do
    test "freezes the day that just ended", %{} do
      :ok = draft!(@day)
      {:ok, _} = Editions.publish(@day)

      assert :ok = FreezeEdition.perform(job(@day))

      assert Editions.get(@day).status == "frozen"
      [run] = Enum.filter(Runs.list(@day), &(&1.stage == "freeze"))
      assert run.status == "ok"
    end

    test "a night with no artifact is skipped, not an alarm" do
      assert :ok = FreezeEdition.perform(job(@day))

      [run] = Enum.filter(Runs.list(@day), &(&1.stage == "freeze"))
      assert run.status == "skipped"
      refute_received {:alert, _level, _title, _body}
    end
  end

  describe "the 05:15 run" do
    test "a failed morning alerts with the day, attempt and fallback" do
      # Test configuration disables the network, so every source fails.
      assert {:error, :every_source_failed} = DailyRun.perform(job(@day))

      assert_receive {:alert, :error, title, body}
      assert title =~ "05:15"
      assert body =~ "Attempt: 1 of 3"
      assert body =~ "previous published edition"

      [run] = Enum.filter(Runs.list(@day), &(&1.stage == "daily"))
      assert run.status == "error"
    end
  end

  describe "job arguments" do
    test "an explicit day is used and a missing one falls back to the edition day" do
      assert Jobs.day(%{"day" => "2026-11-22"}) == ~D[2026-11-22]
      assert Jobs.day(%{}) == Frontier.Newsroom.Dateline.edition_date()
    end

    test "a malformed day is a job error, not a silent wrong edition" do
      assert_raise ArgumentError, fn -> Jobs.day(%{"day" => "not-a-date"}) end
    end
  end
end
