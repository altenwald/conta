import Config

config :conta, Conta.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_test",
  hostname: "localhost",
  pool_size: 10

config :conta, Conta.Repo,
  database: "conta_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
