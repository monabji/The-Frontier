defmodule Frontier.Repo.Migrations.AddCanonicalIdentityToRawItems do
  use Ecto.Migration

  def up do
    # Phase-1 rows predate canonical identity, so they are cleared: the next
    # fetch rebuilds the pool, and nothing has been published from it yet.
    execute("DELETE FROM raw_items")

    alter table(:raw_items) do
      # The identity clustering will key on. Phase-1 rows predate it and carry
      # no canonical form, so they are cleared: the next fetch rebuilds the
      # pool, and nothing has been published from it yet.
      add :canonical_url, :string
      add :content_hash, :string
      add :kind, :string
      add :edition_day, :date
      add :run_id, :integer
      add :first_seen_at, :utc_datetime
    end

    # HN's upvotes are one source's score, not a universal one.
    rename table(:raw_items), :points, to: :score

    create index(:raw_items, [:run_id])

    create index(:raw_items, [:edition_day, :canonical_url])
    create index(:raw_items, [:content_hash])

    create table(:runs) do
      add :stage, :string, null: false
      add :source, :string, null: false
      add :edition_day, :date, null: false
      add :status, :string, null: false
      add :fetched, :integer, null: false, default: 0
      add :inserted, :integer, null: false, default: 0
      add :updated, :integer, null: false, default: 0
      add :skipped, :integer, null: false, default: 0
      add :duration_ms, :integer
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:runs, [:edition_day, :stage])
  end

  def down do
    drop table(:runs)

    alter table(:raw_items) do
      remove :canonical_url
      remove :content_hash
      remove :kind
      remove :edition_day
      remove :first_seen_at
    end
  end
end
