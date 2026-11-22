defmodule Frontier.Alerts do
  @moduledoc """
  Telling a human when the paper is late.

  An alert always reaches the log, and reaches a webhook or Telegram when one
  is configured. The adapter is configurable so a test can prove the message
  was sent without a network; a missing channel is a log line, never a crash.
  """

  require Logger

  @type level :: :warning | :error
  @type adapter :: module() | (level(), String.t(), String.t() -> any())

  @doc """
  Sends an alert. `:adapter` overrides the configured one (tests, admin runs).
  """
  @spec alert(level(), String.t(), String.t(), keyword()) :: :ok
  def alert(level, title, body, opts \\ []) do
    log(level, title, body)
    adapter = Keyword.get(opts, :adapter, configured())
    deliver(adapter, level, title, body)
  end

  @doc "The configured alert channel."
  @spec configured() :: adapter()
  def configured do
    Application.get_env(:frontier, :alert_adapter, Frontier.Alerts.Log)
  end

  defp deliver(adapter, level, title, body) when is_function(adapter, 3) do
    adapter.(level, title, body)
    :ok
  rescue
    exception ->
      Logger.error("[alerts] adapter failed: #{Exception.message(exception)}")
      :ok
  end

  defp deliver(adapter, level, title, body) when is_atom(adapter) do
    adapter.send(level, title, body)
    :ok
  rescue
    exception ->
      Logger.error("[alerts] adapter #{inspect(adapter)} failed: #{Exception.message(exception)}")
      :ok
  end

  defp log(level, title, body) do
    Logger.log(level, "[alert] #{title}: #{body}")
  end
end
