defmodule Frontier.Sources.RSSTest do
  use ExUnit.Case, async: true

  alias Frontier.Fixtures
  alias Frontier.Sources.{Item, RSS}
  alias Frontier.Sources.RSS.{GoogleAI, SimonWillison}

  describe "the feed list" do
    test "every feed is its own source with its own key and name" do
      feeds = RSS.feeds()
      keys = Enum.map(feeds, & &1.key())

      assert length(feeds) == 24
      assert length(Enum.uniq(keys)) == 24
      assert "rss:openai" in keys
      assert "rss:arstechnica" in keys
      assert Enum.all?(feeds, &String.starts_with?(&1.key(), "rss:"))
      assert Enum.all?(feeds, &(&1.label() != ""))
      assert Enum.all?(feeds, &String.starts_with?(&1.url(), "https://"))
    end

    test "every beat of the paper has a feed" do
      keys = RSS.feeds() |> Enum.map(& &1.key())

      for key <- ~w(rss:openai rss:deepmind rss:thehackernews rss:krebs rss:godot
                    rss:gamedeveloper rss:androiddev rss:reactnative rss:phoronix rss:lwn
                    rss:kubernetes rss:cncf rss:quanta rss:ieeespectrum
                    rss:quantumcomputingreport rss:coindesk rss:80lv rss:smashing rss:blender) do
        assert key in keys, "#{key} is missing from the feed list"
      end
    end
  end

  describe "normalize/1 on an RSS 2.0 feed" do
    setup do
      %{payload: File.read!("test/fixtures/rss/google-ai.xml")}
    end

    test "turns the feed into items in the order it printed them", %{payload: payload} do
      assert {:ok, items} = RSS.normalize(payload)

      assert items != []
      assert Enum.all?(items, &match?(%Item{}, &1))
      assert Enum.map(items, & &1.position) == Enum.to_list(1..length(items))
      assert Enum.all?(items, &(&1.kind == :post))
    end

    test "reads the title, the link and the publication date", %{payload: payload} do
      assert {:ok, [first | _]} = RSS.normalize(payload)

      assert first.title == "Introducing Tool Retrieval in the Gemini API"

      assert first.url ==
               "https://blog.google/innovation-and-ai/technology/developers-tools/gemini-api-tool-retrieval/"

      assert first.published_at.year == 2026
      assert first.author != ""
    end

    test "stores the body as plain text that could be quoted", %{payload: payload} do
      assert {:ok, [first | _]} = RSS.normalize(payload)

      assert first.text != nil
      refute first.text =~ "<"
      refute first.text =~ "&amp;"
      assert String.length(first.text) <= 4_000
    end

    test "keeps the feed's own image for the page" do
      assert {:ok, items} = RSS.normalize(File.read!("test/fixtures/rss/ars-technica.xml"))

      item = Enum.find(items, &(&1.title =~ "Godzilla"))

      assert item.image_url =~ "cdn.arstechnica.net"
      assert String.starts_with?(item.image_url, "https://")
    end

    test "gives every item a link the paper can print" do
      assert {:ok, items} = RSS.normalize(File.read!("test/fixtures/rss/google-ai.xml"))

      for item <- items do
        assert %URI{scheme: "https", host: host} = URI.parse(item.url)
        assert host != ""
      end
    end
  end

  describe "normalize/1 on an Atom feed" do
    setup do
      %{payload: File.read!("test/fixtures/rss/simon-willison-atom.xml")}
    end

    test "reads an Atom entry's link from its href", %{payload: payload} do
      assert {:ok, [first | _]} = RSS.normalize(payload)

      assert first.title != ""
      assert first.url =~ ~r{\Ahttps?://}
      assert first.published_at != nil
      assert first.external_id != nil
    end

    test "keeps no more than the newest thirty entries", %{payload: payload} do
      assert {:ok, items} = RSS.normalize(payload)
      assert length(items) == 30
    end
  end

  describe "normalize/1 on something that is not a feed" do
    test "says so instead of returning an empty page" do
      assert {:error, :unreadable_feed} = RSS.normalize("<html><body>404</body></html>")
    end

    test "refuses a payload that is not XML at all" do
      assert {:error, :unreadable_feed} = RSS.normalize("not xml")
      assert {:error, :unexpected_payload} = RSS.normalize(%{"no" => "feed"})
    end
  end

  describe "fetch/2" do
    test "asks the client for its own feed" do
      parent = self()

      client = fn url ->
        send(parent, {:fetched, url})
        {:ok, File.read!("test/fixtures/rss/google-ai.xml")}
      end

      assert {:ok, xml} = GoogleAI.fetch(client: client)
      assert is_binary(xml)
      assert_received {:fetched, "https://blog.google/technology/ai/rss/"}
    end

    test "accepts a raw response body from the HTTP layer" do
      client = fn _url -> {:ok, %{body: "<rss></rss>", status: 200}} end

      assert {:ok, "<rss></rss>"} = SimonWillison.fetch(client: client)
    end

    test "passes a failed request back as an error" do
      assert {:error, :timeout} = GoogleAI.fetch(client: fn _url -> {:error, :timeout} end)
    end
  end

  describe "fixtures" do
    test "the fixture loader reads both recorded feeds" do
      assert Fixtures.rss_fixture("google-ai.xml") =~ "<rss"
      assert Fixtures.rss_fixture("simon-willison-atom.xml") =~ "<feed"
    end
  end
end
