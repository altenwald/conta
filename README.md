![](art/conta.png)

Accounting system.

Someone always asked us (to the Erlang community) to say in a small phrase, a small sentence, what's doing the software and not only: "I did something" or "new version available"; it's important to keep it simple and keep it as the first sentence. And now, why "Conta"? well, in Spanish, we say _Contabilidad_ for accounting and _Conta_ is the short name version so, why not?

And now, maybe the information you could find here, what I used to create it:

- Elixir (1.16)
- Erlang/OTP, BEAM (26)
- Phoenix Framework (1.7)
- Commanded (1.4)

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
