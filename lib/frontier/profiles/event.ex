defmodule Frontier.Profiles.Event do
  @moduledoc """
  One thing a reader said about their taste: a chip, a trusted account, a thumb.

  Events are append-only. The profile document is a projection of them; keeping
  the events means "why does my paper look like this" has an answer.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "profile_events" do
    belongs_to :reader, Frontier.Readers.Reader
    field :kind, :string
    field :target, :string
    field :value, :string
    field :edition_day, :date

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @fields [:reader_id, :kind, :target, :value, :edition_day, :inserted_at]

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required([:reader_id, :kind, :inserted_at])
  end
end
