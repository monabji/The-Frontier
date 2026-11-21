defmodule Frontier.Newsroom.DemoEditionTest do
  use ExUnit.Case, async: true

  alias Frontier.Newsroom.DemoEdition

  setup do
    %{edition: DemoEdition.current()}
  end

  test "the lead runs to the paper's word budget", %{edition: edition} do
    assert word_count(edition.story.body) in 120..150
  end

  test "every field the page prints is present and non-empty", %{edition: edition} do
    story = edition.story

    assert is_integer(edition.number)
    assert edition.label != ""
    assert edition.section != ""
    assert story.headline != ""
    assert story.dek != ""
    assert story.body != []
    assert Enum.all?(story.body, &(String.trim(&1) != ""))
    assert story.quote.text != ""
    assert story.quote.attribution != ""
    assert story.source.name != ""
  end

  test "the source quote stays short enough to quote", %{edition: edition} do
    assert word_count([edition.story.quote.text]) in 1..45
  end

  test "the story links to its one source over https", %{edition: edition} do
    assert %URI{scheme: "https", host: host} = URI.parse(edition.story.source.url)
    assert host != nil
  end

  test "the headline and dek do not run past a lead's line budget", %{edition: edition} do
    assert String.length(edition.story.headline) <= 90
    assert String.length(edition.story.dek) <= 200
  end

  defp word_count(paragraphs) do
    paragraphs
    |> Enum.join(" ")
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
end
