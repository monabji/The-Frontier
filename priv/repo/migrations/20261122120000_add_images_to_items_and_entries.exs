defmodule Frontier.Repo.Migrations.AddImagesToItemsAndEntries do
  use Ecto.Migration

  def change do
    alter table(:raw_items) do
      # The source's own image, stored as a URL with its credit. No image is
      # copied: the paper links to the source's asset.
      add :image_url, :string
    end

    alter table(:edition_entries) do
      add :image_url, :string
    end
  end
end
