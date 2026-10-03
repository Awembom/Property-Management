-- =============================================================================
-- Payment intervals, tenant ID numbers, renewals, and payments with balances
--
-- 1. Tenancy rent is now always stored PER MONTH (`monthly_rent`), and how
--    often the tenant pays is a number of months (`payment_interval_months`:
--    1, 3, 6, 12 or a custom 1-24). Weekly rent is gone. The interval is
--    what rent reminders (push notifications, Phase 11) will follow.
-- 2. Tenant ID card numbers, visible to owners and managers only.
-- 3. Renewing a tenancy: a new lease end date and optionally a new rent.
--    Each renewal is kept as a record.
-- 4. Payments say how many MONTHS they cover. The app pre-fills
--    monthly_rent x months, but the landlord can record a different amount.
--    Both the expected and the paid amount are kept, and the difference is
--    owed (the receipt shows "left to pay"). The months still count as
--    covered. A "balance" payment pays off what is owed without covering
--    new months.
-- =============================================================================


-- 1. Tenancies: monthly rent + payment interval in months ---------------------

alter table public.tenancies add column payment_interval_months int;

-- Convert existing data. Until now rent_amount was per period and each
-- payment counted periods; from now on both are in months. (Payments first,
-- while `frequency` still says how long a period was.)
update public.payments p
set periods = least(60, greatest(1, case t.frequency
    when 'weekly'    then round(p.periods * 12 / 52.0)::int
    when 'quarterly' then p.periods * 3
    when 'yearly'    then p.periods * 12
    else p.periods
  end))
from public.tenancies t
where t.id = p.tenancy_id;

update public.tenancies set
  payment_interval_months = case frequency
    when 'quarterly' then 3
    when 'yearly'    then 12
    else 1
  end,
  rent_amount = greatest(1, case frequency
    when 'weekly'    then round(rent_amount * 52 / 12.0)
    when 'quarterly' then round(rent_amount / 3.0)
    when 'yearly'    then round(rent_amount / 12.0)
    else rent_amount
  end)::bigint;

alter table public.tenancies
  alter column payment_interval_months set not null,
  add constraint tenancies_payment_interval_months_check
    check (payment_interval_months between 1 and 24);

alter table public.tenancies rename column rent_amount to monthly_rent;

-- Things that use the old `frequency` column must go before the column can.
-- (record_payment and void_payment are replaced in part 4.)
drop view public.tenancy_overview;
drop function public.start_tenancy(uuid, bigint, public.rent_frequency, date, uuid, text, text, text, date, date, text);
drop function public.record_payment(uuid, int, date, text, text, bigint);
alter table public.tenancies drop column frequency;
drop function public.period_interval(public.rent_frequency);
drop type public.rent_frequency;

-- Rent changes now go through renew_tenancy() (part 3) so every change is
-- recorded. The payment interval may be edited directly (it only decides
-- when reminders are sent).
revoke update (monthly_rent) on public.tenancies from authenticated;
grant  update (payment_interval_months) on public.tenancies to authenticated;


-- 2. Tenant ID card numbers ----------------------------------------------------
-- Separate table for the same reason as apartment_rents: caretakers can read
-- `tenants`, and RLS can't hide one column.

create table public.tenant_identities (
  tenant_id    uuid primary key,
  property_id  uuid not null,
  id_number    text not null check (length(trim(id_number)) > 0),
  foreign key (tenant_id, property_id)
    references public.tenants (id, property_id) on delete cascade
);

alter table public.tenant_identities enable row level security;

create policy "tenant_identities: read" on public.tenant_identities for select to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'));
create policy "tenant_identities: insert" on public.tenant_identities for insert to authenticated
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "tenant_identities: update" on public.tenant_identities for update to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'))
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "tenant_identities: delete" on public.tenant_identities for delete to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'));

grant select, insert, delete on public.tenant_identities to authenticated;
grant update (id_number) on public.tenant_identities to authenticated;

