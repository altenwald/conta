# Run a bounded Conta task from SuperPlane

SuperPlane dispatches a manually triggered GitHub Actions workflow and waits for its result. GitHub Actions supplies an isolated Ubuntu environment and PostgreSQL. Claude implements Backlog task 12; deterministic checks and a separate Claude review provide evidence for human review. No automatic merge or repeated correction loop is included.

The workflow accepts no arbitrary prompt or shell input. It reads a checked-in task description, uses a repository-scoped Actions token and an ANTHROPIC_API_KEY repository secret, and caps each agent session's budget and turns. The baseline tests run before implementation. Tests and `mix check` run again after implementation. Reports and a patch survive failures as artifacts; a draft pull request is created only if the deterministic checks pass. The reviewer does not edit implementation files or publish comments.

The initial task covers existing ledger pagination only. Invoices and expenses are outside this change. Changes are committed on a run-specific branch with a one-sentence commit message and no attribution trailers. The local Backlog is not reachable from the hosted runner; its lifecycle stays with the operator and is not marked complete until the actual change has been reviewed and verified.
