defmodule Frontier.Editor.Cost do
  @moduledoc """
  What an editor run cost, in whole micro-dollars.

  Prices are per million tokens, from configuration, because a provider can
  change them and the paper should say what it actually spent rather than guess.
  A run with no usage records zero: the number is reported, never invented.
  """

  @default_pricing %{input_per_million: 0.15, output_per_million: 0.60}

  @doc "Micro-dollars for a usage map, using the configured prices."
  @spec micros(map(), map()) :: non_neg_integer()
  def micros(usage, pricing \\ pricing()) do
    input = Map.get(usage, :input_tokens, 0) || 0
    output = Map.get(usage, :output_tokens, 0) || 0

    round(
      input * Map.fetch!(pricing, :input_per_million) +
        output * Map.fetch!(pricing, :output_per_million)
    )
  end

  @doc "Dollars, printed to six places so a cheap run is still visible."
  @spec format(non_neg_integer()) :: String.t()
  def format(micros) when is_integer(micros) do
    "$" <> :erlang.float_to_binary(micros / 1_000_000, decimals: 6)
  end

  @doc "The configured price per million tokens."
  @spec pricing() :: map()
  def pricing do
    Application.get_env(:frontier, :editor_pricing, @default_pricing)
  end
end
