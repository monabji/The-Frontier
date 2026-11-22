defmodule Frontier.Editor.Plain do
  @moduledoc """
  Reads the editor's plain line format back into a plan payload.

      STORY: 12
      SECTION: Security
      HEADLINE: A sentence-case headline
      SUMMARY: 80–100 words in one paragraph
      QUOTE: one verbatim sentence from the source text
      END

      DESK NOTE: one or two sentences

  This is the keyless envelope. A small model can hold a flat list of fields
  where it cannot reliably escape JSON: a misplaced quote in one story cannot
  corrupt the rest of the paper, and a missing field is just a missing field.
  The parser is forgiving about ordering, blank lines and code fences, and
  strict about nothing else — validation and grounding still decide what
  prints.
  """

  @fields %{
    "STORY" => "story_id",
    "SECTION" => "section",
    "HEADLINE" => "headline",
    "DEK" => "dek",
    "SUMMARY" => "summary",
    "QUOTE" => "quote"
  }

  @doc "Turns a plain reply into `%{\"desk_note\" => ..., \"entries\" => [...]}`."
  @spec parse(String.t() | nil) :: {:ok, map()} | {:error, :nothing_parsed}
  def parse(text) when is_binary(text) do
    lines =
      text
      |> strip_fence()
      |> String.split(~r/\r?\n/)

    {note, entries} = read(lines, nil, [], nil)

    entries = entries |> Enum.reverse() |> Enum.map(&finish/1) |> Enum.reject(&is_nil/1)

    if entries == [] do
      {:error, :nothing_parsed}
    else
      {:ok, %{"desk_note" => note, "entries" => entries, "also_today" => []}}
    end
  end

  def parse(_text), do: {:error, :nothing_parsed}

  @doc "The desk note alone, from a plain note reply."
  @spec desk_note(String.t() | nil) :: String.t() | nil
  def desk_note(text) when is_binary(text) do
    text
    |> strip_fence()
    |> String.split(~r/\r?\n/)
    |> Enum.find_value(fn line ->
      case split_field(line) do
        {"DESK NOTE", value} -> blank_to_nil(value)
        _other -> nil
      end
    end)
  end

  def desk_note(_text), do: nil

  defp read([], note, entries, current), do: {note, close(current, entries)}

  defp read([line | rest], note, entries, current) do
    case split_field(line) do
      {"DESK NOTE", value} ->
        read(rest, blank_to_nil(value) || note, entries, current)

      {"STORY", value} ->
        entries = close(current, entries)
        read(rest, note, entries, %{"story_id" => integer(value)})

      {key, value} when is_map_key(@fields, key) ->
        case current do
          nil -> read(rest, note, entries, nil)
          block -> read(rest, note, entries, Map.put(block, Map.fetch!(@fields, key), value))
        end

      {"END", _value} ->
        read(rest, note, entries, close(current, []))

      _other ->
        read(rest, note, entries, current)
    end
  end

  defp close(nil, entries), do: entries

  defp close(block, entries) do
    case finish(block) do
      nil -> entries
      entry -> [entry | entries]
    end
  end

  defp finish(block) when is_map(block) do
    if Map.get(block, "story_id") && Map.get(block, "section") && Map.get(block, "summary") do
      block
      |> Map.reject(fn {_key, value} -> blank?(value) end)
      |> Map.update("story_id", nil, & &1)
    end
  end

  defp finish(_block), do: nil

  defp split_field(line) do
    line = String.trim(line)

    case String.split(line, ":", parts: 2) do
      [key, value] -> {String.upcase(String.trim(key)), String.trim(value)}
      _other -> {nil, nil}
    end
  end

  defp strip_fence(text) do
    text = String.trim(text)

    case Regex.run(~r/\A```(?:[a-z]+)?\s*\n(.*)\n```\s*\z/s, text) do
      [_, inner] -> String.trim(inner)
      _other -> text
    end
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp integer(_value), do: nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
