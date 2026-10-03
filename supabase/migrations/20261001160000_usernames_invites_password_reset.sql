-- =============================================================================
-- Phase 2b: username login, tenant invite codes, password reset
--
-- 1. Usernames. People log in with a username + password. Supabase Auth
--    still needs an email, so the app signs them up as
--    <username>@users.rentalapp.invalid (".invalid" can never be a real
--    domain, so no email is ever sent to anyone). The username is kept in
--    profiles.username.
-- 2. Team members are added by username instead of email.
-- 3. Tenant invite codes. Staff create a one-time code for a tenant contact;
--    the tenant signs up and enters it, which links their account to that
--    contact (and so to their tenancies and receipts). Wrong guesses are
--    limited to 10 per hour per account.
-- 4. Password reset. With no email, an owner/manager can give someone a
--    temporary password through the `reset-password` Edge Function, which
--    asks password_reset_target() whether it's allowed. The user must then
--    choose a new password (flag in their auth app_metadata, which users
--    can't edit themselves).
-- =============================================================================


-- 1. Usernames -------------------------------------------------------------------

-- 3-30 characters: lower-case letters, digits, dots and underscores,
-- starting with a letter or digit.
alter table public.profiles add column username text
  check (username ~ '^[a-z0-9][a-z0-9._]{2,29}$');
create unique index profiles_username_key on public.profiles (username);

-- Sign-up trigger: also store the username (sent by the app as metadata;
-- otherwise taken from the part of the email before the @).
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_username text := lower(coalesce(
    new.raw_user_meta_data ->> 'username',
    split_part(new.email, '@', 1)
  ));
begin
  -- Users created another way (e.g. the Supabase dashboard) may not have a
  -- usable username; leave it empty rather than block the sign-up.
  if v_username !~ '^[a-z0-9][a-z0-9._]{2,29}$'
     or exists (select 1 from public.profiles where username = v_username) then
    v_username := null;
  end if;

  insert into public.profiles (id, full_name, phone, email, username)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.phone, lower(new.email), v_username);
  return new;
end;
$$;


-- 2. Add team members by username ------------------------------------------------

drop function public.add_property_member(uuid, text, public.membership_role, boolean);

create function public.add_property_member(
  p_property_id          uuid,
  p_username             text,
  p_role                 public.membership_role,
  p_can_record_payments  boolean default false
)
returns public.memberships
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid;
  v_membership public.memberships;
begin
  if not public.has_property_role(p_property_id, '{owner}') then
    raise exception 'Only owners can add members.';
  end if;

  select p.id into v_user_id
  from public.profiles p
  where p.username = lower(trim(p_username));

  if v_user_id is null then
    raise exception 'No account has this username. Ask them to sign up in the app first.';
  end if;

  if exists (
    select 1 from public.memberships
    where property_id = p_property_id and user_id = v_user_id
  ) then
    raise exception 'This person is already a member of this property.';
  end if;

  insert into public.memberships (property_id, user_id, role, can_record_payments)
  values (
    p_property_id, v_user_id, p_role,
    p_role = 'caretaker' and coalesce(p_can_record_payments, false)
  )
  returning * into v_membership;

  return v_membership;
end;
$$;


-- 3. Tenant invite codes -----------------------------------------------------------

create table public.tenant_invites (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null,
  tenant_id    uuid not null,
  code         text not null unique,     -- e.g. TEN-4K7Q9M
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  redeemed_at  timestamptz,
  redeemed_by  uuid references auth.users (id) on delete set null,
  cancelled_at timestamptz,
  foreign key (tenant_id, property_id)
    references public.tenants (id, property_id) on delete cascade
);

create index on public.tenant_invites (tenant_id);

alter table public.tenant_invites enable row level security;

-- Owners/managers see their property's codes. Everything else goes through
-- the functions below, so there are no write policies.
create policy "tenant_invites: read" on public.tenant_invites for select to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'));

grant select on public.tenant_invites to authenticated;

