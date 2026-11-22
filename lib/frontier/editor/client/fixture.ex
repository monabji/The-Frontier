defmodule Frontier.Editor.Client.Fixture do
  @moduledoc """
  A recorded reply, for tests and for looking at the paper without a key.

  This is not a fallback: the run log names the model as `fixture` and records
  zero cost, so a page built this way can never be mistaken for a live editor
  run. The fixture file holds the response content and, optionally, the usage
  that came with it.

      mix frontier.edit --client fixture --fixture path/to/reply.json
  """

  @behaviour Frontier.Editor.Client

  @impl true
  def complete(_messages, opts \\ []) do
    path = Keyword.get(opts, :fixture)

    cond do
      is_nil(path) ->
        {:error, :missing_fixture}

      not File.exists?(path) ->
        {:error, {:fixture_not_found, path}}

      true ->
        with {:ok, body} <- File.read(path),
             {:ok, decoded} <- Jason.decode(body) do
          {:ok,
           %{
             content: content(decoded),
             usage: usage(decoded),
             model: "fixture"
           }}
        end
    end
  end

  defp content(%{"content" => content}) when is_binary(content), do: content
  defp content(decoded) when is_map(decoded), do: Jason.encode!(decoded)
  defp content(_decoded), do: "{}"

  defp usage(%{"usage" => %{} = usage}) do
    %{
      input_tokens: usage["input_tokens"] || usage["prompt_tokens"] || 0,
      output_tokens: usage["output_tokens"] || usage["completion_tokens"] || 0
    }
  end

  defp usage(_decoded), do: %{input_tokens: 0, output_tokens: 0}
end
