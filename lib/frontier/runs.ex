defmodule Frontier.Runs do
  @moduledoc """
  The readable record of a scheduled run.

  Fetch, cluster and edit already write their own rows. The daily, publish and
  freeze stages write one row each through here, so the operator can answer
  "what happened at 05:15" without reading Oban's internals. A run is
  append-only: a retry is another row, not an edit.
  """

  import Ecto.Query

  alias Frontier.Clock
  alias Frontier.Repo
  alias Frontier.Sources.Run

  @doc "Opens a run row."
  @spec start(String.t(), Date.t(), map()) :: Run.t()
  def start(stage, day, attrs \\ %{}) do
    %Run{}
    |> Run.changeset(
      Map.merge(
        %{
          stage: stage,
          source: stage,
          edition_day: day,
          status: "running",
          inserted_at: Clock.now()
        },
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  @doc "Closes a run as successful, with whatever it counted."
  @spec finish(Run.t(), map()) :: Run.t()
  def finish(%Run{} = run, attrs \\ %{}) do
    attrs = Map.new(attrs)

    run
    |> Run.changeset(Map.merge(%{status: "ok"}, with_duration(run, attrs)))
    |> Repo.update!()
  end

  @doc "Closes a run as failed, keeping the reason."
  @spec fail(Run.t(), term(), map()) :: Run.t()
  def fail(%Run{} = run, reason, attrs \\ %{}) do
    attrs = Map.new(attrs)

    run
    |> Run.changeset(
      Map.merge(%{status: "error", error: format_reason(reason)}, with_duration(run, attrs))
    )
    |> Repo.update!()
  end

  @doc "Closes a run that had nothing to do, with the reason it was skipped."
  @spec skip(Run.t(), String.t(), map()) :: Run.t()
  def skip(%Run{} = run, note, attrs \\ %{}) do
    attrs = Map.new(attrs)

    run
    |> Run.changeset(Map.merge(%{status: "skipped", error: note}, with_duration(run, attrs)))
    |> Repo.update!()
  end

  @doc "Whether a stage has a successful run for a day."
  @spec successful?(Date.t(), String.t()) :: boolean()
  def successful?(day, stage) do
    Repo.exists?(
      from run in Run,
        where: run.edition_day == ^day and run.stage == ^stage and run.status == "ok"
    )
  end

  @doc "Every run for a day, in the order it happened."
  @spec list(Date.t()) :: [Run.t()]
  def list(day) do
    Repo.all(
      from run in Run,
        where: run.edition_day == ^day,
        order_by: [asc: run.id]
    )
  end

  @doc "One run as the operator's log line."
  @spec format(Run.t()) :: String.t()
  def format(%Run{} = run) do
    counts =
      [
        {"fetched", run.fetched},
        {"new", run.inserted},
        {"updated", run.updated},
        {"skipped", run.skipped},
        {"rejected", run.rejected}
      ]
      |> Enum.reject(fn {_label, value} -> value in [nil, 0] end)
      |> Enum.map_join("  ", fn {label, value} -> "#{value} #{label}" end)

    line =
      "  " <>
        String.pad_trailing(run.stage, 9) <>
        String.pad_trailing(run.source, 20) <>
        String.pad_trailing(run.status, 8) <> counts

    line = if run.duration_ms, do: line <> "  #{run.duration_ms}ms", else: line

    line =
      if run.cost_micros > 0,
        do: line <> "  " <> Frontier.Editor.Cost.format(run.cost_micros),
        else: line

    if run.error, do: line <> "\n    " <> run.error, else: line
  end

  defp with_duration(run, attrs) do
    Map.put_new_lazy(attrs, :duration_ms, fn ->
      max(0, DateTime.diff(Clock.now(), run.inserted_at, :millisecond))
    end)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
