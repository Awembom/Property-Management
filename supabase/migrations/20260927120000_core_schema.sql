-- =============================================================================
-- Phase 1: core schema + row-level security (RLS)
--
-- Tables: profiles, properties, memberships, apartments, tenants, tenancies,
--         payments, payment_voids, receipts, receipt_counters
--
-- Security model (see the permissions table in CLAUDE.md):
--   * Every table has RLS enabled. With RLS on and no matching policy, a row is
--     invisible / the write is refused. So "no policy" = "not allowed".
--   * Policies call small helper functions (is_property_member, has_property_role...)
--     so the role rules are written once and reused everywhere.
--   * Anything that must happen atomically or that needs extra checks
--     (creating a property, recording/voiding payments) is done through
--     functions ("RPCs") that the app calls with supabase.rpc(...).
--   * The `anon` role (not logged in) gets no access to any table.
--
-- Money: bigint in the smallest currency unit (e.g. cents). Never floats.
-- Dates: `date` for calendar days (rent periods), `timestamptz` (UTC) for moments.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------

create type public.membership_role as enum ('owner', 'manager', 'caretaker');

create type public.rent_frequency as enum ('weekly', 'monthly', 'quarterly', 'yearly');

create type public.tenancy_status as enum ('active', 'ended');


-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

-- One row per signed-up user, created automatically by a trigger (below).
-- auth.users is Supabase's own table; we keep app-specific profile data here.
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text,
  phone      text,
  created_at timestamptz not null default now()
);

create table public.properties (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (length(trim(name)) > 0),
  address            text,
  -- ISO 4217 code, e.g. 'XAF', 'NGN', 'USD'. All amounts in this property use it.
  currency           text not null check (currency ~ '^[A-Z]{3}$'),
  -- How many days before the due date rent counts as "Due soon".
  grace_period_days  int  not null default 7 check (grace_period_days between 0 and 60),
  created_by         uuid references auth.users (id) on delete set null,
  created_at         timestamptz not null default now()
);

-- Staff access: links a user to a property with a role.
create table public.memberships (
  id                   uuid primary key default gen_random_uuid(),
  property_id          uuid not null references public.properties (id) on delete cascade,
  user_id              uuid not null references auth.users (id) on delete cascade,
  role                 public.membership_role not null,
  -- Only meaningful for caretakers; owners/managers can always record payments.
  can_record_payments  boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (property_id, user_id)
);

create table public.apartments (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  name         text not null check (length(trim(name)) > 0),  -- e.g. "A1", "Flat 3"
  description  text,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (property_id, name),
  -- Lets other tables reference (apartment, property) as a pair, which
  -- guarantees their property_id matches the apartment's property.
  unique (id, property_id)
);

-- Tenant contacts ("contact first, link later").
-- Staff create these; `user_id` stays null until the tenant signs up and
-- confirms the same email, then link_my_tenant_records() fills it in.
create table public.tenants (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  full_name    text not null check (length(trim(full_name)) > 0),
  phone        text,
  email        text check (email is null or email = lower(email)),
  user_id      uuid references auth.users (id) on delete set null,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (id, property_id)
);

create table public.tenancies (
  id                  uuid primary key default gen_random_uuid(),
  property_id         uuid not null,
  apartment_id        uuid not null,
  tenant_id           uuid not null,
  rent_amount         bigint not null check (rent_amount > 0),  -- per period, smallest unit
  frequency           public.rent_frequency not null,
  start_date          date not null,         -- move-in date
  end_date            date,                  -- planned lease end (optional)
  -- Rent is counted from this date. Normally equal to start_date. For a tenant
  -- who already paid before the app was used, set it to the date they are paid up to.
  billing_start_date  date not null,
  -- First day NOT covered by rent = the next due date. Maintained only by
  -- record_payment()/void_payment(); the app can't edit it directly.
  paid_until          date not null,
  status              public.tenancy_status not null default 'active',
  ended_at            timestamptz,
  notes               text,
  created_by          uuid references auth.users (id) on delete set null,
  created_at          timestamptz not null default now(),
  -- "on delete cascade" only matters when a whole property is deleted: deleting
  -- a single apartment/tenant with tenancy history is blocked by a trigger below.
  foreign key (apartment_id, property_id) references public.apartments (id, property_id) on delete cascade,
  foreign key (tenant_id, property_id)    references public.tenants (id, property_id) on delete cascade,
  check (end_date is null or end_date >= start_date),
  check ((status = 'ended') = (ended_at is not null))
);

