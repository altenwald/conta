# Specification: Match Rule Condition Primary Key & Schema Resolution

## 1. Overview & Context

During earlier development of the Bank Reconciliation match rules screen, opening an edit form for a match rule with 2 or more conditions and clicking "Add condition" triggered an Ecto warning:
```
found duplicate primary keys for association/embed :conditions in Conta.Command.SetMatchRule ... only the last entry with the same ID will be kept
```

The underlying cause was that Ecto's `embeds_many` by default defines a primary key (`field :id, :binary_id, primary_key: true`) on embedded schemas if not specified. When `get_set_match_rule/1` constructed `%SetMatchRule.Condition{}` from the read model without assigning an explicit `:id`, all conditions defaulted to `id: nil`, which caused Ecto changeset casting to perceive them as duplicate primary keys (`nil`).

## 2. Architectural Review: `primary_key: false` vs Explicit `:id`

The task called for reviewing whether the embed needs `primary_key: false` or whether conditions should carry explicit `:id`s:
- **Condition Lifecycle**: Match rule conditions are value objects scoped entirely to the parent match rule. They are evaluated sequentially in order (or as a set) and deleted/replaced wholesale (`on_replace: :delete`) on rule updates.
- **UI Form Handling**: In `ContaWeb.ReconciliationLive.Matches.Form`, condition additions and deletions operate by integer string index (`"0"`, `"1"`, etc.), not by individual condition UUID.
- **Decision**: Setting `primary_key: false` on `embeds_many :conditions` across `Conta.Command.SetMatchRule`, `Conta.Event.MatchRuleSet`, and `Conta.Projector.Reconciliation.MatchRule` is the correct, idiomatic architectural design. It eliminates the spurious `:id` field from JSON serialization, prevents primary key collisions, and simplifies condition management.

In commit `ec9a708` ("Add concept transformation to reconciliation match rules"), `primary_key: false` was applied to `SetMatchRule`.

## 3. Verification & Regression Coverage

To ensure this remains robust and prevents regressions:
1. Add context unit tests in `Conta.ReconciliationContextTest` verifying `get_set_match_rule/1` with 2+ conditions accurately maps all condition fields into `%SetMatchRule{}` without assigning or requiring an `:id`.
2. Add command changeset tests in `Conta.Command.SetMatchRuleTest` demonstrating that initializing `SetMatchRule.changeset/2` with multiple existing conditions and adding a new condition runs cleanly with zero duplicate primary key warnings.
