defmodule Frontier.Editions.Edition do
  @moduledoc """
  One day's paper, before it becomes an artifact.

  An edition is created as a draft by the editor and published at 06:00. Its
  desk note, read time and counts are the paper's own summary of itself; the
  entries are what it prints. Phase 5 adds the artifact that freezes both.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Frontier.Editions.Entry

  @type t :: %__MODULE__{}

  schema "editions" do
    field :day, :date
    field :status, :string, default: "draft"
    field :desk_note, :string
    field :read_minutes, :integer
    field :word_count, :integer, default: 0
    field :story_count, :integer, default: 0
    field :published_at, :utc_datetime
    field :artifact_hash, :string
    field :artifact_path, :string
    field :built_at, :utc_datetime
    field :frozen_at, :utc_datetime

    has_many :entries, Entry, preload_order: [asc: :section, asc: :position]

    timestamps(type: :utc_datetime)
  end

  @fields [
    :day,
    :status,
    :desk_note,
    :read_minutes,
    :word_count,
    :story_count,
    :published_at,
    :artifact_hash,
    :artifact_path,
    :built_at,
    :frozen_at
  ]

  @doc false
  def changeset(edition, attrs) do
    edition
    |> cast(attrs, @fields)
    |> validate_required([:day, :status])
    |> validate_inclusion(:status, ~w(draft published late frozen))
    |> unique_constraint(:day)
  end
end
