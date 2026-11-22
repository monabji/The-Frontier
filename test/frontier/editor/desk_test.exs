defmodule Frontier.Editor.DeskTest do
  use Frontier.DataCase, async: false

  alias Frontier.{EditionStorage, Editions}
  alias Frontier.Editor.Desk
  alias Frontier.EditorFixtures

  @day ~D[2026-11-22]

  setup do
    EditionStorage.tmp!(%{})
    stories = EditorFixtures.seed_stories(32)
    candidates = EditorFixtures.candidates(stories)
    %{candidates: candidates, payload: EditorFixtures.payload(candidates)}
  end

  defp links_ok, do: fn _url -> {:ok, "https://example.com/final"} end

  describe "the brief" do
    test "carries the whole editor prompt and the day's candidates" do
      brief = Desk.brief(@day, limit: 5)

      assert brief.candidates == 5
      assert brief.prompt =~ "Front Page: 3"
      assert brief.prompt =~ "Choose 21 stories"
      assert brief.prompt =~ "character-for-character"
      assert brief.prompt =~ "id="
    end
  end

  describe "a pasted edition" do
    test "is grounded, assembled and recorded as the desk's", %{payload: payload} do
      assert {:ok, %{edition: edition, report: report}} =
               Desk.submit(@day, Jason.encode!(payload),
                 link_checker: links_ok(),
                 assistant: "claude"
               )

      assert report.printed == 21
      assert report.model == "desk:claude"
      assert edition.status == "draft"
      assert length(edition.entries) == 26
      assert Editions.artifact(@day) != nil
    end

    test "still drops a quote the source does not contain", %{payload: payload} do
      [first | rest] = payload["entries"]
      bad = Map.put(first, "quote", "A sentence that nobody in the pool ever wrote.")
      payload = %{payload | "entries" => [bad | rest]}

      assert {:ok, %{edition: edition, report: report}} =
               Desk.submit(@day, Jason.encode!(payload), link_checker: links_ok())

      assert report.printed == 20
      refute Enum.any?(edition.entries, &(&1.story_id == first["story_id"]))
    end

    test "refuses an unreadable reply" do
      assert {:error, {:editor_client, {:reply_not_json, _reason}}} =
               Desk.submit(@day, "Sorry, I can't do that.", link_checker: links_ok())

      assert Desk.explain({:editor_client, {:reply_not_json, :error}}) =~ "not JSON"
    end

    test "refuses a day that is already published", %{payload: payload} do
      assert {:ok, _result} =
               Desk.submit(@day, Jason.encode!(payload), link_checker: links_ok())

      assert {:ok, _edition} = Editions.publish(@day)

      assert {:error, {:edition_is_locked, @day}} =
               Desk.submit(@day, Jason.encode!(payload), link_checker: links_ok())
    end
  end
end
