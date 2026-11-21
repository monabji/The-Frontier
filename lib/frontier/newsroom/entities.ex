defmodule Frontier.Newsroom.Entities do
  @moduledoc """
  The names in a headline, found without a model.

  Clustering has to be deterministic and offline, so "the thing this story is
  about" is read off the title: runs of capitalised words, with numbers kept
  inside them ("Gemini 4 Neon", "Inkling 2 Mini"). Sentence-leading grammar —
  "The", "How", "Why" — is dropped, because it is not a subject.

  A name of one word is a company, and a company is not distinctive enough to
  merge two stories on: OpenAI ships several things a week. A name of two or
  more words, or one carrying a version, is.
  """

  @leading_words ~w(
    a an the this that these those it its in on at for to of and but or is are was were be
    been being can could will would should may might must do does did has have had
    how why what when where who which
    ask show tell hn new now just here there we you they i our your their
    after before during from into over under with without about across against
    top best first last more most less least no not
  )

  @doc """
  Distinctive names in a title, lowercased and in the order they appear.
  """
  @spec from_title(String.t() | nil) :: [String.t()]
  def from_title(title) when is_binary(title) do
    title
    |> tokenize()
    |> collect_runs()
    |> Enum.flat_map(&candidates/1)
    |> Enum.map(&join/1)
    |> Enum.uniq()
  end

  def from_title(_title), do: []

  @doc """
  Whether a name is specific enough to be a clustering signal.
  """
  @spec distinctive?(String.t()) :: boolean()
  def distinctive?(name) do
    case String.split(name, " ", trim: true) do
      [] -> false
      [single] -> versioned?(single)
      _many -> true
    end
  end

  # A run of capitalised words is one phrase on the page, but the name inside
  # it is not always the whole phrase: "Welcome Inkling 2 Mini" opens with a
  # sentence word. So every contiguous piece of the run is a candidate name,
  # and matching takes the shared one.
  defp candidates(run) do
    count = length(run)

    singles =
      run
      |> Enum.reject(&numeric?/1)
      |> Enum.map(&[&1])

    phrases =
      for start <- 0..(count - 1)//1,
          length <- 2..4//1,
          start + length <= count,
          do: Enum.slice(run, start, length)

    singles ++ phrases
  end

  defp tokenize(title) do
    Regex.scan(~r/[\p{L}\p{N}][\p{L}\p{N}+.\-]*/u, title) |> Enum.map(&hd/1)
  end

  defp collect_runs([]), do: []

  defp collect_runs([word | rest]) do
    if name_start?(word) do
      {run, remaining} = take_run([word], rest)
      [run | collect_runs(remaining)]
    else
      collect_runs(rest)
    end
  end

  # A name runs while the words are capitalised or numeric: "Gemini" + "4" +
  # "Neon" is one name; a lowercase verb ends it.
  defp take_run(run, [word | rest]) do
    if capitalised?(word) or numeric?(word) do
      take_run(run ++ [word], rest)
    else
      {run, [word | rest]}
    end
  end

  defp take_run(run, []), do: {run, []}

  defp name_start?(word) do
    capitalised?(word) and not leading?(word)
  end

  defp capitalised?(word) do
    case String.next_grapheme(word) do
      {grapheme, _rest} ->
        grapheme == String.upcase(grapheme) and grapheme != String.downcase(grapheme)

      nil ->
        false
    end
  end

  defp numeric?(word), do: Regex.match?(~r/\A[0-9]+(?:[.\-][0-9A-Za-z]+)*\z/, word)

  defp versioned?(word), do: Regex.match?(~r/\d/, word)

  defp leading?(word), do: String.downcase(word) in @leading_words

  defp join(words), do: words |> Enum.map(&String.downcase/1) |> Enum.join(" ")
end
