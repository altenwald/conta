import Config

config :conta, event_stores: [Conta.EventStore]

config :conta, Conta.EventStore, serializer: Conta.Commanded.Serializer

config :conta, ecto_repos: [Conta.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :conta, Conta.Mailer, adapter: Swoosh.Adapters.Local

config :money,
  # this allows you to do Money.new(100)
  default_currency: :EUR,
  # change the default thousands separator for Money.to_string
  separator: ".",
  # change the default decimal delimiter for Money.to_string
  delimiter: ",",
  # don’t display the currency symbol in Money.to_string
  symbol: true,
  # position the symbol
  symbol_on_right: true,
  # add a space between symbol and number
  symbol_space: true,
  # don’t display the remainder or the delimiter
  fractional_unit: true

config :conta_web,
  ecto_repos: [Conta.Repo],
  generators: [context_app: :conta, binary_id: true]

# Configures the endpoint
config :conta_web, ContaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: ContaWeb.ErrorHTML, json: ContaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Conta.PubSub,
  live_view: [signing_salt: "0p+VBfTB"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/conta_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/conta_web/assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :dart_sass,
  version: "1.36.0",
  default: [
    args:
      ~w(--load-path=../../../deps/bulma --load-path=../assets/vendor/bulma-checkbox css:../priv/static/assets),
    cd: Path.expand("../apps/conta_web/assets", __DIR__)
  ]

config :tesla, adapter: {Tesla.Adapter.Finch, name: ContaBot.Finch}

config :ex_gram, adapter: ExGram.Adapter.Tesla

config :ex_gram, json_engine: Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config("#{config_env()}.exs")
