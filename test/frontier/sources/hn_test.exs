defmodule Frontier.Sources.HNTest do
  use ExUnit.Case, async: true

  alias Frontier.Fixtures
  alias Frontier.Sources.HN
  alias Frontier.Sources.Item

  describe "fetch/1" do
    test "asks the client for the front page and returns the payload" do
      payload = Fixtures.hn_front_page()
      parent = self()

      client = fn url ->
        send(parent, {:fetched, url})
        {:ok, payload}
      end

      assert {:ok, ^payload} = HN.fetch(client: client)

      assert_received {:fetched, url}
      assert url == "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30"
    end

    test "passes a failed request back as an error instead of raising" do
      client = fn _url -> {:error, :timeout} end

      assert {:error, :timeout} = HN.fetch(client: client)
    end
  end

  describe "normalize/1" do
    setup do
      %{payload: Fixtures.hn_front_page()}
    end

    test "turns the recorded front page into one item per story", %{payload: payload} do
      assert {:ok, items} = HN.normalize(payload)

      assert length(items) == 30
      assert Enum.all?(items, &match?(%Item{}, &1))
      assert Enum.map(items, & &1.position) == Enum.to_list(1..30)
      assert Enum.all?(items, &(&1.external_id != "" and &1.title != ""))
    end

    test "keeps the fields the paper will print and link", %{payload: payload} do
      assert {:ok, [lead | _]} = HN.normalize(payload)

      assert lead.external_id == "50579568"
      assert lead.title == "Hurried Announcement: Alessandro Masullo GRH"

      assert lead.url ==
               "https://math216.wordpress.com/2026/11/20/hurried-announcement-alessandro-masullo-grh/"

      assert lead.author == "jasondavies"
      assert lead.score == 2370
      assert lead.comments_count == 1150
      assert lead.discussion_url == "https://news.ycombinator.com/item?id=50579568"
      assert lead.published_at == ~U[2026-11-20 18:33:14Z]
    end

    test "keeps what HN says the hit is" do
      assert {:ok, items} = HN.normalize(Fixtures.hn_front_page())

      assert Enum.find(items, &(&1.external_id == "50583761")).kind == :ask
      assert Enum.find(items, &(&1.external_id == "50593679")).kind == :job
      assert Enum.find(items, &(&1.external_id == "50579568")).kind == :story
    end

    test "links a post with no outside URL to its discussion", %{payload: payload} do
      assert {:ok, items} = HN.normalize(payload)

      ask_hn = Enum.find(items, &(&1.external_id == "50583761"))

      assert ask_hn.title =~ "Ask HN:"
      assert ask_hn.url == "https://news.ycombinator.com/item?id=50583761"
      assert ask_hn.discussion_url == ask_hn.url
    end

    test "stores the story text as plain text, not markup", %{payload: payload} do
      assert {:ok, items} = HN.normalize(payload)

      ask_hn = Enum.find(items, &(&1.external_id == "50583761"))

      assert ask_hn.text =~ "I'm Senior software engineer in the US"
      refute ask_hn.text =~ "<p>"
      refute ask_hn.text =~ "&#x27;"
      refute ask_hn.text =~ "<a href"
    end

    test "every item has a working-looking link", %{payload: payload} do
      assert {:ok, items} = HN.normalize(payload)

      for item <- items do
        assert %URI{scheme: scheme, host: host} = URI.parse(item.url)
        assert scheme in ["http", "https"]
        assert host not in [nil, ""]
      end
    end

    test "skips hits it cannot print instead of inventing them" do
      payload = %{
        "hits" => [
          %{"objectID" => "1", "title" => "Real story", "url" => "https://example.com/a"},
          %{"objectID" => "2", "title" => nil, "url" => "https://example.com/b"},
          %{"title" => "No id", "url" => "https://example.com/c"},
          %{
            "objectID" => "3",
            "title" => "Another real story",
            "url" => "https://example.com/d"
          }
        ]
      }

      assert {:ok, [first, second]} = HN.normalize(payload)
      assert {first.external_id, first.position} == {"1", 1}
      assert {second.external_id, second.position} == {"3", 2}
    end

    test "rejects a payload that is not a front page" do
      assert {:error, :unexpected_payload} = HN.normalize(%{"message" => "nope"})
    end
  end
end
