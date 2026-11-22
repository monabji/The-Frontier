defmodule Frontier.Readers.Reader do
  @moduledoc """
  One anonymous reader.

  `public_id` is a random, unguessable string; the browser holds it in a signed
  cookie. The row exists so a profile and its events have an owner. It holds no
  name, email, password or account.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "readers" do
    field :public_id, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @fields [:public_id, :first_seen_at, :last_seen_at]

  @doc false
  def changeset(reader, attrs) do
    reader
    |> cast(attrs, [:first_seen_at, :last_seen_at])
    |> put_public_id(reader, attrs)
    |> validate_required(@fields)
    |> unique_constraint(:public_id)
  end

  # The public id identifies the reader; it is set once, on creation, and is
  # never accepted from a params map on an update.
  defp put_public_id(changeset, %{id: nil}, attrs) do
    put_change(changeset, :public_id, attrs[:public_id] || attrs["public_id"])
  end

  defp put_public_id(changeset, _reader, _attrs), do: changeset
end
