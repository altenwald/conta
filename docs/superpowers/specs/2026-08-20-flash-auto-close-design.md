# Design Spec: Flash Auto-Close on Inactivity

## Overview
Flash notices (toast alerts) currently require manual dismissal by clicking. This feature adds auto-dismissal after a 3-second timeout (`duration = 3000ms`), with hover-pause functionality so the flash remains open as long as the user hovers with the cursor (or touches on mobile).

## Requirements
1. **Auto-dismiss timer**: Automatically closes flash notices after 3 seconds (configurable via `duration` attribute, default 3000ms).
2. **Hover pause**: When the mouse cursor enters (`mouseenter`) or touch begins (`touchstart`), the timer is cleared and paused.
3. **Hover resume**: When the cursor leaves (`mouseleave`) or touch ends (`touchend`), the 3-second timer starts again.
4. **Manual dismiss**: Clicking the flash or close button still immediately clears the flash and triggers exit animation.
5. **System error notices**: Connection error toasts (`client-error`, `server-error`) remain persistent (`auto_close={false}`).

## Architecture & Implementation

### 1. JS Hook: `FlashAutoClose`
Located at `apps/conta_web/assets/js/hooks/flash_auto_close.js` and registered in `apps/conta_web/assets/js/hooks/index.js`.
- `mounted()` / `updated()`: reads `data-duration` (default 3000ms), sets timeout.
- Event listeners for `mouseenter`, `mouseleave`, `touchstart`, `touchend`.
- `close()`: triggers `this.el.click()` to execute LiveView JS commands (`lv:clear-flash` + `hide`).
- `destroyed()`: cleans up timer and listeners.

### 2. Component: `<.flash>`
In `apps/conta_web/lib/conta_web/components/core_components.ex`:
- `attr :auto_close, :boolean, default: true`
- `attr :duration, :integer, default: 3000`
- `phx-hook={@auto_close && "FlashAutoClose"}`
- `data-duration={@duration}`

### 3. Layouts: `<.flash_group>`
In `apps/conta_web/lib/conta_web/components/layouts.ex`:
- `client-error` and `server-error` specify `auto_close={false}`.
