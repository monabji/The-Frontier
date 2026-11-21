defmodule Frontier.Newsroom.DatelineTest do
  use ExUnit.Case, async: true

  alias Frontier.Newsroom.Dateline

  describe "edition_date/1" do
    test "a UTC evening before midnight IST is still today's edition" do
      assert Dateline.edition_date(~U[2026-11-21 18:29:59Z]) == ~D[2026-11-21]
    end

    test "the edition rolls over at midnight IST, not midnight UTC" do
      assert Dateline.edition_date(~U[2026-11-21 18:30:00Z]) == ~D[2026-11-22]
    end

    test "the 06:00 IST publish falls on the same edition date" do
      assert Dateline.edition_date(~U[2026-11-22 00:30:00Z]) == ~D[2026-11-22]
    end

    test "a UTC day that is still the same IST day" do
      assert Dateline.edition_date(~U[2026-11-22 12:00:00Z]) == ~D[2026-11-22]
    end

    test "a late UTC night is already tomorrow in IST" do
      assert Dateline.edition_date(~U[2026-11-22 18:30:00Z]) == ~D[2026-11-23]
    end
  end

  describe "day_bounds/1" do
    test "an IST day runs from 18:30 UTC the evening before" do
      assert Dateline.day_bounds(~D[2026-11-22]) ==
               {~U[2026-11-21 18:30:00Z], ~U[2026-11-22 18:30:00Z]}
    end

    test "consecutive days meet without a gap or an overlap" do
      {_start, close} = Dateline.day_bounds(~D[2026-11-22])
      {next_start, _close} = Dateline.day_bounds(~D[2026-11-23])

      assert close == next_start
    end

    test "the instant an edition rolls over is the new day's first instant" do
      {start, _close} = Dateline.day_bounds(~D[2026-11-22])

      assert Dateline.edition_date(start) == ~D[2026-11-22]
      assert Dateline.edition_date(DateTime.add(start, -1, :second)) == ~D[2026-11-21]
    end
  end

  describe "format_short/1" do
    test "prints the IST day a story was posted, not the UTC one" do
      assert Dateline.format_short(~U[2026-11-20 18:33:00Z]) == "21 Nov"
    end

    test "leaves a midday UTC time on the same day" do
      assert Dateline.format_short(~U[2026-11-20 12:00:00Z]) == "20 Nov"
    end
  end

  describe "format/1" do
    test "sets the date line the way the paper prints it" do
      assert Dateline.format(~D[2026-11-22]) == "Sunday, 22 November 2026"
    end

    test "single-digit days are not zero-padded" do
      assert Dateline.format(~D[2026-11-01]) == "Sunday, 1 November 2026"
    end
  end
end
