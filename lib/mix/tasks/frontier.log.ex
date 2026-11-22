defmodule Mix.Tasks.Frontier.Log do
  @shortdoc "Prints the run log for a day"

  @moduledoc """
  The readable record of what the paper did.

      mix frontier.log
      mix frontier.log --day 2026-11-22

  One line per run: stage, source, status, what it counted, how long it took
  and what it cost. A failed run prints its reason beneath the line. Every
  scheduled job leaves rows here, so "why is today's paper late" is a command,
  not an investigation.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])
    runs = Frontier.Runs.list(day)

    Mix.shell().info("The Frontier — run log, #{day}")

    case runs do
      [] ->
        Mix.shell().info("  no runs recorded for this day")

      runs ->
        Enum.each(runs, fn run -> Mix.shell().info(Frontier.Runs.format(run)) end)
        Mix.shell().info("  #{length(runs)} runs")
    end
  end

  defp day(nil), do: Frontier.Newsroom.Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--day must be a date, like 2026-11-22")
    end
  end
end
