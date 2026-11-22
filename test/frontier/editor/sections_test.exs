defmodule Frontier.Editor.SectionsTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.Sections

  describe "the paper's sections" do
    test "are the eleven beats the plan names, in printing order" do
      assert Sections.names() == [
               "Front Page",
               "Models & Harnesses",
               "Research",
               "Security",
               "Game Development",
               "App Development",
               "FOSS",
               "DevOps",
               "Frontier Science",
               "Design",
               "Trending"
             ]
    end

    test "each has the cap the plan sets" do
      assert Sections.cap("Front Page") == 3
      assert Sections.cap("Models & Harnesses") == 3
      assert Sections.cap("Research") == 3
      assert Sections.cap("Security") == 2
      assert Sections.cap("Game Development") == 2
      assert Sections.cap("App Development") == 2
      assert Sections.cap("FOSS") == 2
      assert Sections.cap("DevOps") == 2
      assert Sections.cap("Frontier Science") == 2
      assert Sections.cap("Design") == 2
      assert Sections.cap("Trending") == 2
    end

    test "the caps leave room for twenty-one stories without filling every beat" do
      total = Sections.names() |> Enum.map(&Sections.cap/1) |> Enum.sum()

      assert total > 21
    end

    test "Also Today is a strip, not a section with a cap" do
      refute Sections.section?("Also Today")
      assert Sections.ticker_cap() == 5
    end

    test "the first Front Page entry is the lead, the rest are standard" do
      assert Sections.kind("Front Page", 1) == :lead
      assert Sections.kind("Front Page", 2) == :standard
      assert Sections.kind("Research", 1) == :standard
      assert Sections.kind("Security", 1) == :standard
      assert Sections.kind("Also Today", 1) == :ticker
    end
  end

  describe "word budgets" do
    test "a lead gets 140–175 words, a standard story 80–100, a ticker 12–18" do
      assert Sections.word_range(:lead) == 140..175
      assert Sections.word_range(:standard) == 80..100
      assert Sections.word_range(:ticker) == 12..18
    end

    test "a full paper of twenty-one stories reads in eight to ten minutes" do
      words = 150 + 20 * 85 + 20

      assert Sections.read_minutes(words) in 8..10
    end

    test "word count is words, not characters, and markup-free" do
      assert Sections.word_count("One two three, four.") == 4
      assert Sections.word_count("  spaced\twords\nhere ") == 3
      assert Sections.word_count("") == 0
      assert Sections.word_count(nil) == 0
    end
  end

  describe "read time" do
    test "a full paper of 1,800 words reads in about eight minutes" do
      assert Sections.read_minutes(1_800) == 8
    end

    test "2,200 words is ten minutes, and a short paper still says one" do
      assert Sections.read_minutes(2_200) == 10
      assert Sections.read_minutes(120) == 1
    end
  end
end
