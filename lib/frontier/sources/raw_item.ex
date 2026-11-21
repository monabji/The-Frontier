defmodule Frontier.Sources.RawItem do
  @moduledoc """
  A fetched post, article or paper, before clustering.

  The row is identified by `(source, external_id)`: the same HN story seen
  twice is one row, and the same id from two sources is two rows. Everything
  but the identity and `first_seen_at` is refreshed on each fetch, so a story's
  score and comment count are today's, not the day it was first seen.

  `canonical_url` is the article's identity across sources — an HN submission
  and the blog post it points at reduce to the same string — and
  `content_hash` fingerprints the URL plus title. `edition_day` is the IST day
  the row was *last seen* on, which is the day whose page it belongs to.

  ## What `fetched_at` means

  `fetched_at` and `edition_day` are last-seen, not first-seen: re-fetching an
  old front page after midnight moves those rows into the new edition day. That
  is the truth for a live pool, and it is why phase 5 stores published editions
  as artifacts — a printed day must not move when the fetch runs again.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "raw_items" do
    field :source, :string
    field :external_id, :string
    field :title, :string
    field :url, :string
    field :canonical_url, :string
    field :content_hash, :string
    field :kind, :string, default: "story"
    field :discussion_url, :string
    field :author, :string
    field :text, :string
    field :score, :integer
    field :comments_count, :integer
    field :position, :integer
    field :published_at, :utc_datetime
    field :edition_day, :date
    field :run_id, :integer
    field :first_seen_at, :utc_datetime
    field :fetched_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  # Rewritten when an item is seen again. `first_seen_at` and `inserted_at` are
  # deliberately absent: they are provenance, not state.
  @refreshed [
    :title,
    :url,
    :canonical_url,
    :content_hash,
    :kind,
    :discussion_url,
    :author,
    :text,
    :score,
    :comments_count,
    :position,
    :published_at,
    :edition_day,
    :run_id,
    :fetched_at,
    :updated_at
  ]

  @doc "Fields rewritten when an item is seen again."
  def refreshed_fields, do: @refreshed

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
