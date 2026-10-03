-- =============================================================================
-- Push notifications (PLAN.md Phase 11).
--
-- How it works:
-- 1. Everything that should reach someone becomes a row in `notifications`
--    (their in-app list, the bell). Database triggers add rows when things
--    happen; queue_scheduled_notifications() adds rent and bill reminders
--    twice a day (pg_cron, 8:00 and 20:00 Cameroon time).
-- 2. Every minute, dispatch_push() calls the send-push Edge Function if
--    rows are waiting. It sends them to the person's phones with Firebase
--    Cloud Messaging; too many at once become one "open Homedly" summary.
-- 3. Phones register in `device_tokens` after login (register_device).
--
-- Rent reminders (decided 2026-10-03), for tenants with an app account:
--   one month before the paid-until date, 5 days before, on the day, then
--   every 3 days while overdue. They alternate between 8:00 and 20:00:
--   1 month 8:00, 5 days 20:00, due day 8:00, then 20:00 / 8:00 / ...
--   Staff can send one now (send_rent_reminder) or pause them for a unit
--   (set_rent_reminders_muted, e.g. 7 or 30 days).
-- Bill reminders: 2 days before the due date and on the day, at 8:00.
-- =============================================================================


-- 1. Money in messages ----------------------------------------------------------------------

-- 150000, 'XAF' -> 'XAF 150,000'; 2550, 'USD' -> 'USD 25.50' (like formatMoney in Dart).
create function public.format_money(p_amount bigint, p_currency text)
returns text
language sql immutable set search_path = ''
as $$
  select p_currency || ' ' ||
    case when p_currency in ('XAF', 'XOF')
         then regexp_replace(p_amount::text, '(\d)(?=(\d{3})+$)', '\1,', 'g')
         else regexp_replace((p_amount / 100)::text, '(\d)(?=(\d{3})+$)', '\1,', 'g')
              || '.' || lpad((p_amount % 100)::text, 2, '0')
    end;
$$;

-- '2026-11-01' -> '1 Nov 2026'
create function public.format_day(p_date date)
returns text
language sql immutable set search_path = ''
as $$ select to_char(p_date, 'FMDD Mon YYYY'); $$;


-- 2. Phones ---------------------------------------------------------------------------------

create table public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
create index on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
create policy "device_tokens: own" on public.device_tokens for select to authenticated
  using (user_id = (select auth.uid()));
grant select on public.device_tokens to authenticated;

-- This phone belongs to the logged-in user now (a phone shared by two
-- accounts follows whoever logged in last).
create function public.register_device(p_token text, p_platform text default 'android')
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or p_token is null or length(p_token) < 10 then
    raise exception 'Not logged in.';
  end if;
  insert into public.device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'))
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end;
$$;

-- Logging out: this phone gets no more notifications for this account.
create function public.unregister_device(p_token text)
returns void
language sql security definer set search_path = ''
as $$ delete from public.device_tokens where token = p_token and user_id = auth.uid(); $$;


-- 3. Notifications ----------------------------------------------------------------------------

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  property_id  uuid references public.properties (id) on delete cascade,
  tenancy_id   uuid references public.tenancies (id) on delete cascade,
  kind         text not null,      -- rent, rent_manual, bill, receipt, message, issue, dispute, joined
  title        text not null,
  body         text not null,
  route        text,               -- the app screen to open
  -- Same key twice for the same person = sent once (scheduled reminders).
  dedupe_key   text,
  created_at   timestamptz not null default now(),
  read_at      timestamptz,
  sent_at      timestamptz,        -- handled by send-push (pushed or not)
  pushed       boolean not null default false,  -- went out as its own push
  unique (user_id, dedupe_key)
);
create index on public.notifications (user_id, created_at desc);
create index on public.notifications (created_at) where sent_at is null;
alter table public.notifications enable row level security;
create policy "notifications: own" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
grant select on public.notifications to authenticated;

-- When someone last got a "lots of notifications" summary (send-push only).
create table public.push_state (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  last_summary_at  timestamptz
);
alter table public.push_state enable row level security;

