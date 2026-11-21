defmodule Frontier.Fixtures do
  @moduledoc """
  Recorded source payloads, loaded from disk.

  Tests never reach the network: an adapter's client is injected, and what it
  returns is one of these files.
  """

  @fixtures "test/fixtures"

  @spec load!(String.t()) :: map()
  def load!(path) do
    @fixtures
    |> Path.join(path)
    |> File.read!()
    |> Jason.decode!()
  end

  @spec hn_front_page() :: map()
  def hn_front_page, do: load!("hn/front_page.json")

  @spec rss_fixture(String.t()) :: String.t()
  def rss_fixture(file), do: Path.join(@fixtures, "rss/" <> file) |> File.read!()
end
