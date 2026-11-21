defmodule Frontier.Sources.CanonicalTest do
  use ExUnit.Case, async: true

  alias Frontier.Sources.{Canonical, Item}

  describe "normalize/1" do
    test "lowercases the scheme and host but leaves the path alone" do
      assert Canonical.normalize("HTTPS://Example.COM/Blog/Post") ==
               "https://example.com/Blog/Post"
    end

    test "drops the fragment, which is a place in a page, not another page" do
      assert Canonical.normalize("https://example.com/post#section-3") ==
               "https://example.com/post"
    end

    test "drops campaign parameters and keeps the ones that choose content" do
      assert Canonical.normalize(
               "https://example.com/post?id=7&utm_source=hn&utm_medium=social&fbclid=abc"
             ) == "https://example.com/post?id=7"
    end

    test "drops the empty query left behind by the campaign parameters" do
      assert Canonical.normalize("https://example.com/post?utm_campaign=launch&utm_term=ai") ==
               "https://example.com/post"
    end

    test "orders the remaining query so two spellings are one URL" do
      assert Canonical.normalize("https://example.com/p?b=2&a=1") ==
               Canonical.normalize("https://example.com/p?a=1&b=2")
    end

    test "drops a trailing slash unless it is the root" do
      assert Canonical.normalize("https://example.com/post/") == "https://example.com/post"
      assert Canonical.normalize("https://example.com/") == "https://example.com/"
    end

    test "drops the port when it is the scheme's default" do
      assert Canonical.normalize("https://example.com:443/post") == "https://example.com/post"
      assert Canonical.normalize("http://example.com:80/post") == "http://example.com/post"
    end

    test "keeps a port that is not the default" do
      assert Canonical.normalize("https://example.com:8443/post") ==
               "https://example.com:8443/post"
    end

    test "keeps http and https apart: they are different requests" do
      refute Canonical.normalize("http://example.com/post") ==
               Canonical.normalize("https://example.com/post")
    end

    test "refuses anything that is not a web link" do
      assert Canonical.normalize("javascript:alert(1)") == nil
      assert Canonical.normalize("mailto:someone@example.com") == nil
      assert Canonical.normalize("/relative/path") == nil
      assert Canonical.normalize("") == nil
      assert Canonical.normalize(nil) == nil
    end
  end

  describe "content_hash/1" do
    test "is the same for the same story seen twice" do
      a = %Item{
        external_id: "1",
        title: "Inkling 2 Mini",
        url: "https://example.com/a?utm_source=x"
      }

      b = %Item{external_id: "2", title: "Inkling 2 Mini", url: "https://example.com/a"}

      assert Canonical.content_hash(a) == Canonical.content_hash(b)
    end

    test "changes when the story changes" do
      a = %Item{external_id: "1", title: "Inkling 2 Mini", url: "https://example.com/a"}
      b = %Item{external_id: "1", title: "Inkling 2 Mini, updated", url: "https://example.com/a"}

      refute Canonical.content_hash(a) == Canonical.content_hash(b)
    end

    test "is a hex digest" do
      item = %Item{external_id: "1", title: "A story", url: "https://example.com/a"}

      assert Canonical.content_hash(item) =~ ~r/\A[0-9a-f]{64}\z/
    end
  end

  describe "follow_redirects/2" do
    test "leaves an ordinary https link alone without asking anyone" do
      resolver = fn _url -> flunk("nothing to resolve") end

      item = %Item{external_id: "1", title: "Post", url: "https://example.com/post"}

      assert [^item] = Canonical.follow_redirects([item], resolver)
    end

    test "follows a link shortener to the page it points at" do
      resolver = fn "https://t.co/abc" -> {:ok, "https://example.com/post"} end

      item = %Item{external_id: "1", title: "Post", url: "https://t.co/abc"}

      assert [%Item{url: "https://example.com/post"}] =
               Canonical.follow_redirects([item], resolver)
    end

    test "upgrades a plain http link through the resolver" do
      resolver = fn "http://example.com/post" -> {:ok, "https://example.com/post"} end

      item = %Item{external_id: "1", title: "Post", url: "http://example.com/post"}

      assert [%Item{url: "https://example.com/post"}] =
               Canonical.follow_redirects([item], resolver)
    end

    test "keeps the link it had when the resolver cannot say" do
      resolver = fn _url -> {:error, :timeout} end

      item = %Item{external_id: "1", title: "Post", url: "https://bit.ly/xyz"}

      assert [%Item{url: "https://bit.ly/xyz"}] = Canonical.follow_redirects([item], resolver)
    end
  end
end
