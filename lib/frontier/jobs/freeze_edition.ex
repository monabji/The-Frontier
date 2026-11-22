defmodule Frontier.Jobs.FreezeEdition do
  @moduledoc """
  The 00:05 IST close: the day that just ended stops moving.

  Freezing is idempotent. A day with no artifact is skipped, not an alarm: a
  first night before the press was installed is not a failure. A real error —
  an unwritable store, a frozen day that cannot be read — is recorded and
  alerted.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Frontier.{Editions, Runs}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    day = Frontier.Jobs.day(args, Date.add(Frontier.Newsroom.Dateline.edition_date(), -1))
    run = Runs.start("freeze", day)

    case Editions.freeze(day) do
      {:ok, nil} ->
        Runs.skip(run, "no edition to freeze")
        :ok

      {:ok, edition} ->
        Runs.finish(run, inserted: edition.story_count)
        :ok

      {:error, :no_artifact} ->
        Runs.skip(run, "no artifact to freeze")
        :ok

      {:error, reason} ->
        Runs.fail(run, reason)

        Frontier.Jobs.Notify.failed(
          "The midnight freeze failed",
          day,
          reason,
          attempt,
          max_attempts
        )

        {:error, reason}
    end
  end
end