create function public.mark_notifications_read()
returns void
language sql security definer set search_path = ''
as $$ update public.notifications set read_at = now() where user_id = auth.uid() and read_at is null; $$;

-- Adds one notification. Nobody is notified about their own action.
create function public.notify(
  p_user uuid, p_property uuid, p_tenancy uuid, p_kind text,
  p_title text, p_body text, p_route text, p_dedupe text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_user is null or p_user = auth.uid() then
    return;
  end if;
  insert into public.notifications (user_id, property_id, tenancy_id, kind, title, body, route, dedupe_key)
  values (p_user, p_property, p_tenancy, p_kind, left(p_title, 120), left(p_body, 300), p_route, p_dedupe)
  on conflict (user_id, dedupe_key) do nothing;
end;
$$;

-- Notifies the property's team. p_money_only: only owners, managers and
-- caretakers who may see money (receipt disputes).
create function public.notify_staff(
  p_property uuid, p_kind text, p_title text, p_body text, p_route text, p_money_only boolean default false
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m record;
begin
  for m in select user_id, role, can_see_money from public.memberships where property_id = p_property loop
    if p_money_only and not (m.role in ('owner', 'manager') or m.can_see_money) then
      continue;
    end if;
    perform public.notify(m.user_id, p_property, null, p_kind, p_title, p_body, p_route);
  end loop;
end;
$$;

-- The tenant's app account for a tenancy (null if they haven't joined).
create function public.tenancy_user(p_tenancy_id uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select t.user_id from public.tenancies ty join public.tenants t on t.id = ty.tenant_id where ty.id = p_tenancy_id;
$$;


-- 4. Rent reminders ------------------------------------------------------------------------

alter table public.tenancies add column reminders_muted_until date;

-- The overview again, plus reminders_muted_until (not money: caretakers see it).
create or replace view public.tenancy_overview
with (security_invoker = false, security_barrier = true)
as
select
  ty.id,
  ty.property_id,
  ty.apartment_id,
  a.name  as apartment_name,
  ty.tenant_id,
  t.full_name as tenant_name,
  ty.payment_interval_months,
  ty.start_date,
  ty.end_date,
  ty.billing_start_date,
  ty.paid_until,
  (select coalesce(sum(p.months), 0)::int
     from public.payments p
    where p.tenancy_id = ty.id and p.kind = 'rent'
      and not exists (select 1 from public.payment_voids v where v.payment_id = p.id)
  ) as paid_months,
  ty.status,
  case when ty.status = 'active'
       then public.rent_status(ty.paid_until, p.grace_period_days) end as rent_status,
  ty.agreement_accepted_at,
  coalesce(a.agreement_text, p.agreement_text) as agreement_text,
  ty.reminders_muted_until,
  (t.user_id is not null) as tenant_has_account
from public.tenancies ty
join public.apartments a on a.id = ty.apartment_id
join public.tenants    t on t.id = ty.tenant_id
join public.properties p on p.id = ty.property_id
where public.is_property_member(ty.property_id)
   or t.user_id = (select auth.uid())
   or public.is_app_admin();
grant select on public.tenancy_overview to authenticated;

-- The reminder's words. p_stage: month, 5days, due, overdue, manual.
create function public.rent_reminder_text(p_tenancy_id uuid, p_stage text, p_today date)
returns table (title text, body text)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v record;
  v_amount text;
  v_days int;
begin
  select ty.paid_until, ty.monthly_rent * ty.payment_interval_months as amount, p.currency, a.name as unit
  into v
  from public.tenancies ty
  join public.properties p on p.id = ty.property_id
  join public.apartments a on a.id = ty.apartment_id
  where ty.id = p_tenancy_id;

  v_amount := public.format_money(v.amount, v.currency);
  v_days := p_today - v.paid_until;  -- > 0: overdue by that many days

  if p_stage = 'manual' then
    p_stage := case when v_days > 0 then 'overdue' when v_days = 0 then 'due' else 'soon' end;
    title := 'Rent reminder from your landlord';
  end if;

  body := case p_stage
    when 'month'   then 'Your rent for apartment ' || v.unit || ' is paid until ' || public.format_day(v.paid_until)
                        || '. Next payment: ' || v_amount || '.'
    when '5days'   then 'Your rent for apartment ' || v.unit || ' is due on ' || public.format_day(v.paid_until)
                        || ': ' || v_amount || '.'
    when 'soon'    then 'Your rent for apartment ' || v.unit || ' is due on ' || public.format_day(v.paid_until)
                        || ': ' || v_amount || '.'
    when 'due'     then 'Your rent for apartment ' || v.unit || ' is due today: ' || v_amount || '.'
    else 'Your rent for apartment ' || v.unit || ' was due on ' || public.format_day(v.paid_until)
         || ' (' || v_days || ' day' || case when v_days = 1 then '' else 's' end
         || ' ago). Please pay ' || v_amount || ' as soon as you can.'
  end;
  title := coalesce(title, case p_stage
    when 'month' then 'Your rent ends in a month'
    when '5days' then 'Rent due in 5 days'
    when 'due'   then 'Rent is due today'
    else 'Rent is overdue' end);
  return next;
end;
$$;

-- Queues the reminders for one run: p_slot 'morning' (8:00) or 'evening'
-- (20:00). p_today is only for tests (default: today in Cameroon).
-- Returns how many notifications were added.
create function public.queue_scheduled_notifications(p_slot text, p_today date default null)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Africa/Douala')::date);
  v_before int;
  r record;
  v_days int;       -- days until paid_until (negative = overdue)
  v_stage text;
  v_index int;      -- position in the sequence: even = morning, odd = evening
  v_text record;
begin
  select count(*) into v_before from public.notifications;

  -- Rent
  for r in
    select ty.id, ty.property_id, ty.paid_until, t.user_id
    from public.tenancies ty join public.tenants t on t.id = ty.tenant_id
    where ty.status = 'active' and t.user_id is not null
      and (ty.reminders_muted_until is null or ty.reminders_muted_until < v_today)
  loop
    v_days := r.paid_until - v_today;
    if (r.paid_until - interval '1 month')::date = v_today then
      v_stage := 'month';   v_index := 0;
    elsif v_days = 5 then
      v_stage := '5days';   v_index := 1;
    elsif v_days = 0 then
      v_stage := 'due';     v_index := 2;
    elsif v_days < 0 and (-v_days) % 3 = 0 then
      v_stage := 'overdue'; v_index := 2 + (-v_days) / 3;
    else
      continue;
    end if;
    if (case when v_index % 2 = 0 then 'morning' else 'evening' end) <> p_slot then
      continue;
    end if;
    select * into v_text from public.rent_reminder_text(r.id, v_stage, v_today);
    perform public.notify(r.user_id, r.property_id, r.id, 'rent', v_text.title, v_text.body,
                          '/home/my-home/' || r.id,
                          'rent:' || r.id || ':' || r.paid_until || ':' || v_stage || ':' || v_days);
  end loop;

  -- Bills (mornings only): 2 days before the due date and on the day.
  if p_slot = 'morning' then
    for r in
      select a.id, a.tenancy_id, a.property_id, a.amount, b.title, b.due_date, p.currency, t.user_id
      from public.bill_assignments a
      join public.bills b on b.id = a.bill_id
      join public.properties p on p.id = a.property_id
      join public.tenancies ty on ty.id = a.tenancy_id
      join public.tenants t on t.id = ty.tenant_id
      where a.paid_at is null and a.waived_at is null and ty.status = 'active' and t.user_id is not null
        and b.due_date - v_today in (0, 2)
    loop
      perform public.notify(
        r.user_id, r.property_id, r.tenancy_id, 'bill',
        case when r.due_date = v_today then 'Bill due today: ' else 'Bill due in 2 days: ' end || r.title,
        public.format_money(r.amount, r.currency) || ' to pay by ' || public.format_day(r.due_date) || '.',
        '/my-bills',
        'bill:' || r.id || ':' || (r.due_date - v_today));
    end loop;
  end if;

  return (select count(*) from public.notifications) - v_before;
end;
$$;

-- Staff send a rent reminder to one unit now (at most every 6 hours).
create function public.send_rent_reminder(p_tenancy_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_tenancy public.tenancies;
  v_user uuid;
  v_text record;
begin
  select * into v_tenancy from public.tenancies where id = p_tenancy_id;
  if not found or not public.is_property_member(v_tenancy.property_id) then
    raise exception 'Only the property''s team can send rent reminders.';
  end if;
  if v_tenancy.status <> 'active' then
    raise exception 'This tenancy has ended.';
  end if;
  v_user := public.tenancy_user(p_tenancy_id);
  if v_user is null then
    raise exception 'This tenant hasn''t joined the app yet, so they can''t get notifications.';
  end if;
  if exists (select 1 from public.notifications
             where tenancy_id = p_tenancy_id and kind = 'rent_manual'
               and created_at > now() - interval '6 hours') then
    raise exception 'A reminder was already sent in the last 6 hours.';
  end if;
  select * into v_text from public.rent_reminder_text(
    p_tenancy_id, 'manual', (now() at time zone 'Africa/Douala')::date);
  perform public.notify(v_user, v_tenancy.property_id, p_tenancy_id, 'rent_manual',
                        v_text.title, v_text.body, '/home/my-home/' || p_tenancy_id);
end;
$$;

-- Staff pause the automatic rent reminders of one unit for p_days days
-- (0 = turn them back on). Returns the day they start again (null = on).
create function public.set_rent_reminders_muted(p_tenancy_id uuid, p_days int)
returns date
language plpgsql security definer set search_path = ''
as $$
declare
  v_property_id uuid;
  v_until date;
begin
  select property_id into v_property_id from public.tenancies where id = p_tenancy_id;
  if v_property_id is null or not public.is_property_member(v_property_id) then
    raise exception 'Only the property''s team can pause rent reminders.';
  end if;
  if p_days is null or p_days < 0 or p_days > 365 then
    raise exception 'Choose how long to pause (up to a year).';
  end if;
  v_until := case when p_days = 0 then null
                  else (now() at time zone 'Africa/Douala')::date + p_days end;
  update public.tenancies set reminders_muted_until = v_until where id = p_tenancy_id;
  return v_until;
end;
$$;


-- 5. Notifications when things happen ------------------------------------------------------

-- A receipt was issued: the tenant checks it (24 hours to answer).
create function public.on_receipt_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_payment public.payments;
  v_currency text;
begin
  select * into v_payment from public.payments where id = new.payment_id;
  select currency into v_currency from public.properties where id = v_payment.property_id;
  perform public.notify(
    public.tenancy_user(v_payment.tenancy_id), v_payment.property_id, v_payment.tenancy_id, 'receipt',
    'Payment recorded: ' || public.format_money(v_payment.amount, v_currency),
    'Receipt ' || new.receipt_number || '. Check it and confirm it within 24 hours.',
    '/home/my-home/' || v_payment.tenancy_id || '/receipts/' || v_payment.id);
  return null;
end;
$$;
create trigger notify_receipt after insert on public.receipts
  for each row execute function public.on_receipt_notify();

-- A new bill for an apartment: its tenant.
create function public.on_bill_assignment_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_bill public.bills;
  v_currency text;
begin
  select * into v_bill from public.bills where id = new.bill_id;
  select currency into v_currency from public.properties where id = new.property_id;
  perform public.notify(
    public.tenancy_user(new.tenancy_id), new.property_id, new.tenancy_id, 'bill',
    'New bill: ' || v_bill.title,
    public.format_money(new.amount, v_currency) || ' to pay by ' || public.format_day(v_bill.due_date) || '.',
    '/my-bills');
  return null;
end;
$$;
create trigger notify_bill after insert on public.bill_assignments
  for each row execute function public.on_bill_assignment_notify();

-- An announcement to everyone: every current tenant with an account.
create function public.on_announcement_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid;
begin
  if new.audience <> 'all' then
    return null;  -- chosen tenants: see on_announcement_recipient_notify
  end if;
  for v_user in
    select distinct t.user_id from public.tenancies ty join public.tenants t on t.id = ty.tenant_id
    where ty.property_id = new.property_id and ty.status = 'active' and t.user_id is not null
  loop
    perform public.notify(v_user, new.property_id, null, 'message', new.title, new.body, '/home/announcements');
  end loop;
  return null;
end;
$$;
create trigger notify_announcement after insert on public.announcements
  for each row execute function public.on_announcement_notify();

create function public.on_announcement_recipient_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_announcement public.announcements;
begin
  select * into v_announcement from public.announcements where id = new.announcement_id;
  perform public.notify(
    (select user_id from public.tenants where id = new.tenant_id), v_announcement.property_id, null,
    'message', v_announcement.title, v_announcement.body, '/home/announcements');
  return null;
end;
$$;
create trigger notify_announcement_recipient after insert on public.announcement_recipients
  for each row execute function public.on_announcement_recipient_notify();

-- A new issue (or a receipt dispute): the team.
create function public.on_ticket_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_unit text;
begin
  select a.name into v_unit from public.tenancies ty join public.apartments a on a.id = ty.apartment_id
  where ty.id = new.tenancy_id;
  if tg_op = 'INSERT' then
    if new.category = 'receipt' then
      perform public.notify_staff(new.property_id, 'dispute', 'Receipt disputed (' || v_unit || ')',
                                  new.title, '/my-issues/' || new.id, true);
    else
      perform public.notify_staff(new.property_id, 'issue', 'New issue at ' || v_unit || ': ' || new.title,
                                  coalesce(new.description, 'Open it to see the details.'), '/my-issues/' || new.id);
    end if;
  elsif new.status is distinct from old.status then
    perform public.notify(
      public.tenancy_user(new.tenancy_id), new.property_id, new.tenancy_id, 'issue',
      'Your issue is ' || case new.status when 'in_progress' then 'being worked on'
                                          when 'resolved' then 'resolved' else 'open again' end,
      new.title, '/my-issues/' || new.id);
  end if;
  return null;
end;
$$;
create trigger notify_ticket after insert or update of status on public.tickets
  for each row execute function public.on_ticket_notify();

-- A reply: from the team to the tenant, from the tenant to the team.
create function public.on_ticket_message_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_ticket public.tickets;
begin
  select * into v_ticket from public.tickets where id = new.ticket_id;
  if new.from_staff then
    perform public.notify(public.tenancy_user(v_ticket.tenancy_id), v_ticket.property_id, v_ticket.tenancy_id,
                          'issue', 'New reply: ' || v_ticket.title, new.body, '/my-issues/' || v_ticket.id);
  else
    perform public.notify_staff(v_ticket.property_id, 'issue', 'Tenant replied: ' || v_ticket.title, new.body,
                                '/my-issues/' || v_ticket.id, v_ticket.category = 'receipt');
  end if;
  return null;
end;
$$;
create trigger notify_ticket_message after insert on public.ticket_messages
  for each row execute function public.on_ticket_message_notify();

-- A tenant joined with their invite code: the team.
create function public.on_invite_redeemed_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_name text;
begin
  if old.redeemed_at is null and new.redeemed_at is not null then
    select full_name into v_name from public.tenants where id = new.tenant_id;
    perform public.notify_staff(new.property_id, 'joined', v_name || ' joined Homedly',
                                'They can now see their rent, bills and receipts in the app.',
                                '/properties/' || new.property_id);
  end if;
  return null;
end;
$$;
create trigger notify_invite_redeemed after update on public.tenant_invites
  for each row execute function public.on_invite_redeemed_notify();


-- 6. Sending (runs on Supabase only) ------------------------------------------------------

-- Calls the send-push Edge Function when notifications are waiting. The
-- function's address and its shared secret are in Supabase Vault
-- (homedly_functions_url, homedly_dispatch_secret), never in the code.
create function public.dispatch_push()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.notifications where sent_at is null) then
    perform net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'homedly_functions_url')
             || '/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-dispatch-secret',
        (select decrypted_secret from vault.decrypted_secrets where name = 'homedly_dispatch_secret')),
      body := '{}'::jsonb,
      timeout_milliseconds := 30000);
  end if;
