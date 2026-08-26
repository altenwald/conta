# Implementation Plan: Invoice Credit Notes (Devoluciones / Creditfacturen)

**Date**: 2026-08-26  
**Spec**: `docs/superpowers/specs/2026-08-26-invoice-credit-notes-design.md`  

---

## Tasks

- [x] **Task 1: Configuration & Migration**
  - [x] Add `config :conta, credit_note_prefix: "CN"` in `config/config.exs`.
  - [x] Generate migration `add_credit_note_fields_to_book_invoices` for `book_invoices` table (`is_credit_note`, `origin_invoice_number`, `origin_invoice_date`, `origin_invoice_id`).
  - [x] Update `Conta.Projector.Book.Invoice` schema with new fields.
  - [x] Run migration and verify database schema.

- [x] **Task 2: Domain Layer (Commands, Events & Aggregate)**
  - [x] Update `Conta.Command.SetInvoice` with `is_credit_note`, `origin_invoice_number`, `origin_invoice_date`, `origin_invoice_id`.
  - [x] Update `Conta.Event.InvoiceSet` with new fields.
  - [x] Update `Conta.Aggregate.Company` to manage `credit_note_numbers: %{year => MapSet.new()}` and snapshot serializer.
  - [x] Add unit tests in `apps/conta/test/conta/aggregate/company_test.exs` for credit note numbering and serialization.

- [x] **Task 3: Projector & Context Layer (`Conta.Projector.Book` & `Conta.Book`)**
  - [x] Update `Conta.Projector.Book` to format credit note invoice numbers with prefix (e.g. `CN-2026-00001`).
  - [x] Implement `Conta.Book.get_credit_note_by_origin_invoice_id/1` and `get_credit_note_by_origin_invoice_number/1`.
  - [x] Implement `Conta.Book.create_credit_note_from_invoice/2`.
  - [x] Add tests in `apps/conta/test/conta/book_test.exs`.

- [x] **Task 4: Web LiveView (`ContaWeb.InvoiceLive.Index`)**
  - [x] Update `InvoiceLive.Index` to track/display credit note action button per invoice (Create Credit Note vs View Credit Note).
  - [x] Add credit note badge for credit note items and link to original invoice.
  - [x] Handle `"create_credit_note"` event with flash message and stream update.
  - [x] Add LiveView tests in `apps/conta_web/test/conta_web/live/invoice_live_test.exs`.

- [x] **Task 5: PDF Rendering & API**
  - [x] Update `ContaWeb.InvoiceHTML` / `InvoiceController` PDF template for credit note header and original invoice reference.
  - [x] Update `ContaWeb.Api.Book.InvoiceJSON` to include credit note fields.
  - [x] Add `POST /api/v1/books/invoices/:id/credit_note` endpoint in API router and controller.
  - [x] Add tests for PDF download and API credit note creation.

- [x] **Task 6: Verification & Quality Checks**
  - [x] Run `mix test` and ensure all tests pass.
  - [x] Run `mix check` and verify 0 warnings, 0 credo/dialyzer issues.

