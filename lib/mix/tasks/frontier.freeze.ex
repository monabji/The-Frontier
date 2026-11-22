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

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])

    case Frontier.Editions.freeze(day) do
      {:ok, edition} ->
        Mix.shell().info("The Frontier — freeze, #{day}")
        Mix.shell().info("  status: #{edition && edition.status}")
        Mix.shell().info("  artifact: #{edition && edition.artifact_hash}")
        Mix.shell().info("  #{day} will not be rewritten.")

      {:error, reason} ->
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
