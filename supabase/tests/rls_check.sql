-- =============================================================================
-- Security check (Phases 1-6 and 2b)
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

-- account_type is what they chose at sign-up; only landlords create properties.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test.local',      now(), '{"account_type": "landlord"}'),
  ('00000000-0000-0000-0000-000000000002', 'manager@test.local',    now(), '{"account_type": "team"}'),
  ('00000000-0000-0000-0000-000000000003', 'caretaker@test.local',  now(), '{"account_type": "landlord"}'),
  ('00000000-0000-0000-0000-000000000004', 'caretaker2@test.local', now(), '{"account_type": "team"}'),
  ('00000000-0000-0000-0000-000000000005', 'tenant@test.local',     null,  '{"account_type": "tenant"}'),  -- not confirmed yet
  ('00000000-0000-0000-0000-000000000006', 'stranger@test.local',   now(), '{"account_type": "tenant"}'),
  ('00000000-0000-0000-0000-000000000007', 'Extra@Test.local',      now(), '{"account_type": "landlord"}');
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000008', 'admin@test.local', now(), '{"account_type": "landlord"}');
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000009', 'phone@test.local', now(), '{"phone": "+237677000111"}'),
  ('00000000-0000-0000-0000-000000000010', 'badphone@test.local', now(), '{"phone": "12345"}');
select pg_temp.ok('the phone number from sign-up is saved; a wrong one is ignored',
  (select phone from public.profiles where id = '00000000-0000-0000-0000-000000000009') = '+237677000111'
  and (select phone from public.profiles where id = '00000000-0000-0000-0000-000000000010') is null);
delete from auth.users where id in ('00000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000010');

select pg_temp.ok('profiles auto-created on sign-up',
  (select count(*) from public.profiles where id::text like '00000000-0000-0000-0000-00000000000%') = 8);
select pg_temp.ok('account type from sign-up stored on the profile',
  (select account_type from public.profiles where id = '00000000-0000-0000-0000-000000000008') = 'landlord');
select pg_temp.ok('profile email copied (lower-case)',
  (select email from public.profiles where id = '00000000-0000-0000-0000-000000000007') = 'extra@test.local');
select pg_temp.ok('profile username taken from the sign-up (lower-case)',
  (select username from public.profiles where id = '00000000-0000-0000-0000-000000000007') = 'extra');

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

