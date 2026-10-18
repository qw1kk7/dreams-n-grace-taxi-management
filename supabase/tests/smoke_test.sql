-- Checks the confirmed business rules against the schema. Run by scripts/check-schema.sh.
\set ON_ERROR_STOP on

-- Fixed ids: business b0, owner u1, driver login u2, units v1 (new) and v2 (old),
-- drivers d1 (junior, has a login) and d2 (senior).
\set b0 '''00000000-0000-0000-0000-0000000000b0'''
\set u1 '''00000000-0000-0000-0000-0000000000a1'''
\set u2 '''00000000-0000-0000-0000-0000000000a2'''
\set v1 '''00000000-0000-0000-0000-0000000000e1'''
\set v2 '''00000000-0000-0000-0000-0000000000e2'''
\set d1 '''00000000-0000-0000-0000-0000000000d1'''
\set d2 '''00000000-0000-0000-0000-0000000000d2'''

insert into businesses (id, name) values (:b0, 'Dreams ''N Grace Taxi');
insert into business_settings (business_id) values (:b0);
insert into auth.users values (:u1), (:u2);
insert into profiles values (:u1, :b0, 'owner', 'Owner'), (:u2, :b0, 'driver', 'Junior Driver');
insert into boundary_rates (business_id, min_unit_age_years, max_unit_age_years, daily_amount, effective_from)
values (:b0, 0, 5, 1200, '2020-01-01'), (:b0, 5, null, 1100, '2020-01-01');
insert into vehicles (id, business_id, plate_number, first_registered_on)
values (:v1, :b0, 'NEW-001', '2023-03-01'), (:v2, :b0, 'OLD-001', '2021-10-12');
insert into drivers (id, business_id, profile_id, full_name, hire_date)
values (:d1, :b0, :u2, 'Junior Driver', '2024-01-01'), (:d2, :b0, null, 'Senior Driver', '2021-12-25');
insert into holidays (business_id, holiday_date, name, kind) values
  (:b0, '2026-11-30', 'Bonifacio Day', 'regular'),
  (:b0, '2026-11-02', 'All Souls Day', 'special'),
  (:b0, '2026-12-25', 'Christmas Day', 'christmas_new_year'),
  (:b0, '2027-12-26', 'Holiday on a Sunday', 'regular');

-- 1. Expected boundary rules ---------------------------------------------------
create temp table expect (label text, vehicle uuid, driver uuid, d date, base numeric, discount numeric, reason text);
insert into expect values
  ('new unit, Monday',                  :v1, :d1, '2026-10-19', 1200,    0, null),
  ('unit exactly 5 years old',          :v2, :d1, '2026-10-12', 1100,    0, null),
  ('unit one day short of 5 years',     :v2, :d1, '2026-10-09', 1200,    0, null),
  ('Sunday 50%',                        :v1, :d1, '2026-10-18', 1200,  600, 'sunday'),
  ('red-calendar holiday',              :v1, :d1, '2026-11-30', 1200,  200, 'regular_holiday'),
  ('other holiday',                     :v1, :d1, '2026-11-02', 1200,  100, 'special_holiday'),
  ('Christmas, under 5 yrs service',    :v1, :d1, '2026-12-25', 1200,  600, 'christmas_new_year'),
  ('Christmas, exactly 5 yrs service',  :v1, :d2, '2026-12-25', 1200, 1200, 'christmas_new_year'),
  ('holiday on a Sunday: Sunday wins',  :v1, :d1, '2027-12-26', 1200,  600, 'sunday'),
  ('old unit, red-calendar holiday',    :v2, :d1, '2026-11-30', 1100,  200, 'regular_holiday');

do $$
declare e record; g record; fails int := 0;
begin
  for e in select * from expect loop
    select * into g from expected_boundary(e.vehicle, e.driver, e.d);
    if g.base_amount <> e.base or g.day_discount <> e.discount
       or g.day_discount_reason is distinct from e.reason then
      raise warning 'FAIL %: got base % discount % reason %', e.label, g.base_amount, g.day_discount, g.day_discount_reason;
      fails := fails + 1;
    end if;
  end loop;
  if fails > 0 then raise exception '% boundary checks failed', fails; end if;
  raise notice 'boundary rules: % checks passed', (select count(*) from expect);
end $$;

-- 2. Remittances, penalties and flags for the junior driver on the new unit ---
-- Mon 19 pays in full; Tue 20 and Wed 21 pay nothing; Thu 22 clears everything;
-- Fri 23 pays part; Sat 24 pays nothing.
create temp table days (d date, paid numeric);
insert into days values ('2026-10-19', 1200), ('2026-10-20', 0), ('2026-10-21', 0),
                        ('2026-10-22', 3650), ('2026-10-23', 500), ('2026-10-24', 0);

