-- Initial schema for the Dreams 'N Grace Taxi Management System.
-- Business rules: docs/BUSINESS_REQUIREMENTS.md. Table guide: docs/DATABASE_SCHEMA.md.
--
-- Conventions
--   * Every business-owned row carries business_id, so more businesses can be added later.
--   * Money is numeric(10,2) in pesos.
--   * Remittances and adjustments are append-only: mistakes are fixed with a reversal row.
--   * Balances are derived from the ledger view, never stored.

create extension if not exists btree_gist;

-- ---------------------------------------------------------------------------
-- Businesses, users and settings
-- ---------------------------------------------------------------------------

create table businesses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now()
);

create type user_role as enum ('owner', 'admin', 'driver');

-- One row per signed-in user (Supabase auth.users).
create table profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  business_id  uuid not null references businesses (id),
  role         user_role not null,
  full_name    text not null,
  created_at   timestamptz not null default now()
);

-- Tunable numbers from the confirmed rules, one row per business.
create table business_settings (
  business_id                 uuid primary key references businesses (id) on delete cascade,
  sunday_discount_pct         numeric(5,2)  not null default 50,
  regular_holiday_discount    numeric(10,2) not null default 200,
  special_holiday_discount    numeric(10,2) not null default 100,
  christmas_junior_pct        numeric(5,2)  not null default 50,   -- drivers under senior_driver_years
  christmas_senior_pct        numeric(5,2)  not null default 100,  -- drivers at or over senior_driver_years
  senior_driver_years         int           not null default 5,
  no_remit_penalty            numeric(10,2) not null default 50,
  short_grace_days            int           not null default 3,
  oil_change_interval_months  int           not null default 2,
  registration_interval_months int          not null default 12
);

-- ---------------------------------------------------------------------------
-- Drivers, vehicles and assignments
-- ---------------------------------------------------------------------------

create type driver_status as enum ('active', 'inactive', 'terminated');

create table drivers (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references businesses (id),
  profile_id      uuid unique references profiles (id),  -- set once the driver has a portal login
  full_name       text not null,
  contact_number  text,
  address         text,
  license_number  text,
  license_expires_on date,
  hire_date       date not null,                          -- years of service count from here
  status          driver_status not null default 'active',
  notes           text,
  created_at      timestamptz not null default now()
);

create table driver_documents (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references businesses (id),
  driver_id    uuid not null references drivers (id) on delete cascade,
  doc_type     text not null,           -- e.g. license, NBI clearance, contract
  storage_path text not null,           -- Supabase Storage object path
  expires_on   date,
  uploaded_at  timestamptz not null default now()
);

create type vehicle_status as enum ('active', 'in_maintenance', 'retired');

create table vehicles (
  id                   uuid primary key default gen_random_uuid(),
  business_id          uuid not null references businesses (id),
  plate_number         text not null,
  unit_number          text,
  make                 text,
  model                text,
  first_registered_on  date not null,   -- unit age counts from here
  registration_expires_on date,
  status               vehicle_status not null default 'active',
  created_at           timestamptz not null default now(),
  unique (business_id, plate_number)
);

-- One driver per unit and one unit per driver at any time; history is never overwritten.
create table driver_vehicle_assignments (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references businesses (id),
  driver_id    uuid not null references drivers (id),
  vehicle_id   uuid not null references vehicles (id),
  start_date   date not null,
  end_date     date,                    -- null = current assignment
  check (end_date is null or end_date >= start_date),
  exclude using gist (vehicle_id with =, daterange(start_date, end_date, '[]') with &&),
  exclude using gist (driver_id with =, daterange(start_date, end_date, '[]') with &&)
);

-- ---------------------------------------------------------------------------
-- Rates and holidays
-- ---------------------------------------------------------------------------

-- Boundary by unit age. A unit qualifies when min_unit_age_years <= age < max_unit_age_years.
create table boundary_rates (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references businesses (id),
  min_unit_age_years  int not null,
  max_unit_age_years  int,                -- null = no upper bound
  daily_amount        numeric(10,2) not null check (daily_amount >= 0),
  effective_from      date not null,
  effective_to        date,               -- null = still in force
  check (max_unit_age_years is null or max_unit_age_years > min_unit_age_years)
);

