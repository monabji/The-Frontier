defmodule Mix.Tasks.Frontier.Keyless do
  @shortdoc "Edits the day in parts, for a keyless endpoint"

  @moduledoc """
  Writes the paper in parts and assembles a draft.

      mix frontier.keyless
      mix frontier.keyless --day 2026-11-22

  This is the editor for a free endpoint whose replies are short: two sections
  per call, routed candidates, the same caps, word budgets and grounding as the
  full editor. It reads `FRONTIER_LLM_BASE_URL`, `FRONTIER_LLM_MODEL` and
  `FRONTIER_LLM_KEYLESS`; the keyless client sends no Authorization header.

  Nothing is published. Read the draft at `mix frontier.log` and `/desk`, then
  publish with `mix frontier.publish`.
  """

  use Mix.Task

  alias Frontier.Editor
  alias Frontier.Newsroom.Dateline

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])

    case Editor.Keyless.edit(day, part_delay_ms: delay()) do
      {:ok, %{edition: edition, report: report}} ->
        Mix.shell().info("The Frontier — keyless edit, #{Dateline.format(day)}")
        Mix.shell().info("  #{report.printed} stories, #{report.read_minutes} min read")

        Mix.shell().info(
          "  #{report.model}: #{report.input_tokens} in / #{report.output_tokens} out"
        )

        Mix.shell().info("  draft: #{edition.story_count} stories")

        Enum.each(report.issues, fn issue -> Mix.shell().info("  note: #{inspect(issue)}") end)
        Mix.shell().info("  publish with mix frontier.publish")

      {:error, reason} ->
        Mix.raise("the keyless edit for #{day} failed: #{inspect(reason)}")
    end
  end

  # The free keyless endpoint allows one reply every 45 seconds.
  defp delay do
    case Integer.parse(System.get_env("FRONTIER_KEYLESS_DELAY_MS", "50000")) do
      {milliseconds, _rest} -> milliseconds
      :error -> 50_000
    end
  end

  defp day(nil), do: Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--day must be a date, like 2026-11-22")
    end
  end
end
