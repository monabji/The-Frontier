defmodule Frontier.Editions.Entry do
  @moduledoc """
  One story's place in one edition: the section, the slot, and the copy the
  editor wrote for it.

  Editorial copy lives here and never on `stories`, because the clusterer
  rewrites stories on every rebuild. The entry also carries its own link and
  provenance, so a printed edition does not depend on the pool that produced it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "edition_entries" do
    belongs_to :edition, Frontier.Editions.Edition
    belongs_to :story, Frontier.Newsroom.Story

    field :section, :string
    field :position, :integer
    field :kind, :string, default: "standard"
    field :origin, :string, default: "edition"
    field :headline, :string
    field :dek, :string
    field :summary, :string
    field :quote, :string
    field :url, :string
    field :canonical_url, :string
    field :primary_source, :string
    field :source_label, :string
    field :discussion_url, :string
    field :score, :integer
    field :comments_count, :integer
    field :published_at, :utc_datetime
    field :word_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @fields [
    :edition_id,
    :story_id,
    :section,
    :position,
    :kind,
    :origin,
    :headline,
    :dek,
    :summary,
    :quote,
    :url,
    :canonical_url,
    :primary_source,
    :source_label,
    :discussion_url,
    :score,
    :comments_count,
    :published_at,
    :word_count
  ]

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([
      :edition_id,
      :section,
      :position,
      :kind,
      :headline,
      :summary,
      :url,
      :canonical_url
    ])
    |> validate_inclusion(:kind, ~w(lead standard ticker))
    |> unique_constraint([:edition_id, :canonical_url])
    |> unique_constraint([:edition_id, :section, :position])
  end
end
