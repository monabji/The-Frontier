defmodule Mix.Tasks.Frontier.Assemble do
  @shortdoc "Builds the day's artifact from its edition"

  @moduledoc """
  Freezes the day's draft into a content-addressed artifact.

      mix frontier.assemble
      mix frontier.assemble --day 2026-11-22

  Writes the JSON and HTML bundle under `priv/editions/<day>/`, points the day
  at it, and prints the hash. Assembling the same inputs again produces the
  same hash; a changed edition produces a new version and leaves the old one on
  disk. A frozen day is refused.
  """

  use Mix.Task

  alias Frontier.{Editions, Runs}

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])
    run = Runs.start("assemble", day)

    case Editions.assemble(day) do
      {:ok, %{artifact: artifact, stored: stored}} ->
        Runs.finish(run, inserted: artifact.stats["stories"])
        Mix.shell().info("The Frontier — assemble, #{day}")
        Mix.shell().info("  #{artifact.status}, #{stats(artifact)}")
        Mix.shell().info("  #{stored.hash}")
        Mix.shell().info("  #{stored.json_path}")
        Mix.shell().info("  #{path(day)} · /archive")

      {:error, reason} ->
        Runs.fail(run, reason)
        Mix.raise("no artifact was written for #{day}: #{inspect(reason)}")
    end
  end

  defp stats(artifact) do
    "#{artifact.stats["stories"]} stories, #{artifact.stats["tickers"]} tickers, " <>
      "#{artifact.read_minutes} min"
  end

  defp path(day), do: "/#{day.year}/#{day.month}/#{day.day}"

  defp day(nil), do: Frontier.Newsroom.Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--day must be a date, like 2026-11-22")
    end
  end
end
