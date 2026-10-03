-- =============================================================================
-- Sign-up collects a phone number (decided 2026-10-03): the app sends it as
-- '+237' + 9 digits in the sign-up details; it's copied to the profile.
-- Anything that isn't a Cameroon number in that form is ignored.
-- Same as 20261001170000 otherwise.
-- =============================================================================

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
  v_phone text := new.raw_user_meta_data ->> 'phone';
begin
  if v_username !~ '^[a-z0-9][a-z0-9._]{2,29}$'
     or exists (select 1 from public.profiles where username = v_username) then
    v_username := null;
  end if;
  if v_account_type not in ('landlord', 'tenant', 'team') then
    v_account_type := null;
  end if;
  if v_phone !~ '^\+237[26][0-9]{8}$' then
    v_phone := null;
  end if;

  insert into public.profiles (id, full_name, phone, email, username, account_type)
  values (new.id, new.raw_user_meta_data ->> 'full_name', coalesce(v_phone, new.phone), lower(new.email),
          v_username, v_account_type);
  return new;
end;
$$;
