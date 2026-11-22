defmodule Frontier.Sources.BlueskyTest do
  use ExUnit.Case, async: true

  alias Frontier.Sources.{Bluesky, Item}

  describe "fetch/1" do
    test "asks for each account's feed" do
      parent = self()

      client = fn url ->
        send(parent, {:fetched, url})
        {:ok, %{"feed" => []}}
      end

      assert {:ok, feeds} = Bluesky.fetch(client: client)
      assert length(feeds) == length(Bluesky.actors())

      for actor <- Bluesky.actors() do
        assert_received {:fetched, url}
        assert url =~ "actor=#{URI.encode_www_form(actor)}"
      end
    end

    test "one failing account does not lose the others" do
      client = fn url ->
        if url =~ "karpathy" do
          {:error, :timeout}
        else
          {:ok, %{"feed" => []}}
        end
      end

      assert {:ok, feeds} = Bluesky.fetch(client: client)
      assert length(feeds) == length(Bluesky.actors()) - 1
    end

    test "every account failing is an error, not an empty success" do
      client = fn _url -> {:error, :timeout} end

      assert {:error, {:every_account_failed, results}} = Bluesky.fetch(client: client)
      assert length(results) == length(Bluesky.actors())
    end
  end

  describe "normalize/1" do
    setup do
      %{payload: [{"simonwillison.net", payload()}]}
    end

    test "turns posts into items with a headline, a permalink and a time", %{payload: payload} do
      assert {:ok, items} = Bluesky.normalize(payload)

      assert items != []
      assert Enum.all?(items, &match?(%Item{}, &1))
      assert Enum.map(items, & &1.position) == Enum.to_list(1..length(items))

      first = hd(items)

      assert first.kind == :post
      assert first.title != ""
      refute first.title =~ "\n"
      assert first.url =~ ~r{\Ahttps://bsky\.app/profile/[^/]+/post/[a-z0-9]+\z}
      assert first.discussion_url == first.url
      assert first.author != nil
      assert first.published_at != nil
      assert first.external_id =~ "at://"
    end

    test "keeps an image from a post that has one", %{payload: payload} do
      assert {:ok, items} = Bluesky.normalize(payload)

      assert Enum.any?(items, fn item ->
               is_binary(item.image_url) and item.image_url =~ "cdn.bsky.app"
             end)
    end

    test "keeps the post text as plain text a quote could come from", %{payload: payload} do
      assert {:ok, [first | _]} = Bluesky.normalize(payload)

      assert first.text != nil
      refute first.text =~ "<script"
    end

    test "skips replies and reposts" do
      payload = [
        {"actor.test",
         %{
           "feed" => [
             %{"post" => post("at://did/app.bsky.feed.post/1", "A standalone post")},
             %{
               "post" => post("at://did/app.bsky.feed.post/2", "A reply"),
               "reply" => %{"root" => %{}}
             },
             %{
               "reason" => %{"$type" => "app.bsky.feed.defs#reasonRepost"},
               "post" => post("at://did/app.bsky.feed.post/3", "A repost")
             }
           ]
         }}
      ]

      assert {:ok, [item]} = Bluesky.normalize(payload)
      assert item.title == "A standalone post"
    end

    test "skips a post with no words" do
      payload = [
        {"actor.test", %{"feed" => [%{"post" => post("at://did/app.bsky.feed.post/4", "")}]}}
      ]

      assert {:ok, []} = Bluesky.normalize(payload)
    end

    test "refuses a payload that is not a feed" do
      assert {:error, :unexpected_payload} = Bluesky.normalize(%{"nope" => true})
    end
  end

  defp payload do
    "test/fixtures/bsky/simonwillison.json" |> File.read!() |> Jason.decode!()
  end

  defp post(uri, text) do
    %{
      "uri" => uri,
      "author" => %{"handle" => "actor.test"},
      "record" => %{"text" => text, "createdAt" => "2026-11-20T10:00:00Z"},
      "likeCount" => 12,
      "replyCount" => 3
    }
  end
end
