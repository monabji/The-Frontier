defmodule Frontier.ScheduleTest do
  use ExUnit.Case, async: true

  describe "the paper's clock" do
    test "fetch is 05:15 IST, publish 06:00, freeze 00:05" do
      schedule = Application.get_env(:frontier, :schedule)

      assert schedule.daily_ist == "05:15"
      assert schedule.publish_ist == "06:00"
      assert schedule.freeze_ist == "00:05"
    end

    test "the cron expressions are the same instants in UTC" do
      schedule = Application.get_env(:frontier, :schedule)

      # India is UTC+05:30 with no daylight saving, so the expressions never
      # need a timezone database and never drift.
      assert schedule.daily == "45 23 * * *"
      assert schedule.publish == "30 0 * * *"
      assert schedule.freeze == "35 18 * * *"
    end
  end
end
