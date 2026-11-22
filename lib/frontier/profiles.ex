defmodule Frontier.Profiles do
  @moduledoc """
  Taste as a versioned, readable document — never a model.

  A profile is built from append-only events: onboarding chips, trusted
  accounts, and thumbs. Every save inserts a new profile version; the previous
  versions stay, so a reader's taste has a history. The document is passed to
  the editor as context; it is not embeddings and it is not training.

  A thumb is a statement about tomorrow's fold, not today's paper. It appends
  an event immediately and bumps the version, and nothing on the current page
  changes because of it.
  """

  import Ecto.Query

  alias Frontier.Clock
  alias Frontier.Profiles.{Chips, Event, Profile}
  alias Frontier.Readers
  alias Frontier.Readers.Reader
  alias Frontier.Repo

  @default_document %{
    "chips" => [],
    "trusted_accounts" => [],
    "avoid" => [],
    "thumbs" => %{},
    "thumb_counts" => %{"up" => 0, "down" => 0}
  }

  @type summary :: %{
          version: non_neg_integer(),
          chips: [{String.t(), String.t()}],
          trusted_accounts: [String.t()],
          avoid: [String.t()],
          thumbs: map(),
          thumb_counts: map()
        }

  @doc "The shape of a new taste document."
  @spec default_document() :: map()
  def default_document, do: @default_document

  @doc "The latest profile version for a reader, or a version-zero view."
  @spec current(Reader.t()) :: Profile.t()
  def current(%Reader{} = reader) do
    case latest(reader) do
      nil ->
        %Profile{
          reader_id: reader.id,
          version: 0,
          document: @default_document
        }

      profile ->
        profile
    end
  end

  defp latest(reader) do
    Repo.one(
      from profile in Profile,
        where: profile.reader_id == ^reader.id,
        order_by: [desc: profile.version],
        limit: 1
    )
  end

  @doc """
  Saves the onboarding choices as one new profile version.

  `chips` is a list of chip keys; `accounts` is a comma-separated string or a
  list. Unknown chips are ignored rather than stored, so the profile only ever
  contains interests the paper understands.
  """
  @spec onboard(Reader.t(), [String.t()], String.t() | [String.t()]) ::
          {:ok, Profile.t()} | {:error, term()}
  def onboard(%Reader{} = reader, chips, accounts) do
    chip_events =
      chips
      |> List.wrap()
      |> Enum.filter(&Chips.valid?/1)
      |> Enum.uniq()
      |> Enum.map(&event("chip", &1, "add"))

    account_events =
      accounts
      |> parse_accounts()
      |> Enum.map(&event("trusted_account", &1, "add"))

    apply_events(reader, chip_events ++ account_events)
  end

  @doc "Appends a thumb and saves a new profile version."
  @spec thumb(Reader.t(), String.t(), Date.t() | nil, String.t()) ::
          {:ok, Profile.t()} | {:error, term()}
  def thumb(%Reader{} = reader, story, edition_day, value) when value in ["up", "down"] do
    if is_binary(story) and String.trim(story) != "" do
      apply_events(reader, [
        %{
          kind: "thumb_" <> value,
          target: String.trim(story),
          value: value,
          edition_day: edition_day
        }
      ])
    else
      {:error, :invalid_story}
    end
  end

  def thumb(_reader, _story, _day, _value), do: {:error, :invalid_thumb}

  @doc "The profile view for a reader who has not saved anything."
  @spec empty_summary() :: summary()
  def empty_summary do
    %{
      version: 0,
      chips: [],
      trusted_accounts: [],
      avoid: [],
      thumbs: %{},
      thumb_counts: %{"up" => 0, "down" => 0}
    }
  end

  @doc "The profile's events, oldest first."
  @spec events(Reader.t()) :: [Event.t()]
  def events(%Reader{} = reader) do
    Repo.all(
      from event in Event,
        where: event.reader_id == ^reader.id,
        order_by: [asc: event.id]
    )
  end

  @doc "A view for the reader's own page."
  @spec summary(Reader.t()) :: summary()
  def summary(%Reader{} = reader) do
    profile = current(reader)
    document = profile.document || @default_document

    %{
      version: profile.version,
      chips:
        document
        |> Map.get("chips", [])
        |> Enum.filter(&Chips.valid?/1)
        |> Enum.map(&{&1, Chips.label(&1)}),
      trusted_accounts: Map.get(document, "trusted_accounts", []),
      avoid: Map.get(document, "avoid", []),
      thumbs: Map.get(document, "thumbs", %{}),
      thumb_counts: Map.get(document, "thumb_counts", %{"up" => 0, "down" => 0})
    }
  end

  @doc """
  Erases a reader, their profile versions and their events.

  Deleting is the reader's right; it is not an edit to the append-only history.
  The cookie is cleared by the controller, so the erased identity is not reused.
  """
  @spec forget(Reader.t()) :: :ok
  def forget(%Reader{} = reader) do
    Repo.delete!(reader)
    :ok
  end

  defp apply_events(%Reader{} = reader, events) do
    now = Clock.now()

    Repo.transaction(fn ->
      reader = Readers.touch(reader)
      current = current(reader)
      document = Enum.reduce(events, current.document, &apply_event/2)
      version = current.version + 1

      profile =
        %Profile{}
        |> Profile.changeset(%{
          reader_id: reader.id,
          version: version,
          document: document,
          inserted_at: now
        })
        |> Repo.insert!()

      Enum.each(events, fn attrs ->
        %Event{}
        |> Event.changeset(%{
          reader_id: reader.id,
          kind: attrs.kind,
          target: attrs.target,
          value: attrs.value,
          edition_day: attrs[:edition_day],
          inserted_at: now
        })
        |> Repo.insert!()
      end)

      profile
    end)
  end

  defp apply_event(%{kind: "chip", target: chip}, document) when is_binary(chip) do
    if Chips.valid?(chip), do: add_unique(document, "chips", chip), else: document
  end

  defp apply_event(%{kind: "trusted_account", target: account}, document)
       when is_binary(account) do
    add_unique(document, "trusted_accounts", account)
  end

  defp apply_event(%{kind: "avoid", target: account}, document) when is_binary(account) do
    add_unique(document, "avoid", account)
  end

  defp apply_event(%{kind: "thumb_up", target: story} = attrs, document)
       when is_binary(story) do
    put_thumb(document, story, "up", attrs)
  end

  defp apply_event(%{kind: "thumb_down", target: story} = attrs, document)
       when is_binary(story) do
    put_thumb(document, story, "down", attrs)
  end

  defp apply_event(_event, document), do: document

  defp add_unique(document, key, value) do
    values =
      document
      |> Map.get(key, [])
      |> List.wrap()
      |> Kernel.++([value])
      |> Enum.uniq()
      |> Enum.sort()

    Map.put(document, key, values)
  end

  defp put_thumb(document, story, value, _attrs) do
    thumbs = document |> Map.get("thumbs", %{}) |> Map.put(story, value)

    counts =
      document
      |> Map.get("thumb_counts", %{"up" => 0, "down" => 0})
      |> Map.update(value, 1, &(&1 + 1))

    document
    |> Map.put("thumbs", thumbs)
    |> Map.put("thumb_counts", counts)
  end

  defp event(kind, target, value), do: %{kind: kind, target: target, value: value}

  defp parse_accounts(accounts) when is_binary(accounts) do
    accounts
    |> String.split([",", "\n"], trim: true)
    |> parse_accounts()
  end

  defp parse_accounts(accounts) when is_list(accounts) do
    accounts
    |> Enum.map(&normalize_account/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_accounts(_accounts), do: []

  defp normalize_account(account) when is_binary(account) do
    account =
      account
      |> String.trim()
      |> String.trim_leading("@")
      |> String.downcase()

    case account do
      "" -> nil
      account -> account
    end
  end

  defp normalize_account(_account), do: nil
end
