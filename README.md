![](art/conta.png)

Accounting system.

Someone always asked us (to the Erlang community) to say in a small phrase, a small sentence, what's doing the software and not only: "I did something" or "new version available"; it's important to keep it simple and keep it as the first sentence. And now, why "Conta"? well, in Spanish, we say _Contabilidad_ for accounting and _Conta_ is the short name version so, why not?

And now, maybe the information you could find here, what I used to create it:

- Elixir (1.17)
- Erlang/OTP, BEAM (27)
- Phoenix Framework (1.8)
- Commanded (1.4)
- [Plotto](https://hex.pm/packages/plotto) — Pure Elixir charting library (SVG and PNG) for dashboard and financial reports, with zero NIFs or external dependencies.
- [Press](https://hex.pm/packages/press) — Pure Elixir, dependency-free HTML+CSS to PDF engine for invoice export, without requiring headless Chrome or Chromium.

We could say we built the system based on CQRS/ES.

And reply to an old question I received at an Elixir conference in Madrid, in 2015: _Would you do an accounting system using Elixir?_ **Of course!** Here is the sample.

In addition, it's also a demonstration that we could create Telegram bots to help us to perform the activities in a chat system so, the accounting system could be managed and used by the following interfaces:

- LiveView or HTTP + WebSocket.
- Telegram.
- Web service API.

The use cases I want to cover are the use of the accounting system using chat systems (i.e. Telegram), performing integrations for getting moves and generating invoices (via API), and checking everything even when it's changing via the website.

## Goal

To be honest, this is in a very initial version. I could say it's experimental, but I'm using this system for my accounting (personal and professional).

The goal of this project is to accomplish:

- Accounting for assets, liabilities, expenses, revenue, and equities.
- Fast reports generated: income, outcome, patrimony, and profits and losses.
- Invoices and expenses management and link for the accounting.
- Client, provider, and bank management (contacts).
- Product, service, shipping, and discount management (items for invoices).
- Web services (API) for integrating with other systems.
- Extensions made in Lua for reports and other transformations. Initially for launching scripts as shortcuts from Telegram.

These goals could be increased or changed, but I'm completely open to discussing each item.

## Contributing

It's a very ambitious project because it's something I'm using and I want to get it as easy as possible for automating as much as possible the arduous task of accounting. My principles are:

- Keep the code beautiful. Keeping the code beautiful and simple.
- Do the right things right. No workarounds, no temporal code, no dead code.
- Discuss the features and open a discussion if needed. Communication is the key.

## Troubleshooting

### Rebuilding Read Model Projections

Conta is built with CQRS and Event Sourcing (CQRS/ES). Domain events stored in the EventStore serve as the single source of truth, while PostgreSQL tables store the Ecto read-model projections (`ledger`, `book`, `directory`, `reconciliation`, `stats`, and `automator`).

If projection tables ever need to be repaired, resynchronized, or completely rebuilt from historical events, use the rebuild mechanism:

#### Using Mix (development and staging)

```bash
# Rebuild a specific projection
mix conta.rebuild_projection ledger
mix conta.rebuild_projection stats
mix conta.rebuild_projection book
mix conta.rebuild_projection directory
mix conta.rebuild_projection reconciliation
mix conta.rebuild_projection automator

# Rebuild all projections at once
mix conta.rebuild_projection all
```

#### Using Production Releases (Docker / CLI / eval)

```bash
# Rebuild a specific projection in production
bin/conta eval "Conta.Release.rebuild_projection(:ledger)"

# Rebuild all projections in production
bin/conta eval "Conta.Release.rebuild_projection(:all)"
```

#### Programmatically in Elixir / IEx

```elixir
Conta.Projector.rebuild(:ledger)
Conta.Projector.rebuild(:all)
```

