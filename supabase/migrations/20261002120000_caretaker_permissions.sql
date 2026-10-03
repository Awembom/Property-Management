-- =============================================================================
-- Caretaker permissions
--
-- Owners can give a caretaker any of these switches (all of them together =
-- "full access", the same as an owner):
--   can_record_payments    (existed) record rent payments
--   can_see_money          rent amounts, payments, receipts, balances, ID numbers
--   can_manage_apartments  add/edit apartments and their rent, edit the
--                          property details, manage bill types
--   can_manage_tenancies   tenants, tenancies (start/renew/end), invite codes,
--                          tenant password resets
--   can_manage_team        add/change/remove managers and caretakers
-- Always owner-only, whatever the switches: deleting the property, and
-- adding, changing or removing OWNERS (so nobody can take a property over).
--
-- Everything that used to say "owner or manager" now asks has_permission(),
-- which knows these switches. Managers keep what they had (everything except
-- the team).
--
-- Also: caretakers' passwords can no longer be reset by owners or managers,
-- only by the app admin.
-- =============================================================================


-- 1. The switches ---------------------------------------------------------------------

alter table public.memberships
  add column can_see_money          boolean not null default false,
  add column can_manage_apartments  boolean not null default false,
  add column can_manage_tenancies   boolean not null default false,
  add column can_manage_team        boolean not null default false;

grant update (can_see_money, can_manage_apartments, can_manage_tenancies, can_manage_team)
  on public.memberships to authenticated;

-- May the current user do [p_permission] on this property?
--   'money' | 'payments' | 'apartments' | 'tenancies' | 'team'
-- Owners: everything. Managers: everything except 'team'.
-- Caretakers: only what their switches allow.
create function public.has_permission(p_property_id uuid, p_permission text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.property_id = p_property_id
      and m.user_id = (select auth.uid())
      and case m.role
            when 'owner'   then true
            when 'manager' then p_permission <> 'team'
            else case p_permission
                   when 'money'      then m.can_see_money
                   when 'payments'   then m.can_record_payments
                   when 'apartments' then m.can_manage_apartments
                   when 'tenancies'  then m.can_manage_tenancies
                   when 'team'       then m.can_manage_team
                   else false
                 end
          end
  );
$$;

revoke execute on function public.has_permission(uuid, text) from public, anon;
grant  execute on function public.has_permission(uuid, text) to authenticated;


-- 2. Table rules (policies) -------------------------------------------------------------
-- Each "owner or manager" rule becomes the matching permission.

-- properties: editing details goes with managing apartments
drop policy "properties: update" on public.properties;
create policy "properties: update" on public.properties for update to authenticated
  using (public.has_permission(id, 'apartments'))
  with check (public.has_permission(id, 'apartments'));

-- apartments + their standard rent
drop policy "apartments: insert" on public.apartments;
drop policy "apartments: update" on public.apartments;
drop policy "apartments: delete" on public.apartments;
create policy "apartments: insert" on public.apartments for insert to authenticated
  with check (public.has_permission(property_id, 'apartments'));
create policy "apartments: update" on public.apartments for update to authenticated
  using (public.has_permission(property_id, 'apartments'))
  with check (public.has_permission(property_id, 'apartments'));
create policy "apartments: delete" on public.apartments for delete to authenticated
  using (public.has_permission(property_id, 'apartments'));

-- (Reading a rent needs 'money'; changing it needs 'apartments' too.)
drop policy "apartment_rents: read" on public.apartment_rents;
drop policy "apartment_rents: insert" on public.apartment_rents;
drop policy "apartment_rents: update" on public.apartment_rents;
create policy "apartment_rents: read" on public.apartment_rents for select to authenticated
  using (public.has_permission(property_id, 'money') or public.has_permission(property_id, 'apartments'));
create policy "apartment_rents: insert" on public.apartment_rents for insert to authenticated
  with check (public.has_permission(property_id, 'apartments'));
create policy "apartment_rents: update" on public.apartment_rents for update to authenticated
  using (public.has_permission(property_id, 'apartments'))
  with check (public.has_permission(property_id, 'apartments'));

