defmodule FrontierWeb.ArtifactHTML do
  @moduledoc """
  The paper rendered from an artifact, as a standalone HTML document.

  This is the archive copy: it is built from the artifact alone and saved
  beside the JSON, so a published day can be read without the application or
  its database. The live page uses the same components and the same artifact
  data, so the two cannot say different things.
  """

  use FrontierWeb, :html

  alias Frontier.Editions.{Artifact, Edition}
  alias Frontier.Newsroom.Dateline

  embed_templates "templates/edition_html/*"

  @doc "Renders the artifact as a complete HTML document."
  @spec render(Artifact.t()) :: binary()
  def render(%Artifact{} = artifact) do
    assigns = %{
      page_title: "The Frontier — #{Dateline.format(artifact.day)}",
      page_description:
        artifact.desk_note ||
          "The day in AI and technology, edited to be read in ten minutes. " <>
            "Edition of #{Dateline.format(artifact.day)}.",
      date: artifact.day,
      edition: edition_view(artifact),
      sections: artifact.sections,
      tickers: artifact.also_today,
      paper_layout: "reader"
    }

    __MODULE__
    |> Phoenix.Template.render("edition", "html", assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  The edition-shaped view the paper components already know how to print.
  """
  @spec edition_view(Artifact.t()) :: Edition.t()
  def edition_view(%Artifact{} = artifact) do
    %Edition{
      day: artifact.day,
      status: artifact.status,
      published_at: artifact.published_at,
      desk_note: artifact.desk_note,
      read_minutes: artifact.read_minutes,
      word_count: artifact.stats["words"] || 0,
      story_count: artifact.stats["stories"] || 0,
      entries: Enum.flat_map(artifact.sections, &elem(&1, 1)) ++ artifact.also_today
    }
  end
end
