import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/frontier start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :frontier, FrontierWeb.Endpoint, server: true
end

config :frontier, FrontierWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# The editor's provider, from the environment. Any endpoint that speaks the
# OpenAI chat-completions shape works; a missing key makes the run fail, never
# fall back to a canned paper.
parse_price = fn name, default ->
  case System.get_env(name) do
    nil ->
      default

    value ->
      case Float.parse(value) do
        {price, _rest} -> price
        :error -> default
      end
  end
end

config :frontier, Frontier.Editor.Client.HTTP,
  base_url: System.get_env("FRONTIER_LLM_BASE_URL", "https://api.openai.com/v1"),
  model: System.get_env("FRONTIER_LLM_MODEL", "gpt-4o-mini"),
  api_key: System.get_env("FRONTIER_LLM_API_KEY") || System.get_env("OPENAI_API_KEY"),
  allow_missing_api_key: System.get_env("FRONTIER_LLM_KEYLESS") in ["1", "true"],
  reasoning_effort: System.get_env("FRONTIER_LLM_REASONING_EFFORT"),
  temperature: 0.4,
  max_tokens: 8_000,
  timeout: String.to_integer(System.get_env("FRONTIER_LLM_TIMEOUT_MS", "180000"))

# The editing desk pastes a chat window's reply into the paper. It can write an
# edition, so it is disabled unless this token is set and presented.
config :frontier, :desk_token, System.get_env("FRONTIER_DESK_TOKEN")

# "model" asks one endpoint for the whole paper; "keyless" writes it in parts,
# for a free endpoint with a short reply. The client is still the same.
config :frontier, :editor_mode, System.get_env("FRONTIER_EDITOR", "model")

config :frontier, :editor_pricing, %{
  input_per_million: parse_price.("FRONTIER_LLM_INPUT_PRICE", 0.15),
  output_per_million: parse_price.("FRONTIER_LLM_OUTPUT_PRICE", 0.60)
}

# One human channel for a late paper. Telegram is the plan's default; any
# webhook that accepts JSON works. With neither, the alert is a log line.
telegram_token = System.get_env("FRONTIER_TELEGRAM_BOT_TOKEN")
telegram_chat = System.get_env("FRONTIER_TELEGRAM_CHAT_ID")
webhook = System.get_env("FRONTIER_ALERT_WEBHOOK_URL")

config :frontier,
       :alert_adapter,
       if(is_binary(webhook) or (is_binary(telegram_token) and is_binary(telegram_chat)),
         do: Frontier.Alerts.Webhook,
         else: Frontier.Alerts.Log
       )

config :frontier, Frontier.Alerts.Webhook,
  url: webhook,
  telegram_bot_token: telegram_token,
  telegram_chat_id: telegram_chat

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :frontier, FrontierWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/frontier_web/router\.ex$"E,
        ~r"lib/frontier_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The cookie is identity; it must never travel over plain HTTP.
  config :frontier, :secure_cookies, true

  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/frontier/frontier.db
      """

  config :frontier, Frontier.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    journal_mode: :wal,
    busy_timeout: 5_000,
    synchronous: :normal

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :frontier, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :frontier, FrontierWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :frontier, FrontierWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :frontier, FrontierWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
