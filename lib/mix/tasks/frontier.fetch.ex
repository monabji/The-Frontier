defmodule Mix.Tasks.Frontier.Fetch do
  @shortdoc "Fetches every enabled source into raw_items"

  @moduledoc """
  Fetches the paper's sources and stores what they printed.

      mix frontier.fetch
      mix frontier.fetch --source hn

  One run per source. A source that fails is logged and named in the summary;
  the others still run. Re-running is safe: an item already stored is
  refreshed, never duplicated.

  The page reads what this stored, so run it before opening the paper.
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
    Mix.shell().info("The page reads what this stored.")

    if reports != [] and Enum.all?(reports, &(&1.status == :error)) do
      Mix.raise("no source produced items")
    end
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

  @doc """
  One source's line in the run log.
  """
  @spec format_report(Frontier.Sources.report()) :: String.t()
  def format_report(%{status: :ok} = report) do
    "  " <>
      String.pad_trailing(report.source, 10) <>
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
      String.pad_trailing(report.source, 10) <>
      " failed after #{report.duration_ms}ms: #{report.error}"
  end
end
