import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :frontier, Frontier.Repo,
  database: Path.expand("../frontier_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :frontier, FrontierWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7KpYvVjpp2pxuFTBCo70gKbVKQEV4+xrSFyOHMFM2aqb5fIEY7oquTwPV4qcnZH4",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# No test may reach the network: a test that forgets to inject a client gets
# `{:error, :network_disabled}` instead of a real request.
config :frontier, network: false

# Artifact storage is files; tests that write editions get a throwaway root.
config :frontier, :edition_storage, Path.expand("../tmp/editions_test", __DIR__)

# Oban runs no jobs and no plugins in tests: jobs are executed explicitly with
# `Oban.Testing` so `mix test` stays deterministic and offline.
config :frontier, Oban, testing: :manual, queues: false, plugins: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
