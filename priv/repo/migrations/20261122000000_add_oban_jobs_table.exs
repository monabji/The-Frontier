defmodule Frontier.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 14)
  end

  # Migrate all the way back down, whatever version the database is on.
  def down do
    Oban.Migration.down(version: 1)
  end
end
