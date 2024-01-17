defmodule Conta.EsHelper do
  def truncate_readstore_tables do
    Conta.Repo.query!("""
    TRUNCATE TABLE
      ledger_accounts,
      ledger_entries,
      stats_accounts,
      stats_income,
      stats_outcome,
      stats_patrimony,
      stats_profits_loses
    RESTART IDENTITY
    CASCADE;
    """)
  end
end
