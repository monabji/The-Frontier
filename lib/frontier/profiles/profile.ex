defmodule Frontier.Profiles.Profile do
  @moduledoc """
  One version of a reader's taste document.

  Profiles are append-only: a save inserts a new version and leaves the old one
  untouched. The latest version is what the fold reads.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "profiles" do
    belongs_to :reader, Frontier.Readers.Reader
    field :version, :integer
    field :document, Frontier.Profiles.Document

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @fields [:reader_id, :version, :document, :inserted_at]

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @fields)
    |> validate_required([:reader_id, :version, :document])
    |> unique_constraint([:reader_id, :version])
  end
end
