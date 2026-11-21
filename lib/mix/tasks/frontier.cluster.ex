defmodule Mix.Tasks.Frontier.Cluster do
  @shortdoc "Clusters the day's fetched items into stories"

  @moduledoc """
  Rebuilds the day's candidate pool.

      mix frontier.cluster
      mix frontier.cluster --day 2026-11-22

  Reads each source's latest successful run for the day, clusters the items
  into stories, and replaces the day's stories with the result. Running it
  twice over the same pool is safe: the stories come out the same.

  The run log names the biggest clusters, because a cluster of ten is either a
  busy day or an over-merge, and only a human can tell which.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [day: :string])
    day = day(opts[:day])

    report = Frontier.Newsroom.Pool.rebuild(day)

    Mix.shell().info("The Frontier — cluster, #{day}")

    Mix.shell().info(
      "  #{report.items} items became #{report.stories} stories " <>
        "(#{report.merged} items merged)"
    )

    day
    |> then(&Frontier.Newsroom.Pool.list_stories(day: &1, limit: 5))
    |> Enum.each(fn story ->
      Mix.shell().info("  #{story.item_count}× #{story.headline}")
    end)

    Mix.shell().info("  Inspect them at /pool")
  end

  defp day(nil), do: Frontier.Newsroom.Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--day must be a date, like 2026-11-22")
    end
  end
end
