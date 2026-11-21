defmodule Mix.Tasks.Frontier.Fetch do
  @shortdoc "Fetches every enabled source into raw_items"

  @moduledoc """
  Fetches the paper's sources and stores what they printed.

      mix frontier.fetch
      mix frontier.fetch --source hn
      mix frontier.fetch --source rss:openai

  One run per source, one line per source in the summary. A source that fails
  is logged and named; the others still run. Re-running is safe: an item
  already stored is refreshed, never duplicated.

  The task finishes even when every source fails — a scheduled run that
  reports its failure is more useful than a stack trace, and phase 6 turns
  those failures into an alert. It says so plainly instead.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [source: :string])

    adapters = adapters(opts[:source])
    reports = Frontier.Sources.run(adapters: adapters)

    Mix.shell().info("The Frontier — fetch, #{Frontier.Newsroom.Dateline.edition_date()}")
    Enum.each(reports, fn report -> Mix.shell().info(format_report(report)) end)
    Mix.shell().info(summary(reports))
  end

  defp adapters(nil), do: Frontier.Sources.adapters()

  defp adapters(source) do
    case Enum.filter(Frontier.Sources.adapters(), &(&1.key() == source)) do
      [] ->
        known = Frontier.Sources.adapters() |> Enum.map_join(", ", & &1.key())
        Mix.raise("unknown source #{inspect(source)}; known sources: #{known}")

      adapters ->
        adapters
    end
  end

  @doc "One source's line in the run log."
  @spec format_report(Frontier.Sources.report()) :: String.t()
  def format_report(%{status: :ok} = report) do
    "  " <>
      String.pad_trailing(report.source, 18) <>
      String.pad_leading("#{report.fetched}", 4) <>
      " fetched   " <>
      String.pad_leading("#{report.inserted}", 4) <>
      " new   " <>
      String.pad_leading("#{report.updated}", 4) <>
      " refreshed   " <>
      String.pad_leading("#{report.skipped}", 3) <>
      " skipped   " <> "#{report.duration_ms}ms"
  end

  def format_report(%{status: :error} = report) do
    "  " <>
      String.pad_trailing(report.source, 18) <>
      " failed after #{report.duration_ms}ms: #{report.error}"
  end

  @doc """
  What the run says at the end: how much was stored, or that nothing was.
  """
  @spec summary([Frontier.Sources.report()]) :: String.t()
  def summary([]), do: "No sources are enabled."

  def summary(reports) do
    if Enum.all?(reports, &(&1.status == :error)) do
      "Every source failed; nothing new was stored. The page keeps its last edition."
    else
      fresh = reports |> Enum.map(& &1.inserted) |> Enum.sum()
      refreshed = reports |> Enum.map(& &1.updated) |> Enum.sum()

      "Stored #{fresh} new and refreshed #{refreshed} items. The page reads what this stored."
    end
  end
end
