defmodule Frontier.Alerts.Log do
  @moduledoc "The alert channel that always exists: the application log."
  require Logger

  @spec send(Frontier.Alerts.level(), String.t(), String.t()) :: :ok
  def send(level, title, body) do
    Logger.log(level, "[alert] #{title}: #{body}")
    :ok
  end
end
