defmodule Frontier.RunsTest do
  use Frontier.DataCase, async: false

  alias Frontier.Runs

  @day ~D[2026-11-22]

  describe "a run's life" do
    test "starts running, finishes with counts and a duration, and is listed" do
      run = Runs.start("publish", @day)
      assert run.status == "running"

      finished = Runs.finish(run, inserted: 22, fetched: 120)

      assert finished.status == "ok"
      assert finished.inserted == 22
      assert finished.fetched == 120
      assert is_integer(finished.duration_ms)
      assert [^finished] = Runs.list(@day)
    end

    test "a failure keeps its reason" do
      run = Runs.start("daily", @day)
      failed = Runs.fail(run, {:editor_client, :timeout})

      assert failed.status == "error"
      assert failed.error =~ "editor_client"
    end

    test "a skipped run says why without being an error" do
      run = Runs.start("freeze", @day)
      skipped = Runs.skip(run, "no edition to freeze")

      assert skipped.status == "skipped"
      assert skipped.error == "no edition to freeze"
    end

    test "the log line names the stage, status, counts, duration and cost" do
      run =
        Runs.start("edit", @day)
        |> Runs.finish(
          inserted: 22,
          rejected: 2,
          duration_ms: 1_234,
          cost_micros: 420,
          model: "test-model"
        )

      line = Runs.format(run)

      assert line =~ "edit"
      assert line =~ "ok"
      assert line =~ "22 new"
      assert line =~ "2 rejected"
      assert line =~ "1234ms"
      assert line =~ "$0.000420"
    end

    test "the log lists only the day asked for" do
      Runs.start("publish", @day)
      Runs.start("publish", Date.add(@day, -1))

      assert length(Runs.list(@day)) == 1
    end
  end
end