-- tenants (contacts) and their ID numbers
drop policy "tenants: insert" on public.tenants;
drop policy "tenants: update" on public.tenants;
drop policy "tenants: delete" on public.tenants;
create policy "tenants: insert" on public.tenants for insert to authenticated
  with check (public.has_permission(property_id, 'tenancies'));
create policy "tenants: update" on public.tenants for update to authenticated
  using (public.has_permission(property_id, 'tenancies'))
  with check (public.has_permission(property_id, 'tenancies'));
create policy "tenants: delete" on public.tenants for delete to authenticated
  using (public.has_permission(property_id, 'tenancies'));

drop policy "tenant_identities: read" on public.tenant_identities;
drop policy "tenant_identities: insert" on public.tenant_identities;
drop policy "tenant_identities: update" on public.tenant_identities;
drop policy "tenant_identities: delete" on public.tenant_identities;
create policy "tenant_identities: read" on public.tenant_identities for select to authenticated
  using (public.has_permission(property_id, 'money') or public.has_permission(property_id, 'tenancies'));
create policy "tenant_identities: insert" on public.tenant_identities for insert to authenticated
  with check (public.has_permission(property_id, 'tenancies'));
create policy "tenant_identities: update" on public.tenant_identities for update to authenticated
  using (public.has_permission(property_id, 'tenancies'))
  with check (public.has_permission(property_id, 'tenancies'));
create policy "tenant_identities: delete" on public.tenant_identities for delete to authenticated
  using (public.has_permission(property_id, 'tenancies'));

-- tenancies: contain the rent, so reading needs 'money' (or managing them)
drop policy "tenancies: read" on public.tenancies;
drop policy "tenancies: insert" on public.tenancies;
drop policy "tenancies: update" on public.tenancies;
create policy "tenancies: read" on public.tenancies for select to authenticated
  using (
    public.has_permission(property_id, 'money')
    or public.has_permission(property_id, 'tenancies')
    or public.is_tenant_of_tenancy(id)
  );
create policy "tenancies: insert" on public.tenancies for insert to authenticated
  with check (public.has_permission(property_id, 'tenancies'));
create policy "tenancies: update" on public.tenancies for update to authenticated
  using (public.has_permission(property_id, 'tenancies'))
  with check (public.has_permission(property_id, 'tenancies'));

drop policy "tenancy_renewals: read" on public.tenancy_renewals;
create policy "tenancy_renewals: read" on public.tenancy_renewals for select to authenticated
  using (public.has_permission(property_id, 'money') or public.is_tenant_of_tenancy(tenancy_id));

drop policy "tenant_invites: read" on public.tenant_invites;
create policy "tenant_invites: read" on public.tenant_invites for select to authenticated
  using (public.has_permission(property_id, 'tenancies'));

-- payments, voids, receipts: money
drop policy "payments: read" on public.payments;
create policy "payments: read" on public.payments for select to authenticated
  using (public.has_permission(property_id, 'money') or public.is_tenant_of_tenancy(tenancy_id));
drop policy "payment_voids: read" on public.payment_voids;
create policy "payment_voids: read" on public.payment_voids for select to authenticated
  using (
    public.has_permission(property_id, 'money')
    or exists (select 1 from public.payments p
               where p.id = payment_voids.payment_id and public.is_tenant_of_tenancy(p.tenancy_id))
  );
drop policy "receipts: read" on public.receipts;
create policy "receipts: read" on public.receipts for select to authenticated
  using (
    public.has_permission(property_id, 'money')
    or exists (select 1 from public.payments p
               where p.id = receipts.payment_id and public.is_tenant_of_tenancy(p.tenancy_id))
  );

-- memberships (the team): 'team' permission, but OWNER rows stay owner-only:
-- nobody but an owner can add an owner, promote someone to owner, or
-- change/remove an owner.
drop policy "memberships: insert" on public.memberships;
drop policy "memberships: update" on public.memberships;
drop policy "memberships: delete" on public.memberships;
create policy "memberships: insert" on public.memberships for insert to authenticated
  with check (
    public.has_property_role(property_id, '{owner}')
    or (public.has_permission(property_id, 'team') and role <> 'owner')
  );
