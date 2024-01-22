import Config

config :conta, Conta.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_test",
  hostname: "localhost",
  pool_size: 10

config :conta, Conta.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "conta_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :conta_web, ContaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "eaxJEw0IBkn+G6ugEMnKPuhaLb/uXKc4+LwOH0L0NQInD+lHd4YPsEZVNr4QzbbF",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails.
config :conta, Conta.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :ex_gram, test_environment: true
