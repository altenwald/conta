# Design Specification: Invoice Credit Notes (Devoluciones / Creditfacturen)

**Date**: 2026-08-26  
**Status**: Draft / Pending Approval  

---

## 1. Overview

In accounting (both under Spanish AEAT regulations and Dutch *Belastingdienst* rules), issued invoices are immutable once emitted. When a refund, return, or invoice correction occurs, the business must emit a **Credit Note** (*Factura Rectificativa* in Spain, *Creditfactuur* in the Netherlands).

This feature allows users to:
1. Automatically generate a **Credit Note** from an existing issued invoice with a single click.
2. Maintain a separate sequential numbering series for credit notes, configured in `config/config.exs` with default prefix `"CN"` (e.g. `CN-2026-00023`).
3. Explicitly link the credit note to its original invoice (`origin_invoice_number`, `origin_invoice_date`, and `origin_invoice_id`).
4. Display a contextual action button in the Invoices UI (`ContaWeb.InvoiceLive.Index`):
   - If no credit note exists for the invoice: button to **Create Credit Note** (devolución).
   - If a credit note already exists: button to **View Credit Note**.
   - If the item itself is a credit note: visually identify it as a Credit Note and provide a link back to the original invoice.
5. Render the PDF with the appropriate credit note header, prefix, and reference to the original invoice.

---

## 2. Configuration

In `config/config.exs`:

```elixir
config :conta,
  credit_note_prefix: "CN"
```

The prefix is accessible via `Application.get_env(:conta, :credit_note_prefix, "CN")`.

---

## 3. Domain Model (`apps/conta`)

### 3.1 Commands & Events

#### `Conta.Command.SetInvoice`
Add the following optional fields:
- `is_credit_note`: `:boolean`, defaults to `false`.
- `origin_invoice_number`: `:string`, optional.
- `origin_invoice_date`: `:date`, optional.
- `origin_invoice_id`: `:binary_id`, optional.

#### `Conta.Event.InvoiceSet`
Include:
- `is_credit_note`: `:boolean`
- `origin_invoice_number`: `:string`
- `origin_invoice_date`: `:date`
- `origin_invoice_id`: `:binary_id`

### 3.2 Aggregate: `Conta.Aggregate.Company`
- Maintains `credit_note_numbers: %{pos_integer() => MapSet.t(pos_integer())}` alongside `invoice_numbers`.
- Serializer encodes/decodes `credit_note_numbers` in aggregate snapshots.
- When executing `SetInvoice` with `is_credit_note: true` and `invoice_number: nil`:
  - Assigns `credit_note_number = (Enum.max(company.credit_note_numbers[year] || MapSet.new()) || 0) + 1`.
  - Dispatches `InvoiceSet` with `invoice_number: credit_note_number, is_credit_note: true, ...`.
- On `apply(%InvoiceSet{is_credit_note: true})`:
  - Records the number in `company.credit_note_numbers[year]`.

### 3.3 Database & Projector: `Conta.Projector.Book`
- **Migration**: Add columns to `book_invoices`:
  - `is_credit_note: :boolean, default: false, null: false`
  - `origin_invoice_number: :string`
  - `origin_invoice_date: :date`
  - `origin_invoice_id: :binary_id`
  - Index on `origin_invoice_number` and `origin_invoice_id`.
- **Projection**:
  - If `invoice.is_credit_note`:
    `invoice_number = "#{prefix}-#{year}-#{String.pad_leading(to_string(number), 5, "0")}"` (e.g. `CN-2026-00001`).
  - If standard invoice:
    `invoice_number = "#{year}-#{String.pad_leading(to_string(number), 5, "0")}"` (e.g. `2026-00001`).

### 3.4 Context Functions (`Conta.Book`)
- `get_credit_note_by_origin_invoice_number(origin_number)`
- `get_credit_note_by_origin_invoice_id(origin_id)`
- `create_credit_note_from_invoice(invoice, overrides \\ %{})`:
  - Prepares `SetInvoice` with `is_credit_note: true`, `origin_invoice_number: invoice.invoice_number`, `origin_invoice_date: invoice.invoice_date`, `origin_invoice_id: invoice.id`.
  - Replicates client, company, payment method, and invoice details.
  - Sets `action: :insert`, `invoice_date: Date.utc_today()`.
  - Dispatches to Commanded.

---

## 4. Web Interface (`apps/conta_web`)

### 4.1 Invoices LiveView (`ContaWeb.InvoiceLive.Index`)
- Stream items or row helpers check if the invoice has an associated credit note.
- **Action Buttons in Table**:
  - If `invoice.is_credit_note`:
    - Shows badge `<span class="badge badge-warning">Credit Note</span>`.
    - Link to original invoice if present.
  - If standard invoice:
    - If associated credit note exists:
      - Action icon `hero-arrow-uturn-left` with tooltip *"View Credit Note"*, navigating to the credit note.
    - If no credit note exists:
      - Action icon `hero-arrow-uturn-left` with tooltip *"Create Credit Note"*, prompting confirmation *"Create credit note for invoice #{invoice_number}?"* and triggering `create_credit_note`.

### 4.2 PDF Generation & Template (`ContaWeb.InvoiceController` / `Press`)
- If `invoice.is_credit_note`:
  - Document Title / Header: *"CREDIT NOTE"* / *"CREDITFACTUUR"* / *"FACTURA RECTIFICATIVA"*.
  - Reference box: *"Corrects Invoice: #{origin_invoice_number} (Dated: #{origin_invoice_date})"*.

### 4.3 API Endpoints (`ContaWeb.Api.Book.Invoice`)
- Serializer `InvoiceJSON` outputs `is_credit_note`, `origin_invoice_number`, `origin_invoice_date`, `origin_invoice_id`.
- `POST /api/v1/books/invoices/:id/credit_note`: Generates a credit note for invoice `:id`.

---

## 5. Testing Plan
1. **Unit Tests (`apps/conta/test/conta/aggregate/company_test.exs`)**:
   - Sequential credit note numbering per year (`CN-2026-00001`, `CN-2026-00002`).
   - Snapshot serialization and restoration with `credit_note_numbers`.
2. **Context Tests (`apps/conta/test/conta/book_test.exs`)**:
   - `create_credit_note_from_invoice/2` creates linked credit note with `is_credit_note: true`.
   - `get_credit_note_by_origin_invoice_id/1` lookup.
3. **LiveView Tests (`apps/conta_web/test/conta_web/live/invoice_live_test.exs`)**:
   - Button "Create Credit Note" creates the credit note and updates stream.
   - Button turns into "View Credit Note" when already refunded.
4. **Controller & PDF Tests (`apps/conta_web/test/conta_web/controllers/invoice_controller_test.exs`)**:
   - Credit note PDF includes credit note title and original invoice reference.
5. **API Tests (`apps/conta_web/test/conta_web/api/book/invoice_test.exs`)**:
   - Create credit note via API and retrieve JSON representation.
