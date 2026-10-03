-- =============================================================================
-- Announcements, tickets (tenant issues) and bills
--
-- Announcements: any team member sends a message to ALL current tenants of a
--   property, or to chosen tenants. Tenants read the ones meant for them.
-- Tickets: a tenant reports an issue on their tenancy; the whole team sees
--   it, both sides can reply, the team changes its status.
-- Bills: every property has bill types; "Water" and "Electricity" are created
--   automatically and can be switched off; custom types can be added (needs
--   the 'apartments' permission). Any team member creates a bill (type,
--   amount, due date) for all occupied apartments or chosen ones; each
--   apartment's part is marked paid separately (needs 'payments'). Overdue
--   is worked out from the due date by the app (business rule 7).
--
-- Writes go through functions that check who's calling; there are no write
-- policies for the app except where noted.
-- =============================================================================


-- Helper: is the current user a tenant with an ACTIVE tenancy in the property?
create function public.is_active_tenant_in_property(p_property_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.tenancies ty
    join public.tenants t on t.id = ty.tenant_id
    where ty.property_id = p_property_id and ty.status = 'active'
      and t.user_id = (select auth.uid())
  );
$$;


-- 1. Announcements ---------------------------------------------------------------------

create table public.announcements (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  title        text not null check (length(trim(title)) > 0),
  body         text not null check (length(trim(body)) > 0),
  -- 'all' = every current tenant; 'selected' = only announcement_recipients
  audience     text not null check (audience in ('all', 'selected')),
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index on public.announcements (property_id, created_at desc);

create table public.announcement_recipients (
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  tenant_id       uuid not null references public.tenants (id) on delete cascade,
  primary key (announcement_id, tenant_id)
);

alter table public.announcements enable row level security;
alter table public.announcement_recipients enable row level security;

-- The two rules below would read each other's table forever ("infinite
-- recursion"), so each asks a security definer helper instead, which reads
-- the other table without its rules.
create function public.is_announcement_for_me(p_announcement_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.announcement_recipients r
    join public.tenants t on t.id = r.tenant_id
    where r.announcement_id = p_announcement_id and t.user_id = (select auth.uid())
  );
$$;

create function public.is_announcement_staff(p_announcement_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.announcements a
    where a.id = p_announcement_id
      and (public.is_property_member(a.property_id) or public.is_app_admin())
  );
$$;

create policy "announcements: read" on public.announcements for select to authenticated
  using (
    public.is_property_member(property_id)
    or public.is_app_admin()
    or (audience = 'all' and public.is_active_tenant_in_property(property_id))
    or public.is_announcement_for_me(id)
  );
create policy "announcement_recipients: read" on public.announcement_recipients for select to authenticated
  using (
    public.is_announcement_staff(announcement_id)
    or exists (select 1 from public.tenants t
               where t.id = tenant_id and t.user_id = (select auth.uid()))
  );
grant select on public.announcements, public.announcement_recipients to authenticated;

-- Sends an announcement. p_tenant_ids null/empty = all current tenants.
create function public.send_announcement(
  p_property_id uuid,
  p_title       text,
  p_body        text,
  p_tenant_ids  uuid[] default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_selected boolean := p_tenant_ids is not null and cardinality(p_tenant_ids) > 0;
begin
  if not public.is_property_member(p_property_id) then
    raise exception 'Only the property''s team can send announcements.';
  end if;
  if v_selected and exists (
    select 1 from unnest(p_tenant_ids) as x(id)
    where not exists (select 1 from public.tenants t where t.id = x.id and t.property_id = p_property_id)
  ) then
    raise exception 'Some of those tenants don''t belong to this property.';
  end if;

  insert into public.announcements (property_id, title, body, audience, created_by)
  values (p_property_id, trim(p_title), trim(p_body),
          case when v_selected then 'selected' else 'all' end, auth.uid())
  returning id into v_id;

  if v_selected then
    insert into public.announcement_recipients (announcement_id, tenant_id)
    select v_id, x.id from (select distinct unnest(p_tenant_ids) as id) x;
  end if;
  return v_id;
end;
$$;


-- 2. Tickets ------------------------------------------------------------------------------

create type public.ticket_status as enum ('open', 'in_progress', 'resolved');

create table public.tickets (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  tenancy_id   uuid not null references public.tenancies (id) on delete cascade,
  title        text not null check (length(trim(title)) > 0),
  description  text,
  category     text not null default 'other'
               check (category in ('plumbing', 'electrical', 'water', 'security', 'cleaning', 'other')),
  status       public.ticket_status not null default 'open',
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on public.tickets (property_id, created_at desc);
create index on public.tickets (tenancy_id);

create table public.ticket_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets (id) on delete cascade,
  author_id   uuid references auth.users (id) on delete set null,
  -- true = written by the team; false = by the tenant
  from_staff  boolean not null,
  body        text not null check (length(trim(body)) > 0),
  created_at  timestamptz not null default now()
);
create index on public.ticket_messages (ticket_id, created_at);

alter table public.tickets enable row level security;
alter table public.ticket_messages enable row level security;

-- The whole team sees tickets (CLAUDE.md: caretakers too); the tenant sees theirs.
create policy "tickets: read" on public.tickets for select to authenticated
  using (
    public.is_property_member(property_id)
    or public.is_app_admin()
    or public.is_tenant_of_tenancy(tenancy_id)
  );
create policy "ticket_messages: read" on public.ticket_messages for select to authenticated
  using (
    exists (select 1 from public.tickets k
            where k.id = ticket_id
              and (public.is_property_member(k.property_id) or public.is_app_admin()
                   or public.is_tenant_of_tenancy(k.tenancy_id)))
  );
grant select on public.tickets, public.ticket_messages to authenticated;

-- A tenant reports an issue on their (active) tenancy.
create function public.create_ticket(
  p_tenancy_id  uuid,
  p_title       text,
  p_description text default null,
  p_category    text default 'other'
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
  if v_tenancy.status <> 'active' then
    raise exception 'This tenancy has ended.';
  end if;

  insert into public.tickets (property_id, tenancy_id, title, description, category, created_by)
  values (v_tenancy.property_id, v_tenancy.id, trim(p_title),
          nullif(trim(p_description), ''), coalesce(p_category, 'other'), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- The team changes a ticket's status.
create function public.set_ticket_status(p_ticket_id uuid, p_status public.ticket_status)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.tickets where id = p_ticket_id;
  if v_property_id is null or not public.is_property_member(v_property_id) then
    raise exception 'Only the property''s team can change a ticket''s status.';
  end if;
  update public.tickets set status = p_status, updated_at = now() where id = p_ticket_id;
end;
$$;

-- A reply, from the team or from the ticket's tenant.
create function public.add_ticket_message(p_ticket_id uuid, p_body text)
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
  v_staff := public.is_property_member(v_ticket.property_id);
  if not v_staff and not public.is_tenant_of_tenancy(v_ticket.tenancy_id) then
    raise exception 'You can''t reply to this ticket.';
  end if;

  insert into public.ticket_messages (ticket_id, author_id, from_staff, body)
  values (p_ticket_id, auth.uid(), v_staff, trim(p_body))
  returning id into v_id;
  update public.tickets set updated_at = now() where id = p_ticket_id;
  return v_id;
end;
$$;


-- 3. Bills ---------------------------------------------------------------------------------

create table public.bill_types (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  name         text not null check (length(trim(name)) > 0),
  is_standard  boolean not null default false,  -- Water / Electricity
  enabled      boolean not null default true,
  created_at   timestamptz not null default now()
);
create unique index bill_types_property_name_key on public.bill_types (property_id, lower(name));

-- Every new property gets the two standard types.
create function public.add_standard_bill_types()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.bill_types (property_id, name, is_standard)
  values (new.id, 'Water', true), (new.id, 'Electricity', true);
  return null;
end;
$$;
create trigger add_standard_bill_types after insert on public.properties
  for each row execute function public.add_standard_bill_types();

-- ...and so do the properties that already exist.
insert into public.bill_types (property_id, name, is_standard)
select p.id, t.name, true
from public.properties p, (values ('Water'), ('Electricity')) as t(name);

create table public.bills (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  bill_type_id uuid not null references public.bill_types (id) on delete restrict,
  title        text not null check (length(trim(title)) > 0),  -- e.g. "Water - September"
  notes        text,
  due_date     date not null,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index on public.bills (property_id, created_at desc);

-- One line per apartment (tenancy) the bill is for; each is paid separately.
create table public.bill_assignments (
  id           uuid primary key default gen_random_uuid(),
  bill_id      uuid not null references public.bills (id) on delete cascade,
  property_id  uuid not null references public.properties (id) on delete cascade,
  tenancy_id   uuid not null references public.tenancies (id) on delete cascade,
  amount       bigint not null check (amount > 0),   -- smallest currency unit
  paid_at      timestamptz,                           -- null = not paid
  marked_by    uuid references auth.users (id) on delete set null,
  unique (bill_id, tenancy_id)
);
create index on public.bill_assignments (tenancy_id);

alter table public.bill_types enable row level security;
alter table public.bills enable row level security;
alter table public.bill_assignments enable row level security;

create policy "bill_types: read" on public.bill_types for select to authenticated
  using (public.is_property_member(property_id) or public.is_tenant_in_property(property_id)
         or public.is_app_admin());
-- Managing types (add custom, rename, switch on/off) = property setup.
create policy "bill_types: insert" on public.bill_types for insert to authenticated
  with check (public.has_permission(property_id, 'apartments') and not is_standard);
create policy "bill_types: update" on public.bill_types for update to authenticated
  using (public.has_permission(property_id, 'apartments'))
  with check (public.has_permission(property_id, 'apartments'));
create policy "bill_types: delete" on public.bill_types for delete to authenticated
  using (public.has_permission(property_id, 'apartments') and not is_standard);
grant select, insert, delete on public.bill_types to authenticated;
-- Standard types can be switched off but not renamed (only custom names change).
grant update (enabled, name) on public.bill_types to authenticated;

create policy "bills: read" on public.bills for select to authenticated
  using (
    public.is_property_member(property_id)
    or public.is_app_admin()
    or exists (select 1 from public.bill_assignments a
               where a.bill_id = bills.id and public.is_tenant_of_tenancy(a.tenancy_id))
  );
create policy "bill_assignments: read" on public.bill_assignments for select to authenticated
  using (
    public.is_property_member(property_id)
    or public.is_app_admin()
    or public.is_tenant_of_tenancy(tenancy_id)
  );
grant select on public.bills, public.bill_assignments to authenticated;

-- Standard types can't be renamed (they can only be switched off).
create function public.bill_type_guard()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.is_standard and new.name <> old.name then
    raise exception 'Water and Electricity can''t be renamed; switch them off instead.';
  end if;
  return new;
end;
$$;
create trigger bill_type_guard before update on public.bill_types
  for each row execute function public.bill_type_guard();

-- Creates a bill for all occupied apartments (p_tenancy_ids null/empty) or
-- the chosen active tenancies, with the same amount for each.
create function public.create_bill(
  p_property_id  uuid,
  p_bill_type_id uuid,
  p_due_date     date,
  p_amount       bigint,
  p_title        text default null,
  p_notes        text default null,
  p_tenancy_ids  uuid[] default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_type public.bill_types;
  v_id uuid;
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
  if p_amount is null or p_amount <= 0 then
    raise exception 'The amount must be more than zero.';
  end if;
  if p_due_date is null then
    raise exception 'Choose a due date.';
  end if;

  insert into public.bills (property_id, bill_type_id, title, notes, due_date, created_by)
  values (p_property_id, v_type.id, coalesce(nullif(trim(p_title), ''), v_type.name),
          nullif(trim(p_notes), ''), p_due_date, auth.uid())
  returning id into v_id;

  insert into public.bill_assignments (bill_id, property_id, tenancy_id, amount)
  select v_id, p_property_id, ty.id, p_amount
  from public.tenancies ty
  where ty.property_id = p_property_id and ty.status = 'active'
    and (p_tenancy_ids is null or cardinality(p_tenancy_ids) = 0 or ty.id = any (p_tenancy_ids));
  get diagnostics v_count = row_count;

  if v_count = 0 then
    raise exception 'There are no occupied apartments to bill.';
  end if;
  return v_id;
end;
$$;

-- Marks one apartment's part of a bill as paid (or not paid).
create function public.set_bill_paid(p_assignment_id uuid, p_paid boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_property_id uuid;
begin
  select property_id into v_property_id from public.bill_assignments where id = p_assignment_id;
  if v_property_id is null or not public.has_permission(v_property_id, 'payments') then
    raise exception 'You don''t have permission to mark bills as paid.';
  end if;
  update public.bill_assignments
  set paid_at = case when p_paid then coalesce(paid_at, now()) end,
      marked_by = auth.uid()
  where id = p_assignment_id;
end;
$$;


-- 4. Activity log for the new tables ---------------------------------------------------------

create trigger log_activity after insert                     on public.announcements    for each row execute function public.log_activity();
create trigger log_activity after insert or update           on public.tickets          for each row execute function public.log_activity();
create trigger log_activity after insert or update or delete on public.bill_types       for each row execute function public.log_activity();
create trigger log_activity after insert                     on public.bills            for each row execute function public.log_activity();
create trigger log_activity after update                     on public.bill_assignments for each row execute function public.log_activity();


-- Privileges -----------------------------------------------------------------------------------

revoke execute on function public.is_active_tenant_in_property(uuid) from public, anon;
grant  execute on function public.is_active_tenant_in_property(uuid) to authenticated;
revoke execute on function public.add_standard_bill_types() from public, anon, authenticated;
revoke execute on function public.is_announcement_for_me(uuid) from public, anon;
grant  execute on function public.is_announcement_for_me(uuid) to authenticated;
revoke execute on function public.is_announcement_staff(uuid) from public, anon;
grant  execute on function public.is_announcement_staff(uuid) to authenticated;
revoke execute on function public.bill_type_guard() from public, anon, authenticated;

revoke execute on function public.send_announcement(uuid, text, text, uuid[]) from public, anon;
grant  execute on function public.send_announcement(uuid, text, text, uuid[]) to authenticated;
revoke execute on function public.create_ticket(uuid, text, text, text) from public, anon;
grant  execute on function public.create_ticket(uuid, text, text, text) to authenticated;
revoke execute on function public.set_ticket_status(uuid, public.ticket_status) from public, anon;
grant  execute on function public.set_ticket_status(uuid, public.ticket_status) to authenticated;
revoke execute on function public.add_ticket_message(uuid, text) from public, anon;
grant  execute on function public.add_ticket_message(uuid, text) to authenticated;
revoke execute on function public.create_bill(uuid, uuid, date, bigint, text, text, uuid[]) from public, anon;
grant  execute on function public.create_bill(uuid, uuid, date, bigint, text, text, uuid[]) to authenticated;
revoke execute on function public.set_bill_paid(uuid, boolean) from public, anon;
grant  execute on function public.set_bill_paid(uuid, boolean) to authenticated;
