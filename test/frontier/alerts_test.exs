defmodule Frontier.AlertsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Frontier.Alerts
  alias Frontier.Alerts.Webhook

  describe "sending" do
    test "the configured adapter receives the level, title and body" do
      test = self()

      assert :ok =
               Alerts.alert(:error, "The 06:00 edition is late", "No draft.",
                 adapter: fn level, title, body ->
                   send(test, {:alert, level, title, body})
                 end
               )

      assert_received {:alert, :error, "The 06:00 edition is late", "No draft."}
    end

    test "a failing adapter is logged, never raised into the run" do
      log =
        capture_log(fn ->
          assert :ok =
                   Alerts.alert(:error, "title", "body",
                     adapter: fn _l, _t, _b -> raise "no channel" end
                   )
        end)

      assert log =~ "adapter failed"
    end

    test "the log adapter always exists" do
      log =
        capture_log(fn ->
          assert :ok = Alerts.Log.send(:warning, "Late", "The paper is late.")
        end)

      assert log =~ "Late"
    end
  end

  describe "the Telegram payload" do
    test "names the chat and carries the title and body" do
      payload =
        Webhook.telegram_payload("12345", "The 06:00 edition is late", "No draft was written.")

      assert payload.chat_id == "12345"
      assert payload.parse_mode == "HTML"
      assert payload.text =~ "The 06:00 edition is late"
      assert payload.text =~ "No draft was written."
    end
  end
end
