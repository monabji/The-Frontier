defmodule Frontier.Editions do
  @moduledoc """
  The paper as a dated record.

  Phase 4 writes an edition as a draft: the editor's placements and copy, with
  the desk note and read time the issue advertises. Phase 5 adds the artifact;
  this module is the seam both phases use, so the page never reads a story row
  and guesses what it said.

  A draft can be replaced by the next editor run. A published or frozen edition
  cannot: the only way to change what a day said is a new, visible correction,
  which phase 5's artifact versioning owns.
  """

  import Ecto.Query

  alias Frontier.Editions.{Edition, Entry, Rejection}
  alias Frontier.Editor.{Plan, Sections}
  alias Frontier.Repo

  @type save_result :: {:ok, Edition.t()} | {:error, term()}

  @doc "The edition for a day, entries loaded, or nil."
  @spec get(Date.t()) :: Edition.t() | nil
  def get(day) do
    Edition
    |> where([edition], edition.day == ^day)
    |> preload(entries: ^ordered_entries())
    |> Repo.one()
  end

  @doc "The most recent edition on or before today, or nil."
  @spec latest() :: Edition.t() | nil
  def latest do
    Edition
    |> order_by([edition], desc: edition.day)
    |> limit(1)
    |> preload(entries: ^ordered_entries())
    |> Repo.one()
  end

  @doc "Whether a day's edition can still be written by an editor run."
  @spec writable?(Date.t()) :: boolean()
  def writable?(day) do
    case Repo.get_by(Edition, day: day) do
      nil -> true
      %Edition{status: "draft"} -> true
      %Edition{} -> false
    end
  end

  @doc """
  Writes the editor's plan as the day's draft.

  Replaces the draft's entries in one transaction. A published or frozen
  edition is refused rather than overwritten.
  """
  @spec save_draft(Date.t(), Plan.t(), keyword()) :: save_result()
  def save_draft(day, plan, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:second) end)

    Repo.transaction(fn ->
      edition = lock_edition(day, now)

      case edition.status do
        "draft" ->
          edition =
            edition
            |> Edition.changeset(%{
              desk_note: plan.desk_note,
              story_count: plan.story_count,
              word_count: plan.word_count,
              read_minutes: Sections.read_minutes(plan.word_count)
            })
            |> Repo.update!()

          Repo.delete_all(from entry in Entry, where: entry.edition_id == ^edition.id)

          entries = Enum.map(plan.entries, &entry_attrs(&1, edition.id, now))
          tickers = Enum.map(plan.tickers, &entry_attrs(&1, edition.id, now))

          Repo.insert_all(Entry, entries ++ tickers)

          %{edition | entries: load_entries(edition.id)}

        other ->
          Repo.rollback({:edition_is_published, other})
      end
    end)
  end

  @doc "Marks a draft published. Idempotent while the status is published."
  @spec publish(Date.t(), keyword()) :: {:ok, Edition.t()} | {:error, term()}
  def publish(day, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:second) end)

    case Repo.get_by(Edition, day: day) do
      nil ->
        {:error, :no_edition}

      %Edition{status: status} = edition when status in ["published", "late"] ->
        {:ok, edition}

      %Edition{status: "frozen"} ->
        {:error, :edition_is_frozen}

      %Edition{status: "draft"} = edition ->
        edition
        |> Edition.changeset(%{status: "published", published_at: now})
        |> Repo.update()
    end
  end

  @doc "The drop log for a day: what the editor chose and grounding refused."
  @spec rejections(Date.t()) :: [Rejection.t()]
  def rejections(day) do
    Repo.all(
      from rejection in Rejection,
        where: rejection.edition_day == ^day,
        order_by: [asc: rejection.id]
    )
  end

  @doc false
  @spec record_rejections(Date.t(), [map()]) :: :ok
  def record_rejections(day, rejections) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(rejections, fn rejection ->
        %{
          edition_day: day,
          story_id: Map.get(rejection, :story_id),
          headline: Map.get(rejection, :headline),
          reason: to_string(Map.fetch!(rejection, :reason)),
          detail: Map.get(rejection, :detail),
          inserted_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(Rejection, rows)
    :ok
  end

  @doc "The sections a day's edition prints, in paper order, entries placed."
  @spec sections(Edition.t()) :: [{String.t(), [Entry.t()]}]
  def sections(%Edition{entries: entries}) do
    entries
    |> Enum.group_by(& &1.section)
    |> then(fn grouped ->
      Sections.names()
      |> Enum.map(fn section ->
        {section, Enum.sort_by(Map.get(grouped, section, []), & &1.position)}
      end)
      |> Enum.reject(fn {_section, entries} -> entries == [] end)
    end)
  end

  @doc "The Also Today ticker, in order."
  @spec tickers(Edition.t()) :: [Entry.t()]
  def tickers(%Edition{entries: entries}) do
    entries
    |> Enum.filter(&(&1.section == "Also Today"))
    |> Enum.sort_by(& &1.position)
  end

  defp ordered_entries do
    order_by(Entry, asc: :section, asc: :position)
  end

  defp load_entries(edition_id) do
    Entry
    |> where([entry], entry.edition_id == ^edition_id)
    |> order_by([entry], asc: entry.section, asc: entry.position)
    |> Repo.all()
  end

  defp lock_edition(day, now) do
    case Repo.get_by(Edition, day: day) do
      nil ->
        %Edition{}
        |> Edition.changeset(%{day: day, status: "draft"})
        |> Ecto.Changeset.put_change(:inserted_at, now)
        |> Ecto.Changeset.put_change(:updated_at, now)
        |> Repo.insert!()

      edition ->
        edition
    end
  end

  defp entry_attrs(entry, edition_id, now) do
    %{
      edition_id: edition_id,
      story_id: entry.story_id,
      section: entry.section,
      position: entry.position,
      kind: to_string(entry.kind),
      origin: "edition",
      headline: entry.headline,
      dek: entry.dek,
      summary: entry.summary,
      quote: entry.quote,
      url: entry.url,
      canonical_url: entry.canonical_url,
      primary_source: entry.primary_source,
      source_label: entry.source_label,
      discussion_url: entry.discussion_url,
      score: entry.score,
      comments_count: entry.comments_count,
      published_at: entry.published_at,
      word_count: entry.word_count,
      inserted_at: now,
      updated_at: now
    }
  end
end
