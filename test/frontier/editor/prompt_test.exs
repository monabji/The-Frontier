defmodule Frontier.Editor.PromptTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.Prompt

  @day ~D[2026-11-22]

  defp candidate(id, text \\ nil) do
    text = text || "Quokka#{id} Zephyr#{id} opened a bakery in Lisbon today."

    %{
      id: id,
      headline: "Quokka#{id} Zephyr#{id} opens a bakery",
      url: "https://example.com/#{id}",
      primary_source: "rss:openai",
      source_label: "OpenAI",
      published_at: ~U[2026-11-22 04:00:00Z],
      text: text
    }
  end

  describe "the brief" do
    test "carries the sections, caps and word budgets the plan sets" do
      [%{role: "system"}, %{role: "user", content: brief}] =
        Prompt.messages(@day, [candidate(1)])

      assert brief =~ "Front Page: 3"
      assert brief =~ "The Long Read: 1"
      assert brief =~ "120–150 words"
      assert brief =~ "60–80 words"
      assert brief =~ "12–18 words"
      assert brief =~ "maximum 15 entries"
      assert brief =~ "Sunday, 22 November 2026"
    end

    test "carries the quote rule and the output shape" do
      [%{content: system}, %{content: brief}] = Prompt.messages(@day, [candidate(1)])

      assert system =~ "never invent"
      assert brief =~ "character-for-character"
      assert brief =~ "no ellipses"
      assert brief =~ ~s("story_id")
      assert brief =~ ~s("desk_note")
    end

    test "carries each candidate's id, link and source text" do
      [%{content: _system}, %{content: brief}] =
        Prompt.messages(@day, [candidate(7, "A uniquely quotable sentence.")])

      assert brief =~ "id=7"
      assert brief =~ "https://example.com/7"
      assert brief =~ "A uniquely quotable sentence."
      assert brief =~ "OpenAI"
    end
  end

  describe "the repair brief" do
    test "names the failed entry, the reason, and its source text" do
      failed = %{
        entry: %{
          story_id: 7,
          section: "Front Page",
          headline: "A headline",
          summary: "A summary",
          quote: "A fabricated quote"
        },
        reasons: [:quote_not_in_source]
      }

      problem = %{failures: [failed], too_short: nil, desk_note: nil, chosen_ids: MapSet.new([7])}

      [%{content: _}, %{content: brief}] =
        Prompt.repair_messages(
          @day,
          [candidate(7, "The real sentence from the source.")],
          problem
        )

      assert brief =~ "repair pass"
      assert brief =~ "quote is not a substring"
      assert brief =~ "The real sentence from the source."
    end

    test "a short paper asks for more and lists unselected candidates" do
      problem = %{
        failures: [],
        too_short: {10, 22},
        desk_note: nil,
        chosen_ids: MapSet.new([1, 2])
      }

      candidates = Enum.map(1..4, &candidate/1)
      [%{content: _}, %{content: brief}] = Prompt.repair_messages(@day, candidates, problem)

      assert brief =~ "The paper is short"
      assert brief =~ "Add 12 more"

      [_before, unselected] = String.split(brief, "## The paper is short", parts: 2)
      assert unselected =~ "id=3"
      refute unselected =~ "id=1"
    end
  end
end
