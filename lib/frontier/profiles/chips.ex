defmodule Frontier.Profiles.Chips do
  @moduledoc """
  The eight interests a new reader can express.

  Chips are the only place a reader states taste before reading anything, so
  they are broad enough to shape a fold without asking for a biography. Labels
  are printed; keys are stored in the profile document.
  """

  @chips [
    {"models", "Models & releases"},
    {"research", "Research"},
    {"tooling", "Tools & code"},
    {"policy", "Policy & law"},
    {"startups", "Startups & money"},
    {"hardware", "Chips & hardware"},
    {"security", "Security"},
    {"culture", "Culture & argument"}
  ]

  @doc "Every chip as `{key, label}`, in the order the onboarding prints them."
  @spec all() :: [{String.t(), String.t()}]
  def all, do: @chips

  @doc "The chip keys."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(@chips, &elem(&1, 0))

  @doc "Whether a key is one of the chips."
  @spec valid?(String.t()) :: boolean()
  def valid?(key), do: key in keys()

  @doc "The printed label for a key, falling back to the key."
  @spec label(String.t()) :: String.t()
  def label(key) do
    Enum.find_value(@chips, key, fn {candidate, label} ->
      if candidate == key, do: label
    end)
  end
end