-- add_property_member (the app's "Add member" button)
create temp table m7 as select * from public.add_property_member(
  (select property_id from pg_temp.ids), '  EXTRA ', 'manager', true);
select pg_temp.ok('owner: add member by username (any case/spaces)',
  (select role from m7) = 'manager');
select pg_temp.ok('payment toggle ignored for non-caretakers',
  (select can_record_payments from m7) = false);
select pg_temp.fails('owner: adding an unknown username fails',
  format('select public.add_property_member(%L, ''nobody'', ''caretaker'')', (select property_id from pg_temp.ids)));
select pg_temp.fails('owner: adding an existing member fails',
  format('select public.add_property_member(%L, ''extra'', ''caretaker'')', (select property_id from pg_temp.ids)));
select pg_temp.ok('owner: sees members'' emails',
  (select count(*) from public.memberships m join public.profiles p on p.id = m.user_id
   where p.email is not null) = 5);
select pg_temp.ok('owner: can remove a member',
  pg_temp.affected('delete from public.memberships where user_id = ''00000000-0000-0000-0000-000000000007''') = 1);

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

insert into public.tenancies (property_id, apartment_id, tenant_id, monthly_rent, payment_interval_months, start_date, paid_until)
select i.property_id, a.id, t.id, 50000, 1, date '2026-01-31', date '2099-01-01'
from pg_temp.ids i, public.apartments a, public.tenants t where a.name = 'A1';
select pg_temp.ok('new tenancy: client-supplied paid_until ignored, starts at billing start',
  (select paid_until from public.tenancies) = date '2026-01-31');

select pg_temp.fails('only one active tenancy per apartment',
  $q$ insert into public.tenancies (property_id, apartment_id, tenant_id, monthly_rent, payment_interval_months, start_date)
      select i.property_id, a.id, t.id, 1, 1, current_date
      from pg_temp.ids i, public.apartments a, public.tenants t where a.name = 'A1' $q$);

select pg_temp.fails('manager: cannot edit paid_until directly',
  'update public.tenancies set paid_until = date ''2099-01-01''');
select pg_temp.fails('manager: cannot set tenants.user_id (link a stranger)',
  'update public.tenants set user_id = ''00000000-0000-0000-0000-000000000006''');
select pg_temp.ok('manager: cannot delete the property',
  pg_temp.affected('delete from public.properties') = 0);
select pg_temp.ok('manager: cannot manage members',
  pg_temp.affected('delete from public.memberships where role = ''caretaker''') = 0);
select pg_temp.fails('manager: cannot add members',
  format('select public.add_property_member(%L, ''extra'', ''caretaker'')', (select property_id from pg_temp.ids)));
select pg_temp.ok('manager: sees co-members'' profiles',
  (select count(*) from public.profiles) = 4);

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
select pg_temp.ok('amount defaults to monthly rent x months',
  (select amount from public.payments where id = (select payment_id from p1)) = 50000);

select pg_temp.fails('payments cannot be edited',  'update public.payments set amount = 1');
select pg_temp.fails('payments cannot be deleted', 'delete from public.payments');
select pg_temp.fails('payments cannot be inserted directly (RPC only)',
  $q$ insert into public.payments (property_id, tenancy_id, amount, months, period_start, period_end, paid_on)
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

select pg_temp.ok('tenant: sees own tenancy incl. rent', (select monthly_rent from public.tenancies) = 50000);
select pg_temp.ok('tenant: sees own payments',  (select count(*) from public.payments) = 3);
select pg_temp.ok('tenant: sees own receipts',  (select count(*) from public.receipts) = 3);
select pg_temp.ok('tenant: sees the property name', (select name from public.properties) = 'Test Court');
select pg_temp.ok('tenant: cannot see staff list', (select count(*) from public.memberships) = 0);
select pg_temp.fails('tenant: cannot record payments',
  'select public.record_payment((select id from public.tenancies), 1)');
select pg_temp.fails('tenant account: cannot create a property',
  'select public.create_property(''Tenant Place'', ''XAF'')');
select pg_temp.ok('tenant: agreement not accepted yet',
  (select agreement_accepted_at from public.tenancy_overview) is null);
select public.accept_tenancy_agreement((select id from public.tenancy_overview));
select pg_temp.ok('tenant: accepts the tenancy agreement',
  (select agreement_accepted_at from public.tenancy_overview) is not null);
select pg_temp.fails('tenant: cannot set the acceptance date directly',
  'update public.tenancies set agreement_accepted_at = null');
select pg_temp.ok('tenant: cannot edit own tenancy',
  pg_temp.affected('update public.tenancies set notes = ''x''') = 0);

-- ======================= STRANGER =============================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;

select pg_temp.ok('stranger: sees nothing',
  (select count(*) from public.properties) + (select count(*) from public.apartments)
  + (select count(*) from public.tenants) + (select count(*) from public.tenancy_overview)
  + (select count(*) from public.memberships) = 0);
select pg_temp.ok('stranger: sees only own profile (no other emails)',
  (select count(*) from public.profiles) = 1);

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

-- ======================= PHASES 4-5: start / end tenancy ======================
-- (manager) Uses a new apartment A3 so the checks above are unaffected.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

insert into public.apartments (property_id, name) select property_id, 'A3' from pg_temp.ids;
select pg_temp.fails('apartment names are unique within a property',
  'insert into public.apartments (property_id, name) select property_id, ''A3'' from pg_temp.ids');
create temp table a4 as select public.save_apartment(
  (select property_id from pg_temp.ids), ' A4 ', 60000, 'Corner flat') as id;
grant select on a4 to authenticated;
select pg_temp.ok('save_apartment: adds the apartment with its monthly rent',
  (select a.name = 'A4' and r.monthly_rent = 60000
   from public.apartments a join public.apartment_rents r on r.apartment_id = a.id
   where a.id = (select id from pg_temp.a4)));
select public.save_apartment((select property_id from pg_temp.ids), 'A4', 65000,
  p_apartment_id => (select id from pg_temp.a4));
select pg_temp.ok('save_apartment: edit updates the rent',
  (select monthly_rent from public.apartment_rents where apartment_id = (select id from pg_temp.a4)) = 65000);
select pg_temp.fails('save_apartment: rent must be more than zero',
  format('select public.save_apartment(%L, ''A5'', 0)', (select property_id from pg_temp.ids)));
select pg_temp.ok('save_apartment: refused call saved nothing',
  not exists (select 1 from public.apartments where name = 'A5'));
select pg_temp.fails('start_tenancy: occupied apartment refused',
  $q$ select public.start_tenancy((select id from public.apartments where name = 'A1'),
        40000, 1, current_date, p_tenant_name => 'Someone') $q$);
select pg_temp.ok('start_tenancy: refused attempt left no tenant contact behind',
  (select count(*) from public.tenants) = 1);

create temp table t3 as select public.start_tenancy(
  (select id from public.apartments where name = 'A3'), 40000, 1, date '2026-05-01',
  p_tenant_name => ' Nina New ', p_tenant_email => 'Nina@Test.local',
  p_billing_start_date => date '2026-06-01') as id;
grant select on t3 to authenticated;
select pg_temp.ok('start_tenancy: creates the new tenant contact',
  (select email from public.tenants where full_name = 'Nina New') = 'nina@test.local');
select pg_temp.ok('start_tenancy: rent counted from billing start (already paid until)',
  (select paid_until from public.tenancies where id = (select id from t3)) = date '2026-06-01');
select pg_temp.fails('start_tenancy: second tenancy on the same apartment refused',
  $q$ select public.start_tenancy((select id from public.apartments where name = 'A3'),
        1, 1, current_date, (select id from public.tenants where full_name = 'Nina New')) $q$);

-- Caretaker can't start or end tenancies.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.ok('caretaker: sees the apartment but NOT its rent',
  exists (select 1 from public.apartments where id = (select id from pg_temp.a4))
  and (select count(*) from public.apartment_rents) = 0);
select pg_temp.fails('caretaker: cannot add apartments via save_apartment',
  format('select public.save_apartment(%L, ''X'', 1)', (select property_id from pg_temp.ids)));
select pg_temp.fails('caretaker: cannot write apartment rents directly',
  $q$ insert into public.apartment_rents (apartment_id, property_id, monthly_rent)
      select id, property_id, 1 from public.apartments where name = 'A1' $q$);
select pg_temp.fails('caretaker: cannot start a tenancy',
  $q$ select public.start_tenancy((select id from public.apartments where name = 'A1'),
        1, 1, current_date, p_tenant_name => 'X') $q$);
select pg_temp.fails('caretaker: cannot end a tenancy',
  'select public.end_tenancy((select id from pg_temp.t3))');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.fails('end_tenancy: move-out before move-in refused',
  'select public.end_tenancy((select id from pg_temp.t3), date ''2026-04-01'')');
select public.end_tenancy((select id from pg_temp.t3), date '2026-09-30');
select pg_temp.ok('end_tenancy: ended with move-out date, apartment vacant again',
  (select status = 'ended' and end_date = date '2026-09-30' and ended_at is not null
   from public.tenancies where id = (select id from pg_temp.t3))
  and not exists (select 1 from public.tenancy_overview
                  where apartment_name = 'A3' and status = 'active'));
select pg_temp.fails('end_tenancy: cannot end twice',
  'select public.end_tenancy((select id from pg_temp.t3))');
select pg_temp.fails('ended tenancy cannot be reopened',
  'update public.tenancies set status = ''active'', ended_at = null where id = (select id from pg_temp.t3)');
create temp table t4 as select public.start_tenancy(
  (select id from public.apartments where name = 'A3'), 45000, 1, current_date,
  (select id from public.tenants where full_name = 'Nina New')) as id;
select pg_temp.ok('after ending, the apartment can be let again (existing contact)',
  (select count(*) from public.tenancies where apartment_id =
     (select id from public.apartments where name = 'A3')) = 2);

-- ======================= PAYMENTS, BALANCES, RENEWALS, ID NUMBERS =============
-- (manager) New apartment A6: 50,000/month, paid every 3 months.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select public.save_apartment((select property_id from pg_temp.ids), 'A6', 50000);
create temp table t6 as select public.start_tenancy(
  (select id from public.apartments where name = 'A6'), 50000, 3, date '2026-01-31',
  p_tenant_name => 'Paul Payer', p_tenant_id_number => ' ID-123456 ',
  p_end_date => date '2026-12-31') as id;
grant select on t6 to authenticated;
select pg_temp.ok('start_tenancy: ID number saved (owners/managers only table)',
  (select i.id_number from public.tenant_identities i join public.tenants t on t.id = i.tenant_id
   where t.full_name = 'Paul Payer') = 'ID-123456');
select pg_temp.fails('start_tenancy: interval must be 1-24 months',
  $q$ select public.start_tenancy(public.save_apartment((select property_id from pg_temp.ids), 'A7', 1),
        1, 0, current_date, p_tenant_name => 'X') $q$);

-- Pays 3 months but only 120,000 of 150,000.
create temp table pay6 as select * from public.record_payment(
  (select id from pg_temp.t6), 3, date '2026-02-01', 'cash', null, 120000);
grant select on pay6 to authenticated;
select pg_temp.ok('part payment: still covers the 3 months (Jan 31 -> Apr 30)',
  (select paid_until from pay6) = date '2026-04-30');
select pg_temp.ok('part payment: expected and paid amounts kept, 30,000 left to pay',
  (select expected_amount = 150000 and amount = 120000 and balance_after = 30000
   from public.payments where id = (select payment_id from pay6)));
select pg_temp.ok('tenancy_balances shows the 30,000 owed',
  (select balance from public.tenancy_balances where tenancy_id = (select id from pg_temp.t6)) = 30000);
select pg_temp.ok('tenancy_overview: paid_months = 3',
  (select paid_months from public.tenancy_overview where id = (select id from pg_temp.t6)) = 3);
select pg_temp.fails('rent payment needs 1-60 months',
  'select public.record_payment((select id from pg_temp.t6), 0)');
select pg_temp.fails('balance payment cannot cover months',
  'select public.record_payment((select id from pg_temp.t6), 1, p_amount => 10, p_kind => ''balance'')');
select pg_temp.fails('balance payment needs an amount',
  'select public.record_payment((select id from pg_temp.t6), p_kind => ''balance'')');

create temp table bal6 as select * from public.record_payment(
  (select id from pg_temp.t6), p_amount => 30000, p_kind => 'balance');
select pg_temp.ok('balance payment: clears what is owed, due date unchanged',
  (select balance_after from public.payments where id = (select payment_id from bal6)) = 0
  and (select paid_until from bal6) = date '2026-04-30');
select pg_temp.ok('rent payment gets its own reference code (PAY-XXXXXX)',
  (select reference_code from public.payments where id = (select payment_id from pay6)) ~ '^PAY-[2-9A-Z]{6}$');
select pg_temp.ok('balance payment shares the code of the receipt it completes',
  (select reference_code from public.payments where id = (select payment_id from bal6))
  = (select reference_code from public.payments where id = (select payment_id from pay6)));
select public.void_payment((select payment_id from bal6), 'Cheque bounced');
select pg_temp.ok('voiding the balance payment puts the 30,000 back',
  (select balance from public.tenancy_balances where tenancy_id = (select id from pg_temp.t6)) = 30000);

-- Renewal
select pg_temp.fails('renew: new end must be after the current one',
  'select public.renew_tenancy((select id from pg_temp.t6), date ''2026-06-30'')');
select public.renew_tenancy((select id from pg_temp.t6), date '2027-12-31', 55000, 'Second year');
select pg_temp.ok('renew: lease extended and rent changed, old values recorded',
  (select end_date = date '2027-12-31' and monthly_rent = 55000
   from public.tenancies where id = (select id from pg_temp.t6))
  and (select old_end_date = date '2026-12-31' and old_monthly_rent = 50000 and new_monthly_rent = 55000
       from public.tenancy_renewals where tenancy_id = (select id from pg_temp.t6)));
select pg_temp.fails('rent can only change through renew_tenancy (record kept)',
  'update public.tenancies set monthly_rent = 1 where id = (select id from pg_temp.t6)');
select pg_temp.ok('payment interval can be edited',
  pg_temp.affected('update public.tenancies set payment_interval_months = 6 where id = (select id from pg_temp.t6)') = 1);

-- Caretaker with payment permission
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.ok('caretaker: cannot see ID numbers, renewals or balances',
  (select count(*) from public.tenant_identities) + (select count(*) from public.tenancy_renewals)
  + (select count(*) from public.tenancy_balances) = 0);
select pg_temp.fails('caretaker: cannot renew',
  'select public.renew_tenancy((select id from pg_temp.t6), date ''2028-12-31'')');
select pg_temp.fails('caretaker: cannot set ID numbers',
  $q$ select public.set_tenant_id_number((select tenant_id from public.tenancy_overview where id = (select id from pg_temp.t6)), 'X') $q$);
create temp table pay7 as select * from public.record_payment((select id from pg_temp.t6), 1);
select pg_temp.ok('caretaker: records 1 month at the new rent (-> May 31)',
  (select paid_until from pay7) = date '2026-05-31');

reset role;
select pg_temp.ok('a new rent payment gets a new, different code',
  (select reference_code from public.payments where id = (select payment_id from pay7))
  <> (select reference_code from public.payments where id = (select payment_id from pay6)));
select pg_temp.ok('that payment expected the renewed rent (55,000)',
  (select expected_amount from public.payments where id = (select payment_id from pay7)) = 55000);

-- ======================= PHASE 2b: INVITE CODES =================================
-- (manager) Invite "Paul Payer" (tenancy t6, not linked yet).
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

create temp table inv as select * from public.create_tenant_invite(
  (select id from public.tenants where full_name = 'Paul Payer'));
grant select on inv to authenticated, anon;
select pg_temp.ok('invite: code looks like TEN-XXXXXX and lasts 7 days',
  (select code ~ '^TEN-[2-9A-Z]{6}$' and expires_at > now() + interval '6 days' from inv));
select pg_temp.ok('invite: owners/managers can see open codes',
  (select count(*) from public.tenant_invites where redeemed_at is null and cancelled_at is null) = 1);
select pg_temp.fails('invite: a linked tenant cannot be invited again',
  $q$ select public.create_tenant_invite((select id from public.tenants where full_name = 'Tina Tenant')) $q$);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.fails('caretaker: cannot create invites',
  $q$ select public.create_tenant_invite((select tenant_id from public.tenancy_overview where tenant_name = 'Paul Payer')) $q$);
select pg_temp.ok('caretaker: cannot see invite codes', (select count(*) from public.tenant_invites) = 0);

-- (stranger) Signs up and redeems the code.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select pg_temp.ok('redeem: wrong code refused (no error, attempt counted)',
  (public.redeem_tenant_invite('TEN-WRONG1') ->> 'ok')::boolean = false);
select pg_temp.ok('redeem: right code (any case) links the account',
  (public.redeem_tenant_invite(lower((select code from inv))) ->> 'property_name') = 'Test Court');
select pg_temp.ok('redeem: the new tenant now sees their tenancy',
  (select count(*) from public.tenancy_overview where tenant_name = 'Paul Payer') = 1);
select pg_temp.ok('redeem: and only their own (not other tenants)',
  (select count(*) from public.tenancy_overview where tenant_name <> 'Paul Payer') = 0);
select pg_temp.fails('stranger-tenant: cannot create invites',
  $q$ select public.create_tenant_invite((select tenant_id from public.tenancy_overview limit 1)) $q$);

-- (extra user) A used code doesn't work twice; too many wrong codes are blocked.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', true);
set local role authenticated;
select pg_temp.ok('redeem: a used code cannot be used again',
  (public.redeem_tenant_invite((select code from inv)) ->> 'ok')::boolean = false);
