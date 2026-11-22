defmodule Frontier.Editor.Candidates do
  @moduledoc """
  The pool as the editor sees it: a short, ordered list of stories with enough
  source text to write about them.

  The pool can hold 150 stories; a prompt holding all of them is expensive and
  no better than a prompt holding the best forty. Candidates are taken in the
  paper's own order (best-placed first), each with its primary link, provenance
  and source text. A story whose text cannot be read is excluded and named: it
  cannot be quoted, so it cannot print.
  """

  alias Frontier.Editor.SourceText
  alias Frontier.Newsroom.Story
  alias Frontier.Sources

  @default_limit 40

  @type t :: %{
          id: integer(),
          headline: String.t(),
          url: String.t(),
          canonical_url: String.t(),
          primary_source: String.t() | nil,
          source_label: String.t() | nil,
          discussion_url: String.t() | nil,
          score: non_neg_integer() | nil,
          comments_count: non_neg_integer() | nil,
          published_at: DateTime.t() | nil,
          text: String.t()
        }

  @doc """
  Builds candidates from preloaded stories. Options: `:limit` (default 40) and
  the source-text options (`:fetcher`).
  """
  @spec build([Story.t()], keyword()) :: %{candidates: [t()], excluded: [map()]}
  def build(stories, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    stories
    |> Enum.take(limit)
    |> Enum.map(&candidate(&1, opts))
    |> Enum.split_with(&match?({:ok, _candidate}, &1))
    |> then(fn {ok, failed} ->
      %{
        candidates: Enum.map(ok, fn {:ok, candidate} -> candidate end),
        excluded: Enum.map(failed, fn {:error, excluded} -> excluded end)
      }
    end)
  end

  @doc "One story as a candidate, or the reason it cannot be quoted."
  @spec candidate(Story.t(), keyword()) :: {:ok, t()} | {:error, map()}
  def candidate(story, opts \\ []) do
    case Story.primary_item(story) do
      nil ->
        {:error, %{story_id: story.id, headline: story.headline, reason: :no_primary_item}}

      membership ->
        item = membership.raw_item

        case SourceText.for_item(item, opts) do
          {:ok, text} ->
            {:ok,
             %{
               id: story.id,
               headline: story.headline,
               url: story.primary_url,
               canonical_url: story.canonical_url,
               primary_source: story.primary_source || item.source,
               source_label: Sources.label_for(item.source),
               discussion_url: item.discussion_url,
               score: item.score,
               comments_count: item.comments_count,
               published_at: item.published_at || story.first_published_at,
               text: text
             }}

          {:error, reason} ->
            {:error, %{story_id: story.id, headline: story.headline, reason: reason}}
        end
    end
  end
end