do $$
declare r record; op uuid; eb record; added int; expected_added int[] := array[0, 1, 0, 0, 0, 1]; i int := 0;
begin
  for r in select * from days order by d loop
    i := i + 1;
    select * into eb from expected_boundary('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1', r.d);
    insert into daily_operations (business_id, operation_date, vehicle_id, driver_id, boundary_rate_id, base_amount, day_discount, day_discount_reason)
    values ('00000000-0000-0000-0000-0000000000b0', r.d, '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1',
            eb.boundary_rate_id, eb.base_amount, eb.day_discount, eb.day_discount_reason)
    returning id into op;
    if r.paid > 0 then
      insert into remittances (business_id, driver_id, daily_operation_id, amount, received_by, received_at)
      values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d1', op, r.paid,
              '00000000-0000-0000-0000-0000000000a1', r.d + time '18:00');
    end if;
    added := apply_no_remit_penalties('00000000-0000-0000-0000-0000000000b0', r.d);
    if added <> expected_added[i] then
      raise exception 'FAIL penalty on %: added %, expected %', r.d, added, expected_added[i];
    end if;
  end loop;
  raise notice 'penalties: no stacking, none on partial payment, new one after the balance cleared';
end $$;

do $$
declare bal numeric; since date; flagged int;
begin
  select balance, unpaid_since into bal, since from driver_short_status
   where driver_id = '00000000-0000-0000-0000-0000000000d1';
  if bal <> 1950 then raise exception 'FAIL balance: got %, expected 1950', bal; end if;
  if since <> '2026-10-23' then raise exception 'FAIL unpaid_since: got %, expected 2026-10-23', since; end if;

  select count(*) into flagged from flagged_drivers('2026-10-26');
  if flagged <> 0 then raise exception 'FAIL: flagged within the 3-day grace period'; end if;
  select count(*) into flagged from flagged_drivers('2026-10-27');
  if flagged <> 1 then raise exception 'FAIL: not flagged after 3 days'; end if;
  raise notice 'balance 1950, short since Oct 23, flagged only after 3 days';
end $$;

-- 3. Collateral and reversals ---------------------------------------------------
do $$
begin
  begin
    insert into remittances (business_id, driver_id, amount, method, received_by)
    values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d1', 500, 'collateral',
            '00000000-0000-0000-0000-0000000000a1');
    raise exception 'FAIL: collateral without an item was accepted';
  exception when check_violation then null;
  end;
  insert into remittances (business_id, driver_id, amount, method, collateral_item, received_by)
  values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d1', 500, 'collateral',
          'Phone, agreed value 500', '00000000-0000-0000-0000-0000000000a1');
  begin
    insert into adjustments (business_id, driver_id, kind, amount, reason)
    values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d1', 'discount', -100, 'no approver');
    raise exception 'FAIL: discount without owner approval was accepted';
  exception when check_violation then null;
  end;
  raise notice 'collateral needs an item; discounts need an approver';
end $$;

-- 4. Assignment history -----------------------------------------------------------
do $$
begin
  insert into driver_vehicle_assignments (business_id, driver_id, vehicle_id, start_date)
  values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000e1', '2026-01-01');
  begin
    insert into driver_vehicle_assignments (business_id, driver_id, vehicle_id, start_date)
    values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000e1', '2026-06-01');
    raise exception 'FAIL: two drivers on one unit at the same time';
  exception when exclusion_violation then null;
  end;
  raise notice 'one driver per unit at a time';
end $$;

-- 5. Row level security -------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, insert, update on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
set role authenticated;

set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
do $$
declare n int;
begin
  select count(*) into n from drivers;
  if n <> 1 then raise exception 'FAIL: driver sees % driver rows, expected 1', n; end if;
  select count(*) into n from expenses;
  if n <> 0 then raise exception 'FAIL: driver can see expenses'; end if;
  begin
    insert into remittances (business_id, driver_id, amount, received_by)
    values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000d1', 100, '00000000-0000-0000-0000-0000000000a2');
    raise exception 'FAIL: driver recorded a remittance';
  exception when insufficient_privilege then null;
  end;
  raise notice 'driver sees only their own records and cannot record payments';
end $$;

set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
do $$
declare n int;
begin
  select count(*) into n from drivers;
  if n <> 2 then raise exception 'FAIL: owner sees % drivers, expected 2', n; end if;
  update remittances set amount = 1 where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: remittances were edited'; end if;
  raise notice 'owner sees the business; remittances cannot be edited';
end $$;
reset role;

select 'ALL CHECKS PASSED' as result;