-- Business rule 4: at most one ACTIVE tenancy per apartment.
-- A partial unique index only enforces uniqueness on rows matching the WHERE.
create unique index one_active_tenancy_per_apartment
  on public.tenancies (apartment_id) where status = 'active';

-- Payments are immutable: nobody (not even owners) may UPDATE or DELETE them.
-- Rows are only created by record_payment().
create table public.payments (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties (id) on delete cascade,
  tenancy_id    uuid not null references public.tenancies (id) on delete cascade,
  amount        bigint not null check (amount > 0),
  periods       int    not null check (periods between 1 and 60),
  -- The rent period this payment covered at the time it was recorded.
  period_start  date not null,
  period_end    date not null,
  paid_on       date not null,           -- when the money was actually received
  method        text,                    -- e.g. 'cash', 'mobile_money', 'bank'
  reference     text,                    -- transaction id, notes...
  recorded_by   uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now()
);

-- A void cancels one payment (with a reason) without touching the original row.
create table public.payment_voids (
  payment_id  uuid primary key references public.payments (id) on delete cascade,  -- one void max per payment
  property_id uuid not null references public.properties (id) on delete cascade,
  reason      text not null check (length(trim(reason)) > 0),
  voided_by   uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

create table public.receipts (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties (id) on delete cascade,
  payment_id      uuid not null unique references public.payments (id) on delete cascade,
  receipt_number  text not null,   -- e.g. RCT-2026-0001
  issued_at       timestamptz not null default now(),
  unique (property_id, receipt_number)
);

-- Business rule 3: sequential receipt numbers per property (and per year).
-- record_payment() increments this under a row lock, so two simultaneous
-- payments can never get the same number and no numbers are skipped.
create table public.receipt_counters (
  property_id  uuid not null references public.properties (id) on delete cascade,
  year         int  not null,
  last_number  int  not null default 0,
  primary key (property_id, year)
);

-- Indexes for the foreign keys we filter on most.
create index on public.memberships (user_id);
create index on public.apartments (property_id);
create index on public.tenants (property_id);
create index on public.tenants (user_id);
create index on public.tenancies (property_id);
create index on public.tenancies (tenant_id);
create index on public.payments (tenancy_id);
create index on public.payments (property_id);


-- -----------------------------------------------------------------------------
-- Helper functions used by RLS policies
--
-- `security definer` = runs with the function owner's rights, so it can read
-- memberships without triggering memberships' own RLS (which would otherwise
-- recurse forever). `set search_path = ''` is a standard hardening step for
-- security definer functions: every name below is fully qualified.
-- -----------------------------------------------------------------------------

-- Is the current user staff (any role) on this property?
create function public.is_property_member(p_property_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.property_id = p_property_id and m.user_id = (select auth.uid())
  );
$$;

