defmodule Frontier.Repo.Migrations.CreateStories do
  use Ecto.Migration

  def change do
    create table(:stories) do
      add :edition_day, :date, null: false
      add :cluster_key, :string, null: false
      add :headline, :string, null: false
      add :canonical_url, :string, null: false
      add :primary_url, :string, null: false
      add :kind, :string
      add :item_count, :integer, null: false, default: 1
      add :source_count, :integer, null: false, default: 1
      add :first_published_at, :utc_datetime
      add :last_published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One story per event per day, and no article in two stories.
    create unique_index(:stories, [:edition_day, :cluster_key])
    create unique_index(:stories, [:edition_day, :canonical_url])

    create table(:story_items) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :raw_item_id, references(:raw_items, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:story_items, [:story_id, :raw_item_id])
    create index(:story_items, [:raw_item_id])
  end
end
