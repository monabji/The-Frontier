defmodule Frontier.Editor.Sections do
  @moduledoc """
  The paper's fixed furniture: eleven sections, their caps, and the word budgets
  that make an edition read in eight to ten minutes.

  A section is a beat, not a format: models, AI research, security, game
  development, app development, open source, DevOps, frontier science, design
  and what technology is arguing about today. Front Page is where the day's
  three biggest stories sit, whatever their beat.

  These numbers are editorial, not technical. They live here so the prompt, the
  plan check and the read-time estimate cannot drift apart: a section that is
  full is full, and a summary that is long is sent back rather than printed.
  """

  @names [
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

  @caps %{
    "Front Page" => 3,
    "Models & Harnesses" => 3,
    "Research" => 3,
    "Security" => 2,
    "Game Development" => 2,
    "App Development" => 2,
    "FOSS" => 2,
    "DevOps" => 2,
    "Frontier Science" => 2,
    "Design" => 2,
    "Trending" => 2
  }

  @ticker_cap 5
  @words_per_minute 220

  @word_ranges %{lead: 140..175, standard: 80..100, ticker: 12..18}

  @doc "The eleven sections, in the order the paper prints them."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "How many stories a section may hold."
  @spec cap(String.t()) :: non_neg_integer()
  def cap(section), do: Map.get(@caps, section, 0)

  @doc "Whether a name is one of the paper's sections."
  @spec section?(String.t()) :: boolean()
  def section?(section), do: section in @names

  @doc "The most one-line items Also Today may carry."
  @spec ticker_cap() :: non_neg_integer()
  def ticker_cap, do: @ticker_cap

  @doc """
  What an entry is: the lead is the first Front Page story, everything else in
  a section is standard, and Also Today is a ticker.
  """
  @spec kind(String.t(), pos_integer()) :: :lead | :standard | :ticker
  def kind("Also Today", _position), do: :ticker
  def kind("Front Page", 1), do: :lead
  def kind(_section, _position), do: :standard

  @doc "The summary budget for a kind of entry."
  @spec word_range(:lead | :standard | :ticker) :: Range.t()
  def word_range(kind), do: Map.fetch!(@word_ranges, kind)

  @doc "Words in a piece of copy; markup-free text is assumed."
  @spec word_count(String.t() | nil) :: non_neg_integer()
  def word_count(nil), do: 0

  def word_count(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> length()
  end

  @doc """
  Minutes to read a number of words, at newspaper speed. Always at least one:
  a short paper is still a paper.
  """
  @spec read_minutes(non_neg_integer()) :: pos_integer()
  def read_minutes(words) when is_integer(words) do
    max(1, round(words / @words_per_minute))
  end
end
