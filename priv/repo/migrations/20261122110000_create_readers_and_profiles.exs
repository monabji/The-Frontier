defmodule Frontier.Repo.Migrations.CreateReadersAndProfiles do
  use Ecto.Migration

  def change do
    create table(:readers) do
      # The signed anonymous identity. There is no email, password or account.
      add :public_id, :string, null: false
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:readers, [:public_id])

    # Every save is a new version; older versions are never edited. The document
    # is JSON text read through Frontier.Profiles.Document.
    create table(:profiles) do
      add :reader_id, references(:readers, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :document, :text, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:profiles, [:reader_id, :version])
    create index(:profiles, [:reader_id])

    # Append-only: a chip, a trusted account, a thumb. Nothing rewrites a row.
    create table(:profile_events) do
      add :reader_id, references(:readers, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :target, :string
      add :value, :string
      add :edition_day, :date
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:profile_events, [:reader_id])
    create index(:profile_events, [:reader_id, :kind])
  end
end
