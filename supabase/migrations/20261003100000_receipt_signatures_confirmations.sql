-- =============================================================================
-- Receipts that are hard to fake, and the tenant's answer to a receipt.
--
-- 1. Signatures. The sign-receipt Edge Function signs each receipt's details
--    (Ed25519, private key only in the function's secrets) and stores the
--    signed text and signature on the receipt. The app prints both as a QR
--    code; anyone with the app can check it, offline too, with the public key.
--    Only the function (service role) writes these columns.
--
-- 2. Tenant responses. Within 24 hours of a receipt being issued, the tenant
--    can confirm it or report a problem. A problem opens a ticket with
--    category 'receipt' linked to the payment (only staff who may see money
--    see those). After 24 hours without an answer the receipt counts as
--    accepted; that is worked out from issued_at, nothing is stored.
--
-- 3. Offline queue support: create_ticket and add_ticket_message take an
--    optional client id, so a message the phone sends twice (e.g. the
--    connection dropped before the answer came back) is only saved once.
-- =============================================================================


-- 1. Signatures ------------------------------------------------------------------------

alter table public.receipts
  add column signed_payload  text,
  add column signature       text,
  add column signing_key_id  text,
  add column signed_at       timestamptz;
-- (Readable by whoever may read the receipt; nobody but the service role may
-- write: authenticated has no insert/update grant on receipts.)


-- 2. Tickets can be about a receipt ------------------------------------------------------

alter table public.tickets drop constraint tickets_category_check;
alter table public.tickets add constraint tickets_category_check
  check (category in ('plumbing', 'electrical', 'water', 'security', 'cleaning', 'receipt', 'other'));
alter table public.tickets
  add column payment_id uuid references public.payments (id) on delete set null,
  add column client_id  uuid unique;
alter table public.ticket_messages add column client_id uuid unique;
-- A receipt ticket is always about a payment, and only a receipt ticket is.
alter table public.tickets add constraint tickets_receipt_has_payment
  check ((category = 'receipt') = (payment_id is not null));

-- May the current user see this ticket as staff? Receipt disputes are about
-- money, so they need the 'money' permission; other tickets the whole team sees.
create function public.is_ticket_staff(p_property_id uuid, p_category text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case when p_category = 'receipt'
              then public.has_permission(p_property_id, 'money')
              else public.is_property_member(p_property_id) end;
$$;

drop policy "tickets: read" on public.tickets;
create policy "tickets: read" on public.tickets for select to authenticated
  using (
    public.is_ticket_staff(property_id, category)
    or public.is_app_admin()
    or public.is_tenant_of_tenancy(tenancy_id)
  );
drop policy "ticket_messages: read" on public.ticket_messages;
create policy "ticket_messages: read" on public.ticket_messages for select to authenticated
  using (
    exists (select 1 from public.tickets k
            where k.id = ticket_id
              and (public.is_ticket_staff(k.property_id, k.category) or public.is_app_admin()
                   or public.is_tenant_of_tenancy(k.tenancy_id)))
  );

-- A tenant reports an issue on their (active) tenancy. Receipt problems go
-- through dispute_receipt() instead. A repeated p_client_id returns the
-- ticket made the first time.
drop function public.create_ticket(uuid, text, text, text);
create function public.create_ticket(
  p_tenancy_id  uuid,
  p_title       text,
  p_description text default null,
  p_category    text default 'other',
  p_client_id   uuid default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_tenancy public.tenancies;
  v_id uuid;
begin
  select * into v_tenancy from public.tenancies where id = p_tenancy_id;
  if not found or not public.is_tenant_of_tenancy(p_tenancy_id) then
    raise exception 'Only the tenant can report an issue for their home.';
  end if;

  if p_client_id is not null then
    select id into v_id from public.tickets
    where client_id = p_client_id and created_by = auth.uid();
    if v_id is not null then
      return v_id;
    end if;
  end if;

  if v_tenancy.status <> 'active' then
    raise exception 'This tenancy has ended.';
  end if;
  if p_category = 'receipt' then
    raise exception 'Report a problem with a receipt from the receipt itself.';
  end if;

  insert into public.tickets (property_id, tenancy_id, title, description, category, created_by, client_id)
  values (v_tenancy.property_id, v_tenancy.id, trim(p_title),
          nullif(trim(p_description), ''), coalesce(p_category, 'other'), auth.uid(), p_client_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- The team changes a ticket's status.
create or replace function public.set_ticket_status(p_ticket_id uuid, p_status public.ticket_status)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ticket public.tickets;
begin
  select * into v_ticket from public.tickets where id = p_ticket_id;
  if not found or not public.is_ticket_staff(v_ticket.property_id, v_ticket.category) then
    raise exception 'Only the property''s team can change a ticket''s status.';
  end if;
  update public.tickets set status = p_status, updated_at = now() where id = p_ticket_id;
end;
$$;

-- A reply, from the team or from the ticket's tenant. A repeated p_client_id
-- returns the message saved the first time.
drop function public.add_ticket_message(uuid, text);
create function public.add_ticket_message(p_ticket_id uuid, p_body text, p_client_id uuid default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_ticket public.tickets;
  v_staff boolean;
  v_id uuid;
begin
  select * into v_ticket from public.tickets where id = p_ticket_id;
  if not found then
    raise exception 'Ticket not found.';
  end if;
  v_staff := public.is_ticket_staff(v_ticket.property_id, v_ticket.category);
  if not v_staff and not public.is_tenant_of_tenancy(v_ticket.tenancy_id) then
    raise exception 'You can''t reply to this ticket.';
  end if;

  if p_client_id is not null then
    select id into v_id from public.ticket_messages
    where client_id = p_client_id and author_id = auth.uid();
    if v_id is not null then
      return v_id;
    end if;
  end if;

  insert into public.ticket_messages (ticket_id, author_id, from_staff, body, client_id)
  values (p_ticket_id, auth.uid(), v_staff, trim(p_body), p_client_id)
  returning id into v_id;
  update public.tickets set updated_at = now() where id = p_ticket_id;
  return v_id;
end;
$$;


-- 3. Tenant responses -----------------------------------------------------------------

create type public.receipt_response as enum ('confirmed', 'disputed');

-- At most one answer per payment, and it never changes. No row and more than
-- 24 hours since the receipt was issued = accepted automatically.
create table public.receipt_responses (
  payment_id    uuid primary key references public.payments (id) on delete cascade,
  property_id   uuid not null references public.properties (id) on delete cascade,
  tenancy_id    uuid not null references public.tenancies (id) on delete cascade,
  response      public.receipt_response not null,
  -- disputes only: what's wrong
  problem       text check (problem in ('amount', 'months', 'dates', 'not_mine', 'other')),
  ticket_id     uuid references public.tickets (id) on delete set null,
  responded_by  uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  check ((response = 'disputed') = (problem is not null))
);
create index on public.receipt_responses (tenancy_id);

alter table public.receipt_responses enable row level security;
create policy "receipt_responses: read" on public.receipt_responses for select to authenticated
  using (
    public.has_permission(property_id, 'money')
    or public.is_tenant_of_tenancy(tenancy_id)
    or public.is_app_admin()
  );
grant select on public.receipt_responses to authenticated;

create trigger log_activity after insert on public.receipt_responses
  for each row execute function public.log_activity();

-- Checks shared by confirm and dispute; returns the payment's receipt.
create function public.receipt_open_for_response(p_payment_id uuid)
returns public.receipts
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_payment public.payments;
  v_receipt public.receipts;
begin
  select * into v_payment from public.payments where id = p_payment_id;
  if not found or not public.is_tenant_of_tenancy(v_payment.tenancy_id) then
    raise exception 'Only the tenant can answer for their own receipt.';
  end if;
  if exists (select 1 from public.payment_voids where payment_id = p_payment_id) then
    raise exception 'This payment was voided.';
  end if;
  if exists (select 1 from public.receipt_responses where payment_id = p_payment_id) then
    raise exception 'You already answered for this receipt.';
  end if;
  select * into v_receipt from public.receipts where payment_id = p_payment_id;
  if now() > v_receipt.issued_at + interval '24 hours' then
    raise exception 'The 24 hours to answer have passed, so this receipt was accepted automatically. You can still open a ticket.';
  end if;
  return v_receipt;
end;
$$;

-- The tenant confirms a receipt. Confirming twice is harmless (the phone may
-- send a queued confirmation again).
create function public.confirm_receipt(p_payment_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_receipt public.receipts;
begin
  if exists (select 1 from public.receipt_responses r
             where r.payment_id = p_payment_id and r.response = 'confirmed'
               and r.responded_by = auth.uid()) then
    return;
  end if;
  v_receipt := public.receipt_open_for_response(p_payment_id);
  insert into public.receipt_responses (payment_id, property_id, tenancy_id, response, responded_by)
  select p.id, p.property_id, p.tenancy_id, 'confirmed', auth.uid()
  from public.payments p where p.id = p_payment_id;
end;
$$;

-- The tenant reports a problem with a receipt: opens a 'receipt' ticket with
-- their explanation as the first message. Returns the ticket id.
create function public.dispute_receipt(p_payment_id uuid, p_problem text, p_details text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_receipt public.receipts;
  v_payment public.payments;
  v_ticket_id uuid;
begin
  v_receipt := public.receipt_open_for_response(p_payment_id);
  if p_problem is null or p_problem not in ('amount', 'months', 'dates', 'not_mine', 'other') then
    raise exception 'Choose what is wrong with the receipt.';
  end if;
  if p_details is null or length(trim(p_details)) = 0 then
    raise exception 'Explain what is wrong.';
  end if;
  select * into v_payment from public.payments where id = p_payment_id;

  insert into public.tickets (property_id, tenancy_id, title, description, category, payment_id, created_by)
  values (
    v_payment.property_id, v_payment.tenancy_id,
    'Receipt ' || v_receipt.receipt_number || ': ' ||
      case p_problem
        when 'amount'   then 'wrong amount'
        when 'months'   then 'wrong months'
        when 'dates'    then 'wrong dates'
        when 'not_mine' then 'not my payment'
        else 'something is wrong' end,
    trim(p_details), 'receipt', p_payment_id, auth.uid()
  )
  returning id into v_ticket_id;

  insert into public.receipt_responses
    (payment_id, property_id, tenancy_id, response, problem, ticket_id, responded_by)
  values (p_payment_id, v_payment.property_id, v_payment.tenancy_id, 'disputed', p_problem,
          v_ticket_id, auth.uid());
  return v_ticket_id;
end;
$$;


-- Grants ---------------------------------------------------------------------------------

revoke execute on function public.is_ticket_staff(uuid, text) from public, anon;
grant  execute on function public.is_ticket_staff(uuid, text) to authenticated;
revoke execute on function public.create_ticket(uuid, text, text, text, uuid) from public, anon;
grant  execute on function public.create_ticket(uuid, text, text, text, uuid) to authenticated;
revoke execute on function public.add_ticket_message(uuid, text, uuid) from public, anon;
grant  execute on function public.add_ticket_message(uuid, text, uuid) to authenticated;
revoke execute on function public.receipt_open_for_response(uuid) from public, anon, authenticated;
revoke execute on function public.confirm_receipt(uuid) from public, anon;
grant  execute on function public.confirm_receipt(uuid) to authenticated;
revoke execute on function public.dispute_receipt(uuid, text, text) from public, anon;
grant  execute on function public.dispute_receipt(uuid, text, text) to authenticated;
