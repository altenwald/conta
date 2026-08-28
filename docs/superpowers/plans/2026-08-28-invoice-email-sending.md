# Implementation Plan: Invoice Email Delivery with Swoosh, Same-Client Batching, and CQRS/ES Tracking

This implementation plan details the atomic steps to implement multiple contact emails, company email support, single and same-client batch invoice email delivery with Swoosh, CQRS/ES dispatch tracking, and delivery history.

## Proposed Changes

### Phase 1: Company Email & Contact Multiple Emails (Domain & Schema)
- [x] Create Ecto migration `add_emails_to_directories_contacts` adding `:emails, {:array, :string}, default: []`.
- [x] Update `Conta.Command.SetCompany`, `Conta.Event.CompanySet`, `Conta.Event.InvoiceSet.Company`, `Conta.Aggregate.Company`, and `Conta.Projector.Book.Invoice.Company` to include `email: :string`.
- [x] Update `Conta.Command.SetContact` with `:emails, {:array, :string}, default: []` and email format validation.
- [x] Update `Conta.Event.ContactSet` with `:emails, {:array, :string}, default: []`.
- [x] Update `Conta.Aggregate.Company.Contact` with `:emails, {:array, :string}, default: []`.
- [x] Update `Conta.Projector.Directory.Contact` with `:emails, {:array, :string}, default: []`.
- [x] Update `Conta.Event.InvoiceSet.Client` and `Conta.Projector.Book.Invoice.Client` with `:emails, {:array, :string}, default: []`.
- [x] Add unit tests for `SetCompany`, `SetContact`, and `Conta.Projector.Directory`.

### Phase 2: Invoice Email Sent Tracking (CQRS/ES Domain)
- [x] Create Ecto migration `create_book_invoice_emails` for table `book_invoice_emails`.
- [x] Create `Conta.Command.SendInvoiceEmail` command module (`to: :string`).
- [x] Create `Conta.Event.InvoiceEmailSent` event module (`to: :string`).
- [x] Update `Conta.Aggregate.Company` to execute `SendInvoiceEmail` and apply `InvoiceEmailSent`.
- [x] Create read-model schema `Conta.Projector.Book.InvoiceEmail`.
- [x] Update `Conta.Projector.Book.Invoice` schema to associate `has_many :emails, Conta.Projector.Book.InvoiceEmail, foreign_key: :invoice_id`.
- [x] Update `Conta.Projector.Book` to handle `%InvoiceEmailSent{}` inserting into `book_invoice_emails`.
- [x] Update `Conta.Projector.Rebuild` `:book` schemas list to include `Conta.Projector.Book.InvoiceEmail`.
- [x] Add `Conta.Book.list_invoice_emails/1` and update `Conta.Book.get_invoice!/1` with preload option.
- [x] Add unit tests in `Conta.Aggregate.CompanyTest` and `Conta.Projector.BookTest`.

### Phase 3: Email Dispatching Service with Swoosh
- [x] Implement `Conta.Book.send_invoices_email/3` service helper that:
  - Generates invoice PDF for each invoice in the list via `ContaWeb.InvoiceController.to_pdf/2`.
  - Builds individual Swoosh email with single recipient and all invoice PDF attachments.
  - Calls `Conta.Mailer.deliver/1`.
  - On success, dispatches `SendInvoiceEmail` command for each invoice in the batch.
- [x] Add unit tests for email generation and delivery with `Swoosh.Adapters.Test`.

### Phase 4: Contact Web UI (`ContaWeb.ContactLive`)
- [x] Update `ContaWeb.ContactLive.FormComponent` with multiple email input support (comma/newline separated parsing).
- [x] Update `ContaWeb.ContactLive.Index` to display contact emails.
- [x] Add LiveView tests for contact creation/editing with multiple emails.

### Phase 5: Invoice Email Modal & Web UI (`ContaWeb.InvoiceLive` & `InvoiceHTML`)
- [x] Update `ContaWeb.InvoiceLive.Index`:
  - Checkbox column for invoice selection.
  - Track `selected_invoice_ids` in socket assigns.
  - Batch action bar: enabled only when selected invoices belong to the **same client**, disabled with tooltip when mixed clients.
  - Action button `hero-envelope` "Send by email" on individual rows.
  - Action `:send_email` route and modal rendering.
- [x] Create `ContaWeb.InvoiceLive.SendEmailComponent` modal LiveComponent:
  - Supports single invoice or list of selected invoices for the same client.
  - Displays list of invoices to be attached as PDFs (with number and amount).
  - Checkboxes for each client email (checked by default).
  - Checkbox for company email (unchecked by default).
  - Pre-fills default subject and body.
  - Handles send event: iterates over all checked emails and sends each independently with all invoice PDFs attached.
- [x] Update `ContaWeb.InvoiceController` / `ContaWeb.InvoiceHTML.show`:
  - Load invoice emails history in `ContaWeb.InvoiceController.show/2`.
  - In `invoice_html/show.html.heex`, render a non-printable (`print:hidden` / `:if={!assigns[:embedded]}`) section with:
    - Top action bar (Send by email / Download PDF).
    - Email delivery history table (Date, Time, Destination Email, Subject).
- [x] Add LiveView & Controller tests for email modal, same-client batch sending, and email history rendering.

### Phase 6: Verification & Final Checks
- [x] Run full test suite (`mix test`).
- [x] Run `mix check` (compiler 0 warnings, credo, dialyzer, doctor, sobelow, formatter).
- [x] Verify manual interaction in browser.
