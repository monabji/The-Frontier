defmodule Frontier.Sources.RSS do
  @moduledoc """
  Company blogs and changelogs, read through their feeds.

  One parser for both shapes the web actually ships: RSS 2.0 (`<item>`,
  `pubDate`) and Atom (`<entry>`, `<published>`, `href` on the link). Feeds are
  peers of Hacker News, so each one is its own adapter with its own key, its own
  count in the run log, and its own failure — a feed that 404s or sends HTML
  cannot stop the others.

  Feeds carry the last N posts, sometimes the whole archive (OpenAI's feed
  serves 1,400 entries). The paper takes the newest `@feed_size` and keeps the
  feed's own order. A feed item's body is stored as a plain-text excerpt, never
  full text; the plan's compliance rule forbids storing articles wholesale, and
  phase 4 only needs a sentence to quote.
  """

  require Record

  alias Frontier.Sources.{Item, Text}

  # `from_lib:` only looks at dependencies, so the header is found where the
  # OTP install actually keeps it.
  @xmerl_hrl Path.join([:code.lib_dir(:xmerl, :include), "xmerl.hrl"])

  Record.defrecordp(:xmlElement, :xmlElement, Record.extract(:xmlElement, from: @xmerl_hrl))
  Record.defrecordp(:xmlText, :xmlText, Record.extract(:xmlText, from: @xmerl_hrl))

  Record.defrecordp(
    :xmlAttribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from: @xmerl_hrl)
  )

  @feed_size 30
  @discussion nil

  @doc "The feeds the paper reads. They join and leave here, in one list."
  @spec feeds() :: [module()]
  def feeds do
    [
      Frontier.Sources.RSS.OpenAI,
      Frontier.Sources.RSS.HuggingFace,
      Frontier.Sources.RSS.DeepMind,
      Frontier.Sources.RSS.GoogleAI,
      Frontier.Sources.RSS.ArsTechnica,
      Frontier.Sources.RSS.SimonWillison
    ]
  end

  @doc """
  Fetches one feed's XML. Accepts the same `:client` option as every adapter;
  the default calls `Frontier.HTTP.get_xml/1`.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def fetch(url, opts \\ []) do
    client = Keyword.get(opts, :client, &Frontier.HTTP.get_xml/1)

    case client.(url) do
      {:ok, %{body: body}} -> {:ok, body}
      {:ok, body} when is_binary(body) -> {:ok, body}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  @doc """
  Turns a feed document into items, newest first as the feed ordered them.
  """
  @spec normalize(String.t() | term()) :: {:ok, [Item.t()]} | {:error, term()}
  def normalize(xml) when is_binary(xml) do
    with {:ok, document} <- parse(xml) do
      items =
        document
        |> entries()
        |> Enum.take(@feed_size)
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {entry, position} -> item(entry, position) end)

      {:ok, items}
    end
  end

  def normalize(_payload), do: {:error, :unexpected_payload}

  # xmerl wants the document as bytes, not codepoints: given a codepoint list it
  # rejects every non-ASCII character as illegal, which is most prose.
  defp parse(xml) do
    {document, _rest} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)

    if feed_root?(document), do: {:ok, document}, else: {:error, :unreadable_feed}
  rescue
    _ -> {:error, :unreadable_feed}
  catch
    _kind, _reason -> {:error, :unreadable_feed}
  end

  defp feed_root?(document) do
    document
    |> name()
    |> Atom.to_string()
    |> String.upcase()
    |> then(&(&1 in ["RSS", "FEED", "RDF"]))
  end

  defp entries(document) do
    document
    |> children()
    |> Enum.flat_map(&feed_entries/1)
  end

  defp feed_entries(element) when elem(element, 0) == :xmlElement do
    case name(element) do
      name when name in [:rss, :feed, :channel] ->
        children(element) |> Enum.flat_map(&feed_entries/1)

      name when name in [:item, :entry] ->
        [element]

      _other ->
        children(element) |> Enum.flat_map(&feed_entries/1)
    end
  end

  defp feed_entries(_other), do: []

  defp item(entry, position) do
    title = Text.plain(text(find(entry, :title)))
    url = link(entry)
    external_id = text(find(entry, :guid)) || text(find(entry, :id)) || url

    if present?(title) and present?(url) do
      [
        %Item{
          external_id: external_id,
          title: title,
          url: url,
          discussion_url: @discussion,
          author: author(entry),
          text: body(entry),
          kind: :post,
          published_at: published_at(entry),
          position: position
        }
      ]
    else
      []
    end
  end

  # Atom puts the address in an attribute; RSS puts it in the element's text.
  defp link(entry) do
    links =
      entry
      |> children()
      |> Enum.filter(&(elem(&1, 0) == :xmlElement and name(&1) == :link))

    alternate =
      Enum.find(links, fn link ->
        attribute(link, :rel) in [nil, "alternate"]
      end)

    case alternate do
      nil -> nil
      link -> attribute(link, :href) || blank(text(link))
    end
  end

  defp author(entry) do
    blank(text(find(entry, :"dc:creator"))) ||
      blank(text(find(find(entry, :author), :name))) ||
      blank(text(find(entry, :author)))
  end

  defp body(entry) do
    [
      find(entry, :"content:encoded"),
      find(entry, :description),
      find(entry, :content),
      find(entry, :summary)
    ]
    |> Enum.find_value(fn element -> Text.plain(element && text(element)) end)
  end

  defp published_at(entry) do
    [find(entry, :pubDate), find(entry, :published), find(entry, :updated)]
    |> Enum.find_value(fn element -> parse_date(text(element)) end)
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        DateTime.truncate(datetime, :second)

      {:error, _reason} ->
        parse_rfc822(value)
    end
  end

  # RSS 2.0 dates: "Fri, 20 Nov 2026 00:00:00 GMT" — weekday first, then the
  # day, often with a numeric offset.
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  defp parse_rfc822(value) do
    tokens =
      value
      |> String.split([" ", ","], trim: true)
      |> Enum.reject(&(String.length(&1) == 3 and &1 not in @months))

    with [day, month | rest] <- tokens,
         month_index when is_integer(month_index) <- Enum.find_index(@months, &(&1 == month)),
         {day, _} <- Integer.parse(day),
         {year, _} <- Integer.parse(Enum.at(rest, 0) || ""),
         {:ok, time} <- Time.from_iso8601(Enum.at(rest, 1) || ""),
         {:ok, naive} <-
           NaiveDateTime.new(year, month_index + 1, day, time.hour, time.minute, time.second) do
      naive
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-offset_seconds(Enum.at(rest, 2)), :second)
      |> DateTime.truncate(:second)
    else
      _ -> nil
    end
  end

  defp offset_seconds(<<sign, h1, h2, m1, m2>>) when sign in [?+, ?-] do
    seconds = String.to_integer(<<h1, h2>>) * 3600 + String.to_integer(<<m1, m2>>) * 60
    if sign == ?-, do: -seconds, else: seconds
  end

  defp offset_seconds(_zone), do: 0

  defp find(nil, _name), do: nil

  # The needle is matched on its local name too, so a prefixed lookup
  # (`:"dc:creator"`) finds `<dc:creator>` without the prefix leaking in.
  defp find(element, name) do
    local = local_name(name)

    element
    |> children()
    |> Enum.find(fn child ->
      elem(child, 0) == :xmlElement and name(child) == local
    end)
  end

  defp children(element) when elem(element, 0) == :xmlElement do
    element |> xmlElement(:content) |> List.wrap()
  end

  defp children(_other), do: []

  defp name(element), do: element |> xmlElement(:name) |> local_name()

  # `xmerl` keeps a prefix in the name for namespaced elements.
  defp local_name(name) when is_atom(name) do
    case String.split(Atom.to_string(name), ":") do
      [_prefix, local] -> String.to_atom(local)
      [local] -> String.to_atom(local)
    end
  end

  defp attribute(element, name) do
    element
    |> xmlElement(:attributes)
    |> Enum.find_value(fn attribute ->
      if attribute |> xmlAttribute(:name) |> local_name() == name do
        attribute |> xmlAttribute(:value) |> to_string()
      end
    end)
  end

  defp text(nil), do: nil

  defp text(element) when elem(element, 0) == :xmlElement do
    element
    |> xmlElement(:content)
    |> Enum.map(&text_node/1)
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  defp text(_other), do: nil

  defp text_node(node) when elem(node, 0) == :xmlText, do: xmlText(node, :value) |> to_string()
  defp text_node(node) when elem(node, 0) == :xmlElement, do: text(node)
  defp text_node(_node), do: ""

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp blank(value), do: if(present?(value), do: value)
end
