# Build Plan

The step-by-step roadmap for this app. Work through the phases in order and tick items off (`[x]`) as they're finished.
Each phase ends with a **Done when** check, something you can actually run or test. Don't start the next phase until it passes.

See [CLAUDE.md](CLAUDE.md) for the domain model, roles and business rules this plan builds on.

---

## Where we are

> **Current phase:** Phase 2c: Account types and super admin (built; see its (You) steps). Phase 2b (usernames, invites) also needs its (You) steps: Confirm email OFF, delete the old account. Phase 6 payments/receipts also built and waiting for your phone test. Phases 3-5 phone tests are also still open. Email confirmation deferred, see Decided.
> **Last updated:** 2026-10-02 (offline use, signed receipts and tenant confirmations built; see their (You) step)

---

## Open decisions

Answer these before the phase that needs them. Record the answer here and move it to *Decided* below.

_(none right now)_

### Decided

- **Push notifications** (2026-10-03): app name Homedly, ID com.awembom.rental, Firebase project homedly-4a906, Android only for now. Rent reminders 1 month and 5 days before, on the due date, then every 3 days overdue, alternating 8:00 and 20:00 Cameroon time; staff can send one now (max every 6 h) or pause a unit's reminders (a week / a month). Bills: 2 days before and on the due date (8:00), plus when a bill is created. Also: receipts, messages, issue replies/status (tenants); new issues, replies, receipt disputes (money staff only), tenants joining (team). More than 2 at once or 4 an hour: one "You have N notifications, open Homedly" push instead. Everything is also in the bell list in the app.
- **Unit page, repairs, agreements, contact phone** (2026-10-02): each unit shows its tenant, quick actions (message, bill, rent, call, repair), its issues, bills (mark paid or waive with a reason) and repair history. Repairs: what, when, cost (money permission only), optional issue it fixed, optional "Repairs" bill to the tenant. Owners write the tenancy agreement per property and optionally per unit (fields like {tenant} filled in); when it changes, current tenants must accept again; the text each tenant accepted is kept. Each property has a contact phone tenants tap to call.
- **Offline use** (2026-10-02): everything a user loaded stays readable offline, with no expiry, until fresher data replaces it. While online, the main data (properties, apartments, tenancies, payments, bills, tickets, announcements; for tenants their homes, bills, tickets and receipts) is downloaded in the background, so every main screen opens offline. Saved data is encrypted per account (key in the Android Keystore); it stays after logout but only opens for the same account. Changes need a connection, except ticket messages, new tickets and receipt confirmations, which wait in an outbox and are sent automatically. A small grey "Offline" strip shows at the top; tapping it shows when the data was last updated.
- **Receipts can't be faked** (2026-10-02): every receipt is signed by the server (Edge Function `sign-receipt`, Ed25519; the private key is only a Supabase secret) and carries a QR code. "Check a receipt" in the app scans it: it works offline, says "Genuine" or "Not genuine", and online also shows whether the payment was voided later. App users only (no public web page for now). Receipts issued before this were signed retroactively.
- **Tenant confirms or disputes a receipt** (2026-10-02): within 24 hours of a receipt the tenant can confirm it or report a problem (wrong amount, months, dates, not my payment, other). A problem opens a ticket of category "Receipt", seen by the owner and caretakers who may see money. No answer within 24 hours = accepted automatically. The answer is printed on the PDF.