-- Does the current user have one of these roles on this property?
create function public.has_property_role(p_property_id uuid, p_roles public.membership_role[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.property_id = p_property_id
      and m.user_id = (select auth.uid())
      and m.role = any (p_roles)
  );
$$;

-- Owners/managers always; caretakers only with can_record_payments.
create function public.can_record_payments(p_property_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.property_id = p_property_id
      and m.user_id = (select auth.uid())
      and (m.role in ('owner', 'manager') or m.can_record_payments)
  );
$$;

-- Is the current user the (linked) tenant on this tenancy?
create function public.is_tenant_of_tenancy(p_tenancy_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.tenancies ty
    join public.tenants t on t.id = ty.tenant_id
    where ty.id = p_tenancy_id and t.user_id = (select auth.uid())
  );
$$;

-- Is the current user a (linked) tenant anywhere in this property?
create function public.is_tenant_in_property(p_property_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.tenants t
    where t.property_id = p_property_id and t.user_id = (select auth.uid())
  );
$$;

-- Length of one rent period.
create function public.period_interval(p_frequency public.rent_frequency)
returns interval
language sql immutable set search_path = ''
as $$
  select case p_frequency
    when 'weekly'    then interval '1 week'
    when 'monthly'   then interval '1 month'
    when 'quarterly' then interval '3 months'
    when 'yearly'    then interval '1 year'
  end;
$$;

-- Rent status, computed from dates (business rule 1). Never stored.
--   overdue  : today is on/after the due date
--   due_soon : due date is within the grace period
--   paid     : otherwise
-- Note: current_date is the database's date (UTC).
create function public.rent_status(p_paid_until date, p_grace_days int)
returns text
language sql stable set search_path = ''
as $$
  select case
    when current_date >= p_paid_until               then 'overdue'
    when p_paid_until - current_date <= p_grace_days then 'due_soon'
    else 'paid'
  end;
$$;


-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

-- Conventions rule: created_by always comes from the logged-in user, never
-- from what the app sends.
create function public.set_created_by()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.created_by := auth.uid();
  return new;
end;
$$;

create trigger set_created_by before insert on public.apartments
  for each row execute function public.set_created_by();
create trigger set_created_by before insert on public.tenants
  for each row execute function public.set_created_by();
create trigger set_created_by before insert on public.tenancies
  for each row execute function public.set_created_by();

-- New tenancies: default billing start to move-in date and set the first due date.
-- Also normalise tenant emails to lowercase so linking by email is reliable.
create function public.tenancy_before_insert()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.billing_start_date := coalesce(new.billing_start_date, new.start_date);
  new.paid_until := new.billing_start_date;   -- nothing paid yet
  new.status := 'active';
  new.ended_at := null;
  return new;
end;
$$;

create trigger tenancy_before_insert before insert on public.tenancies
  for each row execute function public.tenancy_before_insert();

create function public.tenant_normalise_email()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.email := nullif(lower(trim(new.email)), '');
  return new;
end;
$$;

create trigger tenant_normalise_email before insert or update of email on public.tenants
  for each row execute function public.tenant_normalise_email();

-- Create a profile row whenever someone signs up.
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.phone);
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Business rule 6: a property must always keep at least one owner.
-- Blocks deleting or demoting the last owner. Still allows the whole property
-- to be deleted (its memberships are then removed along with it).
create function public.protect_last_owner()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.role <> 'owner' then
    return coalesce(new, old);
  end if;
  if tg_op = 'UPDATE' and new.role = 'owner' then
    return new;
  end if;
  -- Property itself is being deleted: nothing to protect.
  if not exists (select 1 from public.properties where id = old.property_id) then
    return old;
  end if;
  if not exists (
    select 1 from public.memberships
    where property_id = old.property_id and role = 'owner' and id <> old.id
  ) then
    raise exception 'A property must keep at least one owner. Add another owner first.'
      using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger protect_last_owner before update of role or delete on public.memberships
  for each row execute function public.protect_last_owner();

-- Payment history must not disappear by accident: an apartment or tenant
-- contact that has any tenancy can't be deleted on its own. (Deleting the
-- whole property, which only owners can do, still removes everything.)
create function public.protect_tenancy_history()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Property itself is being deleted: allow the cascade.
  if not exists (select 1 from public.properties where id = old.property_id) then
    return old;
  end if;
  if exists (
    select 1 from public.tenancies
    where (tg_table_name = 'apartments' and apartment_id = old.id)
       or (tg_table_name = 'tenants'    and tenant_id    = old.id)
  ) then
    raise exception 'Cannot delete: it has tenancy history.'
      using errcode = 'P0001';
  end if;
  return old;
end;
$$;

create trigger protect_tenancy_history before delete on public.apartments
  for each row execute function public.protect_tenancy_history();
create trigger protect_tenancy_history before delete on public.tenants
  for each row execute function public.protect_tenancy_history();


-- -----------------------------------------------------------------------------
-- RPC functions (called from the app with supabase.rpc('name', params: {...}))
-- -----------------------------------------------------------------------------

-- Creates a property and makes the caller its owner, in one step.
create function public.create_property(
  p_name     text,
  p_currency text,
  p_address  text default null,
  p_grace_period_days int default 7
)
returns public.properties
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_property public.properties;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;

  insert into public.properties (name, address, currency, grace_period_days, created_by)
  values (p_name, p_address, upper(p_currency), p_grace_period_days, v_user)
  returning * into v_property;

  insert into public.memberships (property_id, user_id, role)
  values (v_property.id, v_user, 'owner');

  return v_property;
