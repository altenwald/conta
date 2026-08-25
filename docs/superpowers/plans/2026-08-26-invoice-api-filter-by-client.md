# Implementation Plan: Filter Invoices by Client ID in API

Implement client filtering for invoice API endpoints in `Conta.Book` and `ContaWeb.Api.Book.Invoice`.

## Tasks

- [x] **Task 1: Domain Logic in `Conta.Book`**
  - [x] Write tests in `apps/conta/test/conta/book_test.exs` for `list_invoices`, `list_invoices_by_term_and_year`, and `list_invoices_filtered` with client filtering (by Contact UUID and by NIF).
  - [x] Implement `by_client/2` and client filter arguments in `Conta.Book`.
  - [x] Verify tests pass in `apps/conta`.

- [x] **Task 2: API Controller and Routing in `ContaWeb`**
  - [x] Update `ContaWeb.Router` to support nested client/contact routes.
  - [x] Update `ContaWeb.Api.Book.Invoice.index/2` to pass `client_id` to `Conta.Book`.
  - [x] Write comprehensive API controller tests in `apps/conta_web/test/conta_web/api/book/invoice_test.exs`.
  - [x] Verify tests pass in `apps/conta_web`.

- [x] **Task 3: Full Verification & Superpowers Completion**
  - [x] Run `mix test` across all apps.
  - [x] Run `mix check` (14/14 checks).
