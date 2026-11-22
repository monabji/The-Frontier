defmodule Frontier.Editions.Store do
  @moduledoc """
  Where editions live on disk, and the only thing that may write them.

  One directory per day holds content-addressed versions:

      priv/editions/2026-11-22/<hash>.json
      priv/editions/2026-11-22/<hash>.html
      priv/editions/2026-11-22/current      (the hash the page shows)
      priv/editions/2026-11-22/frozen       (the hash that may never move)

  Writing a new version for a draft moves `current`; writing for a frozen day
  is refused and leaves the frozen bytes untouched. The old version's files are
  never deleted: republishing a day creates a version, it does not erase one.

  The root is configuration (`:edition_storage`) so tests get their own
  directory and production gets the release's `priv`.
  """

  alias Frontier.Editions.Artifact

  @type write_result :: {:ok, map()} | {:error, term()}

  @doc "The directory artifacts live under."
  @spec root() :: String.t()
  def root do
    Application.get_env(
      :frontier,
      :edition_storage,
      Path.join(:code.priv_dir(:frontier), "editions")
    )
  end

  @doc "The directory for one day."
  @spec day_dir(Date.t()) :: String.t()
  def day_dir(%Date{} = day), do: Path.join(root(), Date.to_iso8601(day))

  @doc """
  Writes a version of the artifact and points the day at it.

  The JSON and HTML files are written only if absent: the same content hash is
  the same bytes, so a rebuild is idempotent. A frozen day is refused before
  anything is written.
  """
  @spec write(Artifact.t(), binary()) :: write_result()
  def write(%Artifact{} = artifact, html) when is_binary(html) do
    with_day_lock(artifact.day, fn -> do_write(artifact, html) end)
  end

  defp do_write(artifact, html) do
    dir = day_dir(artifact.day)

    if frozen?(artifact.day) do
      {:error, :edition_is_frozen}
    else
      File.mkdir_p!(dir)
      json_path = Path.join(dir, artifact.hash <> ".json")
      html_path = Path.join(dir, artifact.hash <> ".html")

      write_new(json_path, Artifact.canonical_json(Artifact.to_json(artifact)))
      write_new(html_path, html)
      write_pointer(Path.join(dir, "current"), artifact.hash)

      {:ok, %{hash: artifact.hash, dir: dir, json_path: json_path, html_path: html_path}}
    end
  end

  @doc "The current artifact for a day, or nil."
  @spec read(Date.t()) :: Artifact.t() | nil
  def read(%Date{} = day) do
    with hash when is_binary(hash) <- visible_hash(day),
         {:ok, json} <- read_json(day, hash) do
      Artifact.from_json(json)
    else
      _ -> nil
    end
  end

  @doc "A specific version of a day's artifact, or nil."
  @spec read(Date.t(), String.t()) :: Artifact.t() | nil
  def read(%Date{} = day, hash) when is_binary(hash) do
    case read_json(day, hash) do
      {:ok, json} -> Artifact.from_json(json)
      _ -> nil
    end
  end

  @doc "The current HTML snapshot for a day."
  @spec html(Date.t()) :: {:ok, binary()} | {:error, term()}
  def html(%Date{} = day) do
    with hash when is_binary(hash) <- visible_hash(day),
         path = Path.join(day_dir(day), hash <> ".html"),
         true <- File.exists?(path) do
      File.read(path)
    else
      _ -> {:error, :no_artifact}
    end
  end

  @doc "The newest artifact across all days, or nil."
  @spec latest() :: Artifact.t() | nil
  def latest do
    case days() do
      [] -> nil
      days -> days |> List.last() |> read()
    end
  end

  @doc "Every day with a current artifact, oldest first."
  @spec days() :: [Date.t()]
  def days do
    case File.ls(root()) do
      {:ok, names} ->
        names
        |> Enum.flat_map(&parse_day/1)
        |> Enum.filter(fn day -> File.exists?(Path.join(day_dir(day), "current")) end)
        |> Enum.sort(Date)

      {:error, _reason} ->
        []
    end
  end

  @doc "Freezes the current version of a day; it can never be written again."
  @spec freeze(Date.t()) :: :ok | {:error, term()}
  def freeze(%Date{} = day) do
    case current_hash(day) do
      nil ->
        {:error, :no_artifact}

      hash ->
        File.write!(Path.join(day_dir(day), "frozen"), hash <> "\n")
        :ok
    end
  end

  @doc "Whether a day has been frozen."
  @spec frozen?(Date.t()) :: boolean()
  def frozen?(%Date{} = day), do: File.exists?(Path.join(day_dir(day), "frozen"))

  @doc "The hash a frozen day is pinned to, or nil."
  @spec frozen_hash(Date.t()) :: String.t() | nil
  def frozen_hash(%Date{} = day) do
    case File.read(Path.join(day_dir(day), "frozen")) do
      {:ok, hash} ->
        case String.trim(hash) do
          "" -> nil
          hash -> hash
        end

      {:error, _reason} ->
        nil
    end
  end

  @doc "The hash the day currently shows, or nil."
  @spec current_hash(Date.t()) :: String.t() | nil
  def current_hash(%Date{} = day) do
    path = Path.join(day_dir(day), "current")

    case File.read(path) do
      {:ok, hash} ->
        case String.trim(hash) do
          "" -> nil
          hash -> hash
        end

      {:error, _reason} ->
        nil
    end
  end

  # A frozen day shows the hash named in its marker, even if the mutable
  # `current` pointer was moved by a stray write. The marker is the record.
  defp visible_hash(day), do: frozen_hash(day) || current_hash(day)

  # Freeze and write are two jobs; a check-then-write race could otherwise put
  # a version after the freeze. One lock per day makes the pair atomic inside
  # the node (the paper runs as one BEAM).
  defp with_day_lock(day, fun) do
    case :global.trans({__MODULE__, day}, fun) do
      :aborted -> {:error, :store_busy}
      result -> result
    end
  end

  defp read_json(day, hash) do
    path = Path.join(day_dir(day), hash <> ".json")

    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      _ -> {:error, :no_artifact}
    end
  end

  # A version file is content-addressed, so the only correct write is the one
  # that leaves identical bytes alone.
  defp write_new(path, content) do
    unless File.exists?(path), do: File.write!(path, content)
    :ok
  end

  # The pointer is replaced atomically so a reader never sees half a hash.
  defp write_pointer(path, hash) do
    temp = path <> ".tmp"
    File.write!(temp, hash <> "\n")
    File.rename!(temp, path)
  end

  defp parse_day(name) do
    case Date.from_iso8601(name) do
      {:ok, day} -> [day]
      {:error, _reason} -> []
    end
  end
end
