# Implementation Plan: Invoice PDF Download via Authenticated API

## Tasks

- [x] **Task 1: Add non-raising template lookup and tests in `Conta.Book`**
  - [x] Add `get_template_by_name/2` in `Conta.Book` and test in `apps/conta/test/conta/book_test.exs`.
  - [x] Verify tests pass.

- [x] **Task 2: API Route and Controller Action for PDF Download**
  - [x] Add route `get "/invoices/:id/download", Invoice, :download` in `ContaWeb.Router`.
  - [x] Implement `download/2` in `ContaWeb.Api.Book.Invoice`.
  - [x] Add integration tests in `apps/conta_web/test/conta_web/api/book/invoice_test.exs`.
  - [x] Verify tests pass.

- [x] **Task 3: Full Verification & Superpowers Completion**
  - [x] Run `mix test` and `mix check`.
