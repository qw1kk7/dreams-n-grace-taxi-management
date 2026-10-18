-- Fixes found while building the daily remittance screen.
--
-- 1. Payment dates use Philippine time. received_at is stored in UTC, so a
--    payment at 7am in Manila used to count as the previous day.
-- 2. The penalty job runs with the caller's permissions, so row level security
--    limits it to staff and their own business.

-- Every money movement per driver: positive = owed, negative = paid.
create or replace view driver_ledger with (security_invoker = true) as
  select o.business_id, o.driver_id, o.operation_date as entry_date, 'boundary'::text as entry_type,
         o.id as source_id, o.amount_due as amount, o.day_discount_reason as note
    from daily_operations o
  union all
  select a.business_id, a.driver_id, a.effective_date, a.kind::text, a.id, a.amount, a.reason
    from adjustments a
  union all
  select r.business_id, r.driver_id, (r.received_at at time zone 'Asia/Manila')::date,
         case when r.reverses_id is null then 'payment' else 'payment_reversal' end,
         r.id, -r.amount, r.note
    from remittances r;

-- Adds the ₱50 penalty for an operating day with no remittance at all,
-- unless the driver already carries an unpaid penalty (penalties do not stack).
-- Run at the end of each operating day. Returns the number of penalties added.
create or replace function apply_no_remit_penalties(p_business_id uuid, p_date date)
returns int
language plpgsql security invoker set search_path = public as $$
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
                          and x.reverses_id is null
                          and (x.daily_operation_id = o.id
                               or (x.received_at at time zone 'Asia/Manila')::date = p_date))
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

