defmodule Frontier.Editor.GroundingTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.Grounding

  @source """
  OpenAI said the model is available today in the API and in ChatGPT.
  “Astra is our most capable model yet,” the company wrote, “and it is
  available to every developer from today.”
  """

  describe "the quote is a substring of the source text" do
    test "a verbatim sentence passes" do
      assert :ok =
               Grounding.check_quote(
                 "Astra is our most capable model yet,",
                 @source
               )
    end

    test "typographic variants of quotes and dashes still count as verbatim" do
      assert :ok =
               Grounding.check_quote(
                 "\"Astra is our most capable model yet,\" the company wrote",
                 @source
               )
    end

    test "a hallucinated quote is rejected, not printed" do
      assert {:error, :quote_not_in_source} =
               Grounding.check_quote(
                 "Astra is our most powerful model ever built.",
                 @source
               )
    end

    test "a quote cannot be one invented word" do
      assert {:error, :quote_too_short} = Grounding.check_quote("Astra", @source)
      assert {:error, :quote_missing} = Grounding.check_quote(nil, @source)
      assert {:error, :source_text_missing} = Grounding.check_quote("Astra is great", nil)
    end
  end

  describe "quote candidates" do
    test "the first candidate that grounds is used" do
      assert {:ok, "Astra is our most capable model yet,"} =
               Grounding.choose_quote(
                 [
                   "A sentence that the source never contained.",
                   "Astra is our most capable model yet,"
                 ],
                 @source
               )
    end

    test "no candidate grounding is a failure" do
      assert {:error, :quote_not_in_source} =
               Grounding.choose_quote(
                 ["Invented one.", "Invented two, with more words."],
                 @source
               )
    end
  end

  describe "the headline's names are in the source" do
    test "every distinctive name appears in the text" do
      assert :ok =
               Grounding.check_entities(
                 "GPT-6.2 Astra opens to every developer",
                 @source <> " GPT-6.2 Astra opens to every developer."
               )
    end

    test "a name the source never mentions fails, and the failure names it" do
      assert {:error, {:missing_entities, ["gemini 4 neon"]}} =
               Grounding.check_entities("Gemini 4 Neon ships", @source)
    end

    test "hyphenation and case do not matter, but a different name does" do
      assert :ok = Grounding.check_entities("Inkling-2-Mini ships", "INKLING 2 MINI ships today")
      refute :ok == Grounding.check_entities("Inkling 2 Mini ships", "Inkling 2 ships today")
    end
  end

  describe "word budgets" do
    test "a summary inside the budget passes" do
      assert :ok = Grounding.check_words(String.duplicate("word ", 85), :standard)
    end

    test "a summary over or under the budget is returned, with the count" do
      assert {:error, {:summary_words, 50, 80..100}} =
               Grounding.check_words(String.duplicate("word ", 50), :standard)

      assert {:error, {:summary_words, 200, 140..175}} =
               Grounding.check_words(String.duplicate("word ", 200), :lead)
    end
  end

  describe "links resolve" do
    test "a link the checker resolves passes" do
      checker = fn _url -> {:ok, "https://example.com/article"} end

      assert {:ok, "https://example.com/article"} =
               Grounding.check_link("https://example.com/x", checker)
    end

    test "a dead link drops the story" do
      checker = fn _url -> {:error, {:http_status, 404, "Not Found"}} end

      assert {:error, {:unresolved_link, _reason}} =
               Grounding.check_link("https://example.com/x", checker)
    end
  end

  describe "the HTTP link checker" do
    test "the injected result follows the same status rule" do
      forbidden = fn _url -> {:error, {:http_status, 403, "Forbidden"}} end
      missing = fn _url -> {:error, {:http_status, 404, "Not Found"}} end

      assert {:ok, "https://example.com/x"} =
               Grounding.resolve_link("https://example.com/x", forbidden)

      assert {:error, {:unresolved_link, {:http_status, 404}}} =
               Grounding.resolve_link("https://example.com/x", missing)
    end

    test "a 200 is alive; 403, 405 and 429 are a live server, not death" do
      assert :ok = Grounding.http_link(200)
      assert :ok = Grounding.http_link(403)
      assert :ok = Grounding.http_link(405)
      assert :ok = Grounding.http_link(429)
    end

    test "a 404 or 410 is a dead story" do
      assert {:error, {:http_status, 404}} = Grounding.http_link(404)
      assert {:error, {:http_status, 410}} = Grounding.http_link(410)
    end
  end
end