create policy "memberships: update" on public.memberships for update to authenticated
  using (
    public.has_property_role(property_id, '{owner}')
    or (public.has_permission(property_id, 'team') and role <> 'owner')
  )
  with check (
    public.has_property_role(property_id, '{owner}')
    or (public.has_permission(property_id, 'team') and role <> 'owner')
  );
create policy "memberships: delete" on public.memberships for delete to authenticated
  using (
    public.has_property_role(property_id, '{owner}')
    or (public.has_permission(property_id, 'team') and role <> 'owner')
  );


-- 3. Functions: same as before, permission check updated ---------------------------------
-- cancel_tenant_invite
CREATE OR REPLACE FUNCTION public.cancel_tenant_invite(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tenants where id = p_tenant_id;
  if v_property_id is null or not public.has_permission(v_property_id, 'tenancies') then
    raise exception 'You don''t have permission to cancel invites.';
  end if;
  update public.tenant_invites set cancelled_at = now()
  where tenant_id = p_tenant_id and redeemed_at is null and cancelled_at is null;
end;
$function$
;

-- create_tenant_invite
CREATE OR REPLACE FUNCTION public.create_tenant_invite(p_tenant_id uuid)
 RETURNS TABLE(code text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_tenant public.tenants;
  v_code text := public.new_invite_code();
  v_expires timestamptz := now() + interval '7 days';
begin
  select * into v_tenant from public.tenants where id = p_tenant_id;
  if not found or not public.has_permission(v_tenant.property_id, 'tenancies') then
    raise exception 'You don''t have permission to invite tenants.';
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
$function$
;

-- end_tenancy
CREATE OR REPLACE FUNCTION public.end_tenancy(p_tenancy_id uuid, p_move_out_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_tenancy public.tenancies;
  v_move_out date := coalesce(p_move_out_date, current_date);
begin
  select * into v_tenancy from public.tenancies where id = p_tenancy_id;

  if not found or not public.has_permission(v_tenancy.property_id, 'tenancies') then
    raise exception 'You don''t have permission to end a tenancy.';
  end if;
  if v_tenancy.status <> 'active' then
    raise exception 'This tenancy has already ended.';
  end if;
  if v_move_out < v_tenancy.start_date then
    raise exception 'The move-out date can''t be before the move-in date.';
  end if;

  update public.tenancies
  set status = 'ended', ended_at = now(), end_date = v_move_out
  where id = p_tenancy_id;
end;
$function$
;

-- renew_tenancy
CREATE OR REPLACE FUNCTION public.renew_tenancy(p_tenancy_id uuid, p_new_end_date date, p_new_monthly_rent bigint DEFAULT NULL::bigint, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tenancy public.tenancies;
  v_rent bigint;
begin
  select * into v_tenancy from public.tenancies where id = p_tenancy_id for update;

  if not found or not public.has_permission(v_tenancy.property_id, 'tenancies') then
    raise exception 'You don''t have permission to renew a tenancy.';
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
$function$
;

-- set_tenant_id_number
CREATE OR REPLACE FUNCTION public.set_tenant_id_number(p_tenant_id uuid, p_id_number text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tenants where id = p_tenant_id;
  if v_property_id is null or not public.has_permission(v_property_id, 'tenancies') then
    raise exception 'You don''t have permission to change ID numbers.';
  end if;

  if nullif(trim(p_id_number), '') is null then
    delete from public.tenant_identities where tenant_id = p_tenant_id;
  else
    insert into public.tenant_identities (tenant_id, property_id, id_number)
    values (p_tenant_id, v_property_id, trim(p_id_number))
    on conflict (tenant_id) do update set id_number = excluded.id_number;
  end if;
end;
$function$
;

-- start_tenancy
CREATE OR REPLACE FUNCTION public.start_tenancy(p_apartment_id uuid, p_monthly_rent bigint, p_payment_interval_months integer, p_start_date date, p_tenant_id uuid DEFAULT NULL::uuid, p_tenant_name text DEFAULT NULL::text, p_tenant_phone text DEFAULT NULL::text, p_tenant_email text DEFAULT NULL::text, p_tenant_id_number text DEFAULT NULL::text, p_end_date date DEFAULT NULL::date, p_billing_start_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_property_id uuid;
  v_tenant_id   uuid := p_tenant_id;
  v_tenancy_id  uuid;
begin
  select a.property_id into v_property_id
  from public.apartments a where a.id = p_apartment_id;

  if v_property_id is null or not public.has_permission(v_property_id, 'tenancies') then
    raise exception 'You don''t have permission to start a tenancy.';
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
$function$
;

-- unlink_tenant_account
CREATE OR REPLACE FUNCTION public.unlink_tenant_account(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tenants where id = p_tenant_id;
  if v_property_id is null or not public.has_permission(v_property_id, 'tenancies') then
    raise exception 'You don''t have permission to do this.';
  end if;
  update public.tenants set user_id = null where id = p_tenant_id;
end;
$function$
;

-- save_apartment
CREATE OR REPLACE FUNCTION public.save_apartment(p_property_id uuid, p_name text, p_monthly_rent bigint, p_description text DEFAULT NULL::text, p_apartment_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_apartment_id uuid := p_apartment_id;
begin
  if not public.has_permission(p_property_id, 'apartments') then
    raise exception 'You don''t have permission to add or edit apartments.';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Enter a name or number for the apartment.';
  end if;
  if p_monthly_rent is null or p_monthly_rent <= 0 then
    raise exception 'Enter the monthly rent (more than zero).';
  end if;

  if v_apartment_id is null then
    insert into public.apartments (property_id, name, description)
    values (p_property_id, trim(p_name), nullif(trim(p_description), ''))
    returning id into v_apartment_id;
  else
    update public.apartments
    set name = trim(p_name), description = nullif(trim(p_description), '')
    where id = v_apartment_id and property_id = p_property_id;
    if not found then
      raise exception 'Apartment not found.';
    end if;
  end if;

  insert into public.apartment_rents as r (apartment_id, property_id, monthly_rent)
  values (v_apartment_id, p_property_id, p_monthly_rent)
  on conflict (apartment_id) do update
    set monthly_rent = excluded.monthly_rent, updated_at = now();

  return v_apartment_id;
end;
$function$
;

-- void_payment
CREATE OR REPLACE FUNCTION public.void_payment(p_payment_id uuid, p_reason text)
 RETURNS date
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payment public.payments;
  v_tenancy public.tenancies;
  v_total_months int;
  v_new_paid_until date;
begin
  select * into v_payment from public.payments where id = p_payment_id;
  if not found or not (public.has_permission(v_payment.property_id, 'money') and public.has_permission(v_payment.property_id, 'payments')) then
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
$function$
;

-- add_property_member: owners, or anyone with 'team' (but only owners add owners)
create or replace function public.add_property_member(
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
  if not public.has_permission(p_property_id, 'team') then
    raise exception 'You don''t have permission to add team members.';
  end if;
  if p_role = 'owner' and not public.has_property_role(p_property_id, '{owner}') then
    raise exception 'Only owners can add another owner.';
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

-- password_reset_target: caretakers can only be reset by the app admin now.
-- Owners reset managers and tenants; managers (and caretakers allowed to
-- manage tenancies) reset tenants. Same "only this property" safety rule.
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
  select role into v_target_role from public.memberships
  where property_id = p_property_id and user_id = p_user_id;
  v_is_tenant := exists (
    select 1 from public.tenants where property_id = p_property_id and user_id = p_user_id
  );

  if v_caller_role is null then
    raise exception 'You don''t have permission to reset passwords.';
  end if;
  if v_target_role = 'caretaker' then
    raise exception 'A caretaker''s password can only be reset by the app admin.';
  end if;
  if v_target_role = 'owner'
     or (v_target_role = 'manager' and v_caller_role <> 'owner') then
    raise exception 'You can only reset passwords for people below your role.';
  end if;
  if v_target_role is null and not v_is_tenant then
    raise exception 'This person isn''t part of this property.';
  end if;
  if v_target_role is null and not public.has_permission(p_property_id, 'tenancies') then
    raise exception 'You don''t have permission to reset tenants'' passwords.';
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
