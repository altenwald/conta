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
