defmodule Frontier.ClockTest do
  use ExUnit.Case, async: false

  alias Frontier.Clock

  test "uses a configured clock and falls back to the system clock for nonsense" do
    previous = Application.get_env(:frontier, :clock)

    Application.put_env(:frontier, :clock, fn -> ~U[2026-11-22 01:02:03Z] end)
    assert Clock.now() == ~U[2026-11-22 01:02:03Z]

    Application.put_env(:frontier, :clock, :not_a_function)
    assert %DateTime{} = Clock.now()

    on_exit(fn ->
      if previous do
        Application.put_env(:frontier, :clock, previous)
      else
        Application.delete_env(:frontier, :clock)
      end
    end)
  end
end
