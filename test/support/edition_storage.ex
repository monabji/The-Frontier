defmodule Frontier.EditionStorage do
  @moduledoc """
  Per-test artifact storage.

  Artifacts are files, so a test that writes one must not see another test's
  edition. Each test gets a fresh directory and the previous configuration is
  restored afterwards.
  """

  import ExUnit.Callbacks

  @spec tmp!(keyword()) :: map()
  def tmp!(_context \\ []) do
    root =
      Path.join(
        System.tmp_dir!(),
        "frontier-editions-#{System.unique_integer([:positive, :monotonic])}"
      )

    previous = Application.get_env(:frontier, :edition_storage)
    Application.put_env(:frontier, :edition_storage, root)

    on_exit(fn ->
      File.rm_rf(root)

      if previous do
        Application.put_env(:frontier, :edition_storage, previous)
      else
        Application.delete_env(:frontier, :edition_storage)
      end
    end)

    %{edition_storage: root}
  end
end
