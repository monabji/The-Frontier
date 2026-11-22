defmodule Frontier.Editor.Client.HTTP do
  @moduledoc """
  An OpenAI-compatible chat-completions client.

  The paper does not depend on one vendor: point `base_url` at any endpoint that
  speaks the same shape. The reply must be a JSON object; the editor's prompt
  carries the schema, so a provider without native schema support still works.
  Token usage is read from the response and recorded per run.
  """

  @behaviour Frontier.Editor.Client

  @default_model "gpt-4o-mini"

  @impl true
  def complete(messages, opts \\ []) do
    config = config()

    with {:ok, api_key} <- api_key(config),
         {:ok, body} <- post_body(messages, config, opts),
         {:ok, decoded} <- post(config, api_key, body, opts),
         {:ok, content} <- content(decoded) do
      {:ok,
       %{
         content: content,
         usage: usage(decoded),
         model: decoded["model"] || Keyword.get(opts, :model, config[:model])
       }}
    end
  end

  @doc "The request body, exposed so a test can assert the shape."
  @spec post_body([map()], keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  def post_body(messages, config \\ [], opts \\ []) do
    {:ok,
     %{
       model: Keyword.get(opts, :model, config[:model] || @default_model),
       messages: messages,
       temperature: Keyword.get(opts, :temperature, config[:temperature] || 0.4),
       max_tokens: Keyword.get(opts, :max_tokens, config[:max_tokens] || 8_000),
       response_format: %{type: "json_object"}
     }}
  end

  @doc "Reads token usage from a completion, tolerating absent usage."
  @spec usage(map()) :: Frontier.Editor.Client.usage()
  def usage(%{"usage" => usage}) when is_map(usage) do
    %{
      input_tokens: usage["prompt_tokens"] || usage["input_tokens"] || 0,
      output_tokens: usage["completion_tokens"] || usage["output_tokens"] || 0
    }
  end

  def usage(_decoded), do: %{input_tokens: 0, output_tokens: 0}

  @doc "The assistant's message content, or an error naming what arrived."
  @spec content(map()) :: {:ok, String.t()} | {:error, term()}
  def content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
      when is_binary(content) do
    {:ok, content}
  end

  def content(decoded), do: {:error, {:unexpected_completion, decoded}}

  @doc "The per-request timeout for a completion."
  @spec timeout(keyword()) :: pos_integer()
  def timeout(opts \\ []), do: Keyword.get(opts, :timeout, config()[:timeout] || 180_000)

  defp config do
    Application.get_env(:frontier, __MODULE__, [])
  end

  defp api_key(config) do
    key = config[:api_key] || System.get_env("OPENAI_API_KEY")

    case key do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_api_key}
    end
  end

  defp post(config, api_key, body, opts) do
    url =
      String.trim_trailing(config[:base_url] || "https://api.openai.com/v1", "/") <>
        "/chat/completions"

    headers = [
      {"authorization", "Bearer " <> api_key},
      {"content-type", "application/json"}
    ]

    http = Keyword.get(opts, :http, &Frontier.HTTP.post/4)
    timeout = Keyword.get(opts, :timeout, config[:timeout] || 180_000)

    case http.(url, Jason.encode!(body), headers, timeout: timeout) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:http_status, status, String.slice(response_body, 0, 500)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
