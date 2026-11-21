defmodule FrontierWeb.PaperComponents do
  @moduledoc """
  The paper's parts: masthead, date band, front-page items, colophon.

  Everything here is type and rule-work. No cards, no buttons, no images, no
  decoration that does not tell the reader something.
  """
  use FrontierWeb, :html

  alias Frontier.Sources.RawItem

  @doc """
  The masthead: edition flag, wordmark, motto and the date line.
  """
  attr :date, Date, required: true, doc: "the edition date, in IST"

  def masthead(assigns) do
    ~H"""
    <header class="masthead">
      <p class="flagline">
        <span class="smallcaps">Daily edition</span>
        <span class="smallcaps">Morning, 06:00 IST</span>
      </p>

      <a class="masthead__wordmark" href={~p"/"}>The Frontier</a>

      <p class="masthead__motto">All the day’s AI and technology, in ten minutes.</p>

      <p class="dateband">
        <time datetime={Date.to_iso8601(@date)}>{Frontier.Newsroom.Dateline.format(@date)}</time>
      </p>
    </header>
    """
  end

  @doc """
  The ruled band that names the section the stories below belong to, and how
  many there are.
  """
  attr :section, :string, required: true
  attr :kicker, :string, required: true

  def section_band(assigns) do
    ~H"""
    <p class="section-band">
      <span class="smallcaps">{@section}</span>
      <span class="smallcaps section-band__kicker">{@kicker}</span>
    </p>
    """
  end

  @doc """
  The front page: the top item set as a lead, the rest ranked beneath it.

  Each item is a headline that goes to the story and a source line that names
  where it came from, when, and how much discussion it drew. No item is
  printed without a link, and no item gets a summary yet — that is the
  editor's work, not the fetch's.
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
      <a class="lead-item__headline" href={@lead.url} rel="noopener noreferrer">
        {@lead.title}
      </a>
      <.item_source item={@lead} />
    </article>

    <ol :if={@rest != []} class="items">
      <li :for={item <- @rest} class="item">
        <a class="item__headline" href={item.url} rel="noopener noreferrer">{item.title}</a>
        <.item_source item={item} />
      </li>
    </ol>
    """
  end

  @doc """
  The line under a story: the site it came from, then its score, then the
  discussion, which is itself a link.
  """
  attr :item, :map, required: true

  def item_source(assigns) do
    ~H"""
    <p class="item-source">
      <span class="smallcaps item-source__host">{RawItem.host(@item)}</span>
      <span class="item-source__meta">
        <span :if={@item.published_at}>{published(@item.published_at)}</span>
        <span :if={@item.points}>{pluralize(@item.points, "point")}</span>
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

  defp published(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%-d %b")
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
