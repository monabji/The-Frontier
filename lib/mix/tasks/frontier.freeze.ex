defmodule Mix.Tasks.Frontier.Freeze do
  @shortdoc "Freezes the day's edition; nothing may rewrite it"

  @moduledoc """
  Closes a day at midnight.

      mix frontier.freeze
      mix frontier.freeze --day 2026-11-22

  The store writes a marker naming the current artifact, and from then on no
  assemble, publish or editor draft may touch the day. Freezing is idempotent.
  """

  use Mix.Task

  alias Frontier.{Editions, Runs}

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])
    run = Runs.start("freeze", day)

    case Editions.freeze(day) do
      {:ok, nil} ->
        Runs.skip(run, "no edition to freeze")
        Mix.shell().info("The Frontier — freeze, #{day}\n  nothing to freeze")

      {:ok, edition} ->
        Runs.finish(run, inserted: edition.story_count)

        Mix.shell().info("The Frontier — freeze, #{day}")
        Mix.shell().info("  status: #{edition.status}")
        Mix.shell().info("  artifact: #{edition.artifact_hash}")
        Mix.shell().info("  #{day} will not be rewritten.")

      {:error, reason} ->
        Runs.fail(run, reason)
        Mix.raise("#{day} was not frozen: #{inspect(reason)}")
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
