defmodule Frontier.Sources.Run do
  @moduledoc """
  One adapter asked once, written down.

  A run is the paper's audit trail for its own fetching: which source, which
  edition day, what it saw, what it stored, how long it took and why it failed
  if it did. The run log the operator reads in phase 10 is these rows, and the
  per-source count phase 2 requires is here rather than only in a terminal.

  Rows are append-only: a re-run adds a run, it never rewrites one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "runs" do
    field :stage, :string, default: "fetch"
    field :source, :string
    field :edition_day, :date
    field :status, :string
    field :fetched, :integer, default: 0
    field :inserted, :integer, default: 0
    field :updated, :integer, default: 0
    field :skipped, :integer, default: 0
    field :rejected, :integer, default: 0
    field :duration_ms, :integer
    field :error, :string
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_micros, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @fields [
    :stage,
    :source,
    :edition_day,
    :status,
    :fetched,
    :inserted,
    :updated,
    :skipped,
    :rejected,
    :duration_ms,
    :error,
    :model,
    :input_tokens,
    :output_tokens,
    :cost_micros,
    :inserted_at
  ]

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, @fields)
    |> validate_required([:stage, :source, :edition_day, :status])
  end
end
