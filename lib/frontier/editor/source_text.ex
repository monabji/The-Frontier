defmodule Frontier.Editor.SourceText do
  @moduledoc """
  The text a quote has to come from.

  Feeds store an excerpt at fetch. An HN link post stores only what the
  submission said, so when the editor needs a sentence to quote it fetches the
  article once, extracts readable text, keeps a bounded excerpt for the run,
  and stores nothing wholesale. The compliance rule is short quotes with
  attribution; storing a whole article would break it.

  A page that cannot be read is a story that cannot be grounded, and a story
  that cannot be grounded does not print.
  """

  alias Frontier.Sources.{RawItem, Text}

  # Enough text to find a sentence and judge what the story is about; an order
  # of magnitude smaller than an article.
  @max_article 6_000

  # Below this, a stored excerpt is too thin to ground a quote on, so the
  # article itself is fetched.
  @min_stored 300

  @doc """
  Source text for a stored item: the stored excerpt when it is substantial,
  otherwise one fetch of the item's link. `:fetcher` replaces the network in
  tests and returns `{:ok, body}` or `{:error, reason}`.
  """
  @spec for_item(RawItem.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def for_item(%RawItem{text: text} = item, opts \\ []) do
    if substantial?(text) do
      {:ok, String.slice(text, 0, @max_article)}
    else
      fetch(item.url, opts)
    end
  end

  @doc """
  Fetches a URL and returns readable text, bounded. HTML is stripped; other
  bodies are treated as text.
  """
  @spec fetch(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, term()}
  def fetch(url, opts \\ [])

  def fetch(nil, _opts), do: {:error, :no_url}

  def fetch(url, opts) do
    fetcher = Keyword.get(opts, :fetcher, &default_fetch/1)

    with {:ok, body, content_type} <- normalize_response(fetcher.(url)),
         text <- extract(body, content_type),
         :ok <- enough?(text) do
      {:ok, text}
    end
  end

  @doc "Readable text from a body, HTML or plain."
  @spec extract(String.t(), String.t() | nil) :: String.t()
  def extract(body, content_type) when is_binary(body) do
    text =
      if html?(content_type, body) do
        from_html(body)
      else
        body |> Text.plain() |> to_string()
      end

    String.slice(text, 0, @max_article)
  end

  @doc """
  Strips the parts of a page that are machinery, not prose.

  Page chrome is longer than an article on most sites, so the readable body is
  taken from `<article>` or `<main>` when the page marks one; navigation,
  headers, footers and asides are removed before the tags are. Without that,
  6,000 characters of menu would be the whole source text, and the editor could
  only quote the navigation.
  """
  @spec from_html(String.t()) :: String.t()
  def from_html(html) do
    body =
      html
      |> without(~w(script style noscript svg template))
      |> without_comments()
      |> main_content()

    body
    |> without(~w(nav header footer aside))
    |> Text.plain()
    |> to_string()
  end

  defp without(html, tags) do
    Enum.reduce(tags, html, fn tag, acc ->
      Regex.replace(~r/<#{tag}\b[^>]*>.*?<\/#{tag}>/is, acc, " ")
    end)
  end

  defp without_comments(html), do: String.replace(html, ~r/<!--.*?-->/s, " ")

  # Some sites mark a teaser as <article> and put the body elsewhere. A
  # candidate part is used only if it actually carries prose; otherwise the
  # whole page (with its chrome already removed) is the source.
  defp main_content(html) do
    [element(html, "article"), element(html, "main")]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(fn part -> readable_length(part) >= 400 end)
    |> case do
      nil -> html
      part -> part
    end
  end

  defp element(html, tag) do
    ~r/<#{tag}\b[^>]*>(.*?)<\/#{tag}>/is
    |> Regex.run(html, capture: :all_but_first)
    |> case do
      [content] -> content
      nil -> nil
    end
  end

  defp readable_length(html) do
    html
    |> without(~w(nav header footer aside))
    |> Text.plain()
    |> to_string()
    |> String.length()
  end

  defp default_fetch(url) do
    case Frontier.HTTP.get(url) do
      {:ok, response} -> {:ok, response.body, response.content_type}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_response({:ok, body}) when is_binary(body), do: {:ok, body, nil}
  defp normalize_response({:ok, body, type}) when is_binary(body), do: {:ok, body, type}
  defp normalize_response({:error, reason}), do: {:error, reason}
  defp normalize_response(other), do: {:error, {:unexpected_response, other}}

  defp enough?(text) when byte_size(text) >= 200, do: :ok
  defp enough?(text), do: {:error, {:too_little_text, byte_size(text)}}

  defp substantial?(text) when is_binary(text), do: byte_size(text) >= @min_stored
  defp substantial?(_text), do: false

  defp html?(type, _body) when is_binary(type) do
    String.contains?(String.downcase(type), "html")
  end

  defp html?(_type, body) do
    String.contains?(String.downcase(String.slice(body, 0, 1_000)), "<html") or
      String.contains?(String.downcase(String.slice(body, 0, 1_000)), "<!doctype")
  end
end
