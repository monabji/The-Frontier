defmodule FrontierWeb.PaperComponents do
  @moduledoc """
  The paper's parts: masthead, date band, lead story, colophon.

  Everything here is type and rule-work. No cards, no buttons, no images, no
  decoration that does not tell the reader something.
  """
  use FrontierWeb, :html

  @doc """
  The masthead: edition flag, wordmark, motto and the date line.
  """
  attr :date, Date, required: true, doc: "the edition date, in IST"
  attr :edition, :map, required: true, doc: "the edition being printed"

  def masthead(assigns) do
    ~H"""
    <header class="masthead">
      <p class="flagline">
        <span class="smallcaps">No. {@edition.number}</span>
        <span class="smallcaps">{@edition.published}</span>
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
  The ruled band that names the section the story below belongs to.
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
  The lead: headline, dek, desk line, body with a drop cap, and the one verbatim
  source quote the summary is grounded on.
  """
  attr :story, :map, required: true

  def lead_story(assigns) do
    ~H"""
    <article class="lead">
      <h1 class="lead__headline">{@story.headline}</h1>
      <p class="lead__dek">{@story.dek}</p>

      <p class="lead__desk">
        <span class="lead__desk-source">
          <span class="smallcaps">Source</span>
          <a class="smallcaps" href={@story.source.url} rel="noopener">{@story.source.name}</a>
        </span>
      </p>

      <div class="lead__body">
        <p :for={paragraph <- @story.body} class="lead__paragraph">{paragraph}</p>
      </div>

      <blockquote class="source-quote">
        <p class="source-quote__text">{@story.quote.text}</p>
        <footer class="source-quote__credit">
          <span class="smallcaps">{@story.quote.attribution}</span>
        </footer>
      </blockquote>
    </article>
    """
  end

  @doc """
  The colophon: who printed this, in what, and when it stops.
  """
  attr :edition, :map, required: true

  def colophon(assigns) do
    ~H"""
    <footer class="colophon">
      <p class="colophon__line">
        The Frontier, {@edition.label}. Set in Fraunces and Newsreader; composed in Elixir.
      </p>
      <p class="colophon__line colophon__line--quiet">
        One page, once a day. It ends at midnight.
      </p>
    </footer>
    """
  end
end
