# Dreams 'N Grace Taxi Management System

A centralized taxi fleet management system for Dreams ’N Grace Taxi, designed to streamline driver and vehicle management, daily remittances, financial adjustments, outstanding balances, maintenance records, and business reporting. Built to improve operational efficiency, financial transparency, and accountability through secure, multi-user access.

## Documentation

- [Setup](docs/SETUP.md): run it locally, or put it online with Supabase, and manage logins
- [Business requirements](docs/BUSINESS_REQUIREMENTS.md): the confirmed rules for boundary, discounts, penalties and shorts
- [Database schema](docs/DATABASE_SCHEMA.md): tables, views and design rules

## Status

Phase 1 in progress, and live for the family business at https://dreams-n-grace-taxi-management.vercel.app/ (Supabase project set up, both migrations applied, logins for the two owners and the admin).

Working now: owner and admin login, drivers, units (with the daily boundary each one pays), driver-to-unit assignments with history, and daily remittances: each day's boundary with Sunday and holiday discounts, cash or collateral payments, the ₱50 no-remit penalty, outstanding balances and the 3-day flag.

Next: auto-loading Philippine holidays, reports, then maintenance, parts and expenses, and the driver portal. The owners enter the real units and drivers through the app.

## Checking the database schema

```sh
scripts/check-schema.sh
```

Applies `supabase/migrations/` to a temporary local Postgres (15 or newer) and runs the business-rule checks in `supabase/tests/smoke_test.sql`.