select public.redeem_tenant_invite('TEN-WRONG' || n) from generate_series(1, 9) as n;
select pg_temp.ok('redeem: after 10 wrong codes in an hour, blocked',
  (public.redeem_tenant_invite('TEN-WRONGX') ->> 'error') like 'Too many wrong codes%');

-- ======================= PHASE 2b: PASSWORD RESET =================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.fails('reset: a caretaker''s password is admin-only (manager refused)',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000003'')', (select property_id from pg_temp.ids)));
select pg_temp.ok('reset: manager may reset a tenant of the property',
  public.password_reset_target((select property_id from pg_temp.ids), '00000000-0000-0000-0000-000000000006')
  = '00000000-0000-0000-0000-000000000006');
select pg_temp.fails('reset: manager cannot reset the owner',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000001'')', (select property_id from pg_temp.ids)));
select pg_temp.fails('reset: nobody resets themselves this way',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000002'')', (select property_id from pg_temp.ids)));
select pg_temp.fails('reset: someone outside the property cannot be reset',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000007'')', (select property_id from pg_temp.ids)));

-- The caretaker also owns another property -> nobody here may reset them.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select public.create_property('Caretaker Own Place', 'XAF');
select pg_temp.fails('reset: caretaker cannot reset anyone',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000006'')', (select property_id from pg_temp.ids)));
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.fails('reset: a caretaker''s password is admin-only (owner refused)',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000003'')', (select property_id from pg_temp.ids)));
-- The tenant (stranger) also joins the caretaker's own place as staff:
-- then nobody here may reset them.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select public.add_property_member((select id from public.properties where name = 'Caretaker Own Place'), 'stranger', 'caretaker');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.fails('reset: not allowed for someone who also uses another property',
  format('select public.password_reset_target(%L, ''00000000-0000-0000-0000-000000000006'')', (select property_id from pg_temp.ids)));
