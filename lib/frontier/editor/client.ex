defmodule Frontier.Editor.Client do
  @moduledoc """
  The one thing the editor asks a model to do: reply with JSON.

  A client is a module implementing this behaviour, or a function of two
  arguments, which is how tests inject a recorded reply. Nothing in this module
  decides what the reply means; `Frontier.Editor` validates and grounds it.
  """

  @type usage :: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}

  @type reply :: %{
          content: String.t(),
          usage: usage(),
          model: String.t() | nil
        }

  @callback complete(messages :: [map()], opts :: keyword()) :: {:ok, reply()} | {:error, term()}

  @doc """
  Calls the configured client. `:client` may be a module or a function.
  """
  @spec complete(module() | function(), [map()], keyword()) :: {:ok, reply()} | {:error, term()}
  def complete(client, messages, opts \\ [])

  def complete(client, messages, opts) when is_function(client, 2) do
    client.(messages, opts)
  end

  def complete(client, messages, opts) when is_atom(client) do
    client.complete(messages, opts)
  end

  @doc "The client configured for this install."
  @spec configured() :: module() | function()
  def configured do
    Application.get_env(:frontier, :editor_client, Frontier.Editor.Client.HTTP)
  end
end
