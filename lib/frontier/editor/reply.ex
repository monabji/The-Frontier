defmodule Frontier.Editor.Reply do
  @moduledoc """
  Reading the editor's decoded JSON reply.

  JSON keys are strings; every reader in the editor goes through here so a
  missing or malformed field is one behaviour, not five. These helpers never
  raise: a reply that is the wrong shape is caught by the plan's validation,
  where it can be reported rather than crashing the run.
  """

  @doc "A field of a decoded reply, or nil."
  @spec get(map() | term(), String.t()) :: term()
  def get(map, key) when is_map(map), do: Map.get(map, key)
  def get(_other, _key), do: nil

  @doc "A list of objects from a reply; anything else is empty."
  @spec list(map() | term(), String.t()) :: [map()]
  def list(map, key) do
    case get(map, key) do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _other -> []
    end
  end
end