end;
$$;

-- For send-push only: takes the waiting notifications (marks them handled)
-- so two overlapping runs never send the same one twice.
create function public.claim_pending_notifications(p_limit int default 300)
returns setof public.notifications
language sql security definer set search_path = ''
as $$
  update public.notifications set sent_at = now()
  where id in (select id from public.notifications where sent_at is null
               order by created_at limit p_limit for update skip locked)
  returning *;
$$;

-- The schedule (only where pg_cron and pg_net exist, i.e. on Supabase).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
    create extension if not exists pg_cron;
    -- Cameroon is UTC+1 all year: 8:00 = 07:00 UTC, 20:00 = 19:00 UTC.
    perform cron.schedule('homedly-send', '* * * * *', 'select public.dispatch_push()');
    perform cron.schedule('homedly-morning', '0 7 * * *',
                          $q$select public.queue_scheduled_notifications('morning')$q$);
    perform cron.schedule('homedly-evening', '0 19 * * *',
                          $q$select public.queue_scheduled_notifications('evening')$q$);
    -- Keep the bell list to the last 90 days.
    perform cron.schedule('homedly-cleanup', '30 3 * * 0',
                          $q$delete from public.notifications where created_at < now() - interval '90 days'$q$);
  end if;
end;
$$;


-- Grants ---------------------------------------------------------------------------------

