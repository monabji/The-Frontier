defmodule Frontier.Sources.RawItem do
  @moduledoc """
  A fetched post, article or paper, before clustering.

  The row is identified by `(source, external_id)`: the same HN story seen
  twice is one row, and the same id from two sources is two rows. Everything
  but the identity is refreshed on each fetch, so a story's score and comment
  count are today's, not the day it was first seen.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "raw_items" do
    field :source, :string
    field :external_id, :string
    field :title, :string
    field :url, :string
    field :discussion_url, :string
    field :author, :string
    field :text, :string
    field :points, :integer
    field :comments_count, :integer
    field :position, :integer
    field :published_at, :utc_datetime
    field :fetched_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required [:source, :external_id, :title, :url, :fetched_at]
  @refreshed @required ++
               [
                 :discussion_url,
                 :author,
                 :text,
                 :points,
                 :comments_count,
                 :position,
                 :published_at,
                 :updated_at
               ]

  @doc "Fields rewritten when an item is seen again."
  def refreshed_fields, do: @refreshed

  @doc false
  def changeset(raw_item, attrs) do
    raw_item
    |> cast(attrs, @refreshed)
    |> validate_required(@required)
    |> unique_constraint([:source, :external_id])
  end

  @doc """
  The host a reader sees in the source line, without a leading `www.`.
  """
  @spec host(t()) :: String.t()
  def host(%__MODULE__{url: url}) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> String.replace_prefix(host, "www.", "")
      _ -> ""
    end
  end
end
