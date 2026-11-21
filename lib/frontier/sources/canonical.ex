defmodule Frontier.Sources.Canonical do
  @moduledoc """
  One article, one URL.

  The same story arrives from a feed with a campaign string, from HN with a
  fragment, and from a shortener pointing at neither. Clustering cannot start
  from three identities, so every item is reduced to a canonical URL before it
  is stored:

    * scheme and host lowercased, `www.` dropped
    * `http` folded into `https`: the identity of an article is not the
      transport it was published over
    * default port dropped
    * fragment dropped — it names a place in the page, not another page
    * campaign parameters dropped, the rest of the query sorted
    * trailing slash dropped, except at the root

  Identity has to be a pure function of the URL, or re-running a cluster over
  the same pool could produce different stories whenever the network answers
  differently. Short links are still followed once, through an injected
  resolver, but a failure keeps the URL as it was rather than making identity
  depend on a request.
  """

  alias Frontier.Sources.Item

  @tracking_prefixes ["utm_"]
  @tracking_params [
    "fbclid",
    "gclid",
    "dclid",
    "msclkid",
    "mc_cid",
    "mc_eid",
    "igshid",
    "twclid",
    "ref_src",
    "ref",
    "__twitter_impression",
    "at_medium",
    "at_campaign"
  ]

  @shorteners [
    "bit.ly",
    "buff.ly",
    "dlvr.it",
    "ift.tt",
    "lnkd.in",
    "ow.ly",
    "rebrand.ly",
    "s.id",
    "t.co",
    "trib.al",
    "tinyurl.com"
  ]

  @doc """
  The canonical form of a web URL, or `nil` when the input is not one.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: nil

  def normalize(url) when is_binary(url) do
    uri = URI.parse(url)
    scheme = uri.scheme |> to_string() |> String.downcase()

    if scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      %URI{
        scheme: identity_scheme(scheme),
        host: uri.host |> String.downcase() |> strip_www(),
        port: kept_port(scheme, uri.port),
        path: path(uri.path),
        query: query(uri.query),
        fragment: nil,
        userinfo: nil
      }
      |> URI.to_string()
    end
  end

  def normalize(_url), do: nil

  @doc """
  A digest of what the item says, independent of where it lives.

  Title plus body text, whitespace collapsed and lowercased: the same article
  syndicated at two addresses hashes the same, which is what the clustering
  pool and the reprint window need. It is a fingerprint, not a merge key —
  dedupe is on the canonical URL.
  """
  @spec content_hash(Item.t()) :: String.t()
  def content_hash(%Item{} = item) do
    payload =
      [item.title, item.text]
      |> Enum.map(&utterance/1)
      |> Enum.join("\n")

    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  end

  defp utterance(nil), do: ""

  defp utterance(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc """
  Follows links that are known to hide their destination: shorteners and
  plain-`http` links that may redirect to `https`.

  `resolver` is a one-argument function returning `{:ok, final_url}` or
  `{:error, reason}`; a failure keeps the URL as it was. Nothing else is
  fetched, so a normal run makes no extra requests.
  """
  @spec follow_redirects([Item.t()], (String.t() -> {:ok, String.t()} | {:error, term()})) :: [
          Item.t()
        ]
  def follow_redirects(items, resolver) when is_function(resolver, 1) do
    Enum.map(items, fn item ->
      if follows?(item.url) do
        case resolver.(item.url) do
          {:ok, final} when is_binary(final) -> %{item | url: final}
          _ -> item
        end
      else
        item
      end
    end)
  end

  defp follows?(nil), do: false

  defp follows?(url) do
    case URI.parse(url) do
      %URI{scheme: "http", host: host} when is_binary(host) -> true
      %URI{host: host} when is_binary(host) -> String.downcase(host) in @shorteners
      _ -> false
    end
  end

  defp identity_scheme("http"), do: "https"
  defp identity_scheme(scheme), do: scheme

  defp strip_www(host), do: String.replace_prefix(host, "www.", "")

  defp kept_port(scheme, port) do
    case {scheme, port} do
      {"http", 80} -> nil
      {"https", 443} -> nil
      {"http", 443} -> nil
      {_scheme, port} -> port
    end
  end

  defp path(nil), do: "/"
  defp path(""), do: "/"
  defp path("/"), do: "/"

  defp path(path) do
    if String.ends_with?(path, "/"), do: String.trim_trailing(path, "/"), else: path
  end

  defp query(nil), do: nil
  defp query(""), do: nil

  defp query(raw) do
    kept =
      raw
      |> URI.query_decoder()
      |> Enum.reject(fn {key, _value} -> tracking?(key) end)
      |> Enum.sort()

    case kept do
      [] -> nil
      pairs -> URI.encode_query(pairs)
    end
  end

  defp tracking?(key) do
    key = String.downcase(key)

    key in @tracking_params or Enum.any?(@tracking_prefixes, &String.starts_with?(key, &1))
  end
end
