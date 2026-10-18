# Database Schema

The schema lives in `supabase/migrations/`. The business rules it implements are in [BUSINESS_REQUIREMENTS.md](BUSINESS_REQUIREMENTS.md). Run `scripts/check-schema.sh` to apply the migrations to a throwaway Postgres and check the rules.

## Tables

| Area | Table | Holds |
| --- | --- | --- |
| Business | `businesses` | One row per taxi business (ready for more than one later) |
| | `profiles` | Signed-in users and their role: `owner`, `admin` or `driver` |
| | `business_settings` | The tunable numbers: discounts, ₱50 penalty, 3-day grace, maintenance intervals |
| Fleet | `drivers` | Driver profiles; `hire_date` drives years of service |
| | `driver_documents` | Files in Supabase Storage (license, contract, clearances) |
| | `vehicles` | Units; `first_registered_on` drives unit age |
| | `driver_vehicle_assignments` | Assignment history; the database blocks two drivers on one unit at the same time |
| Rates | `boundary_rates` | Daily boundary by unit age, with effective dates |
| | `holidays` | `regular` (red-calendar), `special`, `christmas_new_year` |
| Money | `daily_operations` | One row per unit per day: assigned driver, extrador name, amount due |
| | `adjustments` | Discounts (need an owner's approval), penalties, other; append-only |
| | `remittances` | Cash or collateral payments, who received them; append-only |
| Maintenance | `maintenance_records` | Oil changes, registration, repairs, with next due date |
| | `parts`, `part_movements` | Parts inventory; stock = sum of movements |
| | `expenses` | Every cash outflow, including non-fleet ones such as parcels |
| Audit | `audit_logs` | Who changed what, written automatically by triggers |

## Derived views and functions

| Name | What it gives |
| --- | --- |
| `expected_boundary(vehicle, driver, date)` | Base boundary, day discount and reason, applying the unit-age rate and the Sunday, holiday and Christmas rules |
| `driver_ledger` | Every money movement per driver: amounts owed are positive, payments negative |
| `driver_balances` | Each driver's current balance |
| `driver_short_status` | Drivers who owe money and the first day of their current unpaid stretch |
| `flagged_drivers(as_of)` | Drivers unpaid for longer than the grace period; owners decide what happens next |
| `apply_no_remit_penalties(business, date)` | Adds the ₱50 penalty for a day with no remittance, without stacking; run at day's end |

## Design rules

- Balances are never stored. They are always calculated from `driver_ledger`, so they cannot drift from the records.
- Payments and adjustments are never edited or deleted. A correction is a new row whose `reverses_id` points at the original.
- Every business-owned table has `business_id`, and row level security keeps each business's data separate.
- Owners and the admin can read and record everything in their business. Drivers can read only their own records and their current unit's maintenance.

## Going live

Done on 2026-10-18: both migrations applied to the online project, the business and boundary rates (₱1,200 under 5 years, ₱1,100 from 5 years) created, and logins linked for the two owners and the admin.

Still open: the year's holidays. The plan is to pre-fill Philippine regular holidays automatically and let the owners correct them. Until then, holidays can only be added in the SQL editor, and days without a holiday row are charged the normal rate.