select pg_temp.ok('reset: owner may reset a manager',
  public.password_reset_target((select property_id from pg_temp.ids), '00000000-0000-0000-0000-000000000002')
  = '00000000-0000-0000-0000-000000000002');

-- "Must change password" flag is cleared by the user themselves.
reset role;
update auth.users set raw_app_meta_data = '{"provider": "email", "must_change_password": true}'
where id = '00000000-0000-0000-0000-000000000006';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select public.password_changed();
reset role;
select pg_temp.ok('password_changed clears only the flag',
  (select raw_app_meta_data from auth.users where id = '00000000-0000-0000-0000-000000000006')
  = '{"provider": "email"}'::jsonb);

-- (owner) unlink the account again
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.unlink_tenant_account((select id from public.tenants where full_name = 'Paul Payer'));
select pg_temp.ok('unlink: the account is disconnected from the tenant',
  (select user_id from public.tenants where full_name = 'Paul Payer') is null);
reset role;
delete from public.properties where name = 'Caretaker Own Place';

-- ======================= LANDLORD-ONLY PROPERTIES, AGREEMENT ======================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.fails('team account (manager): cannot create a property',
  'select public.create_property(''Manager Place'', ''XAF'')');
select pg_temp.fails('staff cannot accept the agreement for the tenant',
  'select public.accept_tenancy_agreement((select id from pg_temp.t6))');
select pg_temp.fails('staff cannot fake the acceptance date',
  'update public.tenancies set agreement_accepted_at = now() where id = (select id from pg_temp.t6)');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.ok('caretaker sees whether the agreement was accepted',
  (select count(*) from public.tenancy_overview where agreement_accepted_at is not null) = 1);

-- ======================= CARETAKER PERMISSIONS ====================================
-- Caretaker 3 starts with no switches.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.ok('caretaker (no switches): no money, cannot edit apartments',
  not public.has_permission((select property_id from pg_temp.ids), 'money')
  and (select count(*) from public.tenancies) = 0);
select pg_temp.fails('caretaker (no switches): cannot add apartments',
  format('select public.save_apartment(%L, ''C1'', 1000)', (select property_id from pg_temp.ids)));

-- The owner gives caretaker 3 money, apartments, tenancies and team (not payments).
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.ok('owner can switch on caretaker permissions',
  pg_temp.affected($q$ update public.memberships
     set can_see_money = true, can_manage_apartments = true, can_manage_tenancies = true, can_manage_team = true
     where user_id = '00000000-0000-0000-0000-000000000003' and property_id = (select property_id from pg_temp.ids) $q$) = 1);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.ok('caretaker with money: sees rents, payments and ID numbers',
  (select count(*) from public.tenancies) >= 3
  and (select count(*) from public.payments) >= 1
  and (select count(*) from public.tenant_identities) >= 1);
select pg_temp.ok('caretaker with apartments: adds an apartment',
  public.save_apartment((select property_id from pg_temp.ids), 'C1', 1000) is not null);
create temp table c1t as select public.start_tenancy(
  (select id from public.apartments where name = 'C1'), 1000, 1, current_date, p_tenant_name => 'Cara') as id;
grant select on c1t to authenticated;
select pg_temp.ok('caretaker with tenancies: starts a tenancy',
  (select count(*) from public.tenancies where id = (select id from c1t)) = 1);
create temp table c1ret as select * from public.add_property_member(
  (select property_id from pg_temp.ids), 'extra', 'caretaker');
select pg_temp.ok('caretaker with team: adds a caretaker', (select count(*) from c1ret) = 1);
select pg_temp.fails('caretaker with team: cannot add an owner',
  format('select public.add_property_member(%L, ''stranger'', ''owner'')', (select property_id from pg_temp.ids)));
select pg_temp.fails('caretaker with team: cannot make themselves owner',
  'update public.memberships set role = ''owner'' where user_id = auth.uid() and property_id = (select property_id from pg_temp.ids)');
select pg_temp.ok('caretaker with team: cannot change or remove the owner (0 rows)',
  pg_temp.affected('update public.memberships set can_record_payments = true where role = ''owner''') = 0
  and pg_temp.affected('delete from public.memberships where role = ''owner''') = 0);
select pg_temp.ok('caretaker with everything: still cannot delete the property (0 rows)',
  pg_temp.affected('delete from public.properties where id = (select property_id from pg_temp.ids)') = 0);
select pg_temp.fails('caretaker without payments: cannot void payments',
  'select public.void_payment((select payment_id from pg_temp.pay7), ''x'')');
select pg_temp.fails('caretaker without payments: cannot record payments',
  'select public.record_payment((select id from c1t), 1)');

-- ======================= ANNOUNCEMENTS ============================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
create temp table ann_all as select public.send_announcement(
  (select property_id from pg_temp.ids), 'Water cut', 'No water on Saturday 8-12.') as id;