end;
$$;

-- Records a rent payment for `p_periods` periods, moves paid_until forward and
-- issues the next receipt number. All-or-nothing (one transaction).
-- Returns no money figures, so it is safe for caretakers to call.
create function public.record_payment(
  p_tenancy_id uuid,
  p_periods    int,
  p_paid_on    date default current_date,
  p_method     text default null,
  p_reference  text default null,
  p_amount     bigint default null   -- null = rent_amount * periods
)
returns table (payment_id uuid, receipt_number text, paid_until date)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenancy public.tenancies;
  v_new_paid_until date;
  v_payment_id uuid;
  v_total_periods int;
  v_year int := extract(year from now() at time zone 'utc')::int;
  v_number int;
  v_receipt text;
begin
  -- FOR UPDATE locks the tenancy row so two payments at once can't both read
  -- the same paid_until.
  select * into v_tenancy from public.tenancies where id = p_tenancy_id for update;

  if not found or not public.can_record_payments(v_tenancy.property_id) then
    raise exception 'Tenancy not found or not allowed';
  end if;
  if v_tenancy.status <> 'active' then
    raise exception 'Cannot record a payment on an ended tenancy';
  end if;
  if p_periods is null or p_periods < 1 or p_periods > 60 then
    raise exception 'Periods must be between 1 and 60';
  end if;

  -- New due date = billing start + ALL non-voided periods (including these).
  -- Always counting from the fixed start keeps month-end dates exact:
  -- Jan 31 + 2 months = Mar 31, whereas adding one month at a time would give
  -- Jan 31 -> Feb 28 -> Mar 28. void_payment() uses the same calculation.
  select coalesce(sum(p.periods), 0) + p_periods into v_total_periods
  from public.payments p
  where p.tenancy_id = v_tenancy.id
    and not exists (select 1 from public.payment_voids v where v.payment_id = p.id);

  v_new_paid_until := (v_tenancy.billing_start_date
                       + v_total_periods * public.period_interval(v_tenancy.frequency))::date;

  insert into public.payments (
    property_id, tenancy_id, amount, periods, period_start, period_end,
    paid_on, method, reference, recorded_by
  ) values (
    v_tenancy.property_id, v_tenancy.id,
    coalesce(p_amount, v_tenancy.rent_amount * p_periods), p_periods,
    v_tenancy.paid_until, v_new_paid_until,
    coalesce(p_paid_on, current_date), p_method, p_reference, auth.uid()
  ) returning id into v_payment_id;

  update public.tenancies set paid_until = v_new_paid_until where id = v_tenancy.id;

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

-- Voids a payment (owners/managers only). The payment row is untouched; a
-- void row is added and paid_until is recalculated from all non-voided payments.
create function public.void_payment(p_payment_id uuid, p_reason text)
returns date   -- the tenancy's new paid_until
language plpgsql security definer set search_path = ''
as $$
declare
  v_payment public.payments;
  v_tenancy public.tenancies;
  v_total_periods int;
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

  -- Recalculate from the billing start (same method as record_payment()).
  -- Subtracting months would be wrong: "Mar 31 - 1 month" is Feb 28, not the
  -- date we started from.
  select coalesce(sum(p.periods), 0) into v_total_periods
  from public.payments p
  where p.tenancy_id = v_tenancy.id
    and not exists (select 1 from public.payment_voids v where v.payment_id = p.id);

  v_new_paid_until := (v_tenancy.billing_start_date
                       + v_total_periods * public.period_interval(v_tenancy.frequency))::date;

  update public.tenancies set paid_until = v_new_paid_until where id = v_tenancy.id;
  return v_new_paid_until;
end;
$$;

-- "Link later": after a tenant signs up and confirms their email, the app calls
-- this once (e.g. after login). Any tenant contacts with that email get linked
-- to the account. Only confirmed emails count, so nobody can claim someone
-- else's tenancy by signing up with their address.
create function public.link_my_tenant_records()
returns int   -- how many contacts were linked
language plpgsql security definer set search_path = ''
as $$
declare
  v_email text;
  v_count int;
