defmodule Frontier.Sources.Text do
  @moduledoc """
  Turning a source's markup into text the paper could quote.

  Feeds send HTML bodies with entities, HN sends `<p>` and `<a href>` fragments.
  Whatever is stored has to be plain text, because phase 4 grounds a story's
  quote by looking for it inside this text: a quote that only exists between
  tags cannot be found.
  """

  # A feed item's body is kept as an excerpt, not as an article. The plan's
  # compliance rule is no full-text storage; 4,000 characters is enough to find
  # a sentence worth quoting and to judge what the item is about.
  @max_text 4_000

  @named_entities %{
    "amp" => "&",
    "apos" => "'",
    "gt" => ">",
    "hellip" => "…",
    "ldquo" => "“",
    "lsquo" => "‘",
    "lt" => "<",
    "mdash" => "—",
    "nbsp" => " ",
    "ndash" => "–",
    "quot" => "\"",
    "rdquo" => "”",
    "rsquo" => "’"
  }

  @doc """
  Plain text from markup, trimmed to the storage cap. `nil` stays `nil`.
  """
  @spec plain(String.t() | nil) :: String.t() | nil
  def plain(nil), do: nil

  def plain(html) when is_binary(html) do
    text =
      html
      |> String.replace(~r/<[^>]*>/u, " ")
      |> decode_entities()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    case text do
      "" -> nil
      text -> String.slice(text, 0, @max_text)
    end
  end

  def plain(_other), do: nil

  defp decode_entities(text) do
    Regex.replace(~r/&(#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z]+);/, text, fn whole, entity ->
      entity(entity) || whole
    end)
  end

  defp entity("#x" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp entity("#" <> decimal), do: codepoint(String.to_integer(decimal))
  defp entity(name), do: Map.get(@named_entities, name)

  defp codepoint(value) do
    if value in 1..0x10FFFF and value not in 0xD800..0xDFFF do
      <<value::utf8>>
    end
  end
end
