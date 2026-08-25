# Design Spec: Filter Invoices by Client ID in API

- **Date**: 2026-08-26
- **Status**: Approved
- **Scope**: `apps/conta`, `apps/conta_web`

## Overview

Add the capability to filter invoices by client in the JSON API (`ContaWeb.Api.Book.Invoice`). The client can be specified either via a query parameter `client_id` (or `client` / `client_nif`) in `GET /api/v1/books/invoices` or via convenient routes `GET /api/v1/books/clients/:client_id/invoices` and `GET /api/v1/books/contacts/:client_id/invoices`.

## Requirements

1. **Client Identification**:
   - `client_id` can be a Contact UUID (primary key in `directories_contacts`). In this case, `Conta.Directory.get_contact/1` resolves the contact's `nif`.
   - `client_id` can also be a client NIF directly (e.g., `"B11222333"`).
   - Invoices matching the client NIF (or client id in embedded JSON) are returned.

2. **Query & Filtering**:
   - In `Conta.Book`:
     - Add `by_client/2` query filter on `book_invoices.client` JSONB column.
     - Support client filtering in `list_invoices/3`, `list_invoices_by_term_and_year/3`, and `list_invoices_filtered/2`.
   - In `ContaWeb.Api.Book.Invoice`:
     - Support `client_id` (and `client`) parameter in `index/2`.
     - Support pagination (`page`, `page-size`) and `extended=true` with client filtering.
     - Support term/year filtering with client filtering.

3. **Routing**:
   - `GET /api/v1/books/invoices?client_id=...`
   - `GET /api/v1/books/clients/:client_id/invoices`
   - `GET /api/v1/books/contacts/:client_id/invoices`

4. **Testing**:
   - Unit tests for `Conta.Book` client filtering.
   - API controller integration tests in `ContaWeb.Api.Book.InvoiceTest` covering:
     - Authentication (API token).
     - Filtering by contact UUID.
     - Filtering by client NIF.
     - Combining client filter with term/year and pagination.
     - Handling when no invoices match the client.
