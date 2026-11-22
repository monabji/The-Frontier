defmodule FrontierWeb.PaperComponents do
  @moduledoc """
  The paper's parts: masthead, date band, front-page stories, colophon.

  Everything here is type and rule-work. No cards, no buttons, no images, no
  decoration that does not tell the reader something.
  """
  use FrontierWeb, :html

  alias Frontier.Newsroom.Dateline
  alias Frontier.Sources.{Canonical, RawItem}

  @doc """
  The masthead: edition flag, wordmark, motto and the date line.

  The wordmark is the page's one `<h1>`: it is the paper's name, and everything
  below it is a section of the same page.
  """
  attr :date, Date, required: true, doc: "the edition date, in IST"
  attr :read_minutes, :integer, default: nil, doc: "the edition's advertised length"

  def masthead(assigns) do
    ~H"""
    <header class="masthead">
      <p class="flagline">
        <span class="smallcaps">Daily edition</span>
        <span class="smallcaps">
          06:00 IST<span :if={@read_minutes}> · {@read_minutes} min read</span>
        </span>
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
  A dated edition: the desk note, every section in paper order, and the Also
  Today strip. This is the page phase 4 makes; phase 5 renders it from an
  artifact instead of the database.
  """
  attr :edition, :any, required: true
  attr :sections, :list, required: true
  attr :tickers, :list, required: true
  attr :thumbs, :boolean, default: false
  attr :csrf_token, :string, default: nil
  attr :return_to, :string, default: "/"

  def edition(assigns) do
    ~H"""
    <.desk_note :if={@edition.desk_note} note={@edition.desk_note} />

    <section :for={{section, entries} <- @sections} class="section">
      <.section_band section={section} kicker={entry_count(entries)} />

      <article :for={entry <- entries} class={"story story--#{entry.kind}"}>
        <h3 class="story__headline">
          <a href={entry.url} rel="noopener noreferrer">{entry.headline}</a>
        </h3>
        <p :if={entry.dek} class="story__dek">{entry.dek}</p>
        <p class="story__summary">{entry.summary}</p>
        <blockquote :if={entry.quote} class="story__quote">
          <p>{entry.quote}</p>
          <cite class="smallcaps">{entry.source_label || Canonical.host(entry.url)}</cite>
        </blockquote>
        <.entry_source entry={entry} />
        <.thumb_actions
          :if={@thumbs}
          entry={entry}
          edition_date={@edition.day}
          csrf_token={@csrf_token}
          return_to={@return_to}
        />
      </article>
    </section>

    <section :if={@tickers != []} class="section also-today">
      <.section_band section="Also Today" kicker={entry_count(@tickers)} />

      <ol class="ticker">
        <li :for={entry <- @tickers} class="ticker__item">
          <p class="ticker__headline">
            <a href={entry.url} rel="noopener noreferrer">{entry.headline}</a>
          </p>
          <p class="ticker__line">{entry.summary}</p>
          <.entry_source entry={entry} />
        </li>
      </ol>
    </section>
    """
  end

  @doc """
  The strip that says the 06:00 edition is late and names what the reader is
  actually holding. Never a blank page, never a silent fallback.
  """
  attr :date, Date, required: true

  def delayed_banner(assigns) do
    ~H"""
    <aside class="delayed" role="status">
      <p class="smallcaps delayed__label">Delayed edition</p>
      <p class="delayed__text">
        The 06:00 edition has not been published. You are reading the edition of {Dateline.format(
          @date
        )}.
      </p>
    </aside>
    """
  end

  @doc """
  A quiet thumb control: two words, a real form, no JavaScript. It says
  tomorrow, because today's paper is already printed.
  """
  attr :entry, :any, required: true
  attr :edition_date, Date, required: true
  attr :csrf_token, :string, required: true
  attr :return_to, :string, required: true

  def thumb_actions(assigns) do
    ~H"""
    <form class="thumb" method="post" action="/thumbs">
      <input type="hidden" name="_csrf_token" value={@csrf_token} />
      <input type="hidden" name="thumb[story]" value={@entry.canonical_url} />
      <input type="hidden" name="thumb[return]" value={@return_to} />
      <input type="hidden" name="thumb[edition_day]" value={Date.to_iso8601(@edition_date)} />
      <span class="smallcaps thumb__label">More like this?</span>
      <button
        class="thumb__button"
        type="submit"
        name="thumb[value]"
        value="up"
        aria-label={"More like this: " <> @entry.headline}
      >
        Yes
      </button>
      <button
        class="thumb__button"
        type="submit"
        name="thumb[value]"
        value="down"
        aria-label={"Less like this: " <> @entry.headline}
      >
        No
      </button>
    </form>
    """
  end

  @doc """
  The desk note that opens the paper. It is machine-written and says so: the
  reader is never invited to mistake the editor's voice for a person's.
  """
  attr :note, :string, required: true

  def desk_note(assigns) do
    ~H"""
    <aside class="desk-note">
      <p class="smallcaps desk-note__label">
        From the desk <span class="desk-note__machine">machine-written</span>
      </p>
      <p class="desk-note__text">{@note}</p>
    </aside>
    """
  end

  @doc """
  The source line under an edition entry: where it was published, when in IST,
  its score, and the discussion — a link to the argument, not to the article
  again.
  """
  attr :entry, :any, required: true

  def entry_source(assigns) do
    ~H"""
    <p class="item-source">
      <span class="smallcaps item-source__host">{Canonical.host(@entry.url)}</span>
      <span class="item-source__meta">
        <time :if={@entry.published_at} datetime={DateTime.to_iso8601(@entry.published_at)}>
          {Dateline.format_short(@entry.published_at)}
        </time>
        <span :if={@entry.score && @entry.score > 0}>
          {pluralize(@entry.score, "point")}
        </span>
        <a
          :if={@entry.discussion_url}
          class="item-source__discussion"
          href={@entry.discussion_url}
          rel="noopener noreferrer"
        >
          {discussion_label(@entry)}
        </a>
      </span>
    </p>
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
        One page, once a day. It ends at midnight. <a href="/archive">Past editions</a>.
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

  defp entry_count(entries) do
    count = length(entries)

    cond do
      Enum.any?(entries, &(&1.kind == "ticker")) -> pluralize(count, "item")
      count == 1 -> "1 story"
      true -> "#{count} stories"
    end
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
