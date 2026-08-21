# TODO

## Monaco: background web worker

Monaco currently falls back to running its services (bracket matching, diff
computation, etc.) on the main thread because `MonacoEnvironment.getWorkerUrl`
/ `getWorker` isn't configured. This shows up in the console:

```
Could not create web worker(s). Falling back to loading web worker code in
main thread, which might cause UI freezes.
You must define a function MonacoEnvironment.getWorkerUrl or MonacoEnvironment.getWorker
```

Not critical for current usage (editor pinned to `language: "lua"`, small
scripts), but if performance becomes noticeable on larger documents, it can
be fixed:

1. Add a worker entry point (`editor.worker.js`) to the esbuild bundle
   (`config/config.exs`, `bundle_monaco` profile).
2. Configure `self.MonacoEnvironment = { getWorkerUrl: () => "/assets/editor.worker.js" }`
   before creating the editor in `apps/conta_web/assets/js/monaco_bundle.js`.
3. Add `worker-src 'self'` (or `blob:` if needed) to the CSP in
   `apps/conta_web/lib/conta_web/router.ex`.

## Projector: `:consistency` isn't propagated to `Commanded.Event.Handler`

`Conta.Projector` (`apps/conta/lib/conta/projector.ex:25`) does
`Keyword.drop(@opts, [:repo, :timeout, :consistency])` before passing the
options to `use Commanded.Event.Handler`. This drops the `:consistency`
option on **every** projector in the app (not just one specific one): it
doesn't matter whether a module declares `consistency:
Application.compile_env(:conta, :consistency, :eventual)` or whether the
config has `consistency: :strong` — the handler always ends up registered as
`:eventual`.

Practical consequence: requesting `dispatch(command, consistency: :strong)`
anywhere in the app is a silent no-op — it doesn't fail, but it also doesn't
wait for the corresponding projector to finish writing to Postgres, because
Commanded only waits for handlers that are actually registered as `:strong`.
This was discovered while implementing `Conta.Reconciliation.confirm_movement/1`
(bank reconciliation): an `update_movement/2` immediately followed by a
read-model read can see data that hasn't been projected yet. It was worked
around in tests with bounded polling (`eventually/1,2` in
`apps/conta/test/conta/reconciliation_context_test.exs`), but the same gap
exists in production for any caller that chains a dispatch with an immediate
read-model read.

Fix: have `Conta.Projector` let `:consistency` pass through to
`Commanded.Event.Handler` (remove it from the `Keyword.drop/2` list), and
review which projectors should actually be `:strong`.

## `Reconciliation.get_set_match_rule/1` doesn't set `:id` on existing conditions

`get_set_match_rule/1` (`apps/conta/lib/conta/reconciliation.ex`) builds the
edit-form `SetMatchRule` from the read model without assigning `:id` to each
`SetMatchRule.Condition`. Since the embed uses Ecto's default primary key
(`:id`), any real edit session with 2+ conditions that clicks "Add
condition" triggers an Ecto warning:

```
found duplicate primary keys for association/embed :conditions in
Conta.Command.SetMatchRule ... only the last entry with the same ID will be
kept
```

Found during Task 28's code-quality review (Match Rules screen) while
adding a regression test that opens the edit form with existing conditions.
The test still passes (the warning doesn't affect the rendered HTML on this
path), but it's a sign of a latent issue in the embed's schema design —
before real ids are used to identify individual rows (e.g. when implementing
removal of a specific condition instead of by index), review whether the
embed needs `primary_key: false` or whether `get_set_match_rule/1` should
assign an explicit `:id` per condition.

## Bot: Support for complex transactions and account-type aware amounts

In `apps/conta_bot/lib/conta_bot/action/transaction.ex`:
- **Account-type aware signs**: When duplicating simple transactions (`dup_<id>`), the amount is currently computed as `Money.subtract(entry1.debit, entry1.credit)`. The sign should take into account the account type (e.g. credit/debit nature for assets vs expenses vs liabilities).
- **Complex transactions**: Transactions with more than 2 entries currently return `"we've still not support for complex transactions"`. Add conversational flow to duplicate or edit multi-split transactions in Telegram.
- **Multi-currency transactions**: `transaction_create` currently rejects transactions involving multiple currencies with `"Cannot still create transaction multi-currency"`. Add support for exchange rates / multi-currency entries in bot transactions.

## Web: Country selection ordering and internationalization (i18n)

In `apps/conta_web/lib/conta_web/live/contact_live/form_component.ex` and `apps/conta_web/lib/conta_web/live/invoice_live/form_component.ex`:
- **Prioritize frequent countries**: Place commonly used countries (e.g. Spain / user's home country) at the top of the dropdown before the alphabetical list.
- **Localized country names**: Use `:countries_i18n` to translate country names according to the current user locale (`Gettext.get_locale/1`).

## Web: REST API for `/ledger/accounts`

In `apps/conta_web/lib/conta_web/router.ex`:
- Add JSON controller endpoints for `resources "/accounts", Account, only: [:index, :show, :create, :update, :delete]` under the `/ledger/` API scope.

## Automators: result validation after a successful script run

A Lua script can finish without error (`Automator.Lua.run/2` returns `{:ok,
result}`) and still produce a `result` that doesn't match what the rest of
the pipeline expects - e.g. a `commands` entry missing `type = "movement"`,
using a misspelled type, or missing the `data` table. Today this is handled
inconsistently, and mostly silently, across the three automator kinds:

- **Importer** (`apps/conta/lib/conta/automator.ex:344-366`,
  `run_importer/4`): the list comprehension
  `for %{"type" => "movement", "data" => data} <- commands do ... end`
  silently drops any command that doesn't match that shape. If a script
  returns 10 commands and 2 have a typo'd `type` or no `data` key, the
  import just creates 8 movements - no error, no count, no log entry
  pointing at the 2 that were skipped. The implicit contract (illustrated by
  `@importer_code_skeleton`) is one input row -> one `"movement"` command,
  so a silent drop is a silent data-loss bug from the user's point of view.
- **Shortcut** (`process_result/2`, same file, lines 395-433): the opposite
  failure mode. `process_result/2` only has clauses for
  `%{"type" => "transaction", ...}` and `%{"type" => "invoice", ...}`; a
  command with any other `type` has no matching clause, so
  `Enum.reduce_while(commands, :ok, &process_result/2)` raises an
  unstructured `FunctionClauseError` instead of returning a clean
  validation error.
- **Filter** (`run_filter/3`): no structural check at all, which is
  arguably fine since filter output is free-form (just JSON-encoded or
  exported to Excel), not commands to dispatch.
- **Test-run path** (`test_run_importer/2`, used by the "test run" panel in
  `apps/conta_web/lib/conta_web/live/importer_live/form.ex`): does return
  the raw, unfiltered `commands` list, so a careful user testing a script
  by hand could in principle spot a malformed entry in the pretty-printed
  JSON - but there's no automatic count/shape check surfaced (e.g. "8 of 10
  rows produced a valid movement"), so it's easy to miss.

Proposed direction: add a validation pass, shared across importer/shortcut/
filter rather than duplicated per kind (e.g. a `Conta.Automator.Validate`
module), that runs right after a script succeeds and before its commands
are dispatched or silently filtered:

- Validate each command's shape against the contract for that automator
  kind (`type` in the allowed set, `data` present as a map), reusing the
  downstream changesets (`SetAccountTransaction.changeset/1`,
  `SetInvoice.changeset/1`, `ImportMovements.changeset/1`) where possible
  instead of re-implementing field-level checks.
  - Turn `run_importer/4`'s silent drop into an explicit
    `{:error, {:invalid_commands, [...]}}` (or similar) listing which
    entries failed and why, instead of quietly filtering them out of
    `movements`.
  - Give `process_result/2` a catch-all clause that returns a proper error
    tuple instead of crashing with `FunctionClauseError`.
- For importers specifically, consider checking that the number of
  produced `"movement"` commands matches the number of input rows (or that
  any discrepancy is explicit/intentional), since 1-row-in -> 1-movement-out
  is the expectation the skeleton script itself illustrates.
- Surface the same validation in the test-run panels (importer/shortcut/
  filter forms) so script authors see "N of M rows/commands were valid"
  instead of having to eyeball the raw JSON.
