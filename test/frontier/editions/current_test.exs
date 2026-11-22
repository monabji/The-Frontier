defmodule Frontier.Editions.CurrentTest do
  use ExUnit.Case, async: false

  alias Frontier.EditionStorage
  alias Frontier.Editions
  alias Frontier.Editions.{Artifact, Edition, Entry, Store}

  @today ~D[2026-11-22]
  @yesterday ~D[2026-11-21]
  @after_deadline ~U[2026-11-22 01:00:00Z]
  @before_deadline ~U[2026-11-21 23:00:00Z]

  setup do
    EditionStorage.tmp!()
  end

  defp write(day, status) do
    entry = %Entry{
      section: "Front Page",
      position: 1,
      kind: "lead",
      headline: "The #{day} headline",
      summary: "A summary.",
      quote: "A quote.",
      url: "https://example.com/#{day}",
      canonical_url: "https://example.com/#{day}",
      source_label: "OpenAI",
      word_count: 2
    }

    artifact =
      Artifact.build(%Edition{
        day: day,
        status: status,
        desk_note: "The paper of #{day}.",
        read_minutes: 9,
        word_count: 1_900,
        story_count: 1,
        entries: [entry]
      })

    {:ok, _} = Store.write(artifact, "<html></html>")
    artifact
  end

  describe "a normal morning" do
    test "today's published edition is the paper, with no banner" do
      write(@today, "published")
      current = Editions.current(@after_deadline)

      assert current.artifact.day == @today
      refute current.delayed
      assert current.expected_day == @today
    end

    test "before 06:00 yesterday's edition is simply the current paper" do
      write(@yesterday, "published")
      current = Editions.current(@before_deadline)

      assert current.artifact.day == @yesterday
      refute current.delayed
      assert current.expected_day == @today
    end
  end

  describe "a late morning" do
    test "after 06:00 the previous edition is served with a delayed flag" do
      write(@yesterday, "published")
      current = Editions.current(@after_deadline)

      assert current.artifact.day == @yesterday
      assert current.delayed
      assert current.expected_day == @today
    end

    test "today's draft does not hide yesterday's published paper" do
      write(@yesterday, "published")
      write(@today, "draft")

      current = Editions.current(@after_deadline)

      assert current.artifact.day == @yesterday
      assert current.delayed
    end

    test "a future artifact is not the paper" do
      write(@yesterday, "published")
      write(Date.add(@today, 1), "published")

      assert Editions.current(@after_deadline).artifact.day == @yesterday
    end
  end

  describe "the press being installed" do
    test "a draft is previewed when nothing has ever been published" do
      write(@today, "draft")
      current = Editions.current(@after_deadline)

      assert current.artifact.day == @today
      refute current.delayed
    end

    test "no artifact means the pool fallback, not a delayed edition" do
      current = Editions.current(@after_deadline)

      assert current.artifact == nil
      refute current.delayed
    end
  end
end
