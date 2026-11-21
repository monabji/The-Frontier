defmodule Frontier.ClusteringFixtures do
  @moduledoc """
  The golden launch, as stored items.

  `launch/0` is the recorded three-source fixture as `{source, item}` pairs;
  `seed!/1` stores them without going through a run, so clustering tests can
  work on a known pool.
  """

  alias Frontier.Repo
  alias Frontier.Sources
  alias Frontier.Sources.{Item, RawItem}

  @path "test/fixtures/clusters/inkling-launch.json"

  @spec launch() :: [{String.t(), Item.t()}]
  def launch do
    @path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn entry -> {entry["source"], item(entry)} end)
  end

  @spec seed!(Date.t() | nil) :: [RawItem.t()]
  def seed!(day \\ nil) do
    day = day || Frontier.Newsroom.Dateline.edition_date()

    Enum.each(launch(), fn {source, item} ->
      {:ok, _counts} = Sources.upsert_items(source, [item], day: day)
    end)

    RawItem
    |> Repo.all()
    |> Enum.filter(fn item -> item.edition_day == day end)
  end

  defp item(entry) do
    %Item{
      external_id: entry["external_id"],
      title: entry["title"],
      url: entry["url"],
      discussion_url: entry["discussion_url"],
      kind: :post,
      score: entry["score"],
      published_at: parse(entry["published_at"])
    }
  end

  defp parse(nil), do: nil

  defp parse(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end
end