-- regular = red-calendar (₱200 off), special = other holidays (₱100 off),
-- christmas_new_year = 50% off / free depending on years of service.
create type holiday_kind as enum ('regular', 'special', 'christmas_new_year');

create table holidays (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references businesses (id),
  holiday_date  date not null,
  name          text not null,
  kind          holiday_kind not null,
  source        text not null default 'manual' check (source in ('manual', 'auto')),
  unique (business_id, holiday_date)
);

-- ---------------------------------------------------------------------------
-- Daily operations, adjustments and remittances
-- ---------------------------------------------------------------------------

-- One row per unit per operating day. The assigned driver owes the amount,
-- even when an extra (extrador) drove that day.
create table daily_operations (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references businesses (id),
  operation_date      date not null,
  vehicle_id          uuid not null references vehicles (id),
  driver_id           uuid not null references drivers (id),
  extra_driver_name   text,                         -- extrador, for reference only
  boundary_rate_id    uuid references boundary_rates (id),
  base_amount         numeric(10,2) not null check (base_amount >= 0),
  day_discount        numeric(10,2) not null default 0 check (day_discount >= 0),
  day_discount_reason text,                         -- sunday, regular_holiday, special_holiday, christmas_new_year
  amount_due          numeric(10,2) generated always as (greatest(base_amount - day_discount, 0)) stored,
  created_by          uuid references profiles (id),
  created_at          timestamptz not null default now(),
  unique (vehicle_id, operation_date)
);

create type adjustment_kind as enum ('discount', 'penalty', 'other');

-- Positive amount increases what the driver owes, negative decreases it.
create table adjustments (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references businesses (id),
  driver_id           uuid not null references drivers (id),
  daily_operation_id  uuid references daily_operations (id),
  kind                adjustment_kind not null,
  amount              numeric(10,2) not null check (amount <> 0),
  reason              text not null,
  effective_date      date not null default current_date,  -- the day it counts on the ledger
  approved_by         uuid references profiles (id),   -- required for discounts
  reverses_id         uuid unique references adjustments (id),
  created_by          uuid references profiles (id),
  created_at          timestamptz not null default now(),
  check (kind <> 'discount' or approved_by is not null)
);

create type payment_method as enum ('cash', 'collateral');

create table remittances (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references businesses (id),
  driver_id           uuid not null references drivers (id),
  daily_operation_id  uuid references daily_operations (id),  -- null = settles an older balance
  amount              numeric(10,2) not null,                  -- negative only on a reversal row
  method              payment_method not null default 'cash',
  collateral_item     text,
  collateral_returned_at timestamptz,
  received_by         uuid not null references profiles (id),
  received_at         timestamptz not null default now(),
  note                text,
  reverses_id         uuid unique references remittances (id),
  check ((reverses_id is null and amount > 0) or (reverses_id is not null and amount < 0)),
  -- for collateral, amount is the agreed value of the item
  check (method <> 'collateral' or collateral_item is not null)
);

-- ---------------------------------------------------------------------------
-- Maintenance, parts and expenses
-- ---------------------------------------------------------------------------

create type maintenance_kind as enum ('oil_change', 'registration', 'repair', 'inspection', 'other');

create table maintenance_records (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references businesses (id),
  vehicle_id    uuid not null references vehicles (id),
  kind          maintenance_kind not null,
  performed_on  date not null,
  description   text,
  labor_cost    numeric(10,2) not null default 0,
  odometer_km   int,
  next_due_on   date,
  recorded_by   uuid references profiles (id),
  created_at    timestamptz not null default now()
);

create table parts (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references businesses (id),
  name         text not null,
  unit         text not null default 'pc',
  reorder_level numeric(10,2),
  unique (business_id, name)
);

