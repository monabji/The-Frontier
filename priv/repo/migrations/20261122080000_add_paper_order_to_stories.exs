defmodule Frontier.Repo.Migrations.AddPaperOrderToStories do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      # The paper's ordering is a source's own rank, interleaved across sources;
      # a story keeps the best rank any of its items had.
      add :sort_position, :integer
      add :primary_source, :string
    end

    create index(:stories, [:edition_day, :sort_position])
  end
end
