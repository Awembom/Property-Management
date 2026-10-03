-- =============================================================================
-- Phases 4 + 5: apartments and tenancies
--
-- The tables already exist (core schema). This migration adds the two actions
-- that need more than a single insert/update, so they happen all-or-nothing:
--
-- 1. start_tenancy(): creates the tenant contact (if new) AND the tenancy in
--    one transaction. If the apartment is already occupied, nothing is saved,
--    so no orphan tenant contact is left behind.
-- 2. end_tenancy(): marks a tenancy ended with its move-out date, which makes
--    the apartment vacant again.
-- 3. A guard trigger: an ended tenancy can never be switched back to active
--    (its history must stay as it was; start a new tenancy instead).
--
-- Both functions are `security invoker` (the default): they run with the
-- caller's own rights, so the existing RLS policies still decide who may
-- insert/update. The explicit role checks only give clearer error messages.
-- =============================================================================


-- 1. Start a tenancy ----------------------------------------------------------

create function public.start_tenancy(
  p_apartment_id        uuid,
  p_rent_amount         bigint,
  p_frequency           public.rent_frequency,
  p_start_date          date,
  -- Either pick an existing tenant contact...
  p_tenant_id           uuid default null,
  -- ...or give the details of a new one.
  p_tenant_name         text default null,
  p_tenant_phone        text default null,
  p_tenant_email        text default null,
  p_end_date            date default null,
  -- Rent is counted from here. null = the move-in date. Later than move-in
  -- when the tenant had already paid before the app was used.
  p_billing_start_date  date default null,
  p_notes               text default null
)
returns uuid   -- the new tenancy's id
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
  if p_rent_amount is null or p_rent_amount <= 0 then
    raise exception 'Rent must be more than zero.';
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
  elsif not exists (
    select 1 from public.tenants where id = v_tenant_id and property_id = v_property_id
  ) then
    raise exception 'That tenant doesn''t belong to this property.';
  end if;

  -- paid_until and status are set by the tenancy_before_insert trigger.
  insert into public.tenancies (
    property_id, apartment_id, tenant_id, rent_amount, frequency,
    start_date, end_date, billing_start_date, notes
  ) values (
    v_property_id, p_apartment_id, v_tenant_id, p_rent_amount, p_frequency,
    p_start_date, p_end_date, p_billing_start_date, nullif(trim(p_notes), '')
  )
  returning id into v_tenancy_id;

  return v_tenancy_id;
exception
  -- Two people starting a tenancy at the same moment: the unique index
  -- one_active_tenancy_per_apartment stops the second one.
  when unique_violation then
    raise exception 'This apartment already has a tenant. End that tenancy first.';
end;
$$;


-- 2. End a tenancy ------------------------------------------------------------

create function public.end_tenancy(p_tenancy_id uuid, p_move_out_date date default null)
returns void
language plpgsql set search_path = ''
as $$
declare
  v_tenancy public.tenancies;
  v_move_out date := coalesce(p_move_out_date, current_date);
begin
  select * into v_tenancy from public.tenancies where id = p_tenancy_id;

  if not found or not public.has_property_role(v_tenancy.property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can end a tenancy.';
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
$$;


-- 3. Ended tenancies stay ended -----------------------------------------------

create function public.tenancy_guard_status()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.status = 'ended' and new.status = 'active' then
    raise exception 'An ended tenancy can''t be reopened. Start a new tenancy instead.';
  end if;
  return new;
end;
$$;

create trigger tenancy_guard_status before update of status on public.tenancies
  for each row execute function public.tenancy_guard_status();


-- Privileges ------------------------------------------------------------------

revoke execute on function public.start_tenancy(uuid, bigint, public.rent_frequency, date, uuid, text, text, text, date, date, text) from public, anon;
grant  execute on function public.start_tenancy(uuid, bigint, public.rent_frequency, date, uuid, text, text, text, date, date, text) to authenticated;
revoke execute on function public.end_tenancy(uuid, date) from public, anon;
grant  execute on function public.end_tenancy(uuid, date) to authenticated;
revoke execute on function public.tenancy_guard_status() from public, anon, authenticated;