create temp table ann_sel as select public.send_announcement(
  (select property_id from pg_temp.ids), 'For Paul', 'Please call me.',
  array[(select id from public.tenants where full_name = 'Paul Payer')]) as id;
grant select on ann_all, ann_sel to authenticated;
select pg_temp.ok('caretaker sends to all tenants and to chosen tenants',
  (select audience from public.announcements where id = (select id from ann_all)) = 'all'
  and (select audience from public.announcements where id = (select id from ann_sel)) = 'selected');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.ok('tenant sees the "all" announcement, not the one for someone else',
  exists (select 1 from public.announcements where id = (select id from ann_all))
  and not exists (select 1 from public.announcements where id = (select id from ann_sel)));
select pg_temp.fails('tenant cannot send announcements',
  format('select public.send_announcement(%L, ''x'', ''y'')', (select property_id from pg_temp.ids)));

-- ======================= TICKETS =================================================
-- Tenant 5 (Tina, A1) reports an issue.
create temp table tk as select public.create_ticket(
  (select id from public.tenancy_overview where tenant_name = 'Tina Tenant' and status = 'active'),
  'Leaking tap', 'Kitchen tap drips all night', 'plumbing') as id;
grant select on tk to authenticated;
select pg_temp.ok('tenant creates a ticket and sees it',
  (select status from public.tickets where id = (select id from tk)) = 'open');
select public.add_ticket_message((select id from tk), 'It is getting worse');
select pg_temp.fails('tenant cannot change the ticket status',
  'select public.set_ticket_status((select id from pg_temp.tk), ''resolved'')');
select pg_temp.fails('tenant cannot open a ticket on someone else''s tenancy',
  'select public.create_ticket((select id from pg_temp.t6), ''x'')');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.ok('caretaker sees the ticket and the tenant''s message',
  exists (select 1 from public.tickets where id = (select id from tk))
  and (select count(*) from public.ticket_messages where ticket_id = (select id from tk) and not from_staff) = 1);
select public.set_ticket_status((select id from tk), 'in_progress');
select public.add_ticket_message((select id from tk), 'Plumber comes tomorrow');
select pg_temp.ok('caretaker updates the status and replies (marked as team)',
  (select status from public.tickets where id = (select id from tk)) = 'in_progress'
  and (select count(*) from public.ticket_messages where ticket_id = (select id from tk) and from_staff) = 1);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', true);
set local role authenticated;
select pg_temp.ok('another caretaker on the team also sees the tickets',
  (select count(*) from public.tickets) >= 1);
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select pg_temp.ok('a stranger to the property sees no tickets or messages',
  (select count(*) from public.tickets where property_id = (select property_id from pg_temp.ids)) = 0
  and (select count(*) from public.ticket_messages) = 0);

-- ======================= RECEIPTS: signatures, confirm, dispute ==================
-- Tina's payments: p1 (voided), p2, p3.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.fails('owner cannot write a receipt signature (only the signing function can)',
  format('update public.receipts set signature = ''fake'' where payment_id = %L', (select payment_id from p2)));

reset role;
update public.receipts set issued_at = now() - interval '25 hours' where payment_id = (select payment_id from p3);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.fails('tenant cannot answer after 24 hours (accepted automatically)',
  format('select public.confirm_receipt(%L)', (select payment_id from p3)));
reset role;
update public.receipts set issued_at = now() where payment_id = (select payment_id from p3);
set local role authenticated;

select public.confirm_receipt((select payment_id from p2));
select public.confirm_receipt((select payment_id from p2));
select pg_temp.ok('tenant confirms a receipt (twice is harmless, one answer kept)',
  (select count(*) from public.receipt_responses where payment_id = (select payment_id from p2)
   and response = 'confirmed') = 1);
select pg_temp.fails('tenant cannot dispute a receipt they confirmed',
  format('select public.dispute_receipt(%L, ''amount'', ''x'')', (select payment_id from p2)));
select pg_temp.fails('tenant cannot answer for a voided payment',
  format('select public.confirm_receipt(%L)', (select payment_id from p1)));
select pg_temp.fails('a dispute needs an explanation',
  format('select public.dispute_receipt(%L, ''amount'', ''  '')', (select payment_id from p3)));
create temp table disp as select public.dispute_receipt(
  (select payment_id from p3), 'amount', 'I paid 60,000 not 50,000') as id;
grant select on disp to authenticated;
select pg_temp.ok('tenant disputes a receipt: a receipt ticket linked to the payment',
  (select category = 'receipt' and payment_id = (select payment_id from p3)
   from public.tickets where id = (select id from disp))
  and (select response from public.receipt_responses where payment_id = (select payment_id from p3)) = 'disputed');
select pg_temp.fails('tenant cannot open a receipt ticket by hand',
  $q$ select public.create_ticket((select id from public.tenancy_overview where tenant_name = 'Tina Tenant'
       and status = 'active'), 'x', null, 'receipt') $q$);
select public.add_ticket_message((select id from tk), 'Sent from the queue', '11111111-1111-1111-1111-111111111111');
select public.add_ticket_message((select id from tk), 'Sent from the queue', '11111111-1111-1111-1111-111111111111');
select pg_temp.ok('a queued message sent twice is saved once',
  (select count(*) from public.ticket_messages where body = 'Sent from the queue') = 1);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select pg_temp.fails('a stranger cannot confirm someone''s receipt',
  format('select public.confirm_receipt(%L)', (select payment_id from p3)));
select pg_temp.ok('a stranger sees no receipt answers', (select count(*) from public.receipt_responses) = 0);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.ok('caretaker without money: does not see receipt disputes',
  not exists (select 1 from public.tickets where id = (select id from disp))
  and (select count(*) from public.receipt_responses) = 0);
select pg_temp.fails('caretaker without money: cannot reply to a receipt dispute',
  'select public.add_ticket_message((select id from pg_temp.disp), ''hi'')');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.ok('caretaker with money: sees the dispute and the answers',
  exists (select 1 from public.tickets where id = (select id from disp))
  and (select count(*) from public.receipt_responses) = 2);
select public.add_ticket_message((select id from disp), 'Checking the mobile money record');
select public.set_ticket_status((select id from disp), 'resolved');
select pg_temp.ok('caretaker with money: replies to and resolves the dispute',
  (select status from public.tickets where id = (select id from disp)) = 'resolved');

-- ======================= BILLS ===================================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.ok('every property starts with Water, Electricity and Repairs',
  (select string_agg(name, ',' order by name) from public.bill_types
   where property_id = (select property_id from pg_temp.ids) and is_standard) = 'Electricity,Repairs,Water');
select pg_temp.fails('caretaker without apartments permission: cannot add a bill type',
  'insert into public.bill_types (property_id, name) select property_id, ''Internet'' from pg_temp.ids');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.bill_types (property_id, name) select property_id, 'Internet' from pg_temp.ids;
