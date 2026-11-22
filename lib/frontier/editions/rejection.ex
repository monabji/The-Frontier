defmodule Frontier.Editions.Rejection do
  @moduledoc """
  A story the editor chose that did not print, and why.

  Grounding failures are sent back once and then dropped. Dropping silently
  would let the pipeline's quality rot unnoticed, so every drop is a row: the
  run log, the admin page and a human reading the edition's notes can see it.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "editor_rejections" do
    field :edition_day, :date
    field :story_id, :integer
    field :headline, :string
    field :reason, :string
    field :detail, :string
    field :inserted_at, :utc_datetime
  end
end
