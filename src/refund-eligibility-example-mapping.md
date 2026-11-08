# Example Mapping: Refund Eligibility Check

Source policy: `REFUNDS.md`. Session date: 2026-11-08.

## Story (gelb)

As an AI assistant working through the MCP server,
I want to check whether a specific customer's order qualifies for a refund,
so that I can give a clear verdict with the reason that decided it and the refundable amount.

## Rules (blau)

### Regel 0: Evaluation order
Checks are grouped into categories evaluated A → B → C → D. Inside each category the checks
run in a fixed order (A1 … D1, matching REFUNDS.md rules 1–10). The first failing check stops
evaluation; only its reason is reported.

### Regel 1: Category A — Identification
- **A1 Identification required** — customer id and order id must both be non-null.
  Only `null` counts as missing; an empty/blank string proceeds to the existence checks.
  Reason: "Customer and order are required."
- **A2 Customer must exist** — Reason: "Customer was not found."
- **A3 Order must exist** — Reason: "Order was not found."
- **A4 Order must belong to customer** — `order.customerId == customer.id`.
  Reason: "Order does not belong to the selected customer."

### Regel 2: Category B — Customer standing
- **B1 Customer must be active** — `status` equals exactly `active` (case-sensitive).
  Reason: "Customer is not active."
- **B2 Customer must not be blocked** — `risk_level` is not exactly `blocked`. `normal`, `watch`,
  unknown values and `null` all pass. Watch-list customers are plain eligible in this story.
  Reason: "Customer risk level blocks this refund."

### Regel 3: Category C — Order state
- **C1 No existing refund** — `refunded_at` is null. Only `refunded_at` drives this check;
  `status` is not consulted. Reason: "Order has already been refunded."
- **C2 Order must be delivered** — `status` equals exactly `delivered`.
  Reason: "Order must be delivered before a refund can be considered."
- **C3 Delivery date must be known** — `delivered_at` is not null.
  Reason: "Order has no recorded delivery date."

### Regel 4: Category D — Refund window
- **D1 Within refund window** — `delivered_at >= now − 30 days` (30 × 24h, compared to the instant).
  Boundary is inclusive. Window is fixed at 30 days. A future `delivered_at` passes.
  Reason: "Order was delivered outside the refund window."

### Regel 5: Result shape
- Result contains: verdict (eligible / ineligible), reason text (exact strings above).
- Eligible: reason "Order was delivered within the refund window and has no previous refund.",
  amount = full `total_minor` in the order's original `currency` (no conversion; 0 is allowed).
- Ineligible: no amount and no currency.

## Examples (gruen)

**Fixture.** now = `2026-11-08T12:00:00Z` → cutoff = `2026-10-09T12:00:00Z`

| Customer | status | risk_level |
|---|---|---|
| `C1` | active | normal |
| `C2` | active | watch |
| `C3` | active | blocked |
| `C4` | suspended | normal |
| `C5` | suspended | blocked |

Base order `O1`: customer `C1`, status `delivered`, delivered_at `2026-11-01T10:00:00Z`,
total_minor `4999`, currency `GBP`, refunded_at `null`. Each example varies only what it names.

### Zu Regel 0: Evaluation order
- C5 (inactive AND blocked) with an otherwise valid order → "Customer is not active."
- C1, O1 with refunded_at set AND status `pending` → "Order has already been refunded."
- customer `C99` (unknown), order `O-unknown` → "Customer was not found."
- C3 (blocked), order delivered `2026-08-01T10:00:00Z` (outside window) → "Customer risk level blocks this refund."

### Zu Regel 1: Category A — Identification
- A1: customer `null`, order O1 → "Customer and order are required."
- A1: customer C1, order `null` → "Customer and order are required."
- A1/A2: customer `""`, order O1 → "Customer was not found."
- A2: customer `C99`, order O1 → "Customer was not found."
- A3: customer C1, order `O99` → "Order was not found."
- A4: customer C1, order O1 placed by C2 → "Order does not belong to the selected customer."

### Zu Regel 2: Category B — Customer standing
- B1: C4 (suspended) → "Customer is not active."
- B1: customer status `Active` → "Customer is not active."
- B2: C3 (blocked) → "Customer risk level blocks this refund."
- B2: C2 (watch) → Eligible, 4999 GBP
- B2: risk_level `high` / `null` → Eligible, 4999 GBP

### Zu Regel 3: Category C — Order state
- C1: refunded_at `2026-11-02T09:00:00Z` → "Order has already been refunded."
- C2: status `in_transit` → "Order must be delivered before a refund can be considered."
- C2: status `refunded`, refunded_at `null` → "Order must be delivered before a refund can be considered."
- C3: status `delivered`, delivered_at `null` → "Order has no recorded delivery date."

### Zu Regel 4: Category D — Refund window
- delivered_at `2026-10-09T12:00:00Z` (exactly at cutoff) → Eligible
- delivered_at `2026-10-09T11:59:59Z` (1 s before cutoff) → "Order was delivered outside the refund window."
- delivered_at `2026-08-01T10:00:00Z` → "Order was delivered outside the refund window."
- delivered_at `2026-11-09T12:00:00Z` (future) → Eligible

### Zu Regel 5: Result shape
- O1 → Eligible, "Order was delivered within the refund window and has no previous refund.", 4999 GBP
- O1 with total_minor `0` → Eligible, 0 GBP
- O1 with currency `EUR`, total_minor `12000` → Eligible, 12000 EUR
- Any ineligible result → verdict + reason, no amount, no currency

## Questions (rot)

No open questions - all ambiguities were resolved.

## New Stories (ausgelagert)

- Issue an approved refund payment
- Flag watch-list refunds for manual review
- Configurable refund window (by region / product / promotion)