select pg_temp.ok('owner adds a custom bill type and switches Water off',
  pg_temp.affected('update public.bill_types set enabled = false where name = ''Water'' and property_id = (select property_id from pg_temp.ids)') = 1
  and exists (select 1 from public.bill_types where name = 'Internet'));
select pg_temp.fails('standard types cannot be renamed',
  'update public.bill_types set name = ''Aqua'' where name = ''Water''');
select pg_temp.ok('standard types cannot be deleted (0 rows)',
  pg_temp.affected('delete from public.bill_types where name = ''Electricity'' and property_id = (select property_id from pg_temp.ids)') = 0);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.fails('no bills of a switched-off type',
  $q$ select public.create_bill((select property_id from pg_temp.ids),
       (select id from public.bill_types where name = 'Water' and property_id = (select property_id from pg_temp.ids)),
       current_date + 14, 5000) $q$);
create temp table bl as select public.create_bill((select property_id from pg_temp.ids),
  (select id from public.bill_types where name = 'Electricity' and property_id = (select property_id from pg_temp.ids)),
  current_date + 14, 7500, 'Electricity - September') as id;
grant select on bl to authenticated;
select pg_temp.ok('caretaker bills every occupied apartment',
  (select count(*) from public.bill_assignments where bill_id = (select id from bl))
  = (select count(*) from public.tenancy_overview where status = 'active'
     and property_id = (select property_id from pg_temp.ids)));
select public.set_bill_paid(
  (select a.id from public.bill_assignments a join public.tenancy_overview o on o.id = a.tenancy_id
   where a.bill_id = (select id from bl) and o.tenant_name = 'Tina Tenant'), true);
select pg_temp.ok('caretaker with payments marks one apartment paid; the others stay open',
  (select count(*) from public.bill_assignments where bill_id = (select id from bl) and paid_at is not null) = 1
  and (select count(*) from public.bill_assignments where bill_id = (select id from bl) and paid_at is null) >= 1);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.fails('caretaker without payments: cannot mark bills paid',
  'select public.set_bill_paid((select id from public.bill_assignments limit 1), true)');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.ok('tenant sees only their own part of the bill (paid)',
  (select count(*) from public.bill_assignments) = 1
  and (select paid_at is not null from public.bill_assignments)
  and (select title from public.bills) = 'Electricity - September');
select pg_temp.fails('tenant cannot create bills',
  $q$ select public.create_bill((select property_id from pg_temp.ids),
       (select id from public.bill_types where name = 'Electricity' limit 1), current_date, 1) $q$);

-- ======================= UNITS: contact phone, agreements, waivers, repairs =======
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.properties set contact_phone = '+237 677 000 111' where id = (select property_id from pg_temp.ids);
create temp table tina as select id, apartment_id from public.tenancy_overview
  where tenant_name = 'Tina Tenant' and status = 'active';
grant select on tina to authenticated;

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select public.accept_tenancy_agreement((select id from pg_temp.tina));
select pg_temp.ok('tenant sees the property''s contact phone',
  (select contact_phone from public.properties) = '+237 677 000 111');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.fails('caretaker without apartments permission: cannot change the agreement',
  format('select public.set_agreement(%L, null, ''x'')', (select property_id from pg_temp.ids)));

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table ag1 as select public.set_agreement((select property_id from pg_temp.ids), null, 'House rules for {tenant}') as n;
select pg_temp.ok('owner writes the property agreement: current tenants must accept again',
  (select n from ag1) >= 1
  and (select agreement_accepted_at from public.tenancies where id = (select id from pg_temp.tina)) is null);
select pg_temp.ok('saving the same text again changes nothing',
  public.set_agreement((select property_id from pg_temp.ids), null, ' House rules for {tenant} ') = 0);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.ok('tenant sees the text that applies to them',
  (select agreement_text from public.tenancy_overview where id = (select id from pg_temp.tina)) = 'House rules for {tenant}');
select public.accept_tenancy_agreement((select id from pg_temp.tina));
select pg_temp.ok('accepting keeps a copy of the exact text',
  (select agreement_accepted_text from public.tenancies where id = (select id from pg_temp.tina)) = 'House rules for {tenant}');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table ag2 as select public.set_agreement((select property_id from pg_temp.ids), (select apartment_id from pg_temp.tina), 'Special unit') as n;
select pg_temp.ok('a unit''s own agreement: only that unit''s tenant accepts again',
  (select n from ag2) = 1
  and (select agreement_text from public.tenancy_overview where id = (select id from pg_temp.tina)) = 'Special unit');

-- Waiving
create temp table wb as select public.create_bill((select property_id from pg_temp.ids),
  (select id from public.bill_types where name = 'Electricity' and property_id = (select property_id from pg_temp.ids)),
  current_date + 7, 3000, 'Power - test', null, array[(select id from pg_temp.tina)]) as id;
grant select on wb to authenticated;
select pg_temp.fails('waiving needs a reason',
  'select public.set_bill_waived((select id from public.bill_assignments where bill_id = (select id from pg_temp.wb)), true)');
select public.set_bill_waived((select id from public.bill_assignments where bill_id = (select id from wb)), true, 'Pipe was our fault');
select pg_temp.ok('owner waives one unit''s bill',
  (select waived_at is not null and paid_at is null from public.bill_assignments where bill_id = (select id from wb)));
select pg_temp.fails('a waived bill cannot be marked paid',
  'select public.set_bill_paid((select id from public.bill_assignments where bill_id = (select id from pg_temp.wb)), true)');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.ok('tenant sees the bill as waived',
  (select waive_reason from public.bill_assignments where bill_id = (select id from wb)) = 'Pipe was our fault');
select pg_temp.fails('tenant cannot waive bills',
  'select public.set_bill_waived((select id from public.bill_assignments limit 1), false)');
select pg_temp.fails('tenant cannot log repairs',
  'select public.add_repair((select apartment_id from pg_temp.tina), ''x'')');
select pg_temp.ok('tenant sees no repair log', (select count(*) from public.apartment_repairs((select apartment_id from pg_temp.tina))) = 0);

-- Different amount per apartment
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
create temp table pb as select public.create_bill_amounts((select property_id from pg_temp.ids),
  (select id from public.bill_types where name = 'Electricity' and property_id = (select property_id from pg_temp.ids)),
  current_date + 7, jsonb_build_object((select id from pg_temp.tina)::text, 4500), 'Power by meter') as id;
grant select on pb to authenticated;
select pg_temp.ok('caretaker bills one amount per apartment',
  (select amount from public.bill_assignments where bill_id = (select id from pb)) = 4500);
