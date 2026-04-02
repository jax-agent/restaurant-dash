# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :restaurant_dash, :scopes,
  user: [
    default: true,
    module: RestaurantDash.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: RestaurantDash.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :restaurant_dash,
  ecto_repos: [RestaurantDash.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :restaurant_dash, RestaurantDashWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RestaurantDashWeb.ErrorHTML, json: RestaurantDashWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RestaurantDash.PubSub,
  live_view: [signing_salt: "tQrSw+Gs"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :restaurant_dash, RestaurantDash.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  restaurant_dash: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  restaurant_dash: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban
config :restaurant_dash, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    default: 10,
    orders: 5,
    drivers: 5,
    dispatch: 5,
    clover: 5,
    square: 5,
    notifications: 10
  ],
  repo: RestaurantDash.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Driver simulation every 30 seconds
       {"*/1 * * * *", RestaurantDash.Workers.DriverSimulationWorker},
       # Clover inventory sync every 5 minutes
       {"*/5 * * * *", RestaurantDash.Workers.CloverInventorySyncWorker},
       # Square inventory sync every 5 minutes
       {"*/5 * * * *", RestaurantDash.Workers.SquareInventorySyncWorker}
     ]}
  ]

# Stripe configuration (mock mode when no key configured)
config :restaurant_dash, :stripe,
  secret_key: System.get_env("STRIPE_SECRET_KEY"),
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET"),
  # Platform fee percentage (default 5%)
  platform_fee_percent: 5

# Clover POS configuration (mock mode when no key configured)
config :restaurant_dash, :clover,
  app_id: System.get_env("CLOVER_APP_ID"),
  app_secret: System.get_env("CLOVER_APP_SECRET"),
  env: if(System.get_env("CLOVER_ENV") == "production", do: :production, else: :sandbox)

# Square POS configuration (mock mode when no key configured)
config :restaurant_dash, :square,
  app_id: System.get_env("SQUARE_APP_ID"),
  app_secret: System.get_env("SQUARE_APP_SECRET"),
  webhook_signature_key: System.get_env("SQUARE_WEBHOOK_SIGNATURE_KEY"),
  env: if(System.get_env("SQUARE_ENV") == "production", do: :production, else: :sandbox)

# Twilio SMS configuration (mock mode when no credentials configured)
config :restaurant_dash, :twilio,
  account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
  auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
  from_number: System.get_env("TWILIO_FROM_NUMBER")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
