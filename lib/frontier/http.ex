defmodule Frontier.HTTP do
  @moduledoc """
  The one place the paper talks to the network.

  A GET of JSON, with a 10s timeout, a peer-verified TLS connection and an
  honest user agent. Errors come back as `{:error, reason}` — a source that
  times out is a logged failure, never a crash.
  """

  @timeout 10_000

  @user_agent "TheFrontier/0.1 (+https://github.com/monabji/newspaper)"

  @doc """
  GETs a URL and decodes a JSON body.
  """
  @spec get_json(String.t()) :: {:ok, term()} | {:error, term()}
  def get_json(url) when is_binary(url) do
    request = {String.to_charlist(url), [{~c"user-agent", String.to_charlist(@user_agent)}]}

    case :httpc.request(:get, request, http_options(), body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        Jason.decode(body)

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_options do
    [
      timeout: @timeout,
      connect_timeout: @timeout,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
  end
end
