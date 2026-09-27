-- =============================================================================
-- Phase 1 security check
--
-- Pretends to be each kind of user (owner, manager, caretakers, tenant,
-- stranger) and checks they can see and do exactly what CLAUDE.md allows.
--
-- How to run: Supabase dashboard -> SQL Editor -> New query -> paste this
-- whole file -> Run. The output is a table of checks; every row should say
-- passed = true.
--
-- Cleanup: the editor runs the whole script as ONE transaction. The test
-- property is deleted by the last test and the test users are deleted just
-- before the results are shown. If anything errors part-way, Postgres undoes
-- the entire script, so no test data is ever left behind either way.
-- (There's no explicit begin/rollback because the editor only displays the
-- output of the LAST statement, which must be the results table.)
--
-- How "pretending" works: `set local role authenticated` makes Postgres apply
-- RLS exactly like it does for app requests, and setting
-- request.jwt.claim.sub decides what auth.uid() returns.
-- =============================================================================


-- ---------- test helpers (temporary, vanish at the end) ----------------------

create temp table results (n serial, test text, passed boolean, detail text);
grant all on results to authenticated, anon;
grant all on sequence results_n_seq to authenticated, anon;

-- Record a check.
create function pg_temp.ok(p_test text, p_cond boolean, p_detail text default null)
returns void language sql as $$
  insert into pg_temp.results (test, passed, detail) values (p_test, coalesce(p_cond, false), p_detail);
$$;

-- Check that a statement is REFUSED with an error.
create function pg_temp.fails(p_test text, p_sql text)
returns void language plpgsql as $$
begin
  execute p_sql;
  insert into pg_temp.results (test, passed, detail) values (p_test, false, 'no error was raised');
exception when others then
  insert into pg_temp.results (test, passed, detail) values (p_test, true, sqlerrm);
end $$;

