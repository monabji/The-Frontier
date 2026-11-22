defmodule Frontier.Alerts.Webhook do
  @moduledoc """
  A webhook or Telegram channel for failures.

  Telegram is the plan's default human channel: set `FRONTIER_TELEGRAM_BOT_TOKEN`
  and `FRONTIER_TELEGRAM_CHAT_ID`. Any other endpoint can be given
  `FRONTIER_ALERT_WEBHOOK_URL` and receives JSON `{level, title, body}`.
  A delivery failure is logged; it never becomes the reason a run dies.
  """

  require Logger

  @spec send(Frontier.Alerts.level(), String.t(), String.t()) :: :ok
  def send(level, title, body) do
    case target() do
      {:telegram, token, chat_id} ->
        post(telegram_url(token), telegram_payload(chat_id, title, body))

      {:webhook, url} ->
        post(url, %{level: to_string(level), title: title, body: body})

      :none ->
        Frontier.Alerts.Log.send(level, title, body)
    end
  end

  @doc false
  def telegram_payload(chat_id, title, body) do
    %{chat_id: chat_id, text: "#{title}\n\n#{body}"}
  end

  defp target do
    config = Application.get_env(:frontier, __MODULE__, [])

    cond do
      is_binary(config[:url]) and config[:url] != "" ->
        {:webhook, config[:url]}

      is_binary(config[:telegram_bot_token]) and is_binary(config[:telegram_chat_id]) ->
        {:telegram, config[:telegram_bot_token], config[:telegram_chat_id]}

      true ->
        :none
    end
  end

  defp post(url, payload) do
    headers = [{"content-type", "application/json"}]

    case Frontier.HTTP.post(url, Jason.encode!(payload), headers) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("[alerts] delivery failed: #{inspect(reason)}")
        :ok
    end
  end

  defp telegram_url(token), do: "https://api.telegram.org/bot#{token}/sendMessage"
end
