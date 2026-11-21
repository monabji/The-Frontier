defmodule Frontier.ObanTest do
  use Frontier.DataCase, async: false

  test "Oban runs on SQLite's Lite engine against the app repo" do
    config = Oban.config()

    assert config.engine == Oban.Engines.Lite
    assert config.repo == Frontier.Repo
  end

  test "tests never run jobs or plugins" do
    config = Oban.config()

    assert config.testing == :manual
    assert config.queues == []
    assert config.plugins == []
  end

  test "the oban_jobs table is migrated and empty" do
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM oban_jobs")
  end
end