-- Stock on hand = sum(quantity). Purchases are positive, use on a unit is negative.
create table part_movements (
  id                     uuid primary key default gen_random_uuid(),
  business_id            uuid not null references businesses (id),
  part_id                uuid not null references parts (id),
  quantity               numeric(10,2) not null check (quantity <> 0),
  unit_cost              numeric(10,2),
  vehicle_id             uuid references vehicles (id),
  maintenance_record_id  uuid references maintenance_records (id),
  moved_on               date not null default current_date,
  note                   text,
  recorded_by            uuid references profiles (id),
  created_at             timestamptz not null default now()
);

create type expense_category as enum ('maintenance', 'parts', 'registration', 'fuel', 'parcel', 'other');

-- Every cash outflow, fleet-related or not (e.g. cash used to pay for parcels).
create table expenses (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references businesses (id),
  expense_date  date not null,
  category      expense_category not null,
  amount        numeric(10,2) not null check (amount > 0),
  vehicle_id    uuid references vehicles (id),
  description   text not null,
  recorded_by   uuid references profiles (id),
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

create table audit_logs (
  id           bigint generated always as identity primary key,
  business_id  uuid,
  table_name   text not null,
  record_id    uuid,
  action       text not null,
  old_data     jsonb,
  new_data     jsonb,
  actor_id     uuid,
  at           timestamptz not null default now()
);

create function log_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  row_data jsonb := to_jsonb(coalesce(new, old));
begin
  insert into audit_logs (business_id, table_name, record_id, action, old_data, new_data, actor_id)
  values (
    (row_data ->> 'business_id')::uuid,
    tg_table_name,
    (row_data ->> 'id')::uuid,
    tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    auth.uid()
  );
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'drivers', 'vehicles', 'driver_vehicle_assignments', 'boundary_rates', 'holidays',
    'daily_operations', 'adjustments', 'remittances', 'maintenance_records',
    'part_movements', 'expenses', 'business_settings', 'profiles'
  ] loop
    execute format(
      'create trigger audit_%1$s after insert or update or delete on %1$I
         for each row execute function log_audit()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Business logic
-- ---------------------------------------------------------------------------

-- Expected boundary for a unit, driver and date, applying the confirmed rules:
-- rate by unit age; one day discount at most; Sunday wins over any holiday.
create function expected_boundary(p_vehicle_id uuid, p_driver_id uuid, p_date date)
returns table (boundary_rate_id uuid, base_amount numeric, day_discount numeric, day_discount_reason text)
language plpgsql stable set search_path = public as $$
declare
  v_business  uuid;
  v_unit_age  int;
  v_service   int;
  v_settings  business_settings%rowtype;
  v_holiday   holiday_kind;
begin
  select v.business_id, extract(year from age(p_date, v.first_registered_on))::int
    into v_business, v_unit_age
    from vehicles v where v.id = p_vehicle_id;
  if v_business is null then
    raise exception 'vehicle % not found', p_vehicle_id;
  end if;

  select extract(year from age(p_date, d.hire_date))::int into v_service
    from drivers d where d.id = p_driver_id;
  select * into v_settings from business_settings s where s.business_id = v_business;
  if not found then
    raise exception 'business_settings missing for business %', v_business;
  end if;

  select r.id, r.daily_amount into boundary_rate_id, base_amount
    from boundary_rates r
   where r.business_id = v_business
     and v_unit_age >= r.min_unit_age_years
     and (r.max_unit_age_years is null or v_unit_age < r.max_unit_age_years)
     and p_date >= r.effective_from
     and (r.effective_to is null or p_date <= r.effective_to)
   order by r.effective_from desc
   limit 1;
  if base_amount is null then
    raise exception 'no boundary rate for unit age % on %', v_unit_age, p_date;
  end if;

  select h.kind into v_holiday
    from holidays h where h.business_id = v_business and h.holiday_date = p_date;

  day_discount := 0;
  if extract(isodow from p_date) = 7 then
    day_discount := round(base_amount * v_settings.sunday_discount_pct / 100, 2);
    day_discount_reason := 'sunday';
  elsif v_holiday = 'christmas_new_year' then
    day_discount := round(base_amount * (case when v_service >= v_settings.senior_driver_years
                                              then v_settings.christmas_senior_pct
                                              else v_settings.christmas_junior_pct end) / 100, 2);
    day_discount_reason := 'christmas_new_year';
  elsif v_holiday = 'regular' then
    day_discount := v_settings.regular_holiday_discount;
    day_discount_reason := 'regular_holiday';
  elsif v_holiday = 'special' then
    day_discount := v_settings.special_holiday_discount;
    day_discount_reason := 'special_holiday';
  end if;
  day_discount := least(day_discount, base_amount);
  return next;
end $$;

-- Every money movement per driver: positive = owed, negative = paid.
create view driver_ledger with (security_invoker = true) as
  select o.business_id, o.driver_id, o.operation_date as entry_date, 'boundary'::text as entry_type,
         o.id as source_id, o.amount_due as amount, o.day_discount_reason as note
    from daily_operations o
  union all
  select a.business_id, a.driver_id, a.effective_date, a.kind::text, a.id, a.amount, a.reason
    from adjustments a
  union all
  select r.business_id, r.driver_id, r.received_at::date,
         case when r.reverses_id is null then 'payment' else 'payment_reversal' end,
         r.id, -r.amount, r.note
    from remittances r;

create view driver_balances with (security_invoker = true) as
  select d.business_id, d.id as driver_id, d.full_name,
         coalesce(sum(l.amount), 0) as balance
    from drivers d
    left join driver_ledger l on l.driver_id = d.id
   group by d.business_id, d.id, d.full_name;

-- Drivers who owe money, and the first day of their current unpaid stretch
-- (the day after their running balance was last cleared).
create view driver_short_status with (security_invoker = true) as
  with daily as (
    select driver_id, entry_date, sum(amount) as amount
      from driver_ledger group by driver_id, entry_date
  ), running as (
    select driver_id, entry_date,
           sum(amount) over (partition by driver_id order by entry_date) as balance
      from daily
  ), last_clear as (
    select driver_id, max(entry_date) as cleared_on
      from running where balance <= 0 group by driver_id
  )
  select b.business_id, b.driver_id, b.full_name, b.balance,
         (select min(r.entry_date) from running r
           where r.driver_id = b.driver_id
             and r.entry_date > coalesce(lc.cleared_on, '-infinity'::date)) as unpaid_since
    from driver_balances b
    left join last_clear lc on lc.driver_id = b.driver_id
   where b.balance > 0;

-- Drivers whose unpaid stretch is older than the grace period (3 days).
-- The system only flags; termination is the owners' decision.
create function flagged_drivers(p_as_of date default current_date)
returns setof driver_short_status
language sql stable set search_path = public as $$
  select s.*
    from driver_short_status s
    join business_settings bs on bs.business_id = s.business_id
   where s.unpaid_since < p_as_of - bs.short_grace_days
$$;

-- Adds the ₱50 penalty for an operating day with no remittance at all,
-- unless the driver already carries an unpaid penalty (penalties do not stack).
-- Run at the end of each operating day. Returns the number of penalties added.
create function apply_no_remit_penalties(p_business_id uuid, p_date date)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_penalty    numeric;
  v_count      int := 0;
  v_balance    numeric;
  v_last_clear date;
  r record;
begin
  select no_remit_penalty into v_penalty from business_settings where business_id = p_business_id;

  for r in
    select o.id, o.driver_id
      from daily_operations o
     where o.business_id = p_business_id
       and o.operation_date = p_date
       and o.amount_due > 0
       and not exists (select 1 from remittances x
                        where x.driver_id = o.driver_id
                          and x.received_at::date = p_date
                          and x.reverses_id is null)
  loop
    -- Skip when the driver is still in an unpaid stretch that already has a penalty:
    -- balance before today is positive and a penalty was added after the last day
    -- the running balance was cleared.
    select coalesce(sum(l.amount), 0) into v_balance
      from driver_ledger l where l.driver_id = r.driver_id and l.entry_date < p_date;

    select max(entry_date) into v_last_clear
      from (select entry_date, sum(sum(amount)) over (order by entry_date) as running
              from driver_ledger
             where driver_id = r.driver_id and entry_date < p_date
             group by entry_date) t
     where running <= 0;

    if v_balance > 0 and exists (
      select 1 from adjustments a
       where a.driver_id = r.driver_id and a.kind = 'penalty' and a.reverses_id is null
         and not exists (select 1 from adjustments rev where rev.reverses_id = a.id)
         and a.effective_date > coalesce(v_last_clear, '-infinity'::date)
    ) then
      continue;
    end if;
    insert into adjustments (business_id, driver_id, daily_operation_id, kind, amount, reason, effective_date)
    values (p_business_id, r.driver_id, r.id, 'penalty', v_penalty, 'No remittance on ' || p_date, p_date);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

create function current_business_id() returns uuid
language sql stable security definer set search_path = public as $$
  select business_id from profiles where id = auth.uid()
$$;

create function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('owner', 'admin'))
$$;