revoke execute on function public.format_money(bigint, text) from public, anon;
grant  execute on function public.format_money(bigint, text) to authenticated;
revoke execute on function public.format_day(date) from public, anon;
grant  execute on function public.format_day(date) to authenticated;
revoke execute on function public.register_device(text, text) from public, anon;
grant  execute on function public.register_device(text, text) to authenticated;
revoke execute on function public.unregister_device(text) from public, anon;
grant  execute on function public.unregister_device(text) to authenticated;
revoke execute on function public.mark_notifications_read() from public, anon;
grant  execute on function public.mark_notifications_read() to authenticated;
revoke execute on function public.send_rent_reminder(uuid) from public, anon;
grant  execute on function public.send_rent_reminder(uuid) to authenticated;
revoke execute on function public.set_rent_reminders_muted(uuid, int) from public, anon;
grant  execute on function public.set_rent_reminders_muted(uuid, int) to authenticated;
-- Internal only (called by triggers, cron and other functions):
revoke execute on function public.notify(uuid, uuid, uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.notify_staff(uuid, text, text, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.tenancy_user(uuid) from public, anon, authenticated;
revoke execute on function public.rent_reminder_text(uuid, text, date) from public, anon, authenticated;
revoke execute on function public.queue_scheduled_notifications(text, date) from public, anon, authenticated;
revoke execute on function public.dispatch_push() from public, anon, authenticated;
revoke execute on function public.claim_pending_notifications(int) from public, anon, authenticated;
grant  execute on function public.claim_pending_notifications(int) to service_role;
revoke execute on function public.on_receipt_notify() from public, anon, authenticated;
revoke execute on function public.on_bill_assignment_notify() from public, anon, authenticated;
revoke execute on function public.on_announcement_notify() from public, anon, authenticated;
revoke execute on function public.on_announcement_recipient_notify() from public, anon, authenticated;
revoke execute on function public.on_ticket_notify() from public, anon, authenticated;
revoke execute on function public.on_ticket_message_notify() from public, anon, authenticated;
revoke execute on function public.on_invite_redeemed_notify() from public, anon, authenticated;
