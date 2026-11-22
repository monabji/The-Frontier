defmodule Frontier.Repo.Migrations.CreateEditionsAndEditorRuns do
  use Ecto.Migration

  def change do
    create table(:editions) do
      add :day, :date, null: false
      add :status, :string, null: false, default: "draft"
      add :desk_note, :text
      add :read_minutes, :integer
      add :word_count, :integer, null: false, default: 0
      add :story_count, :integer, null: false, default: 0
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One edition a day: a paper is not a feed.
    create unique_index(:editions, [:day])
    create index(:editions, [:status, :day])

    create table(:edition_entries) do
      # A story can be deleted by a cluster rebuild after the edition was
      # written; the entry keeps its own copy and link, so the printed paper
      # does not depend on the pool staying still.
      add :edition_id, references(:editions, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :nilify_all)
      add :section, :string, null: false
      add :position, :integer, null: false
      add :kind, :string, null: false
      add :origin, :string, null: false, default: "edition"

      add :headline, :string, null: false
      add :dek, :text
      add :summary, :text, null: false
      add :quote, :text
      add :url, :string, null: false
      add :canonical_url, :string, null: false
      add :primary_source, :string
      add :source_label, :string
      add :discussion_url, :string
      add :score, :integer
      add :comments_count, :integer
      add :published_at, :utc_datetime
      add :word_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # The paper prints a story at most once, and one slot holds one story.
    create unique_index(:edition_entries, [:edition_id, :canonical_url])
    create unique_index(:edition_entries, [:edition_id, :section, :position])
    create index(:edition_entries, [:edition_id, :section])

    # Why a story the editor chose is not on the page. The paper never hides a
    # drop: this is the audit trail the run log reads.
    create table(:editor_rejections) do
      add :edition_day, :date, null: false
      add :story_id, :integer
      add :headline, :string
      add :reason, :string, null: false
      add :detail, :text
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:editor_rejections, [:edition_day])

    # What an editor run cost. Micro-dollars keep the arithmetic in integers.
    alter table(:runs) do
      add :model, :string
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_micros, :integer, null: false, default: 0
    end
  end
end
