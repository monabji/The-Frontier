defmodule Mix.Tasks.Frontier.Desk do
  @shortdoc "Grounds a pasted editor reply and assembles the draft"

  @moduledoc """
  Takes the JSON a chat window wrote, grounds it, and assembles the day's paper.

      mix frontier.desk --reply tmp/desk/reply.json --assistant chatgpt
      mix frontier.desk --reply tmp/desk/reply.json --assistant claude --publish

  This is the editor's desk, not a fallback: the reply is validated against the
  same sections and caps, every quote must be a substring of the source text,
  and every link must resolve. Failures drop the story and are printed; nothing
  is relaxed because a person did the writing.

  Without `--publish` the paper stays a draft. Read it at `/desk` in the app,
  then publish with `mix frontier.publish`, or rerun this task with `--publish`.
  """

  use Mix.Task

  alias Frontier.Editions
  alias Frontier.Editor.Desk
  alias Frontier.Newsroom.Dateline

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} =
      OptionParser.parse!(args,
        strict: [day: :string, reply: :string, assistant: :string, publish: :boolean]
      )

    reply = opts[:reply] || Mix.raise("--reply path/to/reply.json is required")
    day = day(opts[:day])
    assistant = opts[:assistant] || "chat"

    case Desk.submit(day, reply, assistant: assistant) do
      {:ok, %{edition: edition, report: report}} ->
        Mix.shell().info("The Frontier — desk, #{Dateline.format(day)}")
        Mix.shell().info("  #{report.printed} stories and #{report.tickers} tickers printed")
        Mix.shell().info("  #{report.read_minutes} min read, #{report.word_count} words")
        Mix.shell().info("  model: #{report.model} (pasted reply, no tokens)")

        Enum.each(report.issues, fn
          {:dropped, story_id, reason} ->
            Mix.shell().info("  dropped story #{story_id}: #{inspect(reason)}")

          other ->
            Mix.shell().info("  note: #{inspect(other)}")
        end)

        if opts[:publish] do
          case Editions.publish(day) do
            {:ok, _edition} ->
              Mix.shell().info("  published: http://localhost:4000/")

            {:error, reason} ->
              Mix.raise("  assembled, but publishing failed: #{inspect(reason)}")
          end
        else
          Mix.shell().info(
            "  draft #{edition.story_count} stories; publish with mix frontier.publish"
          )
        end

      {:error, reason} ->
        Mix.raise("the desk could not assemble #{day}: #{Desk.explain(reason)}")
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