-- Sets (or with null/empty, removes) a tenant's ID number.
create function public.set_tenant_id_number(p_tenant_id uuid, p_id_number text)
returns void
language plpgsql set search_path = ''
as $$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tenants where id = p_tenant_id;
  if v_property_id is null or not public.has_property_role(v_property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can change ID numbers.';
  end if;

  if nullif(trim(p_id_number), '') is null then
    delete from public.tenant_identities where tenant_id = p_tenant_id;
  else
    insert into public.tenant_identities (tenant_id, property_id, id_number)
    values (p_tenant_id, v_property_id, trim(p_id_number))
    on conflict (tenant_id) do update set id_number = excluded.id_number;
  end if;
end;
$$;




-- 3. Start and renew tenancies -------------------------------------------------

create function public.start_tenancy(
  p_apartment_id             uuid,
  p_monthly_rent             bigint,
  p_payment_interval_months  int,
  p_start_date               date,
  p_tenant_id                uuid default null,
  p_tenant_name              text default null,
  p_tenant_phone             text default null,
  p_tenant_email             text default null,
  p_tenant_id_number         text default null,
  p_end_date                 date default null,
  p_billing_start_date       date default null,
  p_notes                    text default null
)
returns uuid
language plpgsql set search_path = ''
as $$
declare
  v_property_id uuid;
  v_tenant_id   uuid := p_tenant_id;
  v_tenancy_id  uuid;
begin
  select a.property_id into v_property_id
  from public.apartments a where a.id = p_apartment_id;

  if v_property_id is null or not public.has_property_role(v_property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can start a tenancy.';
  end if;
  if p_monthly_rent is null or p_monthly_rent <= 0 then
    raise exception 'Rent must be more than zero.';
  end if;
  if p_payment_interval_months is null or p_payment_interval_months not between 1 and 24 then
    raise exception 'Choose how often rent is paid (1 to 24 months).';
  end if;
  if p_end_date is not null and p_end_date < p_start_date then
    raise exception 'The lease end date can''t be before the move-in date.';
  end if;
  if p_billing_start_date is not null and p_billing_start_date < p_start_date then
    raise exception 'The "paid until" date can''t be before the move-in date.';
  end if;
  if exists (
    select 1 from public.tenancies
    where apartment_id = p_apartment_id and status = 'active'
  ) then
    raise exception 'This apartment already has a tenant. End that tenancy first.';
  end if;

  if v_tenant_id is null then
    if p_tenant_name is null or length(trim(p_tenant_name)) = 0 then
      raise exception 'Enter the tenant''s name.';
    end if;
    insert into public.tenants (property_id, full_name, phone, email)
    values (v_property_id, trim(p_tenant_name),
            nullif(trim(p_tenant_phone), ''), p_tenant_email)
    returning id into v_tenant_id;

    if nullif(trim(p_tenant_id_number), '') is not null then
      insert into public.tenant_identities (tenant_id, property_id, id_number)
      values (v_tenant_id, v_property_id, trim(p_tenant_id_number));
    end if;
  elsif not exists (
    select 1 from public.tenants where id = v_tenant_id and property_id = v_property_id
  ) then
    raise exception 'That tenant doesn''t belong to this property.';
  end if;

  -- paid_until and status are set by the tenancy_before_insert trigger.
  insert into public.tenancies (
    property_id, apartment_id, tenant_id, monthly_rent, payment_interval_months,
    start_date, end_date, billing_start_date, notes
  ) values (
    v_property_id, p_apartment_id, v_tenant_id, p_monthly_rent, p_payment_interval_months,
    p_start_date, p_end_date, p_billing_start_date, nullif(trim(p_notes), '')
  )
  returning id into v_tenancy_id;

  return v_tenancy_id;
exception
  when unique_violation then
    raise exception 'This apartment already has a tenant. End that tenancy first.';
end;
$$;

-- One row per renewal: what the lease end and rent were before and after.
create table public.tenancy_renewals (
  id                uuid primary key default gen_random_uuid(),
  tenancy_id        uuid not null references public.tenancies (id) on delete cascade,
  property_id       uuid not null references public.properties (id) on delete cascade,
  old_end_date      date,
  new_end_date      date not null,
  old_monthly_rent  bigint not null,
  new_monthly_rent  bigint not null check (new_monthly_rent > 0),
  notes             text,
  renewed_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now()
);

create index on public.tenancy_renewals (tenancy_id);

alter table public.tenancy_renewals enable row level security;

-- Contains rent amounts: owners/managers (and the tenant) only. Written only
-- by renew_tenancy(), so there are no insert/update/delete policies.
create policy "tenancy_renewals: read" on public.tenancy_renewals for select to authenticated
  using (
    public.has_property_role(property_id, '{owner,manager}')
    or public.is_tenant_of_tenancy(tenancy_id)
  );

grant select on public.tenancy_renewals to authenticated;

-- Continue a tenancy: set a new lease end date and, optionally, a new monthly
-- rent. security definer because it writes tenancy_renewals, which the app
-- can't write directly; the role check below is what protects it.
create function public.renew_tenancy(
  p_tenancy_id        uuid,
  p_new_end_date      date,
  p_new_monthly_rent  bigint default null,   -- null = keep the current rent
  p_notes             text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_tenancy public.tenancies;
  v_rent bigint;
begin
  select * into v_tenancy from public.tenancies where id = p_tenancy_id for update;

  if not found or not public.has_property_role(v_tenancy.property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can renew a tenancy.';
  end if;
  if v_tenancy.status <> 'active' then
    raise exception 'An ended tenancy can''t be renewed. Start a new tenancy instead.';
  end if;
  if p_new_end_date is null
     or p_new_end_date <= coalesce(v_tenancy.end_date, v_tenancy.start_date) then
    raise exception 'The new lease end must be after the current one.';
  end if;

  v_rent := coalesce(p_new_monthly_rent, v_tenancy.monthly_rent);
  if v_rent <= 0 then
    raise exception 'Rent must be more than zero.';
  end if;

  insert into public.tenancy_renewals (
    tenancy_id, property_id, old_end_date, new_end_date,
    old_monthly_rent, new_monthly_rent, notes, renewed_by
  ) values (
    v_tenancy.id, v_tenancy.property_id, v_tenancy.end_date, p_new_end_date,
    v_tenancy.monthly_rent, v_rent, nullif(trim(p_notes), ''), auth.uid()
  );

  update public.tenancies
  set end_date = p_new_end_date, monthly_rent = v_rent
  where id = v_tenancy.id;
end;
$$;


-- 4. Payments: months covered, expected vs paid amount, balance -------------

alter table public.payments rename column periods to months;  -- its check (1-60) stays

alter table public.payments
  alter column months       drop not null,
  alter column period_start drop not null,
  alter column period_end   drop not null,
  -- 'rent' covers months; 'balance' pays off money still owed.
  add column kind text not null default 'rent' check (kind in ('rent', 'balance')),
  -- What the covered months cost (monthly rent x months) when recorded.
  add column expected_amount bigint check (expected_amount > 0),
  -- Money still owed on the tenancy right after this payment (negative =
  -- paid in advance). Stored so a receipt always shows what it showed then.
  add column balance_after bigint;

-- Older payments were always the full amount.
update public.payments set expected_amount = amount, balance_after = 0;

alter table public.payments
  alter column balance_after set not null,
  add constraint payments_kind_fields check (
    (kind = 'rent' and months is not null and period_start is not null
       and period_end is not null and expected_amount is not null)
    or
    (kind = 'balance' and months is null and period_start is null
       and period_end is null and expected_amount is null)
  );

-- Money owed on a tenancy: for each non-voided payment, rent payments add
-- (expected - paid) and balance payments subtract what was paid.
create function public.tenancy_balance(p_tenancy_id uuid)
returns bigint
language sql stable set search_path = ''
as $$
  select coalesce(sum(case when p.kind = 'rent' then p.expected_amount - p.amount
                           else -p.amount end), 0)::bigint
  from public.payments p
  where p.tenancy_id = p_tenancy_id
    and not exists (select 1 from public.payment_voids v where v.payment_id = p.id);
$$;

-- Balance per tenancy for the app. security_invoker = true: the caller's own
-- RLS on payments applies, so caretakers get no rows (no money for them).
create view public.tenancy_balances
with (security_invoker = true)
as
select
  p.tenancy_id,
  p.property_id,
  sum(case when p.kind = 'rent' then p.expected_amount - p.amount
           else -p.amount end)::bigint as balance
from public.payments p
where not exists (select 1 from public.payment_voids v where v.payment_id = p.id)
group by p.tenancy_id, p.property_id;

-- Records a payment and issues the next receipt number, all in one step.
--   kind 'rent'    : covers p_months months; moves paid_until forward that far.
--                    p_amount null = the full monthly_rent x months.
--   kind 'balance' : pays p_amount off what is owed; paid_until doesn't move.
-- Returns no money figures, so it is safe for caretakers to call.
create function public.record_payment(
  p_tenancy_id uuid,
  p_months     int default null,
  p_paid_on    date default current_date,
  p_method     text default null,
  p_reference  text default null,
  p_amount     bigint default null,
  p_kind       text default 'rent'
)
returns table (payment_id uuid, receipt_number text, paid_until date)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenancy public.tenancies;
  v_amount bigint;
  v_expected bigint;
  v_total_months int;
  v_period_start date;
  v_new_paid_until date;
  v_balance bigint;
  v_payment_id uuid;
  v_year int := extract(year from now() at time zone 'utc')::int;
  v_number int;
  v_receipt text;
begin
  -- FOR UPDATE locks the tenancy so two payments at once can't clash.
  select * into v_tenancy from public.tenancies where id = p_tenancy_id for update;

  if not found or not public.can_record_payments(v_tenancy.property_id) then
    raise exception 'Tenancy not found or not allowed';
  end if;
  if v_tenancy.status <> 'active' then
    raise exception 'Cannot record a payment on an ended tenancy';
  end if;

  if p_kind = 'rent' then
    if p_months is null or p_months < 1 or p_months > 60 then
      raise exception 'Months paid must be between 1 and 60';
    end if;
    v_expected := v_tenancy.monthly_rent * p_months;
    v_amount := coalesce(p_amount, v_expected);

    -- New due date = billing start + ALL non-voided months (including these).
    -- Counting from the fixed start keeps month-ends exact: Jan 31 + 2 months
    -- = Mar 31, whereas adding one month at a time gives Jan 31 -> Feb 28 -> Mar 28.
    select coalesce(sum(p.months), 0) + p_months into v_total_months
    from public.payments p
    where p.tenancy_id = v_tenancy.id and p.kind = 'rent'
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id);

    v_period_start := v_tenancy.paid_until;
    v_new_paid_until := (v_tenancy.billing_start_date
                         + make_interval(months => v_total_months))::date;
  elsif p_kind = 'balance' then
    if p_months is not null then
      raise exception 'A balance payment doesn''t cover months';
    end if;
    if p_amount is null then
      raise exception 'Enter the amount paid';
    end if;
    v_amount := p_amount;
    v_new_paid_until := v_tenancy.paid_until;
  else
    raise exception 'Unknown payment kind: %', p_kind;
  end if;

  if v_amount <= 0 then
    raise exception 'The amount must be more than zero';
  end if;

  v_balance := public.tenancy_balance(v_tenancy.id)
               + case when p_kind = 'rent' then v_expected - v_amount else -v_amount end;

  insert into public.payments (
    property_id, tenancy_id, kind, amount, expected_amount, balance_after, months,
    period_start, period_end, paid_on, method, reference, recorded_by
  ) values (
    v_tenancy.property_id, v_tenancy.id, p_kind, v_amount, v_expected, v_balance, p_months,
    v_period_start, case when p_kind = 'rent' then v_new_paid_until end,
    coalesce(p_paid_on, current_date), nullif(trim(p_method), ''),
    nullif(trim(p_reference), ''), auth.uid()
  ) returning id into v_payment_id;

  if p_kind = 'rent' then
    update public.tenancies set paid_until = v_new_paid_until where id = v_tenancy.id;
  end if;

  -- Next receipt number: insert the counter for this year or bump it, atomically.
  insert into public.receipt_counters as rc (property_id, year, last_number)
  values (v_tenancy.property_id, v_year, 1)
  on conflict (property_id, year) do update set last_number = rc.last_number + 1
  returning rc.last_number into v_number;

  v_receipt := format('RCT-%s-%s', v_year, lpad(v_number::text, 4, '0'));

  insert into public.receipts (property_id, payment_id, receipt_number)
  values (v_tenancy.property_id, v_payment_id, v_receipt);

  return query select v_payment_id, v_receipt, v_new_paid_until;
end;
$$;

-- Voids a payment (owners/managers only); paid_until is recalculated from
-- the remaining rent payments. The payment row itself never changes.
create or replace function public.void_payment(p_payment_id uuid, p_reason text)
returns date
language plpgsql security definer set search_path = ''
as $$
declare
  v_payment public.payments;
  v_tenancy public.tenancies;
  v_total_months int;
  v_new_paid_until date;
begin
  select * into v_payment from public.payments where id = p_payment_id;
  if not found or not public.has_property_role(v_payment.property_id, '{owner,manager}') then
    raise exception 'Payment not found or not allowed';
  end if;
  if exists (select 1 from public.payment_voids where payment_id = p_payment_id) then
    raise exception 'Payment is already voided';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to void a payment';
  end if;

  select * into v_tenancy from public.tenancies where id = v_payment.tenancy_id for update;

  insert into public.payment_voids (payment_id, property_id, reason, voided_by)
  values (p_payment_id, v_payment.property_id, trim(p_reason), auth.uid());

  select coalesce(sum(p.months), 0) into v_total_months
  from public.payments p
  where p.tenancy_id = v_tenancy.id and p.kind = 'rent'
    and not exists (select 1 from public.payment_voids v where v.payment_id = p.id);

  v_new_paid_until := (v_tenancy.billing_start_date
                       + make_interval(months => v_total_months))::date;

  update public.tenancies set paid_until = v_new_paid_until where id = v_tenancy.id;
  return v_new_paid_until;
end;
$$;


-- 5. The caretaker-safe view again, now with the payment interval and how many
-- months are paid (no money columns, as before).
create view public.tenancy_overview
with (security_invoker = false, security_barrier = true)
as
select
  ty.id,
  ty.property_id,
  ty.apartment_id,
  a.name  as apartment_name,
  ty.tenant_id,
  t.full_name as tenant_name,
  ty.payment_interval_months,
  ty.start_date,
  ty.end_date,
  ty.billing_start_date,
  ty.paid_until,
  -- Months covered by non-voided rent payments; with billing_start_date the
  -- app can show exactly which date a new payment will pay up to.
  (select coalesce(sum(p.months), 0)::int
     from public.payments p
    where p.tenancy_id = ty.id and p.kind = 'rent'
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id)
  ) as paid_months,
  ty.status,
  case when ty.status = 'active'
       then public.rent_status(ty.paid_until, p.grace_period_days) end as rent_status
from public.tenancies ty
join public.apartments a on a.id = ty.apartment_id
join public.tenants    t on t.id = ty.tenant_id
join public.properties p on p.id = ty.property_id
where public.is_property_member(ty.property_id)
   or t.user_id = (select auth.uid());


-- Privileges ------------------------------------------------------------------

grant select on public.tenancy_overview, public.tenancy_balances to authenticated;

revoke execute on function public.start_tenancy(uuid, bigint, int, date, uuid, text, text, text, text, date, date, text) from public, anon;
grant  execute on function public.start_tenancy(uuid, bigint, int, date, uuid, text, text, text, text, date, date, text) to authenticated;
revoke execute on function public.renew_tenancy(uuid, date, bigint, text) from public, anon;
grant  execute on function public.renew_tenancy(uuid, date, bigint, text) to authenticated;
revoke execute on function public.set_tenant_id_number(uuid, text) from public, anon;
grant  execute on function public.set_tenant_id_number(uuid, text) to authenticated;
revoke execute on function public.record_payment(uuid, int, date, text, text, bigint, text) from public, anon;
grant  execute on function public.record_payment(uuid, int, date, text, text, bigint, text) to authenticated;
-- Internal helper: used by record_payment(); the app reads tenancy_balances.
revoke execute on function public.tenancy_balance(uuid) from public, anon, authenticated;
