defmodule Frontier.Newsroom.StoryItem do
  @moduledoc """
  An item's membership in a story, and the part it played.

    * `primary` — the publication that broke the story; its link is printed
    * `duplicate` — another source (or another post) carrying the same event
    * `discussion` — an aggregator's thread about it, where the conversation is

  Role is editorial signal, not storage detail: phase 4 picks discourse quotes
  from the discussion items and links the reader to the primary.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "story_items" do
    belongs_to :story, Frontier.Newsroom.Story
    belongs_to :raw_item, Frontier.Sources.RawItem
    field :role, :string

    timestamps(type: :utc_datetime)
  end

  @roles ~w(primary duplicate discussion)

  @doc false
  def changeset(story_item, attrs) do
    story_item
    |> cast(attrs, [:story_id, :raw_item_id, :role])
    |> validate_required([:story_id, :raw_item_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:story_id, :raw_item_id])
  end
end
