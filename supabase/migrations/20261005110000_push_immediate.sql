-- =============================================================================
-- Push notifications go out immediately (decided 2026-10-03): new bills,
-- receipts to confirm, messages and announcements shouldn't wait for the
-- once-a-minute run.
--
-- A new notification now asks send-push to run right away (pg_net sends the
-- request as soon as the transaction is saved). The minute-by-minute job
-- stays as a safety net. Clearer wording for receipts and messages.
-- =============================================================================

-- Same as before, but does nothing where pg_net or Vault don't exist (tests),
-- and doesn't queue a second call while one is already waiting to go out.
create or replace function public.dispatch_push()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if to_regnamespace('net') is null or to_regnamespace('vault') is null then
    return;
  end if;
  if not exists (select 1 from public.notifications where sent_at is null) then
    return;
  end if;
  if exists (select 1 from net.http_request_queue) then
    return;  -- a call is already on its way; it sends these too
  end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'homedly_functions_url')
           || '/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-dispatch-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'homedly_dispatch_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000);
end;
$$;

create function public.on_notification_dispatch()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.dispatch_push();
  return null;
end;
$$;
create trigger dispatch_now after insert on public.notifications
  for each statement execute function public.on_notification_dispatch();


-- Receipt: ask the tenant to check and confirm it.
create or replace function public.on_receipt_notify()
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
    'Please confirm your receipt',
    'Your landlord recorded a payment of ' || public.format_money(v_payment.amount, v_currency)
      || ' (receipt ' || new.receipt_number || '). Check it is correct and confirm it within 24 hours.',
    '/home/my-home/' || v_payment.tenancy_id || '/receipts/' || v_payment.id);
  return null;
end;
$$;

-- Announcements and direct messages: say who it's from.
create or replace function public.on_announcement_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid;
  v_property text;
begin
  if new.audience <> 'all' then
    return null;  -- chosen tenants: see on_announcement_recipient_notify
  end if;
  select name into v_property from public.properties where id = new.property_id;
  for v_user in
    select distinct t.user_id from public.tenancies ty join public.tenants t on t.id = ty.tenant_id
    where ty.property_id = new.property_id and ty.status = 'active' and t.user_id is not null
  loop
    perform public.notify(v_user, new.property_id, null, 'message',
                          'Announcement from ' || v_property || ': ' || new.title, new.body,
                          '/home/announcements');
  end loop;
  return null;
end;
$$;

create or replace function public.on_announcement_recipient_notify()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_announcement public.announcements;
  v_property text;
begin
  select * into v_announcement from public.announcements where id = new.announcement_id;
  select name into v_property from public.properties where id = v_announcement.property_id;
  perform public.notify(
    (select user_id from public.tenants where id = new.tenant_id), v_announcement.property_id, null,
    'message', 'Message from ' || v_property || ': ' || v_announcement.title, v_announcement.body,
    '/home/announcements');
  return null;
end;
$$;

revoke execute on function public.on_notification_dispatch() from public, anon, authenticated;
