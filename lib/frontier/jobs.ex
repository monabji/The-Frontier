defmodule Frontier.Jobs do
  @moduledoc """
  Small shared helpers for the scheduled workers.
  """

  alias Frontier.Newsroom.Dateline

  @doc "The day a job is for: its argument, or the IST edition day by default."
  @spec day(map(), Date.t()) :: Date.t()
  def day(args, default \\ Dateline.edition_date())

  def day(%{"day" => value}, _default) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, day} -> day
      {:error, _reason} -> raise ArgumentError, "job day is not a date: #{inspect(value)}"
    end
  end

  def day(_args, default), do: default
end
