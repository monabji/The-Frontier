defmodule Frontier.Sources.Item do
  @moduledoc """
  One fetched post, article or paper, before it is stored or clustered.

  Adapters speak in this struct, not in database rows: `normalize/1` returns
  items and `Frontier.Sources.upsert_items/2` is the only thing that knows how
  they are persisted. A source key is not part of the item; the run that
  collected it owns that.

  `kind` is what the source itself says the item is. HN marks its job posts,
  Ask HN threads and Show HN launches in the tags it returns; a blog feed is
  simply a post. Keeping the distinction now means the editorial decision
  ("do job ads belong on the front page?") can be made later without a re-fetch.
  """

  @enforce_keys [:external_id, :title, :url]
  defstruct external_id: nil,
            title: nil,
            url: nil,
            discussion_url: nil,
            author: nil,
            text: nil,
            kind: :story,
            score: nil,
            comments_count: nil,
            published_at: nil,
            position: nil

  @typedoc "What the source says this item is."
  @type kind :: :story | :job | :ask | :show | :post

  @type t :: %__MODULE__{
          external_id: String.t(),
          title: String.t(),
          url: String.t(),
          discussion_url: String.t() | nil,
          author: String.t() | nil,
          text: String.t() | nil,
          kind: kind(),
          score: non_neg_integer() | nil,
          comments_count: non_neg_integer() | nil,
          published_at: DateTime.t() | nil,
          position: pos_integer() | nil
        }
end
