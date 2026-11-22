defmodule Frontier.Jobs.DailyRun do
  @moduledoc """
  The 05:15 IST morning run: fetch, cluster, edit, assemble a draft.

  Cron expressions are UTC because India has no daylight saving and adding a
  timezone database for one fixed offset would be machinery without a decision.
  05:15 IST is 23:45Z on the previous UTC day; the run computes the edition day
  in IST, so it edits the right date. Retries are Oban's exponential backoff;
  each attempt writes its own run row and alerts only with its attempt number.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt, max_attempts: max_attempts} = job) do
    day = Frontier.Jobs.scheduled_day(job)

    case Frontier.Daily.run(day) do
      {:ok, _report} ->
        :ok

      {:error, reason} ->
        Frontier.Jobs.Notify.failed("The 05:15 run failed", day, reason, attempt, max_attempts)
        {:error, reason}
    end
  end
end
