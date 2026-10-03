-- =============================================================================
-- 1. Only landlord accounts may create properties.
--    Tenants and team members signed up for something else; the app hides
--    "Add property" for them, and this makes the database refuse it too.
--    (The app admin may as well, e.g. for testing.)
-- 2. Tenancy agreement: before a tenant sees their rental, they accept the
--    tenancy agreement. tenancies.agreement_accepted_at records when.
--    Only the linked tenant can accept, through accept_tenancy_agreement();
--    staff can't set it for them (no update grant on that column).
-- =============================================================================


-- 1. Landlords only ------------------------------------------------------------------

create or replace function public.create_property(
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
  if not exists (select 1 from public.profiles where id = v_user and account_type = 'landlord')
     and not public.is_app_admin() then
    raise exception 'Only landlord accounts can add properties.';
  end if;

  insert into public.properties (name, address, currency, grace_period_days, created_by)
  values (p_name, p_address, upper(p_currency), p_grace_period_days, v_user)
  returning * into v_property;

  insert into public.memberships (property_id, user_id, role)
  values (v_property.id, v_user, 'owner');

  return v_property;
end;
$$;


-- 2. Tenancy agreement ----------------------------------------------------------------

alter table public.tenancies add column agreement_accepted_at timestamptz;

create function public.accept_tenancy_agreement(p_tenancy_id uuid)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  v_accepted timestamptz;
begin
  if not public.is_tenant_of_tenancy(p_tenancy_id) then
    raise exception 'Only the tenant can accept their tenancy agreement.';
  end if;

  update public.tenancies
  set agreement_accepted_at = coalesce(agreement_accepted_at, now())
  where id = p_tenancy_id
  returning agreement_accepted_at into v_accepted;

  return v_accepted;
end;
$$;

-- The overview view again, now with agreement_accepted_at (not money, so
-- caretakers may see it). Same as 20261001170000 otherwise.
drop view public.tenancy_overview;
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
  (select coalesce(sum(p.months), 0)::int
     from public.payments p
    where p.tenancy_id = ty.id and p.kind = 'rent'
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id)
  ) as paid_months,
  ty.status,
  case when ty.status = 'active'
       then public.rent_status(ty.paid_until, p.grace_period_days) end as rent_status,
  ty.agreement_accepted_at
from public.tenancies ty
join public.apartments a on a.id = ty.apartment_id
join public.tenants    t on t.id = ty.tenant_id
join public.properties p on p.id = ty.property_id
where public.is_property_member(ty.property_id)
   or t.user_id = (select auth.uid())
   or public.is_app_admin();
grant select on public.tenancy_overview to authenticated;

revoke execute on function public.accept_tenancy_agreement(uuid) from public, anon;
grant  execute on function public.accept_tenancy_agreement(uuid) to authenticated;
