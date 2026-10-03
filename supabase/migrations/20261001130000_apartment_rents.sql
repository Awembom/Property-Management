-- =============================================================================
-- Standard monthly rent per apartment
--
-- Owners/managers set a "standard" monthly rent on each apartment. When they
-- start a tenancy, the app pre-fills it; they can change it if they agreed a
-- different rent with that tenant (the tenancy keeps its own rent_amount).
--
-- Why a separate table instead of a column on `apartments`:
-- caretakers can read `apartments`, and RLS can hide rows but not single
-- columns. Business rule 5 says caretakers never see money, so the rent
-- lives here, where only owners and managers can read it.
-- =============================================================================

create table public.apartment_rents (
  apartment_id  uuid primary key,
  property_id   uuid not null,
  monthly_rent  bigint not null check (monthly_rent > 0),  -- smallest currency unit
  updated_at    timestamptz not null default now(),
  -- The pair guarantees property_id matches the apartment's property.
  -- Deleting the apartment (or property) removes its rent too.
  foreign key (apartment_id, property_id)
    references public.apartments (id, property_id) on delete cascade
);

create index on public.apartment_rents (property_id);

alter table public.apartment_rents enable row level security;

create policy "apartment_rents: read" on public.apartment_rents for select to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'));
create policy "apartment_rents: insert" on public.apartment_rents for insert to authenticated
  with check (public.has_property_role(property_id, '{owner,manager}'));
create policy "apartment_rents: update" on public.apartment_rents for update to authenticated
  using (public.has_property_role(property_id, '{owner,manager}'))
  with check (public.has_property_role(property_id, '{owner,manager}'));

grant select, insert on public.apartment_rents to authenticated;
grant update (monthly_rent, updated_at) on public.apartment_rents to authenticated;


-- Add or edit an apartment together with its rent, all-or-nothing.
-- p_apartment_id null = add a new apartment. Returns the apartment id.
-- security invoker (the default): the RLS policies above still apply.
create function public.save_apartment(
  p_property_id   uuid,
  p_name          text,
  p_monthly_rent  bigint,
  p_description   text default null,
  p_apartment_id  uuid default null
)
returns uuid
language plpgsql set search_path = ''
as $$
declare
  v_apartment_id uuid := p_apartment_id;
begin
  if not public.has_property_role(p_property_id, '{owner,manager}') then
    raise exception 'Only owners and managers can add or edit apartments.';
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
$$;

revoke execute on function public.save_apartment(uuid, text, bigint, text, uuid) from public, anon;
grant  execute on function public.save_apartment(uuid, text, bigint, text, uuid) to authenticated;
