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

  alias Frontier.Editions.{Artifact, Edition, Entry, Rejection, Store}
  alias Frontier.Editor.{Plan, Sections}
  alias Frontier.Newsroom.Dateline
  alias Frontier.Repo

  @type save_result :: {:ok, Edition.t()} | {:error, term()}

  @published_statuses ["published", "late", "frozen"]

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
    not Store.frozen?(day) and
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
      if Store.frozen?(day), do: Repo.rollback(:edition_is_frozen)
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

  @doc """
  Builds the day's artifact and points the store at it.

  A draft can be assembled any number of times; each distinct set of inputs is
  a new content-addressed version, and the previous version stays on disk. A
  frozen day is refused.
  """
  @spec assemble(Date.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def assemble(day, opts \\ []) do
    case get(day) do
      nil ->
        {:error, :no_edition}

      %Edition{status: "frozen"} = _edition ->
        {:error, :edition_is_frozen}

      %Edition{} = edition ->
        if Store.frozen?(day) do
          {:error, :edition_is_frozen}
        else
          assemble_if_draft(edition, opts)
        end
    end
  end

  defp assemble_if_draft(%Edition{status: "draft"} = edition, opts) do
    assemble_edition(edition, opts)
  end

  defp assemble_if_draft(%Edition{} = edition, opts) do
    if Keyword.get(opts, :republish, false) do
      assemble_edition(edition, opts)
    else
      {:error, :edition_is_published}
    end
  end

  defp assemble_edition(edition, opts) do
    if Store.frozen?(edition.day) do
      {:error, :edition_is_frozen}
    else
      status = Keyword.get(opts, :status, edition.status)
      published_at = Keyword.get(opts, :published_at, edition.published_at)
      artifact = Artifact.build(%{edition | status: status, published_at: published_at})
      renderer = Keyword.get(opts, :renderer, &FrontierWeb.ArtifactHTML.render/1)

      with {:ok, html} <- render(artifact, renderer),
           {:ok, stored} <- Store.write(artifact, html),
           {:ok, saved} <- save_artifact(edition, stored, status, published_at) do
        {:ok, %{edition: saved, artifact: artifact, stored: stored}}
      end
    end
  end

  @doc """
  Publishes a draft and freezes its first published artifact.

  Publishing is the moment the paper becomes an edition: the artifact is
  written with status published, then the row is updated. An already-published
  edition with an artifact is returned unchanged.
  """
  @spec publish(Date.t(), keyword()) :: {:ok, Edition.t()} | {:error, term()}
  def publish(day, opts \\ []) do
    if Store.frozen?(day) do
      {:error, :edition_is_frozen}
    else
      do_publish(day, opts)
    end
  end

  defp do_publish(day, opts) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:second) end)

    case get(day) do
      nil ->
        {:error, :no_edition}

      %Edition{status: status, artifact_hash: hash} = edition
      when status in ["published", "late"] and is_binary(hash) ->
        if Store.current_hash(day) == hash do
          {:ok, edition}
        else
          # The database says published but the store does not hold that
          # version (a restore, a lost volume). Rebuild it rather than tell the
          # operator everything is fine while readers see yesterday.
          case assemble_edition(edition,
                 status: edition.status,
                 published_at: edition.published_at || now
               ) do
            {:ok, %{edition: saved}} -> {:ok, saved}
            {:error, reason} -> {:error, reason}
          end
        end

      %Edition{status: "frozen"} ->
        {:error, :edition_is_frozen}

      %Edition{} = edition ->
        published_at = edition.published_at || now

        case assemble_edition(edition, status: "published", published_at: published_at) do
          {:ok, %{edition: saved}} -> {:ok, saved}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Closes a day: the store's marker freezes the current artifact, and the row
  records when. Freezing is idempotent.
  """
  @spec freeze(Date.t(), keyword()) :: {:ok, Edition.t() | nil} | {:error, term()}
  def freeze(day, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:second) end)

    case Store.freeze(day) do
      :ok ->
        case Repo.get_by(Edition, day: day) do
          nil ->
            {:ok, nil}

          edition ->
            edition
            |> Edition.changeset(%{status: "frozen", frozen_at: edition.frozen_at || now})
            |> Repo.update()
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The edition a reader gets right now, and whether it is late.

  A published edition for today wins. Before 06:00 the most recent published
  edition is simply the current paper; after 06:00, if today's publish has not
  happened, that same edition is served with `delayed: true`. A draft is shown
  only when no edition has ever been published (the press is being installed).
  Reads storage only, so a delayed morning does not depend on the database.
  """
  @spec current(DateTime.t() | nil) :: %{
          artifact: Artifact.t() | nil,
          delayed: boolean(),
          expected_day: Date.t()
        }
  def current(now \\ nil) do
    now = now || Frontier.Clock.now()
    today = Dateline.edition_date(now)
    today_artifact = Store.read(today)
    latest = latest_published(today)

    cond do
      today_artifact && today_artifact.status in @published_statuses ->
        %{artifact: today_artifact, delayed: false, expected_day: today}

      latest ->
        %{artifact: latest, delayed: Dateline.deadline_passed?(today, now), expected_day: today}

      today_artifact ->
        %{artifact: today_artifact, delayed: false, expected_day: today}

      true ->
        %{artifact: nil, delayed: false, expected_day: today}
    end
  end

  defp latest_published(today) do
    Store.days()
    |> Enum.filter(&(&1 <= today))
    |> Enum.reverse()
    |> Enum.find_value(fn day ->
      case Store.read(day) do
        %Artifact{status: status} = artifact when status in @published_statuses -> artifact
        _ -> nil
      end
    end)
  end

  @doc "The current artifact for a day, read from storage only."
  @spec artifact(Date.t()) :: Artifact.t() | nil
  def artifact(day), do: Store.read(day)

  @doc "The newest stored artifact, read from storage only."
  @spec latest_artifact() :: Artifact.t() | nil
  def latest_artifact, do: Store.latest()

  defp render(artifact, renderer) do
    {:ok, renderer.(artifact)}
  rescue
    exception -> {:error, {:render_failed, Exception.message(exception)}}
  end

  defp save_artifact(edition, stored, status, published_at) do
    attrs = %{
      artifact_hash: stored.hash,
      artifact_path: stored.json_path,
      built_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    attrs =
      if status == edition.status do
        attrs
      else
        Map.merge(attrs, %{status: status, published_at: published_at})
      end

    edition
    |> Edition.changeset(attrs)
    |> Repo.update()
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
