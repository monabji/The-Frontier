defmodule Frontier.Readers do
  @moduledoc """
  Anonymous identity: a random id in a signed cookie, and nothing else.

  There are no accounts, passwords or emails in v1. The cookie carries a signed
  random string; the database has a row per reader so a profile and its events
  have an owner. Reading the cookie never queries the database: a new reader is
  created lazily on their first save, which keeps the artifact page free of
  identity lookups.

  A saveable recovery link signs the same id with a different salt. Opening it
  in a browser with no cookie re-binds that id, so a cleared browser is not
  automatically a lost profile.
  """

  import Ecto.Query

  alias Frontier.Clock
  alias Frontier.Readers.Reader
  alias Frontier.Repo

  @cookie "frontier_reader"
  @cookie_max_age 60 * 60 * 24 * 730
  @cookie_salt "reader"
  @recovery_salt "reader-recovery"

  @doc "The cookie's name, for the privacy page and tests."
  @spec cookie_name() :: String.t()
  def cookie_name, do: @cookie

  @doc "How long the cookie lives, in seconds."
  @spec cookie_max_age() :: pos_integer()
  def cookie_max_age, do: @cookie_max_age

  @doc "A new unguessable reader id."
  @spec new_id() :: String.t()
  def new_id, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  @doc "The signed value the cookie holds for a reader id."
  @spec sign(String.t()) :: String.t()
  def sign(public_id), do: Phoenix.Token.sign(secret(), @cookie_salt, public_id)

  @doc "The reader id in a signed cookie value, if it is genuine."
  @spec verify(String.t()) :: {:ok, String.t()} | {:error, term()}
  def verify(token) do
    Phoenix.Token.verify(secret(), @cookie_salt, token, max_age: @cookie_max_age)
  end

  @doc "A saveable link token for a reader id."
  @spec recovery_token(String.t()) :: String.t()
  def recovery_token(public_id), do: Phoenix.Token.sign(secret(), @recovery_salt, public_id)

  @doc "The reader id in a recovery link token, if it is genuine."
  @spec verify_recovery(String.t()) :: {:ok, String.t()} | {:error, term()}
  def verify_recovery(token) do
    Phoenix.Token.verify(secret(), @recovery_salt, token, max_age: @cookie_max_age)
  end

  @doc "The reader id from the request's cookie, without touching the database."
  @spec read_cookie(Plug.Conn.t()) :: {:ok, String.t()} | :none
  def read_cookie(conn) do
    with token when is_binary(token) <- conn.cookies[@cookie],
         {:ok, public_id} <- verify(token) do
      {:ok, public_id}
    else
      _ -> :none
    end
  end

  @doc "Sets the reader cookie."
  @spec put_cookie(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_cookie(conn, public_id) do
    Plug.Conn.put_resp_cookie(conn, @cookie, sign(public_id),
      http_only: true,
      same_site: "Lax",
      max_age: @cookie_max_age,
      secure: secure?()
    )
  end

  @doc "Clears the reader cookie."
  @spec clear_cookie(Plug.Conn.t()) :: Plug.Conn.t()
  def clear_cookie(conn), do: Plug.Conn.delete_resp_cookie(conn, @cookie)

  @doc """
  The reader row for an id, created on first save and touched afterwards.
  """
  @spec ensure(String.t()) :: Reader.t()
  def ensure(public_id) when is_binary(public_id) do
    now = Clock.now()

    %Reader{}
    |> Reader.changeset(%{public_id: public_id, first_seen_at: now, last_seen_at: now})
    |> Repo.insert!(
      on_conflict: {:replace, [:last_seen_at]},
      conflict_target: :public_id
    )

    Repo.get_by!(Reader, public_id: public_id)
  end

  @doc "Records that the reader was seen, without changing their profile."
  @spec touch(Reader.t()) :: Reader.t()
  def touch(%Reader{} = reader) do
    reader
    |> Reader.changeset(%{last_seen_at: Clock.now()})
    |> Repo.update!()
  end

  @doc "The reader row for an id, or nil."
  @spec get(String.t()) :: Reader.t() | nil
  def get(public_id), do: Repo.one(from reader in Reader, where: reader.public_id == ^public_id)

  defp secure?, do: Application.get_env(:frontier, :secure_cookies, false)

  defp secret do
    :frontier
    |> Application.fetch_env!(FrontierWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
