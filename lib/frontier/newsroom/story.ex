defmodule Frontier.Newsroom.Story do
  @moduledoc """
  One event, as the paper will print it: a headline, one primary link, and the
  raw items that carried it.

  A story is rebuilt from the day's pool every time the clusterer runs, so it
  holds no editorial copy yet — phase 4 writes the dek, the summary and the
  quote. Until then the headline is the primary item's title, kept honest by
  saying so.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Frontier.Newsroom.StoryItem

  @type t :: %__MODULE__{}

  schema "stories" do
    field :edition_day, :date
    field :cluster_key, :string
    field :headline, :string
    field :canonical_url, :string
    field :primary_url, :string
    field :kind, :string
    field :item_count, :integer, default: 1
    field :source_count, :integer, default: 1
    field :first_published_at, :utc_datetime
    field :last_published_at, :utc_datetime
    field :sort_position, :integer
    field :primary_source, :string

    has_many :story_items, StoryItem

    timestamps(type: :utc_datetime)
  end

  @fields [
    :edition_day,
    :cluster_key,
    :headline,
    :canonical_url,
    :primary_url,
    :kind,
    :item_count,
    :source_count,
    :first_published_at,
    :last_published_at,
    :sort_position,
    :primary_source
  ]

  @doc false
  def changeset(story, attrs) do
    story
    |> cast(attrs, @fields)
    |> validate_required([:edition_day, :cluster_key, :headline, :canonical_url, :primary_url])
    |> unique_constraint([:edition_day, :cluster_key])
    |> unique_constraint([:edition_day, :canonical_url])
  end

  @doc """
  The membership whose link the paper prints: the publication, not the
  aggregator. Falls back to the first member so a story is never linkless.
  """
  @spec primary_item(t()) :: Frontier.Newsroom.StoryItem.t() | nil
  def primary_item(%__MODULE__{story_items: items}) do
    Enum.find(items, &(&1.role == "primary")) || List.first(items)
  end

  @doc "The raw item behind the printed link, when it is loaded."
  @spec primary_raw_item(t()) :: Frontier.Sources.RawItem.t() | nil
  def primary_raw_item(%__MODULE__{} = story) do
    case primary_item(story) do
      nil -> nil
      item -> Map.get(item, :raw_item)
    end
  end
end
