defmodule Frontier.Editor.SectionsTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.Sections

  describe "the paper's sections" do
    test "are the seven the plan names, in printing order" do
      assert Sections.names() == [
               "Front Page",
               "Models & Releases",
               "Research",
               "Tooling & Dev",
               "The Discourse",
               "The Long Read",
               "Back Page"
             ]
    end

    test "each has the cap the plan sets" do
      assert Sections.cap("Front Page") == 3
      assert Sections.cap("Models & Releases") == 4
      assert Sections.cap("Research") == 3
      assert Sections.cap("Tooling & Dev") == 4
      assert Sections.cap("The Discourse") == 3
      assert Sections.cap("The Long Read") == 1
      assert Sections.cap("Back Page") == 4
    end

    test "Also Today is a strip, not a section with a cap" do
      refute Sections.section?("Also Today")
      assert Sections.ticker_cap() == 15
    end

    test "the first Front Page entry is the lead, the rest are standard" do
      assert Sections.kind("Front Page", 1) == :lead
      assert Sections.kind("Front Page", 2) == :standard
      assert Sections.kind("Research", 1) == :standard
      assert Sections.kind("Also Today", 1) == :ticker
    end
  end

  describe "word budgets" do
    test "a lead gets 120–150 words, a standard story 60–80, a ticker 12–18" do
      assert Sections.word_range(:lead) == 120..150
      assert Sections.word_range(:standard) == 60..80
      assert Sections.word_range(:ticker) == 12..18
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
