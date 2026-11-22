defmodule Frontier.Newsroom.Dateline do
  @moduledoc """
  The paper's calendar.

  An edition belongs to a day in India Standard Time, so the date line and the
  archive key must be the IST date, never the UTC one. India has a single fixed
  offset and no daylight saving, so UTC+05:30 is exact and needs no time zone
  database.
  """

  alias Frontier.Clock

  @ist_offset_seconds 5 * 3600 + 30 * 60
  @publish_hour 6

  @doc """
  The edition date for a moment in time: today in IST.

      iex> Frontier.Newsroom.Dateline.edition_date(~U[2026-11-21 18:29:00Z])
      ~D[2026-11-21]

      iex> Frontier.Newsroom.Dateline.edition_date(~U[2026-11-21 18:30:00Z])
      ~D[2026-11-22]
  """
  @spec edition_date(DateTime.t() | nil) :: Date.t()
  def edition_date(now \\ nil)

  def edition_date(nil), do: edition_date(Clock.now())

  def edition_date(%DateTime{} = now) do
    now
    |> DateTime.add(@ist_offset_seconds, :second)
    |> DateTime.to_date()
  end

  @doc """
  The UTC instants that bound an IST edition day.

  Stored rows carry UTC timestamps, but the paper's day is IST: the 22nd
  begins at 18:30 UTC on the 21st. Half-open — `start <= t < close` — so two
  consecutive days never both claim or both lose an item.
  """
  @spec day_bounds(Date.t()) :: {DateTime.t(), DateTime.t()}
  def day_bounds(%Date{} = date) do
    start =
      date
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-@ist_offset_seconds, :second)

    {start, DateTime.add(start, 86_400, :second)}
  end

  @doc """
  The moment an edition is due: 06:00 IST on its day, expressed in UTC.

  06:00 IST is 00:30 UTC; India has no daylight saving, so this is exact.
  """
  @spec deadline(Date.t()) :: DateTime.t()
  def deadline(%Date{} = date) do
    DateTime.new!(date, ~T[00:30:00], "Etc/UTC")
  end

  @doc "Whether the 06:00 edition for a day is due by `now`."
  @spec deadline_passed?(Date.t(), DateTime.t() | nil) :: boolean()
  def deadline_passed?(%Date{} = date, now \\ nil) do
    now = now || Clock.now()
    DateTime.compare(now, deadline(date)) != :lt
  end

  @doc "The hour the paper promises, in IST."
  @spec publish_hour() :: pos_integer()
  def publish_hour, do: @publish_hour

  @doc """
  A UTC instant shifted to the IST wall clock.

  The result still carries the UTC zone label with IST wall-clock fields; it is
  for formatting, not for arithmetic or storage. Use `edition_date/1` for the
  day and `day_bounds/1` for the instants.
  """
  @spec to_ist(DateTime.t()) :: DateTime.t()
  def to_ist(%DateTime{} = utc), do: DateTime.add(utc, @ist_offset_seconds, :second)

  @doc """
  A short IST date for a source line: the day the story was posted, as the
  reader's calendar counts it.

      iex> Frontier.Newsroom.Dateline.format_short(~U[2026-11-20 18:33:00Z])
      "21 Nov"
  """
  @spec format_short(DateTime.t()) :: String.t()
  def format_short(%DateTime{} = utc) do
    utc |> to_ist() |> Calendar.strftime("%-d %b")
  end

  @doc """
  Sets a date the way the paper prints it, without a zero-padded day.

      iex> Frontier.Newsroom.Dateline.format(~D[2026-11-22])
      "Sunday, 22 November 2026"
  """
  @spec format(Date.t()) :: String.t()
  def format(%Date{} = date), do: Calendar.strftime(date, "%A, %-d %B %Y")
end
