-- =============================================================================
-- Phase 3: property members
--
-- 1. profiles.email: so the members screen can show each member's email.
--    Kept in sync with auth.users by triggers. Only visible to people who
--    share a property with you (existing profiles RLS policy).
-- 2. memberships.user_id -> profiles: lets the app load members together
--    with their name/email in one query.
-- 3. add_property_member(): owners add staff by email.
-- =============================================================================

-- 1. Email on profiles ---------------------------------------------------------

alter table public.profiles add column email text;

update public.profiles p
set email = lower(u.email)
from auth.users u
where u.id = p.id;

-- Replace the sign-up trigger function so new profiles get the email too.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, email)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.phone, lower(new.email));
  return new;
end;
$$;

-- Keep it in sync if a user changes their email.
create function public.sync_profile_email()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.profiles set email = lower(new.email) where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed after update of email on auth.users
  for each row execute function public.sync_profile_email();


-- 2. Let the app join memberships -> profiles -------------------------------------
-- profiles.id is the same value as auth.users.id, and every user has a
-- profile, so this second foreign key is always satisfied. PostgREST uses it
-- to allow `memberships.select('..., profiles(full_name, email)')`.

alter table public.memberships
  add constraint memberships_user_profile_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;


-- 3. Add a member by email -------------------------------------------------------

-- Owners only. The person must already have an account (they sign up first).
-- security definer because it needs to look up auth.users by email, which
-- normal users can't read.
create function public.add_property_member(
  p_property_id          uuid,
  p_email                text,
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

  select u.id into v_user_id
  from auth.users u
  where lower(u.email) = lower(trim(p_email));

  if v_user_id is null then
    raise exception 'No account uses this email. Ask them to sign up in the app first.';
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
    -- The toggle only means something for caretakers.
    p_role = 'caretaker' and coalesce(p_can_record_payments, false)
  )
  returning * into v_membership;

  return v_membership;
end;
$$;

revoke execute on function public.add_property_member(uuid, text, public.membership_role, boolean) from public, anon;
grant  execute on function public.add_property_member(uuid, text, public.membership_role, boolean) to authenticated;
revoke execute on function public.sync_profile_email() from public, anon, authenticated;
