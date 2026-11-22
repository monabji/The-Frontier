defmodule Frontier.Editor.Client.Desk do
  @moduledoc """
  The editor's reply, pasted in by a person from a chat window.

  When the paper has no API key, the desk still has to close. This client is
  the seam that makes a browser chat window (ChatGPT, Gemini, Claude, anything
  that can answer a long prompt) behave like the model client the editor
  already knows: it returns one JSON reply, records zero tokens and zero cost,
  and names the assistant that produced it in the run log (`desk:chatgpt`).

  It performs no ranking and no writing. The reply goes through the same plan
  validation and the same grounding as a live model's, so a pasted edition is
  never trusted more than a generated one. Chat windows like to wrap JSON in a
  code fence or a sentence of preamble; the outer object is recovered, but a
  reply that does not decode is refused rather than guessed at.
  """

  @behaviour Frontier.Editor.Client

  @impl true
  def complete(_messages, opts \\ []) do
    with {:ok, body} <- reply_body(opts),
         {:ok, payload} <- decode(body) do
      {:ok,
       %{
         content: content(payload),
         usage: %{input_tokens: 0, output_tokens: 0},
         model: model(opts)
       }}
    end
  end

  @doc """
  The pasted text, from an option or a file path. `:reply` may hold either.
  """
  @spec reply_body(keyword()) :: {:ok, String.t()} | {:error, term()}
  def reply_body(opts) do
    case Keyword.get(opts, :reply) do
      value when is_binary(value) and byte_size(value) > 0 ->
        if String.contains?(value, "\n") or not File.exists?(value) do
          {:ok, value}
        else
          case File.read(value) do
            {:ok, body} -> {:ok, body}
            {:error, reason} -> {:error, {:reply_not_readable, reason}}
          end
        end

      _other ->
        {:error, :missing_reply}
    end
  end

  @doc "The model label recorded for a reply from a named assistant."
  @spec model(keyword()) :: String.t()
  def model(opts) do
    case opts |> Keyword.get(:desk_model) |> to_string() |> String.trim() do
      "" -> "desk"
      label -> "desk:" <> label
    end
  end

  @doc """
  Decodes a chat reply, tolerating a code fence or a sentence around the JSON.
  """
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(text) when is_binary(text) do
    with {:ok, candidate} <- extract(text),
         {:ok, payload} when is_map(payload) <- Jason.decode(candidate) do
      {:ok, payload}
    else
      {:ok, _other} -> {:error, {:reply_not_an_object, :json}}
      {:error, reason} -> {:error, {:reply_not_json, reason}}
    end
  end

  defp extract(text) do
    text
    |> strip_fence()
    |> outer_object()
  end

  defp strip_fence(text) do
    text = String.trim(text)

    case Regex.run(~r/\A```(?:json)?\s*\n(.*)\n```\s*\z/s, text) do
      [_, inner] -> String.trim(inner)
      _other -> text
    end
  end

  # A chat window sometimes says "Here is the edition:" before the object. The
  # braces are unambiguous enough to recover the payload without reading prose.
  defp outer_object(text) do
    with {start, _} <- :binary.match(text, "{"),
         {finish, _} <- List.last(:binary.matches(text, "}")),
         true <- finish > start do
      {:ok, String.slice(text, start, finish - start + 1)}
    else
      _other -> {:ok, text}
    end
  end

  defp content(%{"content" => content}) when is_binary(content), do: content
  defp content(payload), do: Jason.encode!(payload)
end
