-- =============================================================================
-- 1. Live updates (decided 2026-10-03): the app listens to changes in these
--    tables through Supabase Realtime and reloads what's on screen. Realtime
--    checks each change against the same RLS rules as a normal read, so
--    people only hear about rows they may see.
-- 2. The team (staff who may see money) is notified when a tenant confirms
--    a receipt.
-- =============================================================================

-- 1. Tables whose changes are sent to the app (only where the Realtime
--    publication exists, i.e. on Supabase).
do $$
declare
  v_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array array[
      'bills', 'bill_assignments', 'payments', 'payment_voids', 'receipt_responses',
      'tickets', 'ticket_messages', 'tenancies', 'apartments', 'announcements', 'notifications'
    ] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table) then
        execute format('alter publication supabase_realtime add table public.%I', v_table);
      end if;
    end loop;
  end if;
end;
$$;

-- 2. "Tina confirmed receipt RCT-2026-0003" for the team.
create function public.on_receipt_response_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_name text;
  v_unit text;
  v_number text;
begin
  if new.response <> 'confirmed' then
    return null;  -- disputes are announced by their ticket
  end if;
  select t.full_name, a.name into v_name, v_unit
  from public.tenancies ty
  join public.tenants t on t.id = ty.tenant_id
  join public.apartments a on a.id = ty.apartment_id
  where ty.id = new.tenancy_id;
  select receipt_number into v_number from public.receipts where payment_id = new.payment_id;
  perform public.notify_staff(
    new.property_id, 'receipt', v_name || ' confirmed receipt ' || v_number,
    'Apartment ' || v_unit || ': the tenant agrees the payment is correct.',
    '/properties/' || new.property_id || '/receipts/' || new.payment_id, true);
  return null;
end;
$$;
create trigger notify_receipt_response after insert on public.receipt_responses
  for each row execute function public.on_receipt_response_notify();

revoke execute on function public.on_receipt_response_notify() from public, anon, authenticated;
