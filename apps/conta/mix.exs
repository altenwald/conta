defmodule Conta.MixProject do
  use Mix.Project

  def project do
    [
      app: :conta,
      version: "0.2.6",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: coverage(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Conta.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp coverage do
    [
      summary: [threshold: 80],
      ignore_modules: [
        # Test fixtures
        Conta.AccountsFixtures,
        Conta.AutomatorFixtures,
        Conta.BookFixtures,
        Conta.DirectoryFixtures,
        Conta.LedgerFixtures,
        Conta.Repo,
        Conta.DataCase,
        # Infrastructure — only used at runtime/release
        Conta.Release,
        Conta.EventStore,
        Conta.EsHelper,
        Conta.Mailer,
        # Commanded infrastructure (no unit-testable logic)
        Conta.Commanded.Application,
        Conta.Commanded.Router,
        Conta.Commanded.Serializer,
        # Stats graphs — depend on Contex + real projection data
        Conta.Stats,
        Conta.Projector.Stats,
        Conta.Projector.Stats.Account,
        Conta.Projector.Stats.Income,
        Conta.Projector.Stats.Outcome,
        Conta.Projector.Stats.Patrimony,
        Conta.Projector.Stats.ProfitsLoses,
        Conta.Projector.Stats.ProjectionVersion,
        # Command Modules (Changesets only)
        Conta.Command.ConciliateAccountTransaction,
        Conta.Command.RemoveAccount,
        Conta.Command.RemoveAccountTransaction,
        Conta.Command.RemoveAccountTransaction.Entry,
        Conta.Command.RemoveContact,
        Conta.Command.RemoveExpense,
        Conta.Command.RemoveFilter,
        Conta.Command.RemoveInvoice,
        Conta.Command.RemoveShortcut,
        Conta.Command.SetAccount,
        Conta.Command.SetAccountTransaction,
        Conta.Command.SetAccountTransaction.Entry,
        Conta.Command.SetCompany,
        Conta.Command.SetContact,
        Conta.Command.SetExpense,
        Conta.Command.SetExpense.Attachment,
        Conta.Command.SetFilter,
        Conta.Command.SetFilter.Param,
        Conta.Command.SetInvoice,
        Conta.Command.SetInvoice.Detail,
        Conta.Command.SetPaymentMethod,
        Conta.Command.SetShortcut,
        Conta.Command.SetShortcut.Param,
        Conta.Command.SetTemplate,
        # Event structure modules
        Conta.Event.ExpenseRemoved,
        Conta.Event.FilterRemoved,
        Conta.Event.FilterSet,
        Conta.Event.FilterSet.Param,
        Conta.Event.InvoiceRemoved,
        Conta.Event.ShortcutSet,
        Conta.Event.ShortcutRemoved,
        Conta.Event.ShortcutSet.Param,
        Conta.Event.AccountRenamed,
        Conta.Event.ExpenseSet.Attachment,
        Conta.Event.ExpenseSet.Provider,
        Conta.Event.TransactionCreated,
        Conta.Event.TransactionRemoved,
        # Automator specific extensions
        Conta.Automator,
        Conta.Automator.Excel,
        Conta.Automator.Lua,
        Conta.Projector.Automator,
        Conta.Projector.Automator.Filter,
        Conta.Projector.Automator.Param,
        Conta.Aggregate.Automator,
        # Aggregate logic details
        Conta.Aggregate.Company,
        Conta.Aggregate.Company.Contact,
        Conta.Aggregate.Company.PaymentMethod,
        # Domain objects without business logic
        Conta.Domain.Expense,
        # Projector base and details
        Conta.Projector,
        Conta.Projector.Book.Expense,
        Conta.Projector.Book.Expense.Attachment,
        Conta.Projector.Book.Expense.PaymentMethod,
        Conta.Projector.Ledger.Balance,
        # Helpers
        Conta.EctoHelpers,
        # Generated Jason.Encoder implementations (derived)
        Jason.Encoder.Money,
        Jason.Encoder.Conta.Aggregate.Automator,
        Jason.Encoder.Conta.Aggregate.Company,
        Jason.Encoder.Conta.Aggregate.Company.Contact,
        Jason.Encoder.Conta.Aggregate.Company.PaymentMethod,
        Jason.Encoder.Conta.Aggregate.Ledger,
        Jason.Encoder.Conta.Aggregate.Ledger.Account,
        Jason.Encoder.Conta.Event.AccountCreated,
        Jason.Encoder.Conta.Event.AccountModified,
        Jason.Encoder.Conta.Event.AccountRemoved,
        Jason.Encoder.Conta.Event.AccountRenamed,
        Jason.Encoder.Conta.Event.Common.Company,
        Jason.Encoder.Conta.Event.Common.PaymentMethod,
        Jason.Encoder.Conta.Event.CompanySet,
        Jason.Encoder.Conta.Event.ContactRemoved,
        Jason.Encoder.Conta.Event.ContactSet,
        Jason.Encoder.Conta.Event.ExpenseRemoved,
        Jason.Encoder.Conta.Event.ExpenseSet,
        Jason.Encoder.Conta.Event.ExpenseSet.Attachment,
        Jason.Encoder.Conta.Event.ExpenseSet.Provider,
        Jason.Encoder.Conta.Event.FilterRemoved,
        Jason.Encoder.Conta.Event.FilterSet,
        Jason.Encoder.Conta.Event.FilterSet.Param,
        Jason.Encoder.Conta.Event.InvoiceRemoved,
        Jason.Encoder.Conta.Event.InvoiceSet,
        Jason.Encoder.Conta.Event.InvoiceSet.Client,
        Jason.Encoder.Conta.Event.InvoiceSet.Detail,
        Jason.Encoder.Conta.Event.PaymentMethodSet,
        Jason.Encoder.Conta.Event.ShortcutRemoved,
        Jason.Encoder.Conta.Event.ShortcutSet,
        Jason.Encoder.Conta.Event.ShortcutSet.Param,
        Jason.Encoder.Conta.Event.TemplateSet,
        Jason.Encoder.Conta.Event.TransactionCreated,
        Jason.Encoder.Conta.Event.TransactionCreated.Entry,
        Jason.Encoder.Conta.Event.TransactionRemoved,
        Jason.Encoder.Conta.Event.TransactionRemoved.Entry,
        Jason.Encoder.Conta.Projector.Automator.Filter,
        Jason.Encoder.Conta.Projector.Automator.Param,
        Jason.Encoder.Conta.Projector.Automator.Shortcut,
        Jason.Encoder.Conta.Projector.Book.Expense,
        Jason.Encoder.Conta.Projector.Book.Expense.Company,
        Jason.Encoder.Conta.Projector.Book.Expense.PaymentMethod,
        Jason.Encoder.Conta.Projector.Book.Expense.Provider,
        Jason.Encoder.Conta.Projector.Book.Invoice,
        Jason.Encoder.Conta.Projector.Book.Invoice.Client,
        Jason.Encoder.Conta.Projector.Book.Invoice.Company,
        Jason.Encoder.Conta.Projector.Book.Invoice.Detail,
        Jason.Encoder.Conta.Projector.Book.Invoice.PaymentMethod,
        # Generated Inspect implementations
        Inspect.Conta.Accounts.User
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:commanded, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:commanded_eventstore_adapter, "~> 1.4"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:typed_ecto_schema, "~> 0.4"},
      {:money, "~> 1.12"},
      {:dns_cluster, "~> 0.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:req, "~> 0.5"},
      {:swoosh, "~> 1.14"},
      {:finch, "~> 0.17"},
      # https://github.com/mindok/contex/pull/93
      {:contex, "~> 0.5", github: "manuel-rubio/contex"},
      {:resvg, "~> 0.3"},
      {:luerl, "~> 1.1"},
      {:elixlsx, "~> 0.6"},
      {:nimble_csv, "~> 1.2"},
      {:ex_machina, "~> 2.7", only: :test},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      reset_es: ~w[event_store.drop event_store.create event_store.init],
      reset_db: ~w[ecto.drop ecto.create ecto.migrate],
      # test: ["reset_es", "reset_db", "test --cover"]
    ]
  end
end