begin
  select lower(u.email) into v_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;

  if v_email is null then
    return 0;
  end if;

  update public.tenants set user_id = auth.uid()
  where user_id is null and email = v_email;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


-- -----------------------------------------------------------------------------
-- Caretaker-safe view (business rule 5: caretakers never see money)
--
-- RLS can hide whole rows but not individual columns, so caretakers can't read
-- `tenancies` directly (it has rent_amount). Instead every staff member and
-- tenant can read this view: same tenancies, no money columns, plus the
-- computed rent status. The WHERE clause does the access check because the
-- view runs with its owner's rights (security_invoker = false).
-- -----------------------------------------------------------------------------

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
  ty.frequency,
  ty.start_date,
  ty.end_date,
  ty.paid_until,
  ty.status,
  case when ty.status = 'active'
       then public.rent_status(ty.paid_until, p.grace_period_days) end as rent_status
from public.tenancies ty
join public.apartments a on a.id = ty.apartment_id
join public.tenants    t on t.id = ty.tenant_id
join public.properties p on p.id = ty.property_id
where public.is_property_member(ty.property_id)
   or t.user_id = (select auth.uid());


-- -----------------------------------------------------------------------------
-- Row-level security policies
-- -----------------------------------------------------------------------------

alter table public.profiles         enable row level security;
alter table public.properties       enable row level security;
alter table public.memberships      enable row level security;
alter table public.apartments       enable row level security;
alter table public.tenants          enable row level security;
alter table public.tenancies        enable row level security;
alter table public.payments         enable row level security;
alter table public.payment_voids    enable row level security;
alter table public.receipts         enable row level security;
alter table public.receipt_counters enable row level security;  -- no policies: RPC-only

-- profiles: see yourself and people you share a property with; edit only yourself.
create policy "profiles: read own and co-members" on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.memberships m
      where m.user_id = profiles.id and public.is_property_member(m.property_id)
    )
  );
create policy "profiles: update own" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- properties: staff and linked tenants can read; owner/manager edit; owner deletes.
-- (Creating goes through create_property(), so there is no insert policy.)
create policy "properties: read" on public.properties for select to authenticated
  using (public.is_property_member(id) or public.is_tenant_in_property(id));
create policy "properties: update" on public.properties for update to authenticated
  using (public.has_property_role(id, '{owner,manager}'))
  with check (public.has_property_role(id, '{owner,manager}'));
create policy "properties: delete" on public.properties for delete to authenticated
  using (public.has_property_role(id, '{owner}'));

-- memberships: staff see the team; only owners manage it.
create policy "memberships: read" on public.memberships for select to authenticated
  using (public.is_property_member(property_id));
create policy "memberships: insert" on public.memberships for insert to authenticated
  with check (public.has_property_role(property_id, '{owner}'));
create policy "memberships: update" on public.memberships for update to authenticated
  using (public.has_property_role(property_id, '{owner}'))
  with check (public.has_property_role(property_id, '{owner}'));
create policy "memberships: delete" on public.memberships for delete to authenticated
  using (public.has_property_role(property_id, '{owner}'));

-- apartments: staff read; tenants read apartments they rent; owner/manager write.
create policy "apartments: read" on public.apartments for select to authenticated
  using (
    public.is_property_member(property_id)
    or exists (
      select 1 from public.tenancies ty join public.tenants t on t.id = ty.tenant_id
      where ty.apartment_id = apartments.id and t.user_id = (select auth.uid())
    )
  );
create policy "apartments: insert" on public.apartments for insert to authenticated
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "apartments: update" on public.apartments for update to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'))
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "apartments: delete" on public.apartments for delete to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'));

-- tenants (contacts): all staff read (caretakers need names/phones for tickets);
-- a tenant reads their own contact; owner/manager write.
create policy "tenants: read" on public.tenants for select to authenticated
  using (public.is_property_member(property_id) or user_id = (select auth.uid()));
create policy "tenants: insert" on public.tenants for insert to authenticated
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "tenants: update" on public.tenants for update to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'))
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "tenants: delete" on public.tenants for delete to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'));

