#!/usr/bin/env bash
# Applies the Supabase migrations to a throwaway local Postgres and runs the
# business-rule smoke test. Needs Postgres 15+ binaries (initdb, pg_ctl, psql).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bindir="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
export PATH="$bindir:$PATH"

tmp="$(mktemp -d)"
trap 'pg_ctl -D "$tmp/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

initdb -D "$tmp/data" -U postgres --auth=trust >/dev/null
pg_ctl -D "$tmp/data" -o "-k $tmp -c listen_addresses=''" -l "$tmp/log" start >/dev/null

run() { psql -h "$tmp" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

run -f "$root/supabase/tests/auth_stub.sql"
for f in "$root"/supabase/migrations/*.sql; do
  echo "applying $(basename "$f")"
  run -f "$f"
done
run -f "$root/supabase/tests/smoke_test.sql"
