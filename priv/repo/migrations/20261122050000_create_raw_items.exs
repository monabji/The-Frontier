defmodule Frontier.Repo.Migrations.CreateRawItems do
  use Ecto.Migration

  def change do
    create table(:raw_items) do
      add :source, :string, null: false
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :url, :string, null: false
      add :discussion_url, :string
      add :author, :string
      add :text, :text
      add :points, :integer
      add :comments_count, :integer
      add :position, :integer
      add :published_at, :utc_datetime
      add :fetched_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # One row per source post, however many runs see it.
    create unique_index(:raw_items, [:source, :external_id])

    # The page asks for one source's items for one edition day.
    create index(:raw_items, [:source, :fetched_at])
  end
end
