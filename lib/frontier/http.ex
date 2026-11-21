defmodule Frontier.HTTP do
  @moduledoc """
  The one place the paper talks to the network.

  `get/1` returns the response as it arrived — status, content type, body, and
  the URL after redirects — so adapters can decide what it means. The `get_*`
  helpers decode JSON and XML for the adapters that expect one or the other.

  A source that times out is a logged failure, never a crash: every path here
  returns `{:error, reason}`. Bodies over 5 MB are refused rather than stored,
  and a non-200 carries a short excerpt so the run log says what the server
  actually sent.
  """

  @timeout 10_000
  @max_body 5 * 1024 * 1024
  @excerpt 500

  @user_agent "TheFrontier/0.1 (+https://github.com/monabji/newspaper)"

  @type response :: %{
          status: pos_integer(),
          content_type: String.t() | nil,
          body: binary(),
          final_url: String.t()
        }

  @doc "GETs a URL and returns the response without interpreting it."
  @spec get(String.t()) :: {:ok, response()} | {:error, term()}
  def get(url) when is_binary(url) do
    if network?() do
      request(url)
    else
      {:error, :network_disabled}
    end
  end

  @doc "GETs a URL and decodes a JSON body."
  @spec get_json(String.t()) :: {:ok, term()} | {:error, term()}
  def get_json(url) do
    with {:ok, response} <- get(url),
         :ok <- json?(response.content_type) do
      Jason.decode(response.body)
    end
  end

  @doc "GETs a URL and returns its body as text, whatever it is."
  @spec get_xml(String.t()) :: {:ok, response()} | {:error, term()}
  def get_xml(url), do: get(url)

  @doc """
  The URL a link finally lands on, following redirects one hop at a time.

  `:httpc` follows redirects internally without telling you where it stopped,
  so canonicalisation asks here instead. A failure returns an error and the
  caller keeps the URL it had.
  """
  @spec final_url(String.t()) :: {:ok, String.t()} | {:error, term()}
  def final_url(url), do: hop(url, 0)

  @max_redirects 5

  defp hop(_url, hops) when hops > @max_redirects, do: {:error, :too_many_redirects}

  defp hop(url, hops) do
    with {:ok, %{status: status, location: location}} <- head(url) do
      cond do
        status in 300..399 and is_binary(location) ->
          hop(url |> URI.merge(location) |> to_string(), hops + 1)

        status in 200..299 ->
          {:ok, url}

        true ->
          {:error, {:http_status, status}}
      end
    end
  end

  defp head(url) do
    request = {String.to_charlist(url), [{~c"user-agent", String.to_charlist(@user_agent)}]}

    case :httpc.request(:head, request, head_options(), body_format: :binary) do
      {:ok, {{_version, status, _reason}, headers, _body}} ->
        {:ok, %{status: status, location: header(headers, "location")}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp head_options, do: Keyword.put(http_options(), :autoredirect, false)

  defp request(url) do
    request = {String.to_charlist(url), [{~c"user-agent", String.to_charlist(@user_agent)}]}

    case :httpc.request(:get, request, http_options(), body_format: :binary) do
      {:ok, {{_version, status, _reason}, headers, body}} ->
        cond do
          byte_size(body) > @max_body -> {:error, {:body_too_large, byte_size(body)}}
          status in 200..299 -> {:ok, response(status, headers, body, url)}
          true -> {:error, {:http_status, status, excerpt(body)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp response(status, headers, body, url) do
    %{
      status: status,
      content_type: header(headers, "content-type"),
      body: body,
      final_url: url
    }
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end

  defp json?(nil), do: :ok

  defp json?(type) do
    if is_json(type), do: :ok, else: {:error, {:not_json, type}}
  end

  defp is_json(type) do
    String.contains?(String.downcase(type), "json")
  end

  defp excerpt(body) do
    body
    |> String.slice(0, @excerpt)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc false
  def network?, do: Application.get_env(:frontier, :network, true)

  defp http_options do
    [
      timeout: @timeout,
      connect_timeout: @timeout,
      autoredirect: true,
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
