# Build Plan

The step-by-step roadmap for this app. Work through the phases in order and tick items off (`[x]`) as they're finished.
Each phase ends with a **Done when** check, something you can actually run or test. Don't start the next phase until it passes.

See [CLAUDE.md](CLAUDE.md) for the domain model, roles and business rules this plan builds on.

---

## Where we are

> **Current phase:** Phase 0: Setup
> **Last updated:** 2026-09-27

---

## Open decisions

Answer these before the phase that needs them. Record the answer here and move it to *Decided* below.

- [ ] **What does "no owner" mean?** (needed by Phase 1)
  - A: An apartment can have no tenant (vacant). This is already supported, so nothing changes.
  - B: A property can exist without an `owner` account (e.g. a manager runs it for an owner who never signs up). Then rule 6 in CLAUDE.md becomes "a property must always keep at least one **owner or manager**."
- [ ] **How do tenants get accounts?** (needed by Phase 5)
  - Email invite / join code / landlord adds the tenant as a contact first and links an account later.

### Decided
_(nothing yet)_

---

## Phase 0: Setup

- [x] Flutter project created
- [x] Supabase project created
- [x] Core packages added: `supabase_flutter`, `flutter_riverpod`, `go_router`, `intl`, `flutter_dotenv`
- [x] `.env` file created
- [x] Scaffold files exist: router, theme, app shell, login page, properties page
- [x] Add `.env` to `.gitignore`; add `.env.example` with placeholder keys
- [x] `git init` and first commit (`.env` confirmed **not** included)
- [ ] **(You)** Install the Supabase CLI, then `supabase init` + `supabase link` (creates `supabase/migrations/`)
- [x] Replace the counter demo in `main.dart`: load `.env`, start Supabase, wrap in `ProviderScope`, use the router and theme
- [x] Switch the router to `go_router`
- [x] Add Android `INTERNET` permission (needed for release builds)
- [x] Register `.env` as an asset in `pubspec.yaml`
- [ ] **(You)** Check the Supabase keys in `.env` are correct, then run the app on your phone

**Done when:** the app runs on your phone, connects to Supabase, and shows the login page from the router.

---

## Phase 1: Core database and security (most important)

- [ ] Tables: `profiles`, `properties`, `memberships`, `apartments`, `tenancies`, `payments`, `receipts`
- [ ] Auto-create a `profiles` row when a user signs up (trigger on `auth.users`)
- [ ] Helper SQL functions, e.g. `has_role(property_id, roles[])` and `is_tenant_of(tenancy_id)`
- [ ] RLS enabled and policies written for **every** table above
- [ ] RPC `create_property`: creates the property and the creator's membership together
- [ ] RPC `record_payment`: inserts the payment, moves `paid_until` forward and creates the receipt number, all in one transaction
- [ ] RPC `void_payment`: adds a void record with a reason (the original row is never changed)
- [ ] Receipt numbers sequential per property (e.g. `RCT-2026-0001`), generated in the database
- [ ] Partial unique index: only one active tenancy per apartment
- [ ] Money stored as `bigint` (smallest unit); dates stored in UTC
- [ ] App users can't UPDATE or DELETE on `payments`
- [ ] Caretaker-safe view(s) with no money columns
- [ ] "Last owner" (or "last owner/manager") rule enforced by a trigger, per the open decision above

**Done when:** you log in as test users for each role (owner, manager, caretaker with and without `can_record_payments`, tenant) in the SQL editor and confirm each one can see and do exactly what the permissions table in CLAUDE.md allows. Nothing more.

---

## Phase 2: Login and signup

- [ ] Email/password signup and login
- [ ] Profile screen (name, phone)
- [ ] Router sends logged-out users to login and logged-in users to home
- [ ] Logout

**Done when:** you can sign up, log out, log back in, and the app remembers the session after a restart.

---

## Phase 3: Properties and members

- [ ] List the properties I'm a member of
- [ ] Create a property (calls `create_property`)
- [ ] Edit a property; delete it (owner only)
- [ ] Invite or add members with a role
- [ ] Caretaker `can_record_payments` setting
- [ ] Change a member's role or remove a member (the last owner/manager is blocked)

**Done when:** two test accounts share a property with different roles, and each one sees the right actions.

---

## Phase 4: Apartments

- [ ] List apartments in a property, each marked Vacant or Occupied
- [ ] Add and edit apartments (owner and manager only)

**Done when:** a caretaker can view apartments but can't add or edit them, and the database also blocks it.

---

## Phase 5: Tenancies

- [ ] Start a tenancy: tenant, rent amount, frequency, start date
- [ ] Link the tenant's account (method per the open decision above)
- [ ] End a tenancy, which marks the apartment Vacant
- [ ] Tenancy history for each apartment

**Done when:** an apartment can't get a second active tenancy, and ending one frees it.

---

## Phase 6: Payments and receipts (core feature)

- [ ] Record-payment screen (calls `record_payment`)
- [ ] Rent status computed from `paid_until`: Paid / Due soon (7-day grace) / Overdue
- [ ] Payment history for each tenancy
- [ ] Void a payment with a reason
- [ ] Add `pdf` + `printing` packages
- [ ] Receipt PDF: view, share, print

**Done when:** recording a payment moves `paid_until` forward and creates the next receipt number, the PDF can be shared, and voiding works without editing the original.

---

## Phase 7: Dashboard

- [ ] For each property: overdue and due-soon tenants
- [ ] Totals collected and outstanding (hidden from caretakers)

**Done when:** a caretaker's dashboard shows no money figures.

---

## Phase 8: Bills

- [ ] Tables `bills` + `bill_assignments` with RLS
- [ ] Create a bill or task for all apartments or selected ones
- [ ] Each assignment has its own status, with overdue worked out from dates (manual override allowed)

**Done when:** one bill assigned to three apartments can be marked paid for one while the other two stay open.

---

## Phase 9: Tenant side and tickets

- [ ] Tenant home: my rent status, receipts, bills
- [ ] Add `image_picker`; Supabase Storage bucket with its own access policies
- [ ] `tickets` table with RLS; tenants create tickets with photos
- [ ] Staff view, reply to and change the status of tickets

**Done when:** a tenant sees only their own tickets and data, and staff can respond.

---

## Phase 10: Maintenance and history

- [ ] `maintenance_records` table; cost hidden from caretakers
- [ ] Turn a resolved ticket into a maintenance record
- [ ] Condition reports (move-in / move-out, notes + photos)
- [ ] Timeline for each apartment: tenancies, payments, repairs, tickets

**Done when:** an apartment's timeline shows its full history, with the right parts hidden for each role.

---

## Phase 11: Notifications

- [ ] Firebase project + `firebase_messaging` (FCM only)
- [ ] Store device tokens for each user
- [ ] Edge Function on a daily schedule: rent due-soon and overdue reminders
- [ ] Alerts for new tickets and ticket replies

**Done when:** a test tenancy about to fall due triggers a push notification on your phone.

---

## Phase 12: Polish and release

- [ ] Loading, empty and error states on every screen
- [ ] Handle no internet connection gracefully
- [ ] Unit tests for rent-status and period calculations
- [ ] App icon, name, splash screen
- [ ] Signed Android release build

**Done when:** the release APK installs and works on a phone that has never run the debug build.

---

## Out of scope for v1

- In-app payments (rent and bills are paid outside the app)
- iOS release (Android first)
- More than one active tenancy per apartment
