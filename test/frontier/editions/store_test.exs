defmodule Frontier.Editions.StoreTest do
  use ExUnit.Case, async: false

  alias Frontier.Editions.{Artifact, Edition, Entry, Store}
  alias Frontier.EditionStorage

  @day ~D[2026-11-22]

  setup do
    EditionStorage.tmp!()
  end

  defp entry(headline) do
    %Entry{
      section: "Front Page",
      position: 1,
      kind: "lead",
      headline: headline,
      summary: "A summary.",
      quote: "A quote.",
      url: "https://example.com/story",
      canonical_url: "https://example.com/story",
      source_label: "OpenAI",
      word_count: 4
    }
  end

  defp artifact(day \\ @day, headline \\ "A headline") do
    Artifact.build(%Edition{
      day: day,
      status: "draft",
      desk_note: "A quiet day.",
      read_minutes: 9,
      word_count: 1_900,
      story_count: 1,
      entries: [entry(headline)]
    })
  end

  describe "writing and reading a day" do
    test "stores JSON and HTML under the day, and reads the current version" do
      artifact = artifact()

      assert {:ok, stored} = Store.write(artifact, "<h1>A headline</h1>")
      assert stored.hash == artifact.hash
      assert File.exists?(Path.join(stored.dir, artifact.hash <> ".json"))
      assert File.exists?(Path.join(stored.dir, artifact.hash <> ".html"))

      read = Store.read(@day)
      assert read.hash == artifact.hash
      assert read.sections == artifact.sections
      assert {:ok, html} = Store.html(@day)
      assert html == "<h1>A headline</h1>"
    end

    test "a second version becomes current and the first stays on disk" do
      first = artifact(@day, "The first")
      second = artifact(@day, "The second")

      {:ok, _} = Store.write(first, "first")
      {:ok, _} = Store.write(second, "second")

      assert Store.read(@day).hash == second.hash
      assert File.exists?(Path.join(Store.day_dir(@day), first.hash <> ".json"))
      assert File.exists?(Path.join(Store.day_dir(@day), second.hash <> ".json"))
    end

    test "writing the same artifact twice is idempotent" do
      artifact = artifact()
      {:ok, first} = Store.write(artifact, "html")
      {:ok, second} = Store.write(artifact, "html")

      assert first.hash == second.hash
      assert Store.read(@day).hash == artifact.hash
    end
  end

  describe "the archive" do
    test "lists every day with an artifact, newest last" do
      other = Date.add(@day, -1)

      {:ok, _} = Store.write(artifact(other), "old")
      {:ok, _} = Store.write(artifact(@day), "new")

      assert Store.days() == [other, @day]
      assert Store.latest().day == @day
    end

    test "a directory without a current pointer is not an edition" do
      File.mkdir_p!(Store.day_dir(@day))
      assert Store.days() == []
      assert Store.latest() == nil
      assert Store.read(@day) == nil
    end
  end

  describe "freezing" do
    test "a frozen day cannot be written again" do
      artifact = artifact()
      {:ok, _} = Store.write(artifact, "html")
      assert :ok = Store.freeze(@day)

      assert {:error, :edition_is_frozen} =
               Store.write(artifact(@day, "A replacement"), "new html")

      assert Store.read(@day).hash == artifact.hash
      assert {:ok, "html"} = Store.html(@day)
    end

    test "freezing a day with no artifact is an error" do
      assert {:error, :no_artifact} = Store.freeze(@day)
    end

    test "the frozen marker names the hash it froze" do
      artifact = artifact()
      {:ok, _} = Store.write(artifact, "html")
      :ok = Store.freeze(@day)

      marker = File.read!(Path.join(Store.day_dir(@day), "frozen"))
      assert String.trim(marker) == artifact.hash
    end
  end
end
