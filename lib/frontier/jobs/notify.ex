defmodule Frontier.Jobs.Notify do
  @moduledoc """
  The one alert format the daily job sends, so every failure says the same
  useful things: which day, which stage, why, and what readers see meanwhile.
  """

  @spec failed(String.t(), Date.t(), term(), pos_integer(), pos_integer()) :: :ok
  def failed(title, day, reason, attempt, max_attempts) do
    body = """
    Edition: #{day}
    Attempt: #{attempt} of #{max_attempts}
    Reason: #{format(reason)}

    Readers are being served the previous published edition with a delayed banner.
    Run log: mix frontier.log --day #{day}
    """

    Frontier.Alerts.alert(:error, title, body)
  end

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
