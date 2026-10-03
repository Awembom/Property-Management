-- =============================================================================
-- Account types, super admin, activity log
--
-- 1. profiles.account_type: what the person chose at sign-up (landlord,
--    tenant or team). Only guides the app's first steps; permissions still
--    come from memberships and tenant links.
-- 2. Super admin (`app_admins`): READ-ONLY access to everything, including
--    money. There are deliberately NO insert/update/delete policies for
--    admins, so the database refuses any change they try; the payment
--    functions also check the caller is staff of that property.
--    Admins are added by hand in SQL (see the end of this file), never
--    through the app.
-- 3. activity_log: who changed what and when (before/after), filled by
--    triggers on the important tables. Only admins can read it.
-- 4. Admin tools: reset anyone's password (not other admins) through the
--    reset-password Edge Function, and transfer ownership of a property
--    (so the last owner's account can then be deleted).
-- =============================================================================


-- 1. Account type -----------------------------------------------------------------

alter table public.profiles add column account_type text
  check (account_type in ('landlord', 'tenant', 'team'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_username text := lower(coalesce(
    new.raw_user_meta_data ->> 'username',
    split_part(new.email, '@', 1)
  ));
  v_account_type text := new.raw_user_meta_data ->> 'account_type';
begin
  if v_username !~ '^[a-z0-9][a-z0-9._]{2,29}$'
     or exists (select 1 from public.profiles where username = v_username) then
    v_username := null;
  end if;
  if v_account_type not in ('landlord', 'tenant', 'team') then
    v_account_type := null;
  end if;

  insert into public.profiles (id, full_name, phone, email, username, account_type)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.phone, lower(new.email),
          v_username, v_account_type);
  return new;
end;
$$;


-- 2. Super admin --------------------------------------------------------------------

create table public.app_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
-- No policies and no grants: the app asks is_app_admin() instead.

create function public.is_app_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.app_admins where user_id = (select auth.uid()));
$$;

-- Read-only access for admins. These are extra SELECT policies; Postgres
-- combines them with the existing ones using OR.
create policy "profiles: app admin reads"          on public.profiles          for select to authenticated using (public.is_app_admin());
create policy "properties: app admin reads"        on public.properties        for select to authenticated using (public.is_app_admin());
create policy "memberships: app admin reads"       on public.memberships       for select to authenticated using (public.is_app_admin());
create policy "apartments: app admin reads"        on public.apartments        for select to authenticated using (public.is_app_admin());
create policy "apartment_rents: app admin reads"   on public.apartment_rents   for select to authenticated using (public.is_app_admin());
create policy "tenants: app admin reads"           on public.tenants           for select to authenticated using (public.is_app_admin());
create policy "tenant_identities: app admin reads" on public.tenant_identities for select to authenticated using (public.is_app_admin());
create policy "tenancies: app admin reads"         on public.tenancies         for select to authenticated using (public.is_app_admin());
create policy "tenancy_renewals: app admin reads"  on public.tenancy_renewals  for select to authenticated using (public.is_app_admin());
create policy "payments: app admin reads"          on public.payments          for select to authenticated using (public.is_app_admin());
create policy "payment_voids: app admin reads"     on public.payment_voids     for select to authenticated using (public.is_app_admin());
create policy "receipts: app admin reads"          on public.receipts          for select to authenticated using (public.is_app_admin());
create policy "tenant_invites: app admin reads"    on public.tenant_invites    for select to authenticated using (public.is_app_admin());

-- The caretaker-safe view checks access in its WHERE clause; add admins.
-- (Same definition as in 20261001140000, plus "or public.is_app_admin()".)
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
       then public.rent_status(ty.paid_until, p.grace_period_days) end as rent_status
from public.tenancies ty
join public.apartments a on a.id = ty.apartment_id
join public.tenants    t on t.id = ty.tenant_id
join public.properties p on p.id = ty.property_id
where public.is_property_member(ty.property_id)
   or t.user_id = (select auth.uid())
   or public.is_app_admin();
grant select on public.tenancy_overview to authenticated;


-- 3. Activity log -------------------------------------------------------------------

create table public.activity_log (
  id          bigint generated always as identity primary key,
  happened_at timestamptz not null default now(),
  actor_id    uuid,          -- who did it (null = the system); no foreign key, so
  property_id uuid,          -- the log survives deleted users and properties
  table_name  text not null, -- e.g. 'payments', or 'auth' for password resets
  action      text not null, -- INSERT / UPDATE / DELETE, or e.g. 'password_reset'
  row_id      text,
  old_data    jsonb,
  new_data    jsonb
);
create index on public.activity_log (happened_at desc);
create index on public.activity_log (property_id, happened_at desc);

alter table public.activity_log enable row level security;
create policy "activity_log: app admin reads" on public.activity_log
  for select to authenticated using (public.is_app_admin());
grant select on public.activity_log to authenticated;
-- No write grants: only the trigger below (and the reset-password Edge
-- Function, with admin rights) add rows. Nobody can edit or delete them.

-- One trigger function for every logged table. It reads the row as JSON, so
-- it works whatever the table's columns are.
create function public.log_activity()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
begin
  -- An UPDATE that changed nothing isn't worth a line.
  if tg_op = 'UPDATE' and v_old = v_new then
    return null;
  end if;

  insert into public.activity_log (actor_id, property_id, table_name, action, row_id, old_data, new_data)
  values (
    auth.uid(),
    (case when tg_table_name = 'properties' then v_row ->> 'id' else v_row ->> 'property_id' end)::uuid,
    tg_table_name,
    tg_op,
    coalesce(v_row ->> 'id', v_row ->> 'payment_id', v_row ->> 'tenant_id', v_row ->> 'apartment_id'),
    v_old,
    v_new
  );
  return null; -- AFTER trigger: the return value is ignored
end;
$$;

create trigger log_activity after insert or update or delete on public.properties        for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.memberships       for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.apartments        for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.apartment_rents   for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.tenants           for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.tenant_identities for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.tenancies         for each row execute function public.log_activity();
create trigger log_activity after insert                     on public.tenancy_renewals  for each row execute function public.log_activity();
create trigger log_activity after insert                     on public.payments          for each row execute function public.log_activity();
create trigger log_activity after insert                     on public.payment_voids     for each row execute function public.log_activity();
create trigger log_activity after insert or update           on public.tenant_invites    for each row execute function public.log_activity();


-- 4. Admin tools ----------------------------------------------------------------------

-- Same rules as before for owners/managers; app admins may reset anyone
-- except themselves and other admins (p_property_id may then be null).
create or replace function public.password_reset_target(p_property_id uuid, p_user_id uuid)
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller_role public.membership_role;
  v_target_role public.membership_role;
  v_is_tenant boolean;
begin
  if p_user_id = auth.uid() then
    raise exception 'To change your own password, use your profile.';
  end if;

  if public.is_app_admin() then
    if exists (select 1 from public.app_admins where user_id = p_user_id) then
      raise exception 'Another admin''s password can only be reset in the Supabase dashboard.';
    end if;
    if not exists (select 1 from auth.users where id = p_user_id) then
      raise exception 'No such account.';
    end if;
    return p_user_id;
  end if;

  select role into v_caller_role from public.memberships
  where property_id = p_property_id and user_id = auth.uid();

  if v_caller_role is null or v_caller_role = 'caretaker' then
    raise exception 'Only owners and managers can reset passwords.';
  end if;

  select role into v_target_role from public.memberships
  where property_id = p_property_id and user_id = p_user_id;
  v_is_tenant := exists (
    select 1 from public.tenants where property_id = p_property_id and user_id = p_user_id
  );

  if v_target_role is null and not v_is_tenant then
    raise exception 'This person isn''t part of this property.';
  end if;
  if v_target_role = 'owner'
     or (v_target_role = 'manager' and v_caller_role <> 'owner') then
    raise exception 'You can only reset passwords for people below your role.';
  end if;

  if exists (select 1 from public.memberships
             where user_id = p_user_id and property_id <> p_property_id)
     or exists (select 1 from public.tenants
                where user_id = p_user_id and property_id <> p_property_id) then
    raise exception 'This person also uses other properties. Ask the app admin to reset their password.';
  end if;

  return p_user_id;
end;
$$;

-- Makes the person with this username an owner of the property (admins only).
-- Not a financial change: it only decides who manages the property. The
-- previous owners stay owners; an owner can then remove them in Team.
create function public.admin_transfer_ownership(p_property_id uuid, p_username text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if not public.is_app_admin() then
    raise exception 'Only the app admin can transfer ownership.';
  end if;
  if not exists (select 1 from public.properties where id = p_property_id) then
    raise exception 'Property not found.';
  end if;

  select id into v_user_id from public.profiles where username = lower(trim(p_username));
  if v_user_id is null then
    raise exception 'No account has this username.';
  end if;

  insert into public.memberships (property_id, user_id, role)
  values (p_property_id, v_user_id, 'owner')
  on conflict (property_id, user_id)
    do update set role = 'owner', can_record_payments = false;
end;
$$;


-- Privileges ---------------------------------------------------------------------------

revoke execute on function public.is_app_admin() from public, anon;
grant  execute on function public.is_app_admin() to authenticated;
revoke execute on function public.log_activity() from public, anon, authenticated;
revoke execute on function public.admin_transfer_ownership(uuid, text) from public, anon;
grant  execute on function public.admin_transfer_ownership(uuid, text) to authenticated;

-- To make someone the super admin, run in the SQL editor (as the project owner):
--   insert into public.app_admins (user_id)
--   select id from public.profiles where username = 'their_username';
