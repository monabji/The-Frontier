defmodule Mix.Tasks.Frontier.Publish do
  @shortdoc "Publishes the day's edition and assembles its artifact"

  @moduledoc """
  Publishes the draft and writes the published artifact.

      mix frontier.publish
      mix frontier.publish --day 2026-11-22

  The artifact's status and published time are part of the hash: the published
  paper is not the draft with a flag flipped afterwards. Publishing twice does
  not move the edition.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])

    case Frontier.Editions.publish(day) do
      {:ok, edition} ->
        Mix.shell().info("The Frontier — publish, #{day}")

        Mix.shell().info(
          "  #{edition.status}, #{edition.story_count} stories, #{edition.read_minutes} min"
        )

        Mix.shell().info("  published #{edition.published_at}")
        Mix.shell().info("  #{edition.artifact_hash}")
        Mix.shell().info("  /#{day.year}/#{day.month}/#{day.day} · /archive")

      {:error, reason} ->
        Mix.raise("no edition was published for #{day}: #{inspect(reason)}")
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
