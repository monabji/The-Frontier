defmodule Frontier.Profiles.Document do
  @moduledoc """
  The taste document as JSON text in SQLite.

  A profile is a readable map — chips, trusted accounts, an avoid list and a
  thumb history — not a model or an embedding. Storing it as JSON keeps the
  document inspectable and versioned, which is the whole point.
  """

  use Ecto.Type

  @impl true
  def type, do: :text

  @impl true
  def cast(document) when is_map(document), do: {:ok, document}
  def cast(_other), do: :error

  @impl true
  def load(nil), do: {:ok, %{}}

  def load(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, document} when is_map(document) -> {:ok, document}
      _ -> :error
    end
  end

  @impl true
  def dump(document) when is_map(document), do: {:ok, Jason.encode!(document)}
  def dump(_other), do: :error
end