- **Caretaker permissions** (2026-10-02): owners switch on, per caretaker: record payments, see money, manage apartments, manage tenants & tenancies, manage the team; all = "full access (same as owner)". Deleting the property and adding/changing/removing owners stay owner-only. One database rule, `has_permission()`, replaces every "owner or manager" check.
- **Caretaker passwords** (2026-10-02): only the app admin resets them (owners still reset managers and tenants).
- **Announcements, tickets, bills** (2026-10-02): any team member sends announcements (all current tenants or chosen ones) and creates bills; tickets are seen and answered by the whole team. Bills: Water + Electricity standard per property (can be switched off), custom types; one amount per apartment, each apartment marked paid separately; overdue from the due date. Caretakers may see bill amounts (they're not rent). Photos on tickets and push notifications come later.

- **Account types** (2026-10-01): one kind of login for everybody; what a person can do comes from their connections (owner/manager/caretaker of a property, tenant via invite code), so one person can be an owner here and a tenant there. Sign-up asks "How will you use the app?" (Landlord / Tenant / Team member) only to guide the first steps. Anyone may sign up as a landlord and create properties.
- **Super admin** (2026-10-01): made in the database (`app_admins`), never through sign-up. Sees everything read-only, including money; reads the activity log; resets anyone's password (not other admins); transfers ownership of a property. Can NEVER make financial or other changes: there are no write permissions for admins, and the payment functions only accept the property's own staff.
- **Activity log** (2026-10-01): all important changes (properties, apartments and their rents, tenants and ID numbers, tenancies, renewals, payments, voids, team, invite codes, password resets): who, what, when, before/after. Only the super admin reads it.
- **Last owner** (2026-10-01): deleting the only owner's account stays blocked (that is why "Failed to delete user" appears). The admin transfers ownership first (or the owner deletes the property); then the account can be deleted.

- **Username + password login, no email** (2026-10-01): replaces email signup and the 6-digit code. Supabase still needs an email per account, so the app turns a username into a hidden address (`tina` -> `tina@users.rentalapp.invalid`); no emails are ever sent. Usernames are unique, case-insensitive. Adding team members switches from email to username. Supersedes "Email confirmation paused" and "Turn email confirmation back on".
- **Tenants join with an invite code** (2026-10-01): staff never hand over accounts and tenants never choose an apartment. Staff assign apartments by starting a tenancy (as before); the tenancy page shows a one-time code (e.g. `TEN-4K7Q`, expires after a few days, owner/manager only). The tenant signs up with username + password and enters the code, which links their account to that tenant contact; their tenancies, receipts and (later) tickets follow. A tenant renting in two properties gets a code from each. Replaces linking by email (`link_my_tenant_records` stays switched off).
- **Password reset by an owner/manager** (2026-10-01): with no email, an owner or manager can set a temporary password for a tenant or team member of their property; the user must change it after logging in. Needs a small Supabase Edge Function (it uses admin rights, so it never runs in the app). Safety rule: they can only reset someone whose ONLY connection is their property (no membership or tenancy elsewhere), so nobody can take over an account that also has access to other people's properties. Others ask the app admin (Supabase dashboard).
- **Start fresh** (2026-10-01): the existing email accounts are test accounts; delete them in Supabase (Authentication -> Users) and sign up again with usernames.

- **Every property always has an owner** (2026-09-27): the landlord who created it. CLAUDE.md rule 6 stands: the last owner can't be removed or demoted. Apartments can be vacant; the owner assigns tenants to apartments.
- **Email confirmation paused** (2026-09-27): emails from Supabase weren't arriving (Brevo sending "from" a Gmail address). Accounts are created without confirmation for now. **Tenant linking is disabled in the database** while confirmation is off (migration `20260927130000_pause_tenant_linking.sql`), because without it anyone could sign up with a tenant's email and see their payments. See "Turn email confirmation back on" below.
- **Rent is monthly; payment intervals in months** (2026-10-01): a tenancy stores rent per month and how often the tenant pays (monthly, every 3 / 6 months, yearly, or custom 1-24 months). No weekly rent. Rent reminders (Phase 11) follow the interval.
- **Part payments** (2026-10-01): a payment says how many months it covers; the amount is pre-filled (monthly rent x months) but can be changed. The months still count as covered and the difference is owed; the receipt shows "Left to pay". A "Pay off balance" payment clears it.
- **Rent changes go through renewals** (2026-10-01): "Renew" sets a new lease end and optionally a new rent; old values are kept in `tenancy_renewals`. The rent can't be edited directly.
- **Tenant ID card numbers** (2026-10-01): owners and managers only (table `tenant_identities`).
- **Colourful, simple UI for now** (2026-10-01): bright violet/pink theme, one colour per property, green/amber/red rent status, blue for vacant. Colours live in `lib/core/theme/app_colors.dart`.
- **Tenants: contact first, link later** (2026-09-27): staff add a tenant as a contact (name, phone, email) and can record rent right away. When the tenant signs up and confirms that email, the app links their account to the contact. Tenants who never install the app still work.

---

## Phase 0: Setup

- [x] Flutter project created
- [x] Supabase project created
- [x] Core packages added: `supabase_flutter`, `flutter_riverpod`, `go_router`, `intl`, `flutter_dotenv`
- [x] `.env` file created
- [x] Scaffold files exist: router, theme, app shell, login page, properties page
- [x] Add `.env` to `.gitignore`; add `.env.example` with placeholder keys
- [x] `git init` and first commit (`.env` confirmed **not** included)
- [x] `supabase/migrations/` created (migrations applied via the SQL editor; the Supabase CLI is optional, use it via `npx supabase`)
- [x] Replace the counter demo in `main.dart`: load `.env`, start Supabase, wrap in `ProviderScope`, use the router and theme
- [x] Switch the router to `go_router`
- [x] Add Android `INTERNET` permission (needed for release builds)
- [x] Register `.env` as an asset in `pubspec.yaml`
- [x] Supabase keys verified; app runs on a real Android phone (2026-09-27)

**Done when:** the app runs on your phone, connects to Supabase, and shows the login page from the router.

---

## Phase 1: Core database and security (most important)

Migration: [supabase/migrations/20260927120000_core_schema.sql](supabase/migrations/20260927120000_core_schema.sql)
Security check: [supabase/tests/rls_check.sql](supabase/tests/rls_check.sql) (52 checks, all passing on a local Postgres imitating Supabase)

- [x] Tables: `profiles`, `properties`, `memberships`, `apartments`, `tenants` (contacts), `tenancies`, `payments`, `payment_voids`, `receipts`, `receipt_counters`
- [x] Auto-create a `profiles` row when a user signs up (trigger on `auth.users`)
- [x] Helper SQL functions: `is_property_member`, `has_property_role`, `can_record_payments`, `is_tenant_of_tenancy`, `is_tenant_in_property`
- [x] RLS enabled and policies written for **every** table above
- [x] Column-level update permissions (e.g. nobody can edit `paid_until` or `tenants.user_id` directly)
- [x] RPC `create_property`: creates the property and the creator's owner membership together
- [x] RPC `record_payment`: inserts the payment, moves `paid_until` forward and creates the receipt number, all in one transaction
- [x] RPC `void_payment`: adds a void record with a reason and recalculates `paid_until` (the original row is never changed)
- [x] RPC `link_my_tenant_records`: links tenant contacts to a signed-up tenant with a confirmed email
- [x] Receipt numbers sequential per property per year (`RCT-2026-0001`), generated in the database
- [x] Partial unique index: only one active tenancy per apartment
- [x] Money stored as `bigint` (smallest unit); dates stored in UTC
- [x] App users can't UPDATE or DELETE on `payments`
- [x] Caretaker-safe view `tenancy_overview` (no money columns, includes computed rent status)
- [x] Last-owner rule enforced by a trigger
- [x] Apartments/tenants with tenancy history can't be deleted on their own (deleting the whole property still can)
- [x] Migration applied to the Supabase project (2026-09-27)
- [x] `rls_check.sql` run in the Supabase SQL editor: all 52 checks passed ✅

**Done when:** you log in as test users for each role (owner, manager, caretaker with and without `can_record_payments`, tenant) in the SQL editor and confirm each one can see and do exactly what the permissions table in CLAUDE.md allows. Nothing more. `rls_check.sql` does exactly this.

---

## Phase 2: Login and signup

- [x] Email/password signup (name, email, password)
- [x] Email confirmation with a 6-digit code typed into the app (no deep links needed)
- [x] Resend code; logging in with an unconfirmed email sends a new code automatically
- [x] Email/password login with friendly error messages
- [x] Router sends logged-out users to login and logged-in users into the app
- [x] Session remembered after restart (Supabase stores it on the phone)
- [x] Profile screen (name, phone) + Log out
- [x] Tenant contacts linked to the account whenever a session starts (`link_my_tenant_records`)
- [x] Tests: 13 passing (form checks, login/signup/verify screens with a fake Supabase)
- [x] "Confirm signup" email template changed to show the code
- [ ] **(You)** Switch off "Confirm email" in Supabase (needed for usernames, see Phase 2b)
- [ ] **(You)** Test on the phone: sign up (goes straight in) -> close and reopen app (still logged in) -> edit profile -> log out -> log in

### Turn email confirmation back on (SUPERSEDED by Phase 2b: no emails, tenants join with invite codes)
- [ ] Working email sending: Gmail SMTP with an App Password (quick), or a custom domain + Brevo/Resend (best)
- [ ] Supabase: switch "Confirm email" back on
- [ ] New migration: `grant execute on function public.link_my_tenant_records() to authenticated;`
- [ ] In `rls_check.sql`, change the "linking paused" check back to expect linking to work
- [ ] Test: sign up -> 6-digit code arrives -> confirm -> tenant contact gets linked

**Done when:** you can sign up, log out, log back in, and the app remembers the session after a restart.

> **Before real users (by Phase 12 at the latest):** Supabase's built-in email service is only for testing. It sends a few emails per hour, and only to your Supabase team members' addresses. Set up a custom SMTP provider (e.g. Resend, Brevo) under Authentication -> Emails -> SMTP Settings.

---

## Phase 2b: Username login and tenant invites

Migration: [supabase/migrations/20261001160000_usernames_invites_password_reset.sql](supabase/migrations/20261001160000_usernames_invites_password_reset.sql)
Edge Function: [supabase/functions/reset-password/index.ts](supabase/functions/reset-password/index.ts)

- [x] Sign up / log in with username + password (hidden address behind it, see `lib/features/auth/data/username.dart`); email code screens removed
- [x] `profiles.username` (unique, case-insensitive); profile screen shows it; "Change password"
- [x] Add team members by username instead of email
- [x] Invite codes (`TEN-XXXXXX`, 7 days, one use): "App access" card on the tenancy page (create / show / copy / new code / cancel); `redeem_tenant_invite(code)` links the account; max 10 wrong codes per hour per account; "Disconnect" for a wrong link
- [x] "Enter your invite code" screen for tenants; "My home" on the home screen shows what they rent (full tenant side: Phase 9)
- [x] Edge Function `reset-password` + `password_reset_target` safety rules; "Reset password" on the Team sheet and on linked tenants; forced "choose a new password" after a reset
- [x] Security check: 129 checks passing locally; app tests: 68 passing
- [ ] **(You)** Supabase: switch OFF "Confirm email" (Authentication -> Sign In / Providers -> Email). It is still ON.
- [x] Old test accounts deleted
- [ ] **(You)** Run migration `20261001160000_usernames_invites_password_reset.sql`, then `rls_check.sql`
- [x] Edge Function `reset-password` deployed (2026-10-01). To redeploy after changes: `npx supabase functions deploy reset-password --project-ref ojhrcwvxauweepripcbi --use-api`
- [ ] **(You)** Test on the phone: sign up as landlord + as tenant; invite code; reset password

**Done when:** a tenant signs up with a username, enters the code from their landlord, and is linked to the right tenancy; a wrong or expired code is refused; an owner can reset a tenant's password.

---

## Phase 2c: Account types, super admin, activity log

Migration: [supabase/migrations/20261001170000_admin_activity_account_types.sql](supabase/migrations/20261001170000_admin_activity_account_types.sql)

- [x] Sign-up asks "How will you use the app?" (Landlord / Tenant / Team member); Home suggests the right first step for each
- [x] `app_admins` + `is_app_admin()`; read-only SELECT policies for the admin on every table (money included); no write policies
- [x] `activity_log` filled by triggers (properties, team, apartments + rents, tenants + ID numbers, tenancies, renewals, payments, voids, invite codes) + password resets (Edge Function)
- [x] Admin screen: Activity (who / what / where / when, before -> after), Properties (owners, Transfer ownership), People (tap to reset a password)
- [x] Admin password reset for anyone except other admins; Edge Function redeployed (2026-10-01)
- [x] `admin_transfer_ownership()`: lets the only owner's account be deleted afterwards (the last-owner rule stays)
- [x] Security check: 149 checks passing locally; app tests: 80 passing
- [x] Migration `20261001170000_admin_activity_account_types.sql` applied on Supabase
- [x] Admin account `adminNkim` created and made app admin (2026-10-01). Change its starting password in Profile -> Change password

**Done when:** the admin sees all activity and properties, can reset a password and transfer ownership, and every attempt to change rent or payments as admin is refused.

---

## Phase 2d: Landlord-only properties, tenant home, tenancy agreement

Migration: [supabase/migrations/20261002100000_landlord_only_properties_agreement.sql](supabase/migrations/20261002100000_landlord_only_properties_agreement.sql) (applied 2026-10-02)

- [x] Only landlord accounts create properties: "Add property" hidden for tenants/team, and `create_property` refuses them
- [x] Tenant taps "My home" -> tenancy agreement first (placeholder lorem ipsum + real summary), tick + Accept (`accept_tenancy_agreement`, only the tenant can)
- [x] Then: time left until rent is due, due date, monthly rent, how often / how much each time, amount left in red, lease end + time left, payments; "Read the agreement"
- [x] Staff tenancy page shows whether the agreement was accepted
- [x] Security check: 157 checks passing locally; app tests: 85 passing
- [ ] Replace the placeholder agreement text (`lib/features/tenant_access/data/agreement_text.dart`)
- [ ] **(You)** Test on the phone: tenant account sees no "Add property"; accept agreement; see the details

---

## UI redesign (2026-10-02)

Inspired by two reference designs: warm off-white background, white rounded cards with soft shadows, orange brand colour (`AppColors.primary`) with a blue accent, Poppins font (`assets/fonts`, OFL licence), drawn "photos" for properties until real photos exist (`PropertyPhoto`).

- [x] Bottom bar: Home / Properties / Tenants / Profile (tenants: Home / Profile)
- [x] Welcome screen -> Log in, or Sign-up in two steps (1: account type, 2: name, username, password)
- [x] Home: greeting, overview cards (properties, occupied units, overdue, paid this month), needs attention, my properties; tenants get their home card
- [x] Property page: photo, address, summary grid, grid of units, team & settings; Tenants tab with search and filters; Tenant details card + rent payment status; Profile with menu
- [x] Invite-code prompts only for tenant accounts
- [x] App tests: 86 passing
- [ ] Known: rent status is computed with the database's UTC date, the app's "days left" with the phone's local date; for about an hour after midnight (Cameroon, UTC+1) they can disagree
- [ ] Real property photos (Supabase Storage), when wanted

---

## Phases 8-9 (part): Permissions, announcements, tickets, bills (2026-10-02)

Migrations: `20261002120000_caretaker_permissions.sql`, `20261002130000_announcements_tickets_bills.sql` (both applied 2026-10-02)

- [x] Caretaker permission switches + "Full access" on the Team sheet; caretaker passwords admin-only
- [x] Announcements: property page -> Announcements -> New (all tenants / choose); tenants see them on Home and in their rental
- [x] Tickets: tenant "Report an issue" (category, title, details); team list with status filters; ticket page with status and conversation
- [x] Bills: property page -> Bills; bill types (Water/Electricity on/off, custom types); new bill for all occupied or chosen apartments; tick apartments as paid; tenants see "My bills"
- [x] Security check: 192 checks passing locally; app tests: 101 passing
- [ ] Ticket photos (image_picker + Storage); push notifications for announcements, tickets and bills (Phase 11)
- [ ] **(You)** Test on the phone: give a caretaker switches; send an announcement; tenant reports an issue; create a water bill and mark one apartment paid

---

## Offline use, signed receipts, tenant confirmations (2026-10-02)

Migration: `20261003100000_receipt_signatures_confirmations.sql` (applied 2026-10-02). Edge Function `sign-receipt` (deployed; secrets RECEIPT_SIGNING_KEY, RECEIPT_SIGNING_KEY_ID=k1 set).

- [x] Offline cache: every read goes through `OfflineCache` (`lib/core/offline/`), encrypted SQLite per account; background download after login / when the app comes back / when the connection returns; "Offline" strip
- [x] Outbox: ticket messages, new tickets and receipt confirmations wait offline and are sent later (sent once even if retried)
- [x] Receipt signatures + QR code on screen and on every PDF page; "Check a receipt" scanner (Profile, staff Home); 4 existing receipts signed
- [x] Tenant receipt page (tap a payment): Confirm / Report a problem within 24 hours; "Receipts to check" on the tenant Home; "Disputed" on the team's payment list; dispute tickets link to the receipt
- [x] Security check: 207 checks passing locally; app tests: 127 passing
- [ ] **(You)** Test on the phone: turn on airplane mode and browse; send a ticket message offline, then reconnect; record a payment and scan its QR code; as the tenant, confirm one receipt and dispute another

---

## Tenant tabs, background shapes, offline profile (2026-10-02)

- [x] Tenants' bottom bar: Home · Bills · Payments · Issues · Profile (badges: unpaid bills, receipts to check); "My home" and receipts open inside the Home tab, so the bar stays
- [x] Faint geometric shapes behind every screen (`GeometricBackdrop`, added to every route by `AppRoute`); tinted cards are solid so shapes never show through
- [x] Name and phone can be changed offline: shown at once, kept on the phone, sent automatically (outbox); passwords still need a connection
- [ ] **(You)** Check on the phone: tenant tabs and badges; the background in light and dark mode; edit your name in airplane mode, reconnect, check it saved

---

## Owner pages, unit page, repairs, agreements (2026-10-02)

Migration: `20261004100000_units_repairs_agreements_contact.sql` (applied 2026-10-02)

- [x] Bottom bar on every page (all pages live inside the tabs; only the forced password change is full-screen)
- [x] Simpler property page: short header, three numbers, quick actions (Bills, Issues, Message, Team), units; agreement / bill types / delete in the ⋮ menu
- [x] Unit page: quick actions, issues, bills with Mark paid / Waive, repair history + "Log a repair" (optionally bills the tenant), its agreement
- [x] Agreement editor (property and unit), real default text instead of lorem ipsum; changes ask current tenants to accept again
- [x] Contact phone on the property; "Call your landlord" on the tenant's home page (opens the dialer)
- [x] Security check: 226 checks passing locally; app tests: 134 passing
- [ ] **(You)** Test on the phone: set the property's contact phone and call it as the tenant; log a repair that bills the tenant, then waive it; write an agreement and check the tenant must accept it again

---

## Money totals, bigger cards, quicker daily tasks (2026-10-02)

Migration: `20261004110000_bill_amounts_per_unit.sql` (applied 2026-10-02)

- [x] "Total collected this month" (property page and Home), hidden until the eye is tapped
- [x] Unit page: rent collected from the current tenant (in the header)
- [x] Tenants: total rent paid (Payments tab, My home) and bills paid so far (Bills tab, My home)
- [x] Property page: big occupancy card, big overdue / open-issues cards, two-per-row unit tiles
- [x] "Record rent" on late units in the property's unit grid
- [x] Home "Needs attention": late rent, receipt disputes, open issues, overdue bills
- [x] "Log the repair" on an open issue (can mark it resolved in the same step)
- [x] Bills with a different amount per apartment (e.g. meter readings)
- [x] "Remind" on late units: a ready-written rent reminder to that tenant
- [x] Security check: 230 checks passing locally; app tests: 136 passing
- [ ] **(You)** Check on the phone: the eye on the monthly total; Record rent from a unit tile; a per-apartment water bill; Remind a late tenant; Log the repair from an issue

---

## Phase 11: Push notifications (2026-10-03)

Migration: `20261005100000_push_notifications.sql` (applied 2026-10-03). Edge Function `send-push` (deployed, --no-verify-jwt; secrets FCM_SERVICE_ACCOUNT, PUSH_DISPATCH_SECRET; Vault: homedly_dispatch_secret, homedly_functions_url). pg_cron jobs: homedly-send (every minute), homedly-morning (07:00 UTC), homedly-evening (19:00 UTC), homedly-cleanup (weekly, keeps 90 days).

- [x] App renamed Homedly, ID com.awembom.rental, Firebase (google-services.json), "Homedly" notification channel and icon
- [x] Phones register after login and unregister on logout; tapping a notification opens its screen; a banner when the app is open
- [x] Bell on Home with unread count; notifications list (marked read on opening)
- [x] Scheduled rent and bill reminders, event notifications, "too many" summary
- [x] Unit page: Remind (send now) and Rent reminders card (pause a week / a month, turn back on)
- [x] Security check: 252 checks passing locally; app tests: 140 passing
- [x] Phone test: notifications arrive (2026-10-03)
- [x] Sent immediately (pg_net from a trigger, ~0.5 s); clearer receipt and message wording (`20261005110000_push_immediate.sql`)
- [x] Live updates: Supabase Realtime on bills, payments, receipts, tickets, tenancies, apartments, announcements, notifications; open screens reload by themselves; team notified when a tenant confirms a receipt (`20261005120000_realtime_receipt_confirmed.sql`)
- [ ] **(You)** Two phones: mark a bill paid as landlord and watch the tenant's Bills tab change; confirm a receipt as tenant and watch the landlord's receipt
- [ ] iOS (needs an Apple developer account)

---

## Sign-up phone, branding, onboarding (2026-10-03)

Migration: `20261006100000_signup_phone.sql` (applied 2026-10-03)

- [x] Sign-up: password typed twice; phone number required. All phone fields: +237 fixed, 9 digits (6 or 2 first), saved as +237XXXXXXXXX, shown as +237 6XX XX XX XX
- [x] Logo: white house with a keyhole door on orange (assets/branding, drawn by a script); app icon (adaptive) and splash screen generated (flutter_launcher_icons.yaml, flutter_native_splash.yaml)
- [x] Splash stays until the app knows who is using it; the saved profile shows the right Home page and tabs at once (no landlord screens flashing for tenants)
- [x] Onboarding: 4 slides, Skip / Next / Get started, shown once per phone before the welcome screen
- [ ] **(You)** Check the icon on the home screen and the splash; log out to see the onboarding once

---

## Phase 3: Properties and members

Migration: [supabase/migrations/20260927140000_property_members.sql](supabase/migrations/20260927140000_property_members.sql)

- [x] List the properties I'm a member of, with my role (pull down to refresh)
- [x] Create a property (calls `create_property`; creator becomes owner)
- [x] Property page: details, my role, links to Team (and Apartments in Phase 4)
- [x] Edit a property (owner/manager); delete it (owner only, must type the name to confirm)
- [x] Add members by email with a role (`add_property_member`; they need an account first)
- [x] Caretaker `can_record_payments` setting
- [x] Change a member's role, remove a member, leave a property (the last owner is blocked by the database)
- [x] `profiles.email` so the team list shows emails (only visible to people sharing a property)
- [x] Security check: 63 checks passing locally; app tests: 28 passing
- [ ] **(You)** Run the two new migrations in the Supabase SQL editor (pause-linking + property members), then `rls_check.sql`
- [ ] **(You)** Test on the phone with two accounts: create a property, add the second account as a caretaker, log in as them and check they can't edit or delete

**Done when:** two test accounts share a property with different roles, and each one sees the right actions.

---

## Phase 4: Apartments

Migration: [supabase/migrations/20261001120000_apartments_tenancies.sql](supabase/migrations/20261001120000_apartments_tenancies.sql) (shared with Phase 5)

- [x] List apartments in a property, each marked Vacant or with its rent status (Paid / Due soon / Overdue)
- [x] Summary header (total, occupied, vacant, overdue) and filters: All / Occupied / Vacant / Needs attention
- [x] Add and edit apartments (owner and manager only); delete only if it never had a tenant (database rule)
- [x] Each apartment has a required standard **monthly rent** (migration `20261001130000_apartment_rents.sql`). It sits in its own `apartment_rents` table so caretakers never receive it. Shown on vacant apartment cards and the apartment page (owners/managers only)
- [x] Apartment page: current tenant, or "Start tenancy" if vacant; list of past tenants
- [x] Property page shows apartment numbers and links to Apartments
- [x] Colourful theme across the app (see Decided)
- [ ] **(You)** Test on the phone: as owner add apartments; as the caretaker account check you can see them but can't add or edit

**Done when:** a caretaker can view apartments but can't add or edit them, and the database also blocks it.

---

## Phase 5: Tenancies

- [x] Rent field pre-filled from the apartment's monthly rent (x3 for quarterly, x12 for yearly); type another amount for a renegotiated rent. The tenancy page shows "Negotiated rent" when it differs from the standard
- [x] Tenant ID card number (owners/managers only); payment interval: monthly, every 3 / 6 months, yearly, custom (migration `20261001140000_payment_intervals_receipts.sql`)
- [x] Renew (continue) a tenancy: new lease end + optional new rent, with renewal history; warning when the lease end has passed
- [x] Start a tenancy: new or existing tenant contact, rent amount, frequency, move-in date, optional lease end, optional "already paid up to" (`start_tenancy`, all-or-nothing)
- [x] Link the tenant's account: contact first, link later by confirmed email (already built in Phase 1; paused until email confirmation is back on)
- [x] Tenancy page: rent status and next due date, rent amount (hidden from caretakers), tenant contact, lease dates
- [x] Edit rent, lease end and notes; edit the tenant contact
- [x] End a tenancy with a move-out date (`end_tenancy`), which marks the apartment Vacant; ended tenancies can't be reopened
- [x] Tenancy history for each apartment
- [x] Security check: 83 checks passing locally; app tests: 47 passing
- [ ] **(You)** Run migrations `20261001120000_apartments_tenancies.sql` then `20261001130000_apartment_rents.sql` in the Supabase SQL editor, then `rls_check.sql`
- [ ] **(You)** Apartments added before this change have no monthly rent: open each one, tap Edit and fill it in
- [ ] **(You)** Test on the phone: start a tenancy, try to start a second one on the same apartment (refused), end it (apartment becomes Vacant), start a new one

**Done when:** an apartment can't get a second active tenancy, and ending one frees it.

---

## Phase 6: Payments and receipts (core feature)

Migration: [supabase/migrations/20261001140000_payment_intervals_receipts.sql](supabase/migrations/20261001140000_payment_intervals_receipts.sql)

- [x] Record-payment screen (calls `record_payment`): choose how many months (1/3/6/12/custom), the period and new "paid until" fill in automatically, the amount fills in (monthly rent x months) and can be changed
- [x] Part payments: expected and paid amounts both kept; "left to pay" shown live, on the tenancy and on the receipt; "Pay off balance" payments
- [x] Caretakers with `can_record_payments` record payments without seeing any amounts
- [x] Rent status computed from `paid_until`: Paid / Due soon / Overdue (database, since Phase 1)
- [x] Payment history for each tenancy
- [x] Void a payment with a reason (stays in history marked VOID; dates recalculated)
- [x] `pdf` + `printing` packages; receipt PDF: view, share, print
- [x] Receipts: "Amount left" in red when not fully paid; automatic unique reference code (e.g. `PAY-7K3QX9`, migration `20261001150000_receipt_reference_codes.sql`). The payment that pays off what was left shares the code, and its PDF has 2 pages: the new receipt plus the earlier one. The typed field is now "Transaction ID"
- [x] Security check: 106 checks passing locally; app tests: 61 passing
- [ ] **(You)** Run migration `20261001150000_receipt_reference_codes.sql` in the Supabase SQL editor (`20261001140000` is already applied), then `rls_check.sql`
- [ ] **(You)** Test on the phone: record a full payment, a part payment (check the red "Amount left" on the receipt), pay off the balance (same reference code; its PDF has 2 pages), share the PDF, void a payment, renew a tenancy

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
- [ ] Edge Function on a daily schedule: rent due-soon and overdue reminders, following each tenancy's payment interval (`payment_interval_months`)
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
