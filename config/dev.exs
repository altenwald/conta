import Config

config :conta, Conta.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_dev",
  hostname: "localhost",
  pool_size: 10

config :conta, Conta.Repo,
  database: "conta_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
