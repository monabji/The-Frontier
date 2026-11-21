defmodule Frontier.HTTPTest do
  use ExUnit.Case, async: false

  alias Frontier.HTTP

  describe "when the network is disabled" do
    test "a request returns an error instead of going out" do
      assert HTTP.get("https://example.com/") == {:error, :network_disabled}
      assert HTTP.get_json("https://example.com/") == {:error, :network_disabled}
      assert HTTP.get_xml("https://example.com/") == {:error, :network_disabled}
      assert HTTP.final_url("https://example.com/") == {:error, :network_disabled}
    end

    test "the guard covers redirect resolution, not just fetching" do
      # The test environment is where a forgotten client must not turn into a
      # real request; both entry points are checked.
      refute HTTP.network?()
    end
  end

  describe "decode_body/2" do
    test "gunzips a gzipped body, because most feeds send one" do
      payload = :zlib.gzip("<rss>compressed</rss>")

      assert HTTP.decode_body([{~c"content-encoding", ~c"gzip"}], payload) ==
               "<rss>compressed</rss>"
    end

    test "leaves a plain body alone" do
      assert HTTP.decode_body([{~c"content-type", ~c"text/xml"}], "<rss/>") == "<rss/>"
    end

    test "leaves a body it cannot decode rather than crashing" do
      assert HTTP.decode_body([{~c"content-encoding", ~c"gzip"}], "not gzip") == "not gzip"
    end
  end
end