-- Run a statement and return how many rows it changed (RLS silently skips
-- rows you aren't allowed to touch, so "0 rows" means "blocked").
create function pg_temp.affected(p_sql text)
returns int language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- test users (created as admin) ------------------------------------

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test.local',      now()),
  ('00000000-0000-0000-0000-000000000002', 'manager@test.local',    now()),
  ('00000000-0000-0000-0000-000000000003', 'caretaker@test.local',  now()),
  ('00000000-0000-0000-0000-000000000004', 'caretaker2@test.local', now()),
  ('00000000-0000-0000-0000-000000000005', 'tenant@test.local',     null),  -- not confirmed yet
  ('00000000-0000-0000-0000-000000000006', 'stranger@test.local',   now());

select pg_temp.ok('profiles auto-created on sign-up',
  (select count(*) from public.profiles where id::text like '00000000-0000-0000-0000-00000000000%') = 6);

-- ======================= OWNER ================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

create temp table ids as
  select id as property_id from public.create_property('Test Court', 'xaf', '1 Test Rd');

select pg_temp.ok('owner: create_property makes caller owner',
  exists (select 1 from public.memberships m join pg_temp.ids using (property_id)
          where m.role = 'owner' and m.user_id = auth.uid()));
select pg_temp.ok('owner: currency upper-cased',
  (select currency from public.properties join pg_temp.ids on id = property_id) = 'XAF');

insert into public.memberships (property_id, user_id, role, can_record_payments)
select property_id, u.id, u.role::public.membership_role, u.pay
from pg_temp.ids, (values
  ('00000000-0000-0000-0000-000000000002'::uuid, 'manager',   false),
  ('00000000-0000-0000-0000-000000000003'::uuid, 'caretaker', false),
  ('00000000-0000-0000-0000-000000000004'::uuid, 'caretaker', true)
) as u(id, role, pay);
select pg_temp.ok('owner: can add members', (select count(*) from public.memberships) = 4);

select pg_temp.fails('owner: cannot remove the last owner',
  'delete from public.memberships where user_id = auth.uid()');
select pg_temp.fails('owner: cannot demote the last owner',
  'update public.memberships set role = ''manager'' where user_id = auth.uid()');

-- ======================= MANAGER ==============================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

insert into public.apartments (property_id, name, created_by)
select property_id, 'A1', '00000000-0000-0000-0000-000000000006' from pg_temp.ids;
insert into public.apartments (property_id, name)
select property_id, 'A2' from pg_temp.ids;
select pg_temp.ok('manager: can add apartments', (select count(*) from public.apartments) = 2);
select pg_temp.ok('created_by comes from the logged-in user, not the client',
  (select created_by from public.apartments where name = 'A1') = auth.uid());

insert into public.tenants (property_id, full_name, email)
select property_id, 'Tina Tenant', '  Tenant@Test.local ' from pg_temp.ids;
select pg_temp.ok('tenant email normalised', (select email from public.tenants) = 'tenant@test.local');

insert into public.tenancies (property_id, apartment_id, tenant_id, rent_amount, frequency, start_date, paid_until)
select i.property_id, a.id, t.id, 50000, 'monthly', date '2026-01-31', date '2099-01-01'
from pg_temp.ids i, public.apartments a, public.tenants t where a.name = 'A1';
select pg_temp.ok('new tenancy: client-supplied paid_until ignored, starts at billing start',
  (select paid_until from public.tenancies) = date '2026-01-31');

select pg_temp.fails('only one active tenancy per apartment',
  $q$ insert into public.tenancies (property_id, apartment_id, tenant_id, rent_amount, frequency, start_date)
      select i.property_id, a.id, t.id, 1, 'monthly', current_date
      from pg_temp.ids i, public.apartments a, public.tenants t where a.name = 'A1' $q$);

select pg_temp.fails('manager: cannot edit paid_until directly',
  'update public.tenancies set paid_until = date ''2099-01-01''');
select pg_temp.fails('manager: cannot set tenants.user_id (link a stranger)',
  'update public.tenants set user_id = ''00000000-0000-0000-0000-000000000006''');
select pg_temp.ok('manager: cannot delete the property',
  pg_temp.affected('delete from public.properties') = 0);
select pg_temp.ok('manager: cannot manage members',
  pg_temp.affected('delete from public.memberships where role = ''caretaker''') = 0);

-- Payments. Month-end check: Jan 31 + 1 month = Feb 28, + 2 months = Mar 31.
create temp table p1 as select * from public.record_payment(
  (select id from public.tenancies), 1, date '2026-01-31', 'cash');
grant select on p1 to authenticated;
select pg_temp.ok('payment 1: paid_until Jan 31 -> Feb 28', (select paid_until from p1) = date '2026-02-28');
create temp table p2 as select * from public.record_payment((select id from public.tenancies), 1);
grant select on p2 to authenticated;
select pg_temp.ok('payment 2: paid_until -> Mar 31 (no month-end drift)',
  (select paid_until from p2) = date '2026-03-31');
select pg_temp.ok('receipt numbers sequential',
  (select receipt_number from p1) like 'RCT-____-0001'
  and (select receipt_number from p2) like 'RCT-____-0002');
select pg_temp.ok('amount defaults to rent x periods',
  (select amount from public.payments where id = (select payment_id from p1)) = 50000);

select pg_temp.fails('payments cannot be edited',  'update public.payments set amount = 1');
select pg_temp.fails('payments cannot be deleted', 'delete from public.payments');
select pg_temp.fails('payments cannot be inserted directly (RPC only)',
  $q$ insert into public.payments (property_id, tenancy_id, amount, periods, period_start, period_end, paid_on)
      select property_id, id, 1, 1, current_date, current_date, current_date from public.tenancies $q$);
select pg_temp.fails('apartment with tenancy history cannot be deleted',
  'delete from public.apartments where name = ''A1''');
select pg_temp.ok('apartment without history can be deleted',
  pg_temp.affected('delete from public.apartments where name = ''A2''') = 1);

-- ======================= CARETAKER (no payment permission) ====================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select pg_temp.ok('caretaker: sees apartments',            (select count(*) from public.apartments) = 1);
select pg_temp.ok('caretaker: NO access to tenancies table (rent amounts)', (select count(*) from public.tenancies) = 0);
select pg_temp.ok('caretaker: NO access to payments',       (select count(*) from public.payments) = 0);
select pg_temp.ok('caretaker: NO access to receipts',       (select count(*) from public.receipts) = 0);
select pg_temp.ok('caretaker: sees rent status via tenancy_overview',
  (select count(*) from public.tenancy_overview where rent_status is not null) = 1);
select pg_temp.fails('caretaker: cannot record payments',
  'select public.record_payment((select id from public.tenancy_overview), 1)');
select pg_temp.fails('caretaker: cannot add apartments',
  'insert into public.apartments (property_id, name) select property_id, ''X'' from pg_temp.ids');

-- ======================= CARETAKER (can_record_payments) ======================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

create temp table p3 as select * from public.record_payment((select id from public.tenancy_overview), 1);
select pg_temp.ok('caretaker with permission: can record payment -> Apr 30',
  (select paid_until from p3) = date '2026-04-30');
select pg_temp.ok('caretaker with permission: still cannot read amounts',
  (select count(*) from public.payments) = 0);
select pg_temp.fails('caretaker: cannot void payments',
  format('select public.void_payment(%L, ''test'')', (select payment_id from p3)));

-- ======================= TENANT ===============================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;

-- Tenant linking is PAUSED while email confirmation is off (migration
-- 20260927130000_pause_tenant_linking.sql): the app may not call it.
-- When linking is switched back on, change this check to expect success.
select pg_temp.fails('tenant: linking paused (app cannot call link_my_tenant_records)',
  'select public.link_my_tenant_records()');
select pg_temp.ok('tenant (unlinked): sees no tenancy', (select count(*) from public.tenancies) = 0);

-- The linking LOGIC is still tested, run as admin on the tenant's behalf
-- (auth.uid() is still the tenant here).
reset role;
select pg_temp.ok('link logic: unconfirmed email links nothing', public.link_my_tenant_records() = 0);
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000005';
select pg_temp.ok('link logic: confirmed email links the contact', public.link_my_tenant_records() = 1);
set local role authenticated;

select pg_temp.ok('tenant: sees own tenancy incl. rent', (select rent_amount from public.tenancies) = 50000);
select pg_temp.ok('tenant: sees own payments',  (select count(*) from public.payments) = 3);
select pg_temp.ok('tenant: sees own receipts',  (select count(*) from public.receipts) = 3);
select pg_temp.ok('tenant: sees the property name', (select name from public.properties) = 'Test Court');
select pg_temp.ok('tenant: cannot see staff list', (select count(*) from public.memberships) = 0);
select pg_temp.fails('tenant: cannot record payments',
  'select public.record_payment((select id from public.tenancies), 1)');
select pg_temp.ok('tenant: cannot edit own tenancy',
  pg_temp.affected('update public.tenancies set rent_amount = 1') = 0);

-- ======================= STRANGER =============================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;

select pg_temp.ok('stranger: sees nothing',
  (select count(*) from public.properties) + (select count(*) from public.apartments)
  + (select count(*) from public.tenants) + (select count(*) from public.tenancy_overview)
  + (select count(*) from public.memberships) = 0);

-- ======================= VOID (manager) =======================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select pg_temp.ok('void payment 1: paid_until recalculated -> Mar 31',
  public.void_payment((select payment_id from p1), 'Recorded twice by mistake') = date '2026-03-31');
select pg_temp.ok('voided payment row itself unchanged',
  (select amount from public.payments where id = (select payment_id from p1)) = 50000);
select pg_temp.fails('cannot void the same payment twice',
  format('select public.void_payment(%L, ''again'')', (select payment_id from p1)));
select pg_temp.fails('void needs a reason',
  format('select public.void_payment(%L, ''  '')', (select payment_id from p2)));

-- ======================= NOT LOGGED IN ========================================
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_temp.fails('anon: cannot read properties', 'select count(*) from public.properties');

-- ======================= OWNER deletes property ===============================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.ok('owner: can delete the property (with all its history)',
  pg_temp.affected('delete from public.properties') = 1);
reset role;
select pg_temp.ok('property delete removed everything under it',
  (select count(*) from public.payments    where property_id = (select property_id from pg_temp.ids))
  + (select count(*) from public.tenancies   where property_id = (select property_id from pg_temp.ids))
  + (select count(*) from public.memberships where property_id = (select property_id from pg_temp.ids)) = 0);

-- ---------- cleanup + results ------------------------------------------------
-- Deleting the test users also removes their profiles (cascade).
delete from auth.users where id in (
  '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000006');

select n, passed, test, detail from results order by n;
