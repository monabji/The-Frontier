defmodule Mix.Tasks.Frontier.Brief do
  @shortdoc "Writes the editor's brief for a chat window"

  @moduledoc """
  Writes the day's editing brief to a file, ready to paste into ChatGPT, Gemini,
  Claude or any chat window.

      mix frontier.brief
      mix frontier.brief --day 2026-11-22 --out tmp/desk/brief.txt

  The brief is exactly what the paper would send to a model: the sections and
  caps, the word budgets, the quote rule, and every candidate story with its id,
  link and source text. Paste the whole file, then paste the reply back with:

      mix frontier.desk --reply tmp/desk/reply.json --assistant chatgpt

  Nothing is fetched or written to the database by this task; run
  `mix frontier.fetch && mix frontier.cluster` first if the pool is stale.
  """

  use Mix.Task

  alias Frontier.Editor.Desk
  alias Frontier.Newsroom.Dateline

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} =
      OptionParser.parse!(args,
        strict: [day: :string, out: :string, limit: :integer]
      )

    day = day(opts[:day])
    limit = opts[:limit] || 100
    brief = Desk.brief(day, limit: limit)
    path = opts[:out] || Path.join("tmp/desk", "#{Date.to_iso8601(day)}-brief.txt")

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, brief.prompt)

    Mix.shell().info("The Frontier — brief, #{Dateline.format(day)}")
    Mix.shell().info("  #{brief.candidates} quotable candidates")
    Mix.shell().info("  #{length(brief.excluded)} candidates could not be quoted")

    Enum.each(brief.excluded, fn excluded ->
      Mix.shell().info("  not quotable: #{excluded.headline} (#{inspect(excluded.reason)})")
    end)

    Mix.shell().info("  brief: #{path} (#{String.length(brief.prompt)} characters)")
    Mix.shell().info("  paste it into a chat window, then run:")
    Mix.shell().info("    mix frontier.desk --reply tmp/desk/reply.json --assistant chatgpt")
  end

  defp day(nil), do: Dateline.edition_date()

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Mix.raise("--day must be a date, like 2026-11-22")
    end
  end
end
