defmodule Frontier.HTTP do
  @moduledoc """
  The one place the paper talks to the network.

  `get/1` returns the response as it arrived — status, content type, decoded
  body, and the URL it finally landed on — so adapters can decide what it means.
  The `get_*` helpers decode JSON and XML for the adapters that expect one or
  the other.

  Redirects are followed here, one hop at a time, because `:httpc`'s own
  redirect handling hides where it stopped and phase 4's "does this link
  resolve" has to know. Bodies are gzipped by most feeds, so they are decoded
  before anything measures or parses them. Bodies over 5 MB are refused rather
  than stored, and a non-200 carries a short excerpt so the run log says what
  the server actually sent.

  A source that times out is a logged failure, never a crash: every path here
  returns `{:error, reason}`. When the environment disables the network (as the
  test environment does), every path returns `{:error, :network_disabled}`.
  """

  @timeout 10_000
  @max_body 5 * 1024 * 1024
  @max_redirects 5
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
    if network?(), do: follow(:get, url, 0), else: {:error, :network_disabled}
  end

  @doc "GETs a URL and decodes a JSON body."
  @spec get_json(String.t()) :: {:ok, term()} | {:error, term()}
  def get_json(url) do
    with {:ok, response} <- get(url),
         :ok <- json?(response.content_type) do
      Jason.decode(response.body)
    end
  end

  @doc """
  POSTs a body and returns the response without interpreting it. Used by the
  editor's model client; redirects are not followed because a POST that
  redirects is a misconfigured endpoint, not a moved article.
  """
  @spec post(String.t(), binary(), [{String.t(), String.t()}]) ::
          {:ok, response()} | {:error, term()}
  def post(url, body, headers) when is_binary(url) and is_binary(body) do
    if network?() do
      case request(:post, url, body, headers) do
        {:ok, %{status: status} = response} when status in 200..299 ->
          {:ok, response}

        {:ok, %{status: status} = response} ->
          {:error, {:http_status, status, excerpt(response.body)}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :network_disabled}
    end
  end

  @doc "GETs a URL and returns its body as text, whatever it is."
  @spec get_xml(String.t()) :: {:ok, response()} | {:error, term()}
  def get_xml(url), do: get(url)

  @doc """
  The URL a link finally lands on, following redirects one hop at a time.
  """
  @spec final_url(String.t()) :: {:ok, String.t()} | {:error, term()}
  def final_url(url) do
    if network?() do
      case follow(:head, url, 0) do
        {:ok, response} -> {:ok, response.final_url}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :network_disabled}
    end
  end

  defp follow(_method, _url, hops) when hops > @max_redirects do
    {:error, :too_many_redirects}
  end

  defp follow(method, url, hops) do
    case request(method, url) do
      {:ok, %{status: status, location: location}}
      when status in 300..399 and is_binary(location) ->
        follow(method, url |> URI.merge(location) |> to_string(), hops + 1)

      {:ok, %{status: status} = response} ->
        if status in 200..299,
          do: {:ok, response},
          else: {:error, {:http_status, status, excerpt(response.body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(method, url) do
    request(method, url, nil, [])
  end

  defp request(method, url, body, extra_headers) do
    headers =
      [
        {~c"user-agent", String.to_charlist(@user_agent)},
        {~c"accept-encoding", ~c"gzip"}
      ] ++
        Enum.map(extra_headers, fn {key, value} ->
          {String.to_charlist(key), String.to_charlist(value)}
        end)

    request =
      case body do
        nil -> {String.to_charlist(url), headers}
        body -> {String.to_charlist(url), headers, ~c"application/json", body}
      end

    case :httpc.request(method, request, http_options(), body_format: :binary) do
      {:ok, {{_version, status, _reason}, response_headers, body}} ->
        body = decode_body(response_headers, body)

        cond do
          byte_size(body) > @max_body ->
            {:error, {:body_too_large, byte_size(body)}}

          true ->
            {:ok,
             %{
               status: status,
               content_type: header(response_headers, "content-type"),
               location: header(response_headers, "location"),
               body: body,
               final_url: url
             }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Decodes a response body according to its content-encoding."
  @spec decode_body([{charlist() | String.t(), charlist() | String.t()}], binary()) :: binary()
  def decode_body(headers, body) do
    case header(headers, "content-encoding") do
      encoding when is_binary(encoding) ->
        if String.contains?(String.downcase(encoding), "gzip"), do: gunzip(body), else: body

      nil ->
        body
    end
  end

  defp gunzip(body) do
    :zlib.gunzip(body)
  rescue
    _ -> body
  catch
    _kind, _reason -> body
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end

  defp json?(nil), do: :ok

  defp json?(type) do
    if String.contains?(String.downcase(type), "json"),
      do: :ok,
      else: {:error, {:not_json, type}}
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
      autoredirect: false,
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
