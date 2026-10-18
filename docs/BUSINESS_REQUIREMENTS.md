# Business Requirements

Confirmed business rules for the Dreams 'N Grace Taxi Management System. The owners confirmed every rule below on 2026-10-18. This file is the source of truth for the schema and all financial calculations: if code disagrees with it, the code is wrong.

## 1. People and roles

| Role | Who | Can do |
| --- | --- | --- |
| Owner | Father and mother (operator and business owners) | Everything: record, approve, edit, reverse transactions; approve discounts; decide terminations |
| Admin | Dan (system IT) | Same record, approve, edit and reverse rights as the owners |
| Driver | Each assigned driver | Read-only access to their own records through the driver portal |

- Only owners can authorize discounts.
- Drivers never see another driver's records.

## 2. Drivers, units and assignments

- One driver is assigned to one unit. The driver may take the unit home.
- A driver may arrange an "extra" (extrador) to cover a shift for rest, a day off or other needs.
- On extrador days the **assigned driver still owes the boundary**. The extra is recorded for reference only.
- Changing an assignment never erases earlier assignments; history is kept with start and end dates.
- A driver's years of service are counted from their hire date.

## 3. Daily boundary (rent)

The boundary is the fixed daily amount a driver owes for using a unit.

| Unit age on the operating date | Daily boundary |
| --- | --- |
| Under 5 years | ₱1,200 |
| 5 years or older (including exactly 5) | ₱1,100 |

- Unit age is counted from the unit's first registration date.
- Rates are stored with effective dates so past records keep the rate that applied at the time.

## 4. Operating days and day discounts

Monday to Saturday are charged the full boundary. Discounts apply on these days:

| Day | Discount |
| --- | --- |
| Sunday | 50% off |
| Red-calendar (regular) holiday | ₱200 off |
| Other holiday | ₱100 off |
| Christmas and New Year, driver with under 5 years of service | 50% off |
| Christmas and New Year, driver with 5 or more years of service | Free (100% off) |

- When a holiday falls on a Sunday, **only the Sunday discount applies**.
- The Sunday rule also wins over the Christmas and New Year rule, so a long-serving driver pays 50% on a Sunday Christmas, not zero.
- A driver with exactly 5 years of service counts as 5 or more years.
- Only one day discount applies per day; discounts never combine.
- The holiday list is kept by the owners. The system should pre-fill the Philippine regular holidays each year, and the owners add or correct dates (for example, special holidays announced late).

## 5. Remittances and partial payments

- Every remittance records the amount, the date, and who received it.
- Partial payments are allowed, as long as the full amount is eventually paid.
- A remittance can settle the current day or an older outstanding balance.
- Payments are never edited or deleted. A mistake is corrected with a reversal entry, so the history stays intact.

## 6. Shorts and penalties

- A "short" is any unpaid balance from a day's boundary.
- A ₱50 penalty applies only when the driver **remits nothing** on an operating day. A partial payment carries no penalty.
- The penalty does not stack: missing several days in a row, or leaving a short unpaid for weeks, still adds a single ₱50 penalty for that short.
- A short must be settled within 3 days, together with the penalty.
- After 3 days unpaid, the system **flags** the driver. Termination is decided by the owners, never by the system.
- If a driver cannot pay in cash, they may settle with collateral (any item). The system records the item's description and its agreed value, and the agreed value counts as payment.

## 7. Payment confirmation

After each remittance the driver can see: the expected rent for the day, the amount remitted, the date, and who received it.

## 8. Driver portal

Each driver can see only their own:

- profile and documents
- current balance and any shorts
- remittance history
- unit maintenance schedule: next oil change (every 2 months) and next registration (yearly)

## 9. Maintenance, parts and expenses

- Maintenance is recorded per unit, with cost and the next due date.
- Oil changes are due every 2 months. Registration is due every year.
- Parts inventory is tracked: purchases add stock, use on a unit removes it.
- Expenses unrelated to the fleet are recorded too (for example, cash used to pay for parcels).

## Worked example

A driver with 2 years of service drives a 3-year-old unit on a Sunday and remits ₱400.

| Item | Amount (₱) |
| --- | --- |
| Boundary for a unit under 5 years | 1,200 |
| Sunday discount (50%) | −600 |
| Amount due | 600 |
| Remitted | 400 |
| Short | 200 |

No penalty applies, because the driver remitted something. If the ₱200 is still unpaid 3 days later, the system flags the driver for the owners.
