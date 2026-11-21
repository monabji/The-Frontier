defmodule FrontierWeb.PaperComponents do
  @moduledoc """
  The paper's parts: masthead, date band, front-page stories, colophon.

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
  The front page: the best-placed story set as a lead, the rest ranked beneath.

  A story is one event however many sources carried it: the headline goes to
  the publication's link, and the source line carries the conversation — the
  aggregator's thread, its comment count and its score — so the reader can read
  the story or the argument about it.
  """
  attr :stories, :list, required: true

  def front_page(assigns) do
    {lead, rest} =
      case assigns.stories do
        [] -> {nil, []}
        [lead | rest] -> {lead, rest}
      end

    assigns = assign(assigns, lead: lead, rest: rest)

    ~H"""
    <p :if={@stories == []} class="empty">
      No stories yet. Run <code class="empty__task">mix frontier.fetch</code>
      and <code class="empty__task">mix frontier.cluster</code>
      before the paper can print.
    </p>

    <article :if={@lead} class="lead-item">
      <h3 class="lead-item__headline">
        <a href={primary(@lead).url} rel="noopener noreferrer">{@lead.headline}</a>
      </h3>
      <.story_source story={@lead} />
    </article>

    <ol :if={@rest != []} class="items">
      <li :for={story <- @rest} class="item">
        <h3 class="item__headline">
          <a href={primary(story).url} rel="noopener noreferrer">{story.headline}</a>
        </h3>
        <.story_source story={story} />
      </li>
    </ol>
    """
  end

  @doc """
  The line under a story: where it was published, when in IST, its score, and
  the discussion — which is a link to the argument, not to the article again.
  """
  attr :story, :map, required: true

  def story_source(assigns) do
    primary = primary(assigns.story)
    discussion = discussion(assigns.story)

    assigns = assign(assigns, primary: primary, discussion: discussion)

    ~H"""
    <p class="item-source">
      <span class="smallcaps item-source__host">{RawItem.host(@primary)}</span>
      <span class="item-source__meta">
        <time :if={@primary.published_at} datetime={DateTime.to_iso8601(@primary.published_at)}>
          {Dateline.format_short(@primary.published_at)}
        </time>
        <span :if={@primary.score && @primary.score > 0}>
          {pluralize(@primary.score, "point")}
        </span>
        <a
          :if={@discussion}
          class="item-source__discussion"
          href={discussion_url(@discussion)}
          rel="noopener noreferrer"
        >
          {discussion_label(@discussion)}
        </a>
        <span :if={@primary.author} class="item-source__author">by {@primary.author}</span>
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

  defp primary(story) do
    story.story_items
    |> Enum.find(&(&1.role == "primary"))
    |> case do
      nil -> story.story_items |> List.first() |> item_of()
      member -> item_of(member)
    end
  end

  defp discussion(story) do
    story.story_items
    |> Enum.find(&(&1.role == "discussion"))
    |> item_of()
  end

  defp item_of(nil), do: nil
  defp item_of(member), do: member.raw_item

  defp discussion_url(item), do: item.discussion_url || item.url

  # A thread with no comments yet is still worth a link; it just cannot claim a
  # count it does not have.
  defp discussion_label(%{comments_count: count}) when is_integer(count) and count > 0,
    do: pluralize(count, "comment")

  defp discussion_label(_item), do: "Discussion"

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
