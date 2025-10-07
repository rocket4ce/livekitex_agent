import Config

# Basic Phoenix test app configuration
config :phoenix_test_app,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :phoenix_test_app, PhoenixTestAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: PhoenixTestAppWeb.ErrorHTML, json: PhoenixTestAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PhoenixTestApp.PubSub,
  live_view: [signing_salt: "test_salt"],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "test_secret_key_base_for_testing_phoenix_integration_with_livekitex_agent_library_configuration_fix",
  watchers: []

# Configure livekitex_agent (this is what we're testing)
config :livekitex_agent,
  default_worker_options: [
    worker_pool_size: 2,
    agent_name: "phoenix_test_agent"
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure logger for test environment
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
