defmodule Frontier.Repo.Migrations.AddRejectedToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      # A run can see work it throws away. Overloading `updated` for drops made
      # the run log lie; drops get their own count.
      add :rejected, :integer, null: false, default: 0
    end
  end
end
