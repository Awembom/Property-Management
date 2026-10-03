-- =============================================================================
-- Unit page, repairs, waived bills, own tenancy agreements, contact phone.
--
-- 1. properties.contact_phone: the number tenants tap to call (the owner's or
--    a caretaker's). Tenants can already read their property's row.
-- 2. Tenancy agreements written by the owner: one text per property, and
--    optionally a different one for a unit. NULL = the app's default text.
--    Changing the text that applies to a current tenant clears their
--    acceptance: they must accept the new version (decided 2026-10-02). The
--    exact text each tenant accepted is kept on the tenancy.
-- 3. Bills can be waived per apartment (the tenant doesn't have to pay it),
--    with a reason; needs the 'payments' permission like marking paid.
--    A third standard bill type, "Repairs", for billing a repair.
-- 4. Repairs: a simple log per unit (what, when, cost, optional issue it
--    fixed, optional bill to the tenant). Costs only for staff who may see
--    money, so the log is read through apartment_repairs().
-- =============================================================================


-- 1. Contact phone -------------------------------------------------------------------------

alter table public.properties add column contact_phone text;
grant update (contact_phone) on public.properties to authenticated;


-- 2. Tenancy agreements -----------------------------------------------------------------

alter table public.properties add column agreement_text text;
alter table public.apartments add column agreement_text text;
alter table public.tenancies  add column agreement_accepted_text text;

-- Sets the agreement for a whole property (p_apartment_id null) or for one
-- unit. Empty text = back to the default (the property's text for a unit,
-- the app's text for a property). Returns how many current tenants must
-- accept it again.
create function public.set_agreement(p_property_id uuid, p_apartment_id uuid, p_text text)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_text text := nullif(trim(p_text), '');
  v_old text;
  v_count int := 0;
begin
  if not public.has_permission(p_property_id, 'apartments') then
    raise exception 'You don''t have permission to change the tenancy agreement.';
  end if;

  if p_apartment_id is null then
    select agreement_text into v_old from public.properties where id = p_property_id;
    if v_old is distinct from v_text then
      update public.properties set agreement_text = v_text where id = p_property_id;
      -- Current tenants whose unit uses the property's text accept again.
      update public.tenancies ty set agreement_accepted_at = null
      from public.apartments a
      where a.id = ty.apartment_id and ty.property_id = p_property_id
        and ty.status = 'active' and a.agreement_text is null
        and ty.agreement_accepted_at is not null;
      get diagnostics v_count = row_count;
    end if;
  else
    select agreement_text into v_old from public.apartments
    where id = p_apartment_id and property_id = p_property_id;
    if not found then
      raise exception 'Apartment not found.';
    end if;
    if v_old is distinct from v_text then
      update public.apartments set agreement_text = v_text where id = p_apartment_id;
      update public.tenancies set agreement_accepted_at = null
      where apartment_id = p_apartment_id and status = 'active' and agreement_accepted_at is not null;
      get diagnostics v_count = row_count;
    end if;
  end if;
  return v_count;
end;
$$;

-- The tenant accepts their agreement; the text they accepted is kept.
create or replace function public.accept_tenancy_agreement(p_tenancy_id uuid)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  v_accepted timestamptz;
begin
  if not public.is_tenant_of_tenancy(p_tenancy_id) then
    raise exception 'Only the tenant can accept their tenancy agreement.';
  end if;

  update public.tenancies ty
  set agreement_accepted_at = coalesce(ty.agreement_accepted_at, now()),
      agreement_accepted_text = case when ty.agreement_accepted_at is null
                                     then coalesce(a.agreement_text, p.agreement_text)
                                     else ty.agreement_accepted_text end
  from public.apartments a, public.properties p
  where ty.id = p_tenancy_id and a.id = ty.apartment_id and p.id = ty.property_id
  returning ty.agreement_accepted_at into v_accepted;

  return v_accepted;
end;
$$;

-- The overview view again, plus the agreement text that applies (null = the
-- app's default). Same as 20261002100000 otherwise.
create or replace view public.tenancy_overview
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
  (select coalesce(sum(p.months), 0)::int
     from public.payments p
    where p.tenancy_id = ty.id and p.kind = 'rent'
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id)
  ) as paid_months,
  ty.status,
  case when ty.status = 'active'
       then public.rent_status(ty.paid_until, p.grace_period_days) end as rent_status,
  ty.agreement_accepted_at,
  coalesce(a.agreement_text, p.agreement_text) as agreement_text
from public.tenancies ty
join public.apartments a on a.id = ty.apartment_id
join public.tenants    t on t.id = ty.tenant_id
join public.properties p on p.id = ty.property_id
where public.is_property_member(ty.property_id)
   or t.user_id = (select auth.uid())
   or public.is_app_admin();
grant select on public.tenancy_overview to authenticated;


-- 3. Waived bills, "Repairs" bill type ------------------------------------------------------

alter table public.bill_assignments
  add column waived_at    timestamptz,
  add column waive_reason text,
  add column waived_by    uuid references auth.users (id) on delete set null;

-- Waive (p_waived) or un-waive one apartment's part of a bill.
create function public.set_bill_waived(p_assignment_id uuid, p_waived boolean, p_reason text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_row public.bill_assignments;
begin
  select * into v_row from public.bill_assignments where id = p_assignment_id;
  if not found or not public.has_permission(v_row.property_id, 'payments') then
    raise exception 'You don''t have permission to waive bills.';
  end if;
  if p_waived and v_row.paid_at is not null then
    raise exception 'This bill is already paid.';
  end if;
  if p_waived and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'Give a reason for waiving the bill.';
  end if;
  update public.bill_assignments
  set waived_at    = case when p_waived then now() end,
      waive_reason = case when p_waived then trim(p_reason) end,
      waived_by    = case when p_waived then auth.uid() end
  where id = p_assignment_id;
end;
$$;

-- Marking paid: not for a waived bill (un-waive it first).
create or replace function public.set_bill_paid(p_assignment_id uuid, p_paid boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_row public.bill_assignments;
begin
  select * into v_row from public.bill_assignments where id = p_assignment_id;
  if not found or not public.has_permission(v_row.property_id, 'payments') then
    raise exception 'You don''t have permission to mark bills as paid.';
  end if;
  if p_paid and v_row.waived_at is not null then
    raise exception 'This bill was waived. Undo the waiver first.';
  end if;
  update public.bill_assignments
  set paid_at = case when p_paid then coalesce(paid_at, now()) end,
      marked_by = auth.uid()
  where id = p_assignment_id;
end;
$$;

-- New properties get Water, Electricity and Repairs...
create or replace function public.add_standard_bill_types()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.bill_types (property_id, name, is_standard)
  values (new.id, 'Water', true), (new.id, 'Electricity', true), (new.id, 'Repairs', true);
  return null;
end;
$$;
-- ...and existing ones get Repairs (a custom type of that name becomes standard).
update public.bill_types set is_standard = true where name = 'Repairs';
insert into public.bill_types (property_id, name, is_standard)
select p.id, 'Repairs', true from public.properties p
where not exists (select 1 from public.bill_types b where b.property_id = p.id and b.name = 'Repairs');

create or replace function public.bill_type_guard()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.is_standard and new.name <> old.name then
    raise exception 'Standard bill types can''t be renamed; switch them off instead.';
  end if;
  return new;
end;
$$;


-- 4. Repairs -------------------------------------------------------------------------------

create table public.repairs (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  apartment_id uuid not null references public.apartments (id) on delete cascade,
  tenancy_id   uuid references public.tenancies (id) on delete set null,  -- who lived there
  ticket_id    uuid references public.tickets (id) on delete set null,    -- the issue it fixed
  bill_id      uuid references public.bills (id) on delete set null,      -- if the tenant was billed
  title        text not null check (length(trim(title)) > 0),
  details      text,
  repaired_on  date not null default current_date,
  cost         bigint check (cost is null or cost >= 0),  -- smallest currency unit
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index on public.repairs (apartment_id, repaired_on desc);

-- No direct access: the app reads through apartment_repairs() (which hides
-- costs from staff who may not see money) and writes through add_repair().
alter table public.repairs enable row level security;
create policy "repairs: app admin reads" on public.repairs for select to authenticated
  using (public.is_app_admin());
grant select on public.repairs to authenticated;

create trigger log_activity after insert or delete on public.repairs
  for each row execute function public.log_activity();

-- A unit's repairs, newest first. cost is null for staff without 'money'.
create function public.apartment_repairs(p_apartment_id uuid)
returns table (
  id uuid, apartment_id uuid, tenancy_id uuid, ticket_id uuid, bill_id uuid,
  title text, details text, repaired_on date, cost bigint, created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_property_id uuid;
  v_money boolean;
begin
  select property_id into v_property_id from public.apartments where apartments.id = p_apartment_id;
  if v_property_id is null
     or not (public.is_property_member(v_property_id) or public.is_app_admin()) then
    return;
  end if;
  v_money := public.has_permission(v_property_id, 'money') or public.is_app_admin();
  return query
    select r.id, r.apartment_id, r.tenancy_id, r.ticket_id, r.bill_id, r.title, r.details,
           r.repaired_on, case when v_money then r.cost end, r.created_at
    from public.repairs r
    where r.apartment_id = p_apartment_id
    order by r.repaired_on desc, r.created_at desc;
end;
$$;

-- Logs a repair (any team member). Optionally bills the current tenant for
-- it (p_bill_amount, due p_bill_due) with the "Repairs" bill type.
create function public.add_repair(
  p_apartment_id uuid,
  p_title        text,
  p_details      text default null,
  p_repaired_on  date default null,
  p_cost         bigint default null,
  p_ticket_id    uuid default null,
  p_bill_amount  bigint default null,
  p_bill_due     date default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_apartment public.apartments;
  v_tenancy_id uuid;
  v_type_id uuid;
  v_bill_id uuid;
  v_id uuid;
begin
  select * into v_apartment from public.apartments where id = p_apartment_id;
  if not found or not public.is_property_member(v_apartment.property_id) then
    raise exception 'Only the property''s team can log repairs.';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'Say what was repaired.';
  end if;
  if p_ticket_id is not null and not exists (
       select 1 from public.tickets k join public.tenancies ty on ty.id = k.tenancy_id
       where k.id = p_ticket_id and ty.apartment_id = p_apartment_id) then
    raise exception 'That issue is not from this unit.';
  end if;

  select id into v_tenancy_id from public.tenancies
  where apartment_id = p_apartment_id and status = 'active';

  if coalesce(p_bill_amount, 0) > 0 then
    if v_tenancy_id is null then
      raise exception 'No one lives in this unit, so there is no one to bill.';
    end if;
    select id into v_type_id from public.bill_types
    where property_id = v_apartment.property_id and name = 'Repairs';
    v_bill_id := public.create_bill(
      v_apartment.property_id, v_type_id, coalesce(p_bill_due, current_date + 14), p_bill_amount,
      'Repair: ' || trim(p_title), nullif(trim(p_details), ''), array[v_tenancy_id]);
  end if;

  insert into public.repairs (property_id, apartment_id, tenancy_id, ticket_id, bill_id, title, details,
                              repaired_on, cost, created_by)
  values (v_apartment.property_id, p_apartment_id, v_tenancy_id, p_ticket_id, v_bill_id, trim(p_title),
          nullif(trim(p_details), ''), coalesce(p_repaired_on, current_date),
          -- Only staff who may see money can record what it cost.
          case when public.has_permission(v_apartment.property_id, 'money') then p_cost end,
          auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Removes a repair from the log (whoever logged it, or staff who manage
-- apartments). A bill made for it stays (waive it if needed).
create function public.delete_repair(p_repair_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_repair public.repairs;
begin
  select * into v_repair from public.repairs where id = p_repair_id;
  if not found or not (public.has_permission(v_repair.property_id, 'apartments')
                       or (v_repair.created_by = auth.uid() and public.is_property_member(v_repair.property_id))) then
    raise exception 'You can''t remove this repair.';
  end if;
  delete from public.repairs where id = p_repair_id;
end;
$$;


-- Grants ---------------------------------------------------------------------------------

revoke execute on function public.set_agreement(uuid, uuid, text) from public, anon;
grant  execute on function public.set_agreement(uuid, uuid, text) to authenticated;
revoke execute on function public.set_bill_waived(uuid, boolean, text) from public, anon;
grant  execute on function public.set_bill_waived(uuid, boolean, text) to authenticated;
revoke execute on function public.apartment_repairs(uuid) from public, anon;
grant  execute on function public.apartment_repairs(uuid) to authenticated;
revoke execute on function public.add_repair(uuid, text, text, date, bigint, uuid, bigint, date) from public, anon;
grant  execute on function public.add_repair(uuid, text, text, date, bigint, uuid, bigint, date) to authenticated;
revoke execute on function public.delete_repair(uuid) from public, anon;
grant  execute on function public.delete_repair(uuid) to authenticated;
