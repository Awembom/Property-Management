-- =============================================================================
-- Receipt reference codes
--
-- Every rent payment gets a unique, automatically generated reference code
-- (e.g. PAY-7K3QX9), printed on its receipt. When a tenant pays only part of
-- the rent and later pays the rest ("pay off balance"), that later payment
-- gets the SAME code, so the receipts belong together: the completing
-- receipt's PDF includes the earlier one.
--
-- The `reference` column (typed by staff, e.g. a mobile-money transaction ID)
-- stays as it is; the app now calls it "Transaction ID".
-- =============================================================================

-- Characters that can't be confused when read aloud or copied by hand
-- (no 0/O, 1/I/L).
create function public.new_payment_reference()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  v_chars constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_code text;
begin
  loop
    v_code := 'PAY-';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    end loop;
    -- About 887 million possible codes; retry in the rare case of a clash.
    exit when not exists (select 1 from public.payments where reference_code = v_code);
  end loop;
  return v_code;
end;
$$;

alter table public.payments add column reference_code text;

-- Existing payments: each rent payment gets its own code; a balance payment
-- takes the code of the latest rent payment before it.
update public.payments set reference_code = public.new_payment_reference()
where kind = 'rent';

update public.payments b
set reference_code = coalesce(
  (select r.reference_code from public.payments r
    where r.tenancy_id = b.tenancy_id and r.kind = 'rent' and r.created_at <= b.created_at
    order by r.created_at desc limit 1),
  public.new_payment_reference())
where b.kind = 'balance';

alter table public.payments alter column reference_code set not null;

-- A code starts with exactly one rent payment; balance payments reuse it.
create unique index payments_rent_reference_code_key
  on public.payments (reference_code) where kind = 'rent';
create index on public.payments (reference_code);


-- record_payment(): same as before, plus the reference code.
--   rent    : a new code.
--   balance : the code of the most recent (non-voided) rent payment that was
--             not paid in full, i.e. the receipt this payment completes.
create or replace function public.record_payment(
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
  v_code text;
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
    select coalesce(sum(p.months), 0) + p_months into v_total_months
    from public.payments p
    where p.tenancy_id = v_tenancy.id and p.kind = 'rent'
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id);

    v_period_start := v_tenancy.paid_until;
    v_new_paid_until := (v_tenancy.billing_start_date
                         + make_interval(months => v_total_months))::date;
    v_code := public.new_payment_reference();
  elsif p_kind = 'balance' then
    if p_months is not null then
      raise exception 'A balance payment doesn''t cover months';
    end if;
    if p_amount is null then
      raise exception 'Enter the amount paid';
    end if;
    v_amount := p_amount;
    v_new_paid_until := v_tenancy.paid_until;

    select p.reference_code into v_code
    from public.payments p
    where p.tenancy_id = v_tenancy.id and p.kind = 'rent' and p.amount < p.expected_amount
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id)
    order by p.created_at desc
    limit 1;
    v_code := coalesce(v_code, public.new_payment_reference());
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
    period_start, period_end, paid_on, method, reference, reference_code, recorded_by
  ) values (
    v_tenancy.property_id, v_tenancy.id, p_kind, v_amount, v_expected, v_balance, p_months,
    v_period_start, case when p_kind = 'rent' then v_new_paid_until end,
    coalesce(p_paid_on, current_date), nullif(trim(p_method), ''),
    nullif(trim(p_reference), ''), v_code, auth.uid()
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

-- Only record_payment() (running as the owner) needs it.
revoke execute on function public.new_payment_reference() from public, anon, authenticated;
