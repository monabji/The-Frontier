defmodule Frontier.Editor.Grounding do
  @moduledoc """
  The mechanical checks that stand between the editor's copy and the page.

  Nothing here asks a model whether it was right. A quote is printed only if it
  is a substring of the source text the pipeline actually read; a headline's
  names must appear in that text; a link must resolve; a summary must sit inside
  its word budget. A failure sends the story back, and a story that fails again
  is dropped and logged. It never prints with a guess.
  """

  alias Frontier.Editor.Sections
  alias Frontier.Newsroom.Entities

  @quote_min_words 5

  @doc """
  The quote must appear in the source text, verbatim up to the typography.

  Straight and curly quotes, en/em dashes and ellipses are normalised on both
  sides because feeds disagree about them; words are not. A reworded sentence
  is not the source's sentence.
  """
  @spec check_quote(String.t() | nil, String.t() | nil) :: :ok | {:error, term()}
  def check_quote(nil, _source), do: {:error, :quote_missing}
  def check_quote(_quote, nil), do: {:error, :source_text_missing}

  def check_quote(quote, source) when is_binary(quote) and is_binary(source) do
    quote = normalize(quote)

    cond do
      Sections.word_count(quote) < @quote_min_words -> {:error, :quote_too_short}
      String.contains?(normalize(source), quote) -> :ok
      true -> {:error, :quote_not_in_source}
    end
  end

  @doc """
  Every distinctive name in the headline must be mentioned in the source text.

  Names are compared by their alphanumeric key, so a feed that hyphenates
  "Inkling-2-Mini" and a headline that spaces it are the same name. A name the
  text never mentions is a fact the editor invented.
  """
  @spec check_entities(String.t() | nil, String.t() | nil) :: :ok | {:error, term()}
  def check_entities(_headline, nil), do: {:error, :source_text_missing}
  def check_entities(nil, _source), do: :ok

  def check_entities(headline, source) when is_binary(headline) and is_binary(source) do
    names =
      headline
      |> Entities.from_title()
      |> Enum.filter(&Entities.distinctive?/1)

    source_key = Entities.key(source)

    missing =
      names
      |> Enum.reject(fn name -> String.contains?(source_key, Entities.key(name)) end)
      |> maximal()

    case missing do
      [] -> :ok
      names -> {:error, {:missing_entities, names}}
    end
  end

  @doc """
  A summary must sit inside its kind's word budget.

  A keyless run may pass its own ranges: a small model writes shorter
  summaries than the paper's ideal, and the honest options are to print them or
  to lose the story. The advertised read time is computed from what actually
  prints, so the shorter budget is visible to the reader, not hidden.
  """
  @spec check_words(String.t() | nil, :lead | :standard | :ticker, map() | nil) ::
          :ok | {:error, term()}
  def check_words(text, kind, ranges \\ nil) do
    range = (ranges && Map.get(ranges, kind)) || Sections.word_range(kind)
    count = Sections.word_count(text)

    if count in range, do: :ok, else: {:error, {:summary_words, count, range}}
  end

  @doc """
  The first quote candidate that grounds, or the last failure.

  The model is asked for a quote and up to two alternates. Trying them in order
  turns a near-miss in one sentence into a printed story instead of a dropped
  one, without relaxing the check: every candidate must still be found verbatim.
  """
  @spec choose_quote([String.t() | nil], String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def choose_quote(quotes, source) when is_list(quotes) do
    quotes
    |> Enum.filter(&is_binary/1)
    |> Enum.reduce_while({:error, :quote_missing}, fn quote, _previous ->
      case check_quote(quote, source) do
        :ok -> {:halt, {:ok, quote}}
        {:error, reason} -> {:cont, {:error, reason}}
      end
    end)
  end

  def choose_quote(_quotes, _source), do: {:error, :quote_missing}

  @doc """
  Checks a link with the injected checker and returns where it landed.

  The checker returns `{:ok, final_url}` or `{:error, reason}`; a dead link
  becomes `{:unresolved_link, reason}` and the story is dropped.
  """
  @spec check_link(String.t() | nil, (String.t() -> {:ok, String.t()} | {:error, term()})) ::
          {:ok, String.t()} | {:error, term()}
  def check_link(nil, _checker), do: {:error, {:unresolved_link, :missing}}

  def check_link(url, checker) when is_binary(url) and is_function(checker, 1) do
    case checker.(url) do
      {:ok, final} when is_binary(final) -> {:ok, final}
      :ok -> {:ok, url}
      {:error, reason} -> {:error, {:unresolved_link, reason}}
    end
  end

  @doc """
  The production link checker: a browser-like HEAD through `Frontier.HTTP`.

  403 and 429 are bot protection, not death: the plan says those count as alive
  when the source is real. 405 means the server answered but does not allow
  HEAD, which is a live page refusing a method, not a missing one. A 404, a 410
  or a dead host is a dead story.
  """
  @spec resolve_link(String.t()) :: {:ok, String.t()} | {:error, term()}
  def resolve_link(url), do: resolve_link(url, &Frontier.HTTP.final_url/1)

  @doc """
  The same rule with the HTTP call injected, so the status handling is testable
  without a request. `http` returns `{:ok, final_url}` or `{:error, reason}`.
  """
  @spec resolve_link(String.t(), (String.t() -> {:ok, String.t()} | {:error, term()})) ::
          {:ok, String.t()} | {:error, term()}
  def resolve_link(url, http) when is_binary(url) and is_function(http, 1) do
    case http.(url) do
      {:ok, final} ->
        {:ok, final}

      {:error, {:http_status, status, _excerpt}} ->
        case http_link(status) do
          :ok -> {:ok, url}
          {:error, reason} -> {:error, {:unresolved_link, reason}}
        end

      {:error, reason} ->
        {:error, {:unresolved_link, reason}}
    end
  end

  @doc "The status-code half of the link rule, without the request."
  @spec http_link(non_neg_integer()) :: :ok | {:error, term()}
  def http_link(status) when status in 200..299, do: :ok
  def http_link(status) when status in [403, 405, 429], do: :ok
  def http_link(status), do: {:error, {:http_status, status}}

  # "Gemini 4" and "Gemini 4 Neon" are missing together; naming the longer one
  # is the useful report, so sub-names that sit inside another missing name go.
  defp maximal(names) do
    Enum.reject(names, fn name ->
      Enum.any?(names, fn other ->
        other != name and String.contains?(Entities.key(other), Entities.key(name))
      end)
    end)
  end

  defp normalize(text) do
    text
    |> String.replace(["“", "”"], "\"")
    |> String.replace(["‘", "’"], "'")
    |> String.replace(["—", "–", "−"], "-")
    |> String.replace("…", "...")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
