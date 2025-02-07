[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  import_deps: [:ecto, :ecto_sql, :phoenix],
  inputs: [
    "*{.html.heex,_html.heex,.ex,.exs}",
    "config/*.exs",
    "apps/*/{lib,test}/**/*{.html.heex,_html.heex,.ex,.exs}"
  ],
  subdirectories: ["priv/*/migrations"],
  line_length: 110
]
