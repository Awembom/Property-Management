-- =============================================================================
-- A bill with a different amount for each apartment (e.g. water by meter
-- reading), made in one step. Same rules as create_bill(); p_amounts maps
-- tenancy id -> amount (smallest currency unit), e.g.
--   {"<tenancy uuid>": 4500, "<tenancy uuid>": 3000}
-- Only active tenancies of the property; every amount must be above zero.
-- =============================================================================

create function public.create_bill_amounts(
  p_property_id  uuid,
  p_bill_type_id uuid,
  p_due_date     date,
  p_amounts      jsonb,
  p_title        text default null,
  p_notes        text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_type public.bill_types;
  v_id uuid;
  v_wanted int;
  v_count int;
begin
  if not public.is_property_member(p_property_id) then
    raise exception 'Only the property''s team can create bills.';
  end if;
  select * into v_type from public.bill_types where id = p_bill_type_id and property_id = p_property_id;
  if not found then
    raise exception 'Choose a bill type of this property.';
  end if;
  if not v_type.enabled then
    raise exception '% bills are switched off for this property.', v_type.name;
  end if;
  if p_due_date is null then
    raise exception 'Choose a due date.';
  end if;
  if p_amounts is null or jsonb_typeof(p_amounts) <> 'object' or p_amounts = '{}'::jsonb then
    raise exception 'Enter an amount for at least one apartment.';
  end if;
  if exists (select 1 from jsonb_each_text(p_amounts) e
             where e.value !~ '^[0-9]+$' or e.value::bigint <= 0) then
    raise exception 'Every amount must be more than zero.';
  end if;

  select count(*) into v_wanted from jsonb_object_keys(p_amounts);
  insert into public.bills (property_id, bill_type_id, title, notes, due_date, created_by)
  values (p_property_id, v_type.id, coalesce(nullif(trim(p_title), ''), v_type.name),
          nullif(trim(p_notes), ''), p_due_date, auth.uid())
  returning id into v_id;

  insert into public.bill_assignments (bill_id, property_id, tenancy_id, amount)
  select v_id, p_property_id, ty.id, (p_amounts ->> ty.id::text)::bigint
  from public.tenancies ty
  where ty.property_id = p_property_id and ty.status = 'active' and p_amounts ? ty.id::text;
  get diagnostics v_count = row_count;

  if v_count <> v_wanted then
    raise exception 'Some of those apartments are not occupied in this property.';
  end if;
  return v_id;
end;
$$;

revoke execute on function public.create_bill_amounts(uuid, uuid, date, jsonb, text, text) from public, anon;
grant  execute on function public.create_bill_amounts(uuid, uuid, date, jsonb, text, text) to authenticated;
