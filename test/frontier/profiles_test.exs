defmodule Frontier.ProfilesTest do
  use Frontier.DataCase, async: false

  alias Frontier.Profiles
  alias Frontier.Profiles.{Event, Profile}
  alias Frontier.Readers

  @day ~D[2026-11-22]

  setup do
    reader = Readers.ensure(Readers.new_id())
    %{reader: reader}
  end

  describe "onboarding" do
    test "saves chips and trusted accounts as one version with events", %{reader: reader} do
      assert {:ok, profile} =
               Profiles.onboard(
                 reader,
                 ["models", "research", "not-a-chip", "models"],
                 "simonwillison.net, @Karpathy.Bsky.Social, simonwillison.net"
               )

      assert profile.version == 1
      assert profile.document["chips"] == ["models", "research"]
      assert profile.document["trusted_accounts"] == ["karpathy.bsky.social", "simonwillison.net"]

      events = Profiles.events(reader)
      assert length(events) == 4
      assert Enum.any?(events, &(&1.kind == "chip" and &1.target == "models"))
      assert Enum.any?(events, &(&1.kind == "trusted_account"))
    end

    test "a second save is a new version, not an edit", %{reader: reader} do
      {:ok, _} = Profiles.onboard(reader, ["models"], "")
      {:ok, profile} = Profiles.onboard(reader, ["tooling"], "")

      assert profile.version == 2
      assert profile.document["chips"] == ["models", "tooling"]
      assert Repo.aggregate(Profile, :count) == 2
    end
  end

  describe "thumbs" do
    test "append an event, bump the version and are summarised", %{reader: reader} do
      {:ok, _} = Profiles.onboard(reader, ["models"], "")
      story = "https://example.com/a-story"

      assert {:ok, profile} = Profiles.thumb(reader, story, @day, "up")

      assert profile.version == 2
      assert profile.document["thumbs"] == %{story => "up"}
      assert profile.document["thumb_counts"] == %{"up" => 1, "down" => 0}

      [event] = Profiles.events(reader) |> Enum.take(-1)
      assert event.kind == "thumb_up"
      assert event.target == story
      assert event.edition_day == @day
    end

    test "a second thumb changes the map and counts both statements", %{reader: reader} do
      story = "https://example.com/a-story"

      {:ok, _} = Profiles.thumb(reader, story, @day, "up")
      {:ok, profile} = Profiles.thumb(reader, story, @day, "down")

      assert profile.version == 2
      assert profile.document["thumbs"] == %{story => "down"}
      assert profile.document["thumb_counts"] == %{"up" => 1, "down" => 1}
      assert length(Profiles.events(reader)) == 2
    end

    test "a malformed thumb is refused, not stored", %{reader: reader} do
      assert {:error, :invalid_thumb} =
               Profiles.thumb(reader, "https://example.com/x", @day, "sideways")

      assert {:error, :invalid_story} = Profiles.thumb(reader, "  ", @day, "up")
      assert Profiles.events(reader) == []
    end
  end

  describe "the reader's view" do
    test "prints labels for chips and the counts of thumbs", %{reader: reader} do
      {:ok, _} = Profiles.onboard(reader, ["models", "research"], "example.com")
      {:ok, _} = Profiles.thumb(reader, "https://example.com/x", @day, "up")

      summary = Profiles.summary(reader)

      assert summary.version == 2
      assert summary.chips == [{"models", "Models & releases"}, {"research", "Research"}]
      assert summary.trusted_accounts == ["example.com"]
      assert summary.thumb_counts == %{"up" => 1, "down" => 0}
    end
  end

  describe "erasing" do
    test "deletes the reader, every version and every event", %{reader: reader} do
      {:ok, _} = Profiles.onboard(reader, ["models"], "example.com")
      {:ok, _} = Profiles.thumb(reader, "https://example.com/x", @day, "down")

      assert :ok = Profiles.forget(reader)

      assert Repo.aggregate(Frontier.Readers.Reader, :count) == 0
      assert Repo.aggregate(Profile, :count) == 0
      assert Repo.aggregate(Event, :count) == 0
    end
  end
end