create function current_driver_id() returns uuid
language sql stable security definer set search_path = public as $$
  select d.id from drivers d where d.profile_id = auth.uid()
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'businesses', 'profiles', 'business_settings', 'drivers', 'driver_documents', 'vehicles',
    'driver_vehicle_assignments', 'boundary_rates', 'holidays', 'daily_operations',
    'adjustments', 'remittances', 'maintenance_records', 'parts', 'part_movements',
    'expenses', 'audit_logs'
  ] loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Staff (owners and admin) read everything in their business.
do $$
declare t text;
begin
  foreach t in array array[
    'business_settings', 'drivers', 'driver_documents', 'vehicles', 'driver_vehicle_assignments',
    'boundary_rates', 'holidays', 'daily_operations', 'adjustments', 'remittances',
    'maintenance_records', 'parts', 'part_movements', 'expenses', 'audit_logs'
  ] loop
    execute format(
      'create policy staff_read on %I for select to authenticated
         using (is_staff() and business_id = current_business_id())', t);
  end loop;
end $$;

-- Staff insert and update most tables in their business.
do $$
declare t text;
begin
  foreach t in array array[
    'business_settings', 'drivers', 'driver_documents', 'vehicles', 'driver_vehicle_assignments',
    'boundary_rates', 'holidays', 'daily_operations', 'maintenance_records', 'parts',
    'part_movements', 'expenses'
  ] loop
    execute format(
      'create policy staff_insert on %I for insert to authenticated
         with check (is_staff() and business_id = current_business_id())', t);
    execute format(
      'create policy staff_update on %I for update to authenticated
         using (is_staff() and business_id = current_business_id())
         with check (is_staff() and business_id = current_business_id())', t);
  end loop;
end $$;

-- Money records are append-only: insert yes, update and delete never.
create policy staff_insert on adjustments for insert to authenticated
  with check (is_staff() and business_id = current_business_id());
create policy staff_insert on remittances for insert to authenticated
  with check (is_staff() and business_id = current_business_id());

create policy own_business on businesses for select to authenticated
  using (id = current_business_id());
create policy own_profile on profiles for select to authenticated
  using (id = auth.uid() or (is_staff() and business_id = current_business_id()));

-- Drivers read only their own records.
create policy driver_self on drivers for select to authenticated
  using (profile_id = auth.uid());
create policy driver_self on driver_documents for select to authenticated
  using (driver_id = current_driver_id());
create policy driver_self on driver_vehicle_assignments for select to authenticated
  using (driver_id = current_driver_id());
create policy driver_self on daily_operations for select to authenticated
  using (driver_id = current_driver_id());
create policy driver_self on adjustments for select to authenticated
  using (driver_id = current_driver_id());
create policy driver_self on remittances for select to authenticated
  using (driver_id = current_driver_id());
create policy driver_assigned_vehicle on vehicles for select to authenticated
  using (id in (select vehicle_id from driver_vehicle_assignments
                 where driver_id = current_driver_id() and end_date is null));
create policy driver_assigned_vehicle on maintenance_records for select to authenticated
  using (vehicle_id in (select vehicle_id from driver_vehicle_assignments
                         where driver_id = current_driver_id() and end_date is null));
