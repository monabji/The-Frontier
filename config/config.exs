# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :frontier,
  ecto_repos: [Frontier.Repo],
  generators: [timestamp_type: :utc_datetime]

# Oban is the paper's clock: fetching, editing and publishing all run as jobs.
# SQLite has no `FOR UPDATE SKIP LOCKED`, so Oban runs on its Lite engine.
# Queues, plugins and (from phase 6) Cron entries live here and nowhere else.
config :frontier, Oban,
  engine: Oban.Engines.Lite,
  repo: Frontier.Repo,
  queues: [default: 10],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {2, :hours}]

# Configure the endpoint
config :frontier, FrontierWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FrontierWeb.ErrorHTML, json: FrontierWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Frontier.PubSub,
  live_view: [signing_salt: "8Z+2WbkS"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  frontier: [
    args:
      ~w(css/app.css --bundle --target=es2022 --outbase=. --outdir=../priv/static/assets --external:/fonts/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# The editor: one OpenAI-compatible endpoint, named in configuration so the
# paper is not tied to a vendor. A run without a key fails loudly; it never
# falls back to a canned edition.
config :frontier, :editor_client, Frontier.Editor.Client.HTTP

config :frontier, Frontier.Editor.Client.HTTP,
  base_url: "https://api.openai.com/v1",
  model: "gpt-4o-mini",
  temperature: 0.4,
  max_tokens: 8_000

# Dollars per million tokens. The run records micro-dollars from these; change
# them when a provider changes its price rather than editing code.
config :frontier, :editor_pricing, %{input_per_million: 0.15, output_per_million: 0.60}

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
