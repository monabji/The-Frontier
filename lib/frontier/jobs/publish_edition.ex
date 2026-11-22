defmodule Frontier.Jobs.PublishEdition do
  @moduledoc """
  The 06:00 IST publish: the draft becomes the day's dated artifact.

  If there is no draft — because the morning run failed — the job records the
  failure, alerts, and lets Oban retry. The page does the rest: it serves the
  previous published edition with a delayed banner rather than a blank sheet.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Frontier.{Editions, Runs}

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt, max_attempts: max_attempts} = job) do
    day = Frontier.Jobs.scheduled_day(job)
    run = Runs.start("publish", day)

    if Editions.get(day) != nil and not Runs.successful?(day, "daily") do
      reason = :no_successful_morning_run
      Runs.fail(run, reason)
      Frontier.Jobs.Notify.failed("The 06:00 edition is late", day, reason, attempt, max_attempts)
      {:error, reason}
    else
      publish(day, run, attempt, max_attempts)
    end
  end

  defp publish(day, run, attempt, max_attempts) do
    case Editions.publish(day) do
      {:ok, edition} ->
        Runs.finish(run, inserted: edition.story_count, model: nil)
        :ok

      {:error, reason} ->
        Runs.fail(run, reason)

        Frontier.Jobs.Notify.failed(
          "The 06:00 edition is late",
          day,
          reason,
          attempt,
          max_attempts
        )

        {:error, reason}
    end
  end
end
