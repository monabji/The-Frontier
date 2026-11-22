defmodule Frontier.Editor.Desk do
  @moduledoc """
  The paper's editor when there is no API key: a brief out, a reply in.

  The same pipeline the morning run uses, split around a person. `brief/2`
  builds the day's candidate list and writes the exact prompt the editor would
  send to a model. `submit/3` takes the JSON a person pasted back from a chat
  window, validates and grounds it exactly as a live reply is validated and
  grounded, and assembles the day's draft.

  Nothing here relaxes a rule. A pasted reply gets no more trust than a
  generated one: a quote that is not in the source drops the story, a link that
  does not resolve drops it, and the plan still owns caps and placement. The
  only difference is where the prose came from, and the run log records that
  (`desk:chatgpt`, zero tokens, zero cost).
  """

  alias Frontier.Editions
  alias Frontier.Editor
  alias Frontier.Editor.{Candidates, Client.Desk, Prompt}
  alias Frontier.Newsroom.{Dateline, Pool}

  @doc """
  The day's brief: the prompt text and what it was built from.

  Options are the candidate options (`:limit`, `:fetcher`).
  """
  @spec brief(Date.t(), keyword()) :: %{
          day: Date.t(),
          prompt: String.t(),
          candidates: non_neg_integer(),
          excluded: [map()]
        }
  def brief(day, opts \\ []) do
    %{candidates: candidates, excluded: excluded} =
      Pool.paper_stories(day: day)
      |> Candidates.build(opts)

    %{
      day: day,
      prompt: prompt_text(day, candidates, opts),
      candidates: length(candidates),
      excluded: excluded
    }
  end

  @doc """
  Turns a pasted reply into the day's assembled draft.

  `reply` is the chat window's answer, a JSON object possibly wrapped in a code
  fence. `:assistant` names the window for the run log. Returns the edition
  with its entries loaded, or a reason fit for a person to read.
  """
  @spec submit(Date.t(), String.t(), keyword()) ::
          {:ok, %{edition: Editions.Edition.t(), report: map()}} | {:error, term()}
  def submit(day, reply, opts \\ []) when is_binary(reply) do
    editor_opts = [
      client: Desk,
      reply: reply,
      repair: false,
      desk_model: Keyword.get(opts, :assistant, "chat")
    ]

    editor_opts = Keyword.take(opts, [:link_checker, :limit, :fetcher]) ++ editor_opts

    with :ok <- writable(day),
         {:ok, %{edition: edition, report: report}} <- Editor.edit(day, editor_opts),
         {:ok, %{edition: assembled}} <- Editions.assemble(day) do
      {:ok, %{edition: assembled || edition, report: report}}
    end
  end

  @doc "A person-readable sentence for a failed desk run."
  @spec explain(term()) :: String.t()
  def explain({:editor_client, {:reply_not_json, _reason}}),
    do: "That reply is not JSON. Paste the whole object, including the outer braces."

  def explain({:editor_client, :missing_reply}), do: "The reply was empty."

  def explain({:edition_is_locked, day}),
    do: "#{Dateline.format(day)} is already published or frozen; the desk cannot rewrite it."

  def explain({:edition_is_frozen, day}), do: explain({:edition_is_locked, day})

  def explain({:nothing_printed, failures}),
    do: "No story passed grounding. #{Enum.map_join(failures, "; ", &inspect/1)}"

  def explain({:desk_note_invalid, reason}), do: "The desk note failed its check (#{reason})."

  def explain({:missing_desk_note}), do: "The reply has no desk note."

  def explain(other), do: inspect(other)

  defp prompt_text(day, candidates, opts) do
    [%{content: system}, %{content: brief}] = Prompt.messages(day, candidates, opts)

    """
    #{system}

    ---

    #{brief}
    """
  end

  defp writable(day) do
    if Editions.writable?(day), do: :ok, else: {:error, {:edition_is_locked, day}}
  end
end
