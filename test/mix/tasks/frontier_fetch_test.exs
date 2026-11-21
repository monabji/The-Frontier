defmodule Mix.Tasks.Frontier.FetchTest do
  use Frontier.DataCase, async: false

  import ExUnit.CaptureIO

  alias Frontier.Sources.Run
  alias Mix.Tasks.Frontier.Fetch

  @ok %{
    source: "hn",
    label: "Hacker News",
    status: :ok,
    duration_ms: 12,
    fetched: 30,
    inserted: 30,
    updated: 0,
    skipped: 0,
    error: nil
  }

  @failed %{
    source: "rss:openai",
    label: "OpenAI",
    status: :error,
    duration_ms: 3,
    fetched: 0,
    inserted: 0,
    updated: 0,
    skipped: 0,
    error: ":timeout"
  }

  describe "format_report/1" do
    test "prints the counts for a source that worked" do
      line = Fetch.format_report(@ok)

      assert line =~ "hn"
      assert line =~ "30 fetched"
      assert line =~ "30 new"
      assert line =~ "0 refreshed"
      assert line =~ "12ms"
    end

    test "prints the failure for a source that did not" do
      line = Fetch.format_report(@failed)

      assert line =~ "rss:openai"
      assert line =~ "failed"
      assert line =~ ":timeout"
    end
  end

  describe "summary/1" do
    test "says what was stored when something worked" do
      assert Fetch.summary([@ok]) =~ "30 new"
    end

    test "says so plainly when every source failed" do
      assert Fetch.summary([@failed]) =~ "Every source failed"
    end
  end

  describe "run/1" do
    test "completes instead of aborting when every source fails" do
      output =
        capture_io(fn ->
          Fetch.run(["--source", "hn"])
        end)

      assert output =~ "The Frontier — fetch"
      assert output =~ "hn"
      assert output =~ "Every source failed"
      assert %Run{status: "error", source: "hn"} = Repo.get_by!(Run, source: "hn")
    end

    test "rejects a source it does not know" do
      assert_raise Mix.Error, ~r/unknown source/, fn ->
        Fetch.run(["--source", "nope"])
      end
    end
  end
end