-- Wrong codes typed by each account, to stop people guessing codes.
-- No policies and no grants: only redeem_tenant_invite() uses it.
create table public.invite_attempts (
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index on public.invite_attempts (user_id, created_at);
alter table public.invite_attempts enable row level security;

-- TEN- + 6 characters that can't be confused (no 0/O, 1/I/L).
create function public.new_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  v_chars constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_code text;
begin
  loop
    v_code := 'TEN-';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    end loop;
    exit when not exists (select 1 from public.tenant_invites where code = v_code);
  end loop;
  return v_code;
end;
$$;

-- A new code for a tenant contact (owners/managers). Any older open code for
-- that tenant stops working. Valid for 7 days.
create function public.create_tenant_invite(p_tenant_id uuid)
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant public.tenants;
  v_code text := public.new_invite_code();
  v_expires timestamptz := now() + interval '7 days';
begin
  select * into v_tenant from public.tenants where id = p_tenant_id;
  if not found or not public.has_property_role(v_tenant.property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can invite tenants.';
  end if;
  if v_tenant.user_id is not null then
    raise exception 'This tenant is already using the app.';
  end if;

  update public.tenant_invites set cancelled_at = now()
  where tenant_id = p_tenant_id and redeemed_at is null and cancelled_at is null;

  insert into public.tenant_invites (property_id, tenant_id, code, created_by, expires_at)
  values (v_tenant.property_id, v_tenant.id, v_code, auth.uid(), v_expires);

  return query select v_code, v_expires;
end;
$$;

-- Stops a tenant's open code from working.
create function public.cancel_tenant_invite(p_tenant_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tenants where id = p_tenant_id;
  if v_property_id is null or not public.has_property_role(v_property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can cancel invites.';
  end if;
  update public.tenant_invites set cancelled_at = now()
  where tenant_id = p_tenant_id and redeemed_at is null and cancelled_at is null;
end;
$$;

-- The tenant enters their code. Returns {"ok": true, "property_name": ...}
-- or {"ok": false, "error": "..."}. It returns an error instead of raising
-- one so that the wrong attempt is still recorded (raising would undo it).
create function public.redeem_tenant_invite(p_code text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_invite public.tenant_invites;
  v_tenant public.tenants;
  v_property_name text;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;

  if (select count(*) from public.invite_attempts
      where user_id = v_user and created_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('ok', false,
      'error', 'Too many wrong codes. Please wait an hour and try again.');
  end if;

  select * into v_invite from public.tenant_invites
  where code = upper(trim(p_code))
    and redeemed_at is null and cancelled_at is null and expires_at > now()
  for update;

  if not found then
    insert into public.invite_attempts (user_id) values (v_user);
    return jsonb_build_object('ok', false,
      'error', 'That code is wrong, used or expired. Ask your landlord for a new one.');
  end if;

  select * into v_tenant from public.tenants where id = v_invite.tenant_id for update;
  if v_tenant.user_id is not null and v_tenant.user_id <> v_user then
    return jsonb_build_object('ok', false,
      'error', 'This tenant is already linked to another account. Ask your landlord.');
  end if;

  update public.tenants set user_id = v_user where id = v_tenant.id;
  update public.tenant_invites set redeemed_at = now(), redeemed_by = v_user
  where id = v_invite.id;

  select name into v_property_name from public.properties where id = v_tenant.property_id;
  return jsonb_build_object('ok', true,
    'property_name', v_property_name, 'tenant_name', v_tenant.full_name);
end;
$$;

-- Disconnects an app account from a tenant contact (e.g. the wrong person
-- used the code). Owners/managers. The tenancy and its history stay.
create function public.unlink_tenant_account(p_tenant_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tenants where id = p_tenant_id;
  if v_property_id is null or not public.has_property_role(v_property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can do this.';
  end if;
  update public.tenants set user_id = null where id = p_tenant_id;
end;
$$;


-- 4. Password reset -----------------------------------------------------------------

-- May the caller give user p_user_id a temporary password? Returns that user's
-- id if yes, raises an error otherwise. Called by the reset-password Edge
-- Function AS THE CALLER (with their login), before it uses admin rights.
--
-- Rules:
--  * the caller is an owner or manager of p_property_id, and not resetting
--    themselves;
--  * the target belongs to that property: a team member with a LOWER role
--    (owners reset managers and caretakers; managers reset caretakers), or a
--    tenant linked to one of its tenant contacts;
--  * the target has NO membership or tenant link in any other property, so a
--    reset can never open up someone else's property.
create function public.password_reset_target(p_property_id uuid, p_user_id uuid)
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller_role public.membership_role;
  v_target_role public.membership_role;
  v_is_tenant boolean;
begin
  select role into v_caller_role from public.memberships
  where property_id = p_property_id and user_id = auth.uid();

  if v_caller_role is null or v_caller_role = 'caretaker' then
    raise exception 'Only owners and managers can reset passwords.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'To change your own password, use your profile.';
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

-- Called by the app after the user chose a new password: clears the
-- "must change password" flag that a reset set.
create function public.password_changed()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'must_change_password'
  where id = auth.uid();
end;
$$;


-- Privileges ------------------------------------------------------------------

revoke execute on function public.add_property_member(uuid, text, public.membership_role, boolean) from public, anon;
grant  execute on function public.add_property_member(uuid, text, public.membership_role, boolean) to authenticated;
revoke execute on function public.new_invite_code() from public, anon, authenticated;
revoke execute on function public.create_tenant_invite(uuid) from public, anon;
grant  execute on function public.create_tenant_invite(uuid) to authenticated;
revoke execute on function public.cancel_tenant_invite(uuid) from public, anon;
grant  execute on function public.cancel_tenant_invite(uuid) to authenticated;
revoke execute on function public.redeem_tenant_invite(text) from public, anon;
grant  execute on function public.redeem_tenant_invite(text) to authenticated;
revoke execute on function public.unlink_tenant_account(uuid) from public, anon;
grant  execute on function public.unlink_tenant_account(uuid) to authenticated;
revoke execute on function public.password_reset_target(uuid, uuid) from public, anon;
grant  execute on function public.password_reset_target(uuid, uuid) to authenticated;
revoke execute on function public.password_changed() from public, anon;
grant  execute on function public.password_changed() to authenticated;
