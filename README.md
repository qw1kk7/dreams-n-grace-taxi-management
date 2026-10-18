# Dreams 'N Grace Taxi Management System

A centralized taxi fleet management system for Dreams ’N Grace Taxi, designed to streamline driver and vehicle management, daily remittances, financial adjustments, outstanding balances, maintenance records, and business reporting. Built to improve operational efficiency, financial transparency, and accountability through secure, multi-user access.

## Documentation

- [Business requirements](docs/BUSINESS_REQUIREMENTS.md): the confirmed rules for boundary, discounts, penalties and shorts
- [Database schema](docs/DATABASE_SCHEMA.md): tables, views and design rules

## Checking the database schema

```sh
scripts/check-schema.sh
```

Applies `supabase/migrations/` to a temporary local Postgres (15 or newer) and runs the business-rule checks in `supabase/tests/smoke_test.sql`.
