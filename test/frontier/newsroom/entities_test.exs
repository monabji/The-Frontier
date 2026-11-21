defmodule Frontier.Newsroom.EntitiesTest do
  use ExUnit.Case, async: true

  alias Frontier.Newsroom.Entities

  describe "from_title/1" do
    test "finds the named thing in a headline" do
      assert "inkling 2 mini" in Entities.from_title("Thinking Machines releases Inkling 2 Mini")

      assert "thinking machines" in Entities.from_title(
               "Thinking Machines releases Inkling 2 Mini"
             )
    end

    test "keeps version numbers inside a name" do
      entities = Entities.from_title("Gemini 4 Neon is now available")

      assert "gemini 4 neon" in entities
      assert "gemini 4" in entities
    end

    test "does not treat a sentence's first word as a name" do
      assert Entities.from_title("The model that runs on a laptop") == []
      assert Entities.from_title("How we cut inference costs") == []
    end

    test "normalises case and punctuation" do
      assert Entities.from_title("OPENAI ships GPT-5?") == ["openai", "gpt-5"]
      # "GPT-5" keeps its version; the sentence's first word is not a name.
      assert Entities.from_title("Qwen3.8-27B tops the chart") == ["qwen3.8-27b"]
    end

    test "finds several names in one headline" do
      entities = Entities.from_title("Anthropic and OpenAI respond to the EU AI Act")

      assert "anthropic" in entities
      assert "openai" in entities
      assert "eu ai act" in entities
    end

    test "a name made of one word is not distinctive enough on its own" do
      [entity] = Entities.from_title("OpenAI announces a partnership")

      refute Entities.distinctive?(entity)
    end

    test "a multi-word or versioned name is distinctive" do
      assert Entities.distinctive?("inkling 2 mini")
      assert Entities.distinctive?("gemini 4 neon")
      assert Entities.distinctive?("thinking machines")
      refute Entities.distinctive?("openai")
      refute Entities.distinctive?("the")
    end

    test "an empty or unknown title yields nothing" do
      assert Entities.from_title(nil) == []
      assert Entities.from_title("") == []
      assert Entities.from_title("lowercase words only") == []
    end
  end
end
