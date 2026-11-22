defmodule Mix.Tasks.Frontier.Edit do
  @shortdoc "Edits the day's pool into an edition draft"

  @moduledoc """
  Asks the editor for the day's paper and grounds every entry.

      mix frontier.edit
      mix frontier.edit --day 2026-11-22
      mix frontier.edit --client fixture --fixture test/fixtures/editor/edition.json

  The run writes a draft; publishing is the daily run's job. The summary names
  what printed, what was dropped and why, the read time, and exactly what the
  model cost. A draft that is published or frozen is never overwritten.

  `--client fixture` is for looking at the page without an API key. It is not a
  fallback: the run records the model as `fixture` and zero cost.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} =
      OptionParser.parse!(args,
        strict: [
          day: :string,
          client: :string,
          fixture: :string,
          repair: :boolean,
          limit: :integer
        ]
      )

    day = day(opts[:day])
    client = client(opts[:client])

    editor_opts =
      [
        client: client,
        repair: Keyword.get(opts, :repair, true),
        limit: opts[:limit] || 100
      ]
      |> maybe_fixture(opts[:fixture])

    case Frontier.Editor.edit(day, editor_opts) do
      {:ok, %{edition: edition, report: report}} ->
        Mix.shell().info("The Frontier — edit, #{day}")
        print_report(report)
        Mix.shell().info("  draft: #{edition.story_count} stories, #{edition.read_minutes} min")
        Mix.shell().info("  preview it at http://localhost:4000/")

      {:error, reason} ->
        Mix.raise("no edition was written for #{day}: #{inspect(reason)}")
    end
  end

  defp print_report(report) do
    Mix.shell().info(
      "  #{report.printed} stories and #{report.tickers} tickers from " <>
        "#{report.candidates} candidates; #{report.rejected} dropped"
    )

    Mix.shell().info("  #{report.read_minutes} min read, #{report.word_count} words")

    Mix.shell().info(
      "  #{report.model || "unknown model"}: #{report.input_tokens} in / " <>
        "#{report.output_tokens} out, #{Frontier.Editor.Cost.format(report.cost_micros)}"
    )

    Enum.each(report.excluded, fn excluded ->
      Mix.shell().info("  not quotable: #{excluded.headline} (#{inspect(excluded.reason)})")
    end)

    Enum.each(report.issues, fn
      {:dropped, story_id, reason} ->
        Mix.shell().info("  dropped story #{story_id}: #{inspect(reason)}")

      {:too_short, count, target} ->
        Mix.shell().info("  short paper: #{count} of #{target} stories")

      {:desk_note, reason} ->
        Mix.shell().info("  desk note: #{inspect(reason)}")

      _issue ->
        :ok
    end)
  end

  defp client(nil), do: Frontier.Editor.Client.configured()
  defp client("http"), do: Frontier.Editor.Client.HTTP
  defp client("fixture"), do: Frontier.Editor.Client.Fixture

  defp client(other) do
    Mix.raise("unknown --client #{inspect(other)}; use http or fixture")
  end

  defp maybe_fixture(opts, nil), do: opts
  defp maybe_fixture(opts, path), do: Keyword.put(opts, :fixture, path)

  defp day(nil), do: Frontier.Newsroom.Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--day must be a date, like 2026-11-22")
    end
  end
end
