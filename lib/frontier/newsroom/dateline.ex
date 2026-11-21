defmodule Frontier.Newsroom.Dateline do
  @moduledoc """
  The paper's calendar.

  An edition belongs to a day in India Standard Time, so the date line and the
  archive key must be the IST date, never the UTC one. India has a single fixed
  offset and no daylight saving, so UTC+05:30 is exact and needs no time zone
  database.
  """

  @ist_offset_seconds 5 * 3600 + 30 * 60

  @doc """
  The edition date for a moment in time: today in IST.

      iex> Frontier.Newsroom.Dateline.edition_date(~U[2026-11-21 18:29:00Z])
      ~D[2026-11-21]

      iex> Frontier.Newsroom.Dateline.edition_date(~U[2026-11-21 18:30:00Z])
      ~D[2026-11-22]
  """
  @spec edition_date(Calendar.datetime() | nil) :: Date.t()
  def edition_date(now \\ nil)

  def edition_date(nil), do: edition_date(DateTime.utc_now())

  def edition_date(%DateTime{} = now) do
    now
    |> DateTime.add(@ist_offset_seconds, :second)
    |> DateTime.to_date()
  end

  @doc """
  Sets a date the way the paper prints it, without a zero-padded day.

      iex> Frontier.Newsroom.Dateline.format(~D[2026-11-22])
      "Sunday, 22 November 2026"
  """
  @spec format(Date.t()) :: String.t()
  def format(%Date{} = date), do: Calendar.strftime(date, "%A, %-d %B %Y")
end