select pg_temp.fails('amounts must be above zero',
  format($q$ select public.create_bill_amounts(%L, (select id from public.bill_types where name = 'Electricity' and property_id = %L),
    current_date, jsonb_build_object(%L, 0)) $q$,
    (select property_id from pg_temp.ids), (select property_id from pg_temp.ids), (select id from pg_temp.tina)));
select pg_temp.fails('only occupied apartments of this property',
  format($q$ select public.create_bill_amounts(%L, (select id from public.bill_types where name = 'Electricity' and property_id = %L),
    current_date, jsonb_build_object(%L, 100)) $q$,
    (select property_id from pg_temp.ids), (select property_id from pg_temp.ids), gen_random_uuid()));
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select pg_temp.fails('a stranger cannot bill per apartment',
  format($q$ select public.create_bill_amounts(%L, gen_random_uuid(), current_date, '{}'::jsonb) $q$,
    (select property_id from pg_temp.ids)));

-- Repairs
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table rp as select public.add_repair((select apartment_id from pg_temp.tina), 'New tap', 'Kitchen tap replaced',
  current_date, 12000, (select id from pg_temp.tk), 8000, current_date + 10) as id;
grant select on rp to authenticated;
select pg_temp.ok('owner logs a repair for the issue and bills the tenant (Repairs type)',
  (select r.cost = 12000 and r.ticket_id = (select id from pg_temp.tk) and r.bill_id is not null
   from public.apartment_repairs((select apartment_id from pg_temp.tina)) r where r.id = (select id from rp))
  and (select t.name from public.apartment_repairs((select apartment_id from pg_temp.tina)) r
       join public.bills b on b.id = r.bill_id join public.bill_types t on t.id = b.bill_type_id
       where r.id = (select id from rp)) = 'Repairs'
  and (select a.amount from public.apartment_repairs((select apartment_id from pg_temp.tina)) r
       join public.bill_assignments a on a.bill_id = r.bill_id where r.id = (select id from rp)) = 8000);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.add_repair((select apartment_id from pg_temp.tina), 'Bulb', null, null, 500);
select pg_temp.ok('caretaker without money: logs repairs, never sees or sets costs',
  (select count(*) from public.apartment_repairs((select apartment_id from pg_temp.tina))) = 2
  and (select count(*) from public.apartment_repairs((select apartment_id from pg_temp.tina)) where cost is not null) = 0);
select pg_temp.ok('caretaker cannot read the repairs table directly', (select count(*) from public.repairs) = 0);
select pg_temp.fails('caretaker cannot remove someone else''s repair',
  'select public.delete_repair((select id from pg_temp.rp))');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select pg_temp.fails('a stranger cannot log repairs',
  'select public.add_repair((select apartment_id from pg_temp.tina), ''x'')');

-- ======================= NOTIFICATIONS ==========================================
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select public.register_device('tina-phone-token-123', 'android');
select pg_temp.ok('tenant registers their phone and sees only their own',
  (select count(*) from public.device_tokens) = 1);
select pg_temp.ok('tenant sees only their own notifications (and has some)',
  (select count(*) from public.notifications) > 0
  and (select count(*) from public.notifications where user_id <> auth.uid()) = 0);
select pg_temp.ok('tenant was told about the team''s reply and new bills',
  exists (select 1 from public.notifications where title like 'New reply:%')
  and exists (select 1 from public.notifications where title like 'New bill:%'));
select pg_temp.ok('tenant got the announcement, saying which property it is from',
  exists (select 1 from public.notifications where title = 'Announcement from Test Court: Water cut'));
select pg_temp.fails('tenant cannot create notifications directly',
  $q$ select public.notify(auth.uid(), null, null, 'x', 'x', 'x', null) $q$);
select pg_temp.fails('tenant cannot run the reminder schedule',
  $q$ select public.queue_scheduled_notifications('morning') $q$);
select pg_temp.fails('tenant cannot send rent reminders',
  'select public.send_rent_reminder((select id from pg_temp.tina))');
select public.mark_notifications_read();
select pg_temp.ok('tenant marks their notifications read',
  (select count(*) from public.notifications where read_at is null) = 0);

reset role;
select pg_temp.ok('the team heard about the new issue; nobody about their own action',
  exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000004'
          and title like 'New issue at %')
  and not exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000005'
          and title like 'New issue at %'));
select pg_temp.ok('a confirmed receipt is announced to staff who may see money only',
  exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000001'
          and title like 'Tina Tenant confirmed receipt %')
  and not exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000004'
          and title like '%confirmed receipt%'));
select pg_temp.ok('receipt disputes go only to staff who may see money',
  exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000003' and kind = 'dispute')
  and not exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000004' and kind = 'dispute'));

-- The schedule, run as the database (like pg_cron). Tina's paid-until = P.
select set_config('request.jwt.claim.sub', '', true);  -- pg_cron runs as nobody
create temp table pu as select paid_until as p from public.tenancies where id = (select id from pg_temp.tina);
create function pg_temp.rent_count() returns bigint language sql as
  $$ select count(*) from public.notifications where kind = 'rent' and tenancy_id = (select id from pg_temp.tina) $$;
update public.tenancies set reminders_muted_until = null where id = (select id from pg_temp.tina);
select public.queue_scheduled_notifications('morning', ((select p from pu) - interval '1 month')::date);
select pg_temp.ok('one month before: a reminder at 8:00', pg_temp.rent_count() = 1);
select public.queue_scheduled_notifications('morning', ((select p from pu) - interval '1 month')::date);
select public.queue_scheduled_notifications('evening', ((select p from pu) - interval '1 month')::date);
select pg_temp.ok('...only once, and not again at 20:00', pg_temp.rent_count() = 1);
select public.queue_scheduled_notifications('morning', (select p from pu) - 5);
select public.queue_scheduled_notifications('evening', (select p from pu) - 5);
select pg_temp.ok('5 days before: at 20:00', pg_temp.rent_count() = 2);
select public.queue_scheduled_notifications('morning', (select p from pu) - 4);
select public.queue_scheduled_notifications('evening', (select p from pu) - 4);
select pg_temp.ok('nothing on other days', pg_temp.rent_count() = 2);
select public.queue_scheduled_notifications('morning', (select p from pu));
select pg_temp.ok('on the due date: at 8:00', pg_temp.rent_count() = 3
  and exists (select 1 from public.notifications where kind = 'rent' and title = 'Rent is due today'));
select public.queue_scheduled_notifications('morning', (select p from pu) + 3);
select public.queue_scheduled_notifications('evening', (select p from pu) + 3);
select public.queue_scheduled_notifications('evening', (select p from pu) + 6);
select public.queue_scheduled_notifications('morning', (select p from pu) + 6);
select pg_temp.ok('every 3 days overdue, alternating 20:00 and 8:00', pg_temp.rent_count() = 5
  and exists (select 1 from public.notifications where kind = 'rent' and body like '%(3 days ago)%'));
update public.tenancies set reminders_muted_until = (select p from pu) + 10 where id = (select id from pg_temp.tina);
select public.queue_scheduled_notifications('morning', (select p from pu) + 9);
select public.queue_scheduled_notifications('evening', (select p from pu) + 9);
select pg_temp.ok('a paused unit gets no reminders', pg_temp.rent_count() = 5);
update public.tenancies set reminders_muted_until = null where id = (select id from pg_temp.tina);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
create temp table due2 as select public.create_bill((select property_id from pg_temp.ids),
  (select id from public.bill_types where name = 'Electricity' and property_id = (select property_id from pg_temp.ids)),
  current_date + 2, 2500, 'Power - reminder test', null, array[(select id from pg_temp.tina)]) as id;
select public.queue_scheduled_notifications('morning', current_date);
select pg_temp.ok('bills: a reminder 2 days before the due date',
  exists (select 1 from public.notifications where title = 'Bill due in 2 days: Power - reminder test'));

-- A payment: the tenant is asked to confirm the receipt.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select public.record_payment((select id from pg_temp.tina), 1);
select pg_temp.ok('a new receipt asks the tenant to confirm it',
  exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000005'
          and kind = 'receipt' and title = 'Please confirm your receipt'
          and body like '%confirm it within 24 hours.'));

