# Design Spec: Invoice PDF Download via Authenticated API

- **Date**: 2026-08-26
- **Status**: Approved
- **Scope**: `apps/conta`, `apps/conta_web`

## Overview

Allow downloading an invoice in PDF format via an authenticated API request (`Bearer` token authentication under `/api/v1`).

## Requirements

1. **Routing & Authentication**:
   - `GET /api/v1/books/invoices/:id/download`
   - Protected by `pipeline :api` (`Bearer` token header).
   - Content-Type: `application/pdf` with header `Content-Disposition: attachment; filename=<invoice_number>.pdf`.

2. **Error Handling**:
   - Return 401 Unauthorized if no valid API token is provided.
   - Return 404 Not Found (`%{"errors" => %{"id" => "invoice not found"}}`) if the invoice doesn't exist.
   - Return 200 OK with binary PDF when the invoice exists and template renders.

3. **Implementation**:
   - In `ContaWeb.Api.Book.Invoice`:
     - Add `download/2` action.
     - Leverage `Conta.Book.get_invoice/1`, `Conta.Book.get_template_by_name/2` (or `get_template_by_name!/2`), and `ContaWeb.InvoiceController.to_pdf/2`.
   - In `ContaWeb.Router`:
     - Add `get "/invoices/:id/download", Invoice, :download` under `/api/v1/books/`.

4. **Testing**:
   - Integration tests in `apps/conta_web/test/conta_web/api/book/invoice_test.exs` verifying:
     - 401 on unauthenticated requests.
     - 404 when invoice ID is not found.
     - 200 with valid PDF binary and headers when authenticated and invoice exists.
