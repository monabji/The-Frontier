defmodule Frontier.Editor.PlanTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.Plan

  defp candidate(id, overrides \\ %{}) do
    Map.merge(
      %{
        id: id,
        headline: "Story #{id}",
        url: "https://example.com/#{id}",
        canonical_url: "https://example.com/#{id}",
        primary_source: "openai",
        source_label: "OpenAI",
        published_at: ~U[2026-11-22 04:00:00Z],
        score: nil,
        comments_count: nil,
        discussion_url: nil,
        text: "Story #{id} happened today."
      },
      overrides
    )
  end

  defp pool(count) do
    Enum.map(1..count, &candidate/1)
  end

  defp entry(id, overrides \\ %{}) do
    Map.merge(
      %{
        "story_id" => id,
        "section" => "Front Page",
        "headline" => "Headline #{id}",
        "dek" => "The one-line dek.",
        "summary" => String.duplicate("word ", 70),
        "quote" => "Story #{id} happened today."
      },
      overrides
    )
  end

  defp payload(entries, overrides \\ %{}) do
    Map.merge(
      %{
        "desk_note" => "A busy morning in models, and a quieter afternoon in research.",
        "entries" => entries,
        "also_today" => []
      },
      overrides
    )
  end

  describe "a well-formed plan" do
    test "becomes placed entries: first Front Page is the lead, the rest standard" do
      plan = Plan.validate(payload([entry(1), entry(2), entry(3)]), pool(3))

      assert plan.issues == []
      assert [lead, second, third] = plan.entries
      assert lead.kind == :lead
      assert lead.section == "Front Page"
      assert lead.position == 1
      assert second.kind == :standard
      assert second.position == 2
      assert third.position == 3
      assert plan.story_count == 3
    end

    test "entries print in section order, then the model's order inside a section" do
      entries = [
        entry(1, %{"section" => "Research"}),
        entry(2, %{"section" => "Front Page"}),
        entry(3, %{"section" => "Front Page"})
      ]

      plan = Plan.validate(payload(entries), pool(3))
      assert Enum.map(plan.entries, & &1.story_id) == [2, 3, 1]
      assert Enum.map(plan.entries, & &1.kind) == [:lead, :standard, :standard]
    end

    test "the entry carries the story's link and provenance from the pool" do
      story =
        candidate(1, %{
          score: 120,
          comments_count: 45,
          discussion_url: "https://news.ycombinator.com/item?id=1"
        })

      [entry] = Plan.validate(payload([entry(1)]), [story]).entries

      assert entry.url == "https://example.com/1"
      assert entry.canonical_url == "https://example.com/1"
      assert entry.primary_source == "openai"
      assert entry.discussion_url == "https://news.ycombinator.com/item?id=1"
      assert entry.score == 120
      assert entry.comments_count == 45
      assert entry.word_count == 70
    end
  end

  describe "once only" do
    test "the same story cannot print twice" do
      plan = Plan.validate(payload([entry(1), entry(1, %{"headline" => "Again"})]), pool(3))

      assert length(plan.entries) == 1
      assert {:dropped, 1, :duplicate} in plan.issues
    end

    test "a story in a section cannot also be a ticker" do
      plan =
        Plan.validate(
          payload([entry(1)], %{"also_today" => [entry(1)]}),
          pool(3)
        )

      assert plan.tickers == []
      assert {:dropped, 1, :duplicate} in plan.issues
    end
  end

  describe "the page's shape" do
    test "a section over its cap keeps the first entries and drops the rest" do
      entries = Enum.map(1..5, &entry(&1, %{"section" => "Research"}))
      plan = Plan.validate(payload(entries), pool(5))

      assert length(plan.entries) == 3
      assert Enum.map(plan.entries, & &1.story_id) == [1, 2, 3]
      assert {:dropped, 4, :section_over_cap} in plan.issues
    end

    test "Also Today is capped at fifteen" do
      tickers =
        Enum.map(1..17, &entry(&1, %{"section" => "Also Today", "summary" => "A short line."}))

      plan =
        Plan.validate(
          payload([], %{"also_today" => tickers}),
          pool(20)
        )

      assert length(plan.tickers) == 15
      assert plan.tickers |> List.first() |> Map.get(:kind) == :ticker
      assert {:dropped, 16, :ticker_over_cap} in plan.issues
    end

    test "an unknown section is dropped, never printed" do
      plan = Plan.validate(payload([entry(1, %{"section" => "Sports"})]), pool(3))

      assert plan.entries == []
      assert {:dropped, 1, {:unknown_section, "Sports"}} in plan.issues
    end

    test "a story that is not in the pool is dropped" do
      plan = Plan.validate(payload([entry(99)]), pool(3))
      assert plan.entries == []
      assert {:dropped, 99, :unknown_story} in plan.issues
    end

    test "a full pool must produce a full paper" do
      plan = Plan.validate(payload([entry(1)]), pool(30))
      assert {:too_short, 1, 22} in plan.issues
    end

    test "a quiet day is allowed to be short" do
      plan = Plan.validate(payload([entry(1), entry(2)]), pool(6))
      refute Enum.any?(plan.issues, fn issue -> match?({:too_short, _, _}, issue) end)
      assert plan.story_count == 2
    end

    test "a missing desk note is an issue, not an empty page" do
      assert {:desk_note, :missing} in Plan.validate(
               payload([entry(1)], %{"desk_note" => nil}),
               pool(3)
             ).issues
    end
  end
end
