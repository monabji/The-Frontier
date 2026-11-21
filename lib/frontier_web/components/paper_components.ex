defmodule FrontierWeb.PaperComponents do
  @moduledoc """
  The paper's parts: masthead, date band, front-page items, colophon.

  Everything here is type and rule-work. No cards, no buttons, no images, no
  decoration that does not tell the reader something.
  """
  use FrontierWeb, :html

  alias Frontier.Newsroom.Dateline
  alias Frontier.Sources.RawItem

  @doc """
  The masthead: edition flag, wordmark, motto and the date line.

  The wordmark is the page's one `<h1>`: it is the paper's name, and everything
  below it is a section of the same page.
  """
  attr :date, Date, required: true, doc: "the edition date, in IST"

  def masthead(assigns) do
    ~H"""
    <header class="masthead">
      <p class="flagline">
        <span class="smallcaps">Daily edition</span>
        <span class="smallcaps">Morning, 06:00 IST</span>
      </p>

      <h1 class="masthead__wordmark"><a href={~p"/"}>The Frontier</a></h1>

      <p class="masthead__motto">All the day’s AI and technology, in ten minutes.</p>

      <p class="dateband">
        <time datetime={Date.to_iso8601(@date)}>{Dateline.format(@date)}</time>
      </p>
    </header>
    """
  end

  @doc """
  The ruled band that names the section the stories below belong to, and how
  much is on the page.
  """
  attr :section, :string, required: true
  attr :kicker, :string, required: true

  def section_band(assigns) do
    ~H"""
    <h2 class="section-band">
      <span class="smallcaps">{@section}</span>
      <span class="smallcaps section-band__kicker">{@kicker}</span>
    </h2>
    """
  end

  @doc """
  The front page: the newest item set as a lead, the rest ranked beneath it.

  Each item is a headline that goes to the story and a source line that names
  where it came from, when, and how much discussion it drew. No item is printed
  without a link, and none gets a summary yet — that is the editor's work, not
  the fetch's.
  """
  attr :items, :list, required: true

  def front_page(assigns) do
    {lead, rest} =
      case assigns.items do
        [] -> {nil, []}
        [lead | rest] -> {lead, rest}
      end

    assigns = assign(assigns, lead: lead, rest: rest)

    ~H"""
    <p :if={@items == []} class="empty">
      No stories yet. Run <code class="empty__task">mix frontier.fetch</code>
      before the paper can print.
    </p>

    <article :if={@lead} class="lead-item">
      <h3 class="lead-item__headline">
        <a href={@lead.url} rel="noopener noreferrer">{@lead.title}</a>
      </h3>
      <.item_source item={@lead} />
    </article>

    <ol :if={@rest != []} class="items">
      <li :for={item <- @rest} class="item">
        <h3 class="item__headline">
          <a href={item.url} rel="noopener noreferrer">{item.title}</a>
        </h3>
        <.item_source item={item} />
      </li>
    </ol>
    """
  end

  @doc """
  The line under a story: the site it came from, how old it is in IST, its
  score, the discussion, and who wrote it.
  """
  attr :item, :map, required: true

  def item_source(assigns) do
    ~H"""
    <p class="item-source">
      <span class="smallcaps item-source__host">{RawItem.host(@item)}</span>
      <span class="item-source__meta">
        <time :if={@item.published_at} datetime={DateTime.to_iso8601(@item.published_at)}>
          {Dateline.format_short(@item.published_at)}
        </time>
        <span :if={@item.score}>{pluralize(@item.score, "point")}</span>
        <a
          :if={@item.discussion_url}
          class="item-source__discussion"
          href={@item.discussion_url}
          rel="noopener noreferrer"
        >
          {pluralize(@item.comments_count || 0, "comment")}
        </a>
        <span :if={@item.author} class="item-source__author">by {@item.author}</span>
      </span>
    </p>
    """
  end

  @doc """
  The colophon: who printed this, in what, and when it stops.
  """

  def colophon(assigns) do
    ~H"""
    <footer class="colophon">
      <p class="colophon__line">
        The Frontier. Set in Fraunces and Newsreader; composed in Elixir.
      </p>
      <p class="colophon__line colophon__line--quiet">
        One page, once a day. It ends at midnight.
      </p>
    </footer>
    """
  end

  defp pluralize(1, noun), do: "1 #{noun}"
  defp pluralize(count, noun), do: "#{thousands(count)} #{noun}s"

  defp thousands(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
