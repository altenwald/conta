# Invoice Creation API: ID and Invoice Number Implementation Plan

- **Spec**: `docs/superpowers/specs/2026-09-07-invoice-api-id-and-number-design.md`
- **Date**: 2026-09-07

---

## Tasks

- [x] **Task 1: Add optional `:id` field to `Conta.Command.SetInvoice` and `Conta.Event.InvoiceSet`**
  - [x] Write failing test for `SetInvoice` changeset casting `:id` and `InvoiceSet` changeset casting `:id`.
  - [x] Add `field :id, :binary_id` and include in `@optional_fields` in `Conta.Command.SetInvoice`.
  - [x] Add `field :id, :binary_id` and include in `@optional_fields` in `Conta.Event.InvoiceSet`.
  - [x] Verify aggregate `Conta.Aggregate.Company` passes `id` through when building `InvoiceSet`.
  - [x] Run tests and verify they pass.

- [x] **Task 2: Update Projector to use event `:id` or autogenerate UUID**
  - [x] Write failing tests in `Conta.Projector.BookTest` verifying an event with explicit `id` keeps it, and with `id: nil` generates one.
  - [x] Update `Conta.Projector.Book.Invoice.changeset/2` to include `:id` in `@optional_fields`.
  - [x] Update `Conta.Projector.Book` for `InvoiceSet` to set `id = invoice.id || Ecto.UUID.generate()`.
  - [x] Run tests and verify they pass.

- [x] **Task 3: Implement `Conta.Book.to_invoice_number/3` and dual lookup in `Conta.Book.get_invoice/1` & `get_invoice!/1`**
  - [x] Write failing tests in `Conta.BookTest` for `to_invoice_number/3` (regular and credit note).
  - [x] Write failing tests in `Conta.BookTest` for `get_invoice/1` and `get_invoice!/1` with UUID and formatted `invoice_number`.
  - [x] Implement `Conta.Book.to_invoice_number/3` and reuse it in `Conta.Projector.Book`.
  - [x] Update `Conta.Book.get_invoice/1` and `get_invoice!/1` to dispatch on UUID vs `invoice_number`.
  - [x] Run tests and verify they pass.

- [x] **Task 4: Update API Controller `create/2` to generate UUID if missing, dispatch with `returning: :execution_result`, and respond with 201 Created**
  - [x] Write failing tests in `ContaWeb.Api.Book.InvoiceTest` for `POST /api/v1/books/invoices`:
    - Successful creation without `id` returns 201, UUID in `"id"`, and formatted `"invoice_number"`.
    - Successful creation with provided `id` preserves that exact `"id"`.
    - `GET /api/v1/books/invoices/:id` works with either the `"id"` or `"invoice_number"`.
    - `GET /api/v1/books/invoices/:id/download` works with `invoice_number`.
  - [x] Update `ContaWeb.Api.Book.Invoice.create/2` and `set_invoice/3` to inject UUID, call `dispatch(command, returning: :execution_result)`, format `invoice_number`, and render HTTP 201 with `id` and `invoice_number`.
  - [x] Run tests and verify they pass.

- [x] **Task 5: Verification & Quality Checks**
  - [x] Run `mix test` across the umbrella project.
  - [x] Run `mix check` (Credo, Dialyzer, Sobelow, compiler warnings).
