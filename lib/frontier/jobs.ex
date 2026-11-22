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

  @doc """
  The day a scheduled job was *enqueued* for.

  A job delayed past IST midnight (a lifeline rescue, a restart, a long queue)
  must still act on the morning it belongs to. `inserted_at` is the enqueue
  time; the edition day is computed from that, not from when the worker finally
  runs. `offset` is -1 for the midnight freeze, which closes the day that just
  ended.
  """
  @spec scheduled_day(Oban.Job.t(), integer()) :: Date.t()
  def scheduled_day(%Oban.Job{args: args} = job, offset \\ 0) do
    case day_arg(args) do
      nil ->
        inserted_at = job.inserted_at || Frontier.Clock.now()
        Date.add(Frontier.Newsroom.Dateline.edition_date(inserted_at), offset)

      day ->
        day
    end
  end

  defp day_arg(%{"day" => value}) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, day} -> day
      {:error, _reason} -> raise ArgumentError, "job day is not a date: #{inspect(value)}"
    end
  end

  defp day_arg(_args), do: nil
end
