defmodule Mix.Tasks.Frontier.Daily do
  @shortdoc "Runs the morning: fetch, cluster, edit, assemble"

  @moduledoc """
  Runs the whole morning by hand, the way the 05:15 job does.

      mix frontier.daily
      mix frontier.daily --day 2026-11-22

  Fetches every enabled source, rebuilds the pool, edits and assembles a
  draft. It does not publish: `mix frontier.publish` is the 06:00 step. The
  per-source lines are the fetch report; the run rows are readable with
  `mix frontier.log`.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])

    case Frontier.Daily.run(day) do
      {:ok, report} ->
        Mix.shell().info("The Frontier — daily, #{day}")

        Enum.each(report.fetch, fn source ->
          Mix.shell().info(Mix.Tasks.Frontier.Fetch.format_report(source))
        end)

        Mix.shell().info(
          "  #{report.stories} stories in the pool; #{report.printed} printed " <>
            "and #{report.tickers} tickers, #{report.rejected} dropped"
        )

        Mix.shell().info(
          "  #{report.read_minutes} min read, #{report.word_count} words, " <>
            "#{Frontier.Editor.Cost.format(report.cost_micros)}"
        )

        Mix.shell().info("  artifact #{report.artifact.hash}")
        Mix.shell().info("  draft assembled; publish it at 06:00 with mix frontier.publish")

      {:error, reason} ->
        Mix.raise("the morning run for #{day} failed: #{inspect(reason)}")
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