-- tenancies: contains rent_amount, so only owner/manager and the tenant
-- themselves can read it. Caretakers use tenancy_overview instead.
-- No delete: tenancies are history. End them by setting status = 'ended'.
create policy "tenancies: read" on public.tenancies for select to authenticated
  using (
    public.has_property_role(property_id, '{owner,manager}')
    or public.is_tenant_of_tenancy(id)
  );
create policy "tenancies: insert" on public.tenancies for insert to authenticated
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "tenancies: update" on public.tenancies for update to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'))
  with check (public.has_property_role(property_id, '{owner,manager}'));

-- payments / voids / receipts: read-only for owner/manager and the tenant.
-- Written only by record_payment() / void_payment(). No update/delete policies
-- exist, and the privileges below also forbid it (business rule 2).
create policy "payments: read" on public.payments for select to authenticated
  using (
    public.has_property_role(property_id, '{owner,manager}')
    or public.is_tenant_of_tenancy(tenancy_id)
  );
create policy "payment_voids: read" on public.payment_voids for select to authenticated
  using (
    public.has_property_role(property_id, '{owner,manager}')
    or exists (
      select 1 from public.payments p
      where p.id = payment_voids.payment_id and public.is_tenant_of_tenancy(p.tenancy_id)
    )
  );
create policy "receipts: read" on public.receipts for select to authenticated
  using (
    public.has_property_role(property_id, '{owner,manager}')
    or exists (
      select 1 from public.payments p
      where p.id = receipts.payment_id and public.is_tenant_of_tenancy(p.tenancy_id)
    )
  );


-- -----------------------------------------------------------------------------
-- Privileges (a second lock on top of RLS)
--
-- Supabase grants every table to anon/authenticated by default. We tighten
-- that: anon gets nothing, and authenticated only gets the operations the
-- app actually needs. Even a mistaken policy can't allow what isn't granted.
-- NOTE: later migrations that add tables must add their own grants the same way.
-- -----------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon;

grant select                 on public.profiles    to authenticated;
grant select, delete         on public.properties  to authenticated;
grant select, insert, delete on public.memberships to authenticated;
grant select, insert, delete on public.apartments  to authenticated;
grant select, insert, delete on public.tenants     to authenticated;
grant select, insert         on public.tenancies   to authenticated;
grant select on public.payments, public.payment_voids, public.receipts to authenticated;
grant select on public.tenancy_overview to authenticated;

-- UPDATE is granted per column: only the fields listed can ever be changed.
-- Ids, property_id, created_by etc. are never editable, so rows can't be
-- moved between properties.
grant update (full_name, phone)                             on public.profiles    to authenticated;
grant update (name, address, currency, grace_period_days)   on public.properties  to authenticated;
grant update (role, can_record_payments)                    on public.memberships to authenticated;
grant update (name, description)                            on public.apartments  to authenticated;
-- tenants.user_id is missing on purpose: only link_my_tenant_records() sets it,
-- so staff can't attach someone else's account to a tenant contact.
grant update (full_name, phone, email)                      on public.tenants     to authenticated;
-- tenancies: paid_until is missing (only the payment functions change it), as
-- are frequency and billing_start_date (changing them would rewrite payment
-- history; end the tenancy and start a new one instead).
grant update (rent_amount, end_date, status, ended_at, notes) on public.tenancies to authenticated;

-- Functions the app may call.
grant execute on function public.create_property(text, text, text, int)                  to authenticated;
grant execute on function public.record_payment(uuid, int, date, text, text, bigint)     to authenticated;
grant execute on function public.void_payment(uuid, text)                                to authenticated;
grant execute on function public.link_my_tenant_records()                                to authenticated;
-- Helpers are used inside policies, which run as the calling user.
grant execute on function public.is_property_member(uuid)                                to authenticated;
grant execute on function public.has_property_role(uuid, public.membership_role[])       to authenticated;
grant execute on function public.can_record_payments(uuid)                               to authenticated;
grant execute on function public.is_tenant_of_tenancy(uuid)                              to authenticated;
grant execute on function public.is_tenant_in_property(uuid)                             to authenticated;
grant execute on function public.period_interval(public.rent_frequency)                  to authenticated;
grant execute on function public.rent_status(date, int)                                  to authenticated;
