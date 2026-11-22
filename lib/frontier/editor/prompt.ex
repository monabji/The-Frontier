defmodule Frontier.Editor.Prompt do
  @moduledoc """
  The editor's brief.

  The prompt carries the paper's shape as numbers — section caps, word budgets,
  the quote rule — so the model is asked for the paper the plan describes, not
  for "a summary". The schema is in the prompt as well as in the request, so a
  provider without native structured output still returns the right object.
  """

  alias Frontier.Editor.Sections
  alias Frontier.Newsroom.Dateline

  @excerpt 900

  @doc "The messages for a first edit."
  @spec messages(Date.t(), [map()], keyword()) :: [map()]
  def messages(day, candidates, opts \\ []) do
    [
      %{role: "system", content: system()},
      %{role: "user", content: brief(day, candidates, opts)}
    ]
  end

  @doc """
  The messages for the one repair pass: the entries that failed grounding and
  the stories the paper still needs, with the same rules.
  """
  @spec repair_messages(Date.t(), [map()], map(), keyword()) :: [map()]
  def repair_messages(day, candidates, problem, opts \\ []) do
    [
      %{role: "system", content: system()},
      %{
        role: "user",
        content:
          brief(day, candidates, opts) <>
            "\n\n## This is a repair pass\n" <> repair_brief(problem, candidates)
      }
    ]
  end

  @doc "The system message, exposed so a test can pin the voice and the rules."
  @spec system() :: String.t()
  def system do
    """
    You are the editor of The Frontier, a daily newspaper for AI and technology. \
    You are writing one edition for a smart reader in a hurry: concrete, calm, \
    specific, never breathless. No hype, no listicle voice, no "in today's fast-moving \
    world", no rhetorical questions, no exclamation marks. You never invent a fact, \
    number, name, quote or link. Every sentence must be supported by the source text \
    you are given. If the day is thin, the paper is shorter and says so.
    """
  end

  defp brief(day, candidates, opts) do
    pool_note =
      case Keyword.get(opts, :reason) do
        nil ->
          ""

        reason ->
          "\nThe pool is smaller than a full day: #{reason}. Print what is real; never pad.\n"
      end

    """
    Edition: #{Dateline.format(day)} (IST). The pool holds #{length(candidates)} quotable stories.
    #{pool_note}
    ## Sections and caps

    #{section_lines()}

    Also Today is a one-line ticker, maximum #{Sections.ticker_cap()} entries, no minimum.

    ## Word budgets (strict)

    - lead summary: 120–150 words, with a dek of at most 30 words
    - standard summary: 60–80 words
    - Also Today line: 12–18 words
    - desk note: 20–60 words, one or two sentences, "From the desk" voice
    - headline: at most 90 characters; a headline's distinctive names must appear verbatim in the source text

    ## Rules

    1. Choose 22 stories in total when the pool allows it, across at most the seven sections. \
    Never exceed a cap. Omit a section with nothing real in it. Do not print a story twice, \
    not even once in a section and once in Also Today.
    2. The quote is copied character-for-character from that story's source text: one sentence \
    or a clean part of one, at least five words, no ellipses, no paraphrase, no joining two \
    sentences. If you cannot copy a sentence exactly, do not choose that story.
    3. The summary reports what the source says: who did what, what changed, and why it matters. \
    No reaction you cannot source, no prediction, no "this could change everything".
    4. The desk note reads the shape of the day — what is busy, what is quiet — and is honest \
    when the paper is short. It is not a greeting and does not address the reader.
    5. Also Today is for real but minor items: a release note, a small tool, a paper. \
    Give each a 12–18 word line and a copied quote. Ten to fifteen is a full day; fewer is honest.
    6. Order each section by importance. The first Front Page story is the lead.
    7. Reply with JSON only, no prose, no code fence. Use this shape exactly:

    {"desk_note": "one or two sentences",
     "entries": [
       {"story_id": 12, "section": "Front Page", "headline": "...",
        "dek": "lead only, otherwise omit", "summary": "...",
        "quote": "verbatim from that story's source text"}
     ],
     "also_today": [
       {"story_id": 44, "headline": "...", "summary": "12–18 words",
        "quote": "verbatim from that story's source text"}
     ]}

    ## The day's candidates

    #{candidate_lines(candidates)}
    """
  end

  defp section_lines do
    Sections.names()
    |> Enum.map_join("\n", fn section -> "- #{section}: #{Sections.cap(section)}" end)
  end

  defp candidate_lines(candidates) do
    Enum.map_join(candidates, "\n\n", fn candidate ->
      """
      ### id=#{candidate.id} | #{candidate.source_label || candidate.primary_source} | #{candidate.published_at |> format_time()}
      Headline: #{candidate.headline}
      Link: #{candidate.url}
      Source text: #{excerpt(candidate.text)}
      """
    end)
  end

  defp repair_brief(problem, candidates) do
    by_id = Map.new(candidates, &{&1.id, &1})

    failed =
      problem.failures
      |> Enum.map_join("\n", fn failure ->
        entry = failure.entry
        campaign = by_id[entry.story_id]

        """
        - story_id #{entry.story_id} (#{entry.section}): #{format_reasons(failure.reasons)}
          Rejected headline: #{entry.headline}
          Rejected summary: #{entry.summary}
          Rejected quote: #{entry.quote}
          Source text to quote from: #{excerpt(campaign && campaign.text)}
        """
      end)

    short =
      case problem.too_short do
        nil ->
          ""

        {chosen, target} ->
          needed = target - chosen
          unselected = Enum.reject(candidates, &MapSet.member?(problem.chosen_ids, &1.id))

          """
          ## The paper is short

          You chose #{chosen} stories; this pool supports #{target}. Add #{needed} more from \
          these unselected candidates, with the same rules:

          #{candidate_lines(Enum.take(unselected, 30))}
          """
      end

    note =
      case problem.desk_note do
        nil -> ""
        reason -> "\nThe desk note failed its check (#{reason}); rewrite it.\n"
      end

    """
    Fix these and reply with the full JSON object again. Include the corrected or added \
    entries in `entries` (only the ones you are fixing or adding). Include `also_today` \
    only for ticker failures or additions. Include `desk_note` only if it needs rewriting.

    #{failed}
    #{short}
    #{note}
    """
  end

  defp format_reasons(reasons) do
    reasons
    |> Enum.map_join("; ", fn
      :quote_not_in_source ->
        "quote is not a substring of the source text"

      :quote_too_short ->
        "quote is shorter than five words"

      {:summary_words, count, range} ->
        "summary is #{count} words; the budget is #{inspect(range)}"

      {:missing_entities, names} ->
        "headline names not in the source: #{Enum.join(names, ", ")}"

      {:unresolved_link, reason} ->
        "link does not resolve: #{inspect(reason)}"

      other ->
        inspect(other)
    end)
  end

  defp excerpt(nil), do: "(none)"

  defp excerpt(text) do
    if String.length(text) > @excerpt do
      String.slice(text, 0, @excerpt) <> " […]"
    else
      text
    end
  end

  defp format_time(nil), do: "time unknown"

  defp format_time(%DateTime{} = datetime) do
    datetime
    |> Dateline.to_ist()
    |> Calendar.strftime("%-d %b, %H:%M IST")
  end
end
