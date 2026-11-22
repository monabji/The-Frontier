defmodule Frontier.Repo.Migrations.AddArtifactToEditions do
  use Ecto.Migration

  def change do
    alter table(:editions) do
      # The artifact is the paper's record; these columns point at the version
      # the database considers current. The files remain after a republish.
      add :artifact_hash, :string
      add :artifact_path, :string
      add :built_at, :utc_datetime
      add :frozen_at, :utc_datetime
    end

    create index(:editions, [:frozen_at])
  end
end