-- Staff: send now, pause
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.send_rent_reminder((select id from pg_temp.tina));
select pg_temp.fails('one reminder per 6 hours',
  'select public.send_rent_reminder((select id from pg_temp.tina))');
select pg_temp.ok('caretaker pauses reminders for a week',
  public.set_rent_reminders_muted((select id from pg_temp.tina), 7) is not null);
reset role;
select pg_temp.ok('the manual reminder reached the tenant',
  exists (select 1 from public.notifications where kind = 'rent_manual'
          and user_id = '00000000-0000-0000-0000-000000000005'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
set local role authenticated;
select pg_temp.fails('a stranger cannot pause reminders',
  'select public.set_rent_reminders_muted((select id from pg_temp.tina), 30)');
select pg_temp.ok('a stranger sees nobody''s phones or notifications',
  (select count(*) from public.device_tokens) = 0
  and (select count(*) from public.notifications where user_id <> auth.uid()) = 0);

-- ======================= SUPER ADMIN (read-only) ================================
reset role;
insert into public.app_admins (user_id) values ('00000000-0000-0000-0000-000000000008');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', true);
set local role authenticated;

select pg_temp.ok('admin: is_app_admin() says yes', public.is_app_admin());
select pg_temp.ok('admin: sees every property, tenancy, payment (with amounts) and ID number',
  (select count(*) from public.properties) >= 1
  and (select count(*) from public.tenancy_overview) >= 3
  and (select sum(amount) from public.payments) > 0
  and (select count(*) from public.tenant_identities) >= 1
  and (select count(*) from public.memberships) >= 4);
select pg_temp.ok('admin: reads the activity log',
  (select count(*) from public.activity_log where table_name = 'payments' and action = 'INSERT') >= 1);
select pg_temp.fails('admin: cannot record payments',
  'select public.record_payment((select id from pg_temp.t6), 1)');
select pg_temp.fails('admin: cannot void payments',
  'select public.void_payment((select payment_id from pg_temp.pay6), ''x'')');
select pg_temp.fails('admin: cannot start tenancies',
  $q$ select public.start_tenancy((select id from public.apartments where name = 'A2' limit 1), 1, 1, current_date, p_tenant_name => 'X') $q$);
select pg_temp.fails('admin: cannot renew tenancies',
  'select public.renew_tenancy((select id from pg_temp.t6), date ''2030-01-01'')');
select pg_temp.fails('admin: cannot add apartments',
  'insert into public.apartments (property_id, name) select property_id, ''ZZ'' from pg_temp.ids');
select pg_temp.fails('admin: cannot create invite codes',
  $q$ select public.create_tenant_invite((select id from public.tenants where full_name = 'Paul Payer')) $q$);
select pg_temp.ok('admin: cannot edit tenancies, members or delete properties (0 rows)',
  pg_temp.affected('update public.tenancies set notes = ''x''') = 0
  and pg_temp.affected('update public.memberships set role = ''caretaker''') = 0
  and pg_temp.affected('delete from public.properties') = 0);
select pg_temp.ok('admin: may reset anyone''s password (even an owner, no property needed)',
  public.password_reset_target(null, '00000000-0000-0000-0000-000000000001')
  = '00000000-0000-0000-0000-000000000001');
select pg_temp.fails('admin: not their own password this way',
  'select public.password_reset_target(null, ''00000000-0000-0000-0000-000000000008'')');

-- Others: no admin powers, no activity log.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.ok('manager: not an admin, cannot read the activity log',
  not public.is_app_admin() and (select count(*) from public.activity_log) = 0);
select pg_temp.fails('manager: cannot transfer ownership',
  format('select public.admin_transfer_ownership(%L, ''manager'')', (select property_id from pg_temp.ids)));
select pg_temp.fails('nobody can write to the activity log',
  'insert into public.activity_log (table_name, action) values (''x'', ''y'')');

-- Activity log content
reset role;
select pg_temp.ok('activity log: who did it, and before/after of a rent change',
  exists (select 1 from public.activity_log
          where table_name = 'tenancies' and action = 'UPDATE'
            and actor_id = '00000000-0000-0000-0000-000000000002'
            and (old_data ->> 'monthly_rent')::bigint = 50000
            and (new_data ->> 'monthly_rent')::bigint = 55000));

-- Last owner: the only owner's account can't be deleted until the admin
-- transfers ownership.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', true);
set local role authenticated;
create temp table extra_prop as select id from public.create_property('Extra Place', 'XAF');
grant select on extra_prop to authenticated;
reset role;
select pg_temp.fails('deleting the only owner''s account is refused',
  'delete from auth.users where id = ''00000000-0000-0000-0000-000000000007''');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', true);
set local role authenticated;
select public.admin_transfer_ownership((select id from extra_prop), ' Stranger ');
reset role;
select pg_temp.ok('admin transferred ownership',
  exists (select 1 from public.memberships where property_id = (select id from extra_prop)
          and user_id = '00000000-0000-0000-0000-000000000006' and role = 'owner'));
select pg_temp.ok('after the transfer the old owner''s account can be deleted',
  pg_temp.affected('delete from auth.users where id = ''00000000-0000-0000-0000-000000000007''') = 1);
delete from public.properties where id = (select id from extra_prop);

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
  '00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000006',
  '00000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000008');

select n, passed, test, detail from results order by n;
