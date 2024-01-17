import Config

config :conta, event_stores: [Conta.EventStore]

config :conta, ecto_repos: [Conta.Repo]

config :money,
  # this allows you to do Money.new(100)
  default_currency: :EUR,
  # change the default thousands separator for Money.to_string
  separator: ".",
  # change the default decimal delimeter for Money.to_string
  delimiter: ",",
  # don’t display the currency symbol in Money.to_string
  symbol: true,
  # position the symbol
  symbol_on_right: true,
  # add a space between symbol and number
  symbol_space: true,
  # don’t display the remainder or the delimeter
  fractional_unit: true

import_config("#{config_env()}.exs")
