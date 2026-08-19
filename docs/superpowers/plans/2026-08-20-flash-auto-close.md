# Implementation Plan: Flash Auto-Close on Inactivity

## Goal
Implement automatic closing of flash notices after 3 seconds of user inactivity with pause-on-hover functionality.

## Tasks

- [x] **Task 1: Create `FlashAutoClose` JS Hook**
  - Create `apps/conta_web/assets/js/hooks/flash_auto_close.js`.
  - Register `FlashAutoClose` in `apps/conta_web/assets/js/hooks/index.js`.

- [x] **Task 2: Update Core Components `<.flash>` and Layouts**
  - In `apps/conta_web/lib/conta_web/components/core_components.ex`, add `:auto_close` and `:duration` attributes and wire up `phx-hook="FlashAutoClose"` and `data-duration={@duration}`.
  - In `apps/conta_web/lib/conta_web/components/layouts.ex`, set `auto_close={false}` on `client-error` and `server-error`.

- [x] **Task 3: Verification & Tests**
  - Run asset build / test suite `mix test`.
  - Verify formatting and clean compiler warnings with `mix compile --warnings-as-errors`.
