defmodule Frontier.Clock do
  @moduledoc """
  The paper's clock, in one place.

  Every scheduled decision — which edition day it is, whether 06:00 has passed,
  when to freeze — reads time through here. Production uses the system clock;
  a test can set a function and prove the morning it means to.
  """

  @spec now() :: DateTime.t()
  def now do
    case Application.get_env(:frontier, :clock) do
      nil -> DateTime.utc_now() |> DateTime.truncate(:second)
      clock when is_function(clock, 0) -> clock.() |> DateTime.truncate(:second)
    end
  end
end
