# Plan: Match Rule Condition Primary Key & Schema Resolution

- [x] Task 1: Audit schemas for condition primary_key: false consistency <!-- id: 0 -->
  - [x] Confirm `Conta.Command.SetMatchRule` has `primary_key: false` on `embeds_many :conditions`
  - [x] Confirm `Conta.Event.MatchRuleSet` has `primary_key: false` on `embeds_many :conditions`
  - [x] Confirm `Conta.Projector.Reconciliation.MatchRule` has `primary_key: false` on `embeds_many :conditions`
- [x] Task 2: Add regression tests for `get_set_match_rule/1` with multiple conditions <!-- id: 1 -->
  - [x] Add unit test in `apps/conta/test/conta/reconciliation_context_test.exs` verifying `get_set_match_rule/1` with multiple conditions
  - [x] Add changeset test in `apps/conta/test/conta/command/set_match_rule_test.exs` verifying adding/editing conditions without primary key collisions
- [x] Task 3: Verification & Commit <!-- id: 2 -->
  - [x] Run test suite (`mix test`)
  - [x] Commit regression tests and documentation
  - [x] Complete Task #2 in Backlog and update project spec
