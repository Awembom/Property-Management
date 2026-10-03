# CLAUDE.md

Guidance for Claude (and any AI assistant) working in this repository.

## Project Overview

A Flutter mobile app (Android-first, iOS later) for landlords who manage multiple apartments across one or more properties. Rent is paid in advance; the app records payments, issues digital receipts, tracks how much time is left before rent is due, and flags overdue tenants. It also handles utility/custom bills, maintenance tickets from tenants, and a full apartment history including repairs and costs.

This is the developer's **first Flutter app**. Prefer clear, well-commented code over clever abstractions. Explain non-obvious decisions in code comments, not just chat.

## Tech Stack

- **Framework:** Flutter (Dart), Android-first
- **Backend:** Supabase (Postgres, Auth, Storage, Edge Functions, RLS)
- **State management:** flutter_riverpod
- **Routing:** go_router
- **Push notifications:** Firebase Cloud Messaging (only Firebase service used; everything else is Supabase)
- **Receipts:** pdf + printing packages
- **Photos (tickets/repairs):** image_picker, stored in Supabase Storage
- **Env config:** flutter_dotenv (`.env` file, gitignored, never committed)
- **Dates/formatting:** intl

## Authentication

Username + password only, no emails (PLAN.md Phase 2b). Supabase Auth needs an email, so `lib/features/auth/data/username.dart` maps `tina` to `tina@users.rentalapp.invalid`; never show or ask for emails. "Confirm email" must be OFF in Supabase. Forgotten passwords: owners/managers give a temporary password through the `reset-password` Edge Function (rules in `password_reset_target()`); the service-role key lives only in that function, never in the app.

## Offline and receipts

- Every Supabase **read** in a repository goes through `OfflineCache` (`lib/core/offline/offline_cache.dart`): `_cache.rows('key/$id', () => query)`. New repository reads must do the same, with a key unique to the query and its parameters. Writes go straight to Supabase (they need a connection), except what `OutboxNotifier` queues (ticket messages, new tickets, receipt confirmations); queued RPCs take a client id so retries are saved once.
- Background download for offline use: `downloadForOffline` in `lib/core/offline/sync_controller.dart`. Add new main screens' loads there.
- Receipts are signed by the `sign-receipt` Edge Function; the public key is in `lib/features/receipts/data/signed_receipt.dart`. Never put the private key in the repo.

## Notifications

Anything that should reach someone is a row in `notifications` (via `public.notify()` / `notify_staff()` in SQL, from triggers or `queue_scheduled_notifications()`); the `send-push` Edge Function delivers them every minute. Don't send pushes from the app. Routes in notifications are app paths (see AppRoutes). App ID `com.awembom.rental`, Firebase project `homedly-4a906`; never commit the service account key.

## Project Structure

Feature-based, not type-based:

```
lib/
  core/          # Supabase client init, router config, theme, constants, shared providers
  shared/        # Reusable widgets used across features
  features/
    auth/
    properties/
    apartments/
    tenancies/
    tenant_access/   # invite codes, joining as a tenant, password resets
    payments/
    bills/
    tickets/
    maintenance/
```

Each feature folder holds its own screens, widgets, providers/controllers, and models. Don't create generic `models/`, `screens/`, `widgets/` top-level folders — keep everything colocated by feature.

## Domain Model (core concepts)

- **Property**: a group of apartments managed together. Has members (staff), not a single owner field.
- **Apartment**: belongs to a property. Has at most one *active* tenancy at a time (v1 constraint).
- **Membership**: links a user to a property with a role: `owner`, `manager`, or `caretaker`. Caretakers have a `can_record_payments` boolean toggle.
- **Tenant**: a contact (name, phone, email, ID number) created by staff for a property. Linked to a user account later: staff create a one-time invite code (`tenant_invites`) and the tenant enters it after signing up. Tenants who never use the app still work.
- **Tenancy**: links a tenant contact to an apartment. Stores the monthly rent, how often the tenant pays (`payment_interval_months`: 1, 3, 6, 12 or custom; drives rent reminders), start/end dates, and a computed `paid_until` date. Can be renewed (new lease end, optional new rent, recorded in `tenancy_renewals`).
- **Payment**: recorded against a tenancy. Says how many months it covers and extends `paid_until` by that many months. Keeps the expected amount (monthly rent x months) and the amount actually paid; any difference is owed and shown on the receipt. Immutable once created — corrections are made via a voiding entry, never an edit or delete.
- **Receipt**: auto-generated on payment creation, sequential number per property (e.g. `RCT-2026-0001`). Signed by the server (QR code proves it's genuine). The tenant confirms it or reports a problem within 24 hours (`receipt_responses`); no answer = accepted.
- **Bill**: a utility bill or task created by staff, assigned to all apartments in a property or specific ones. Each assignment tracks its own status independently.
- **Ticket**: a maintenance complaint raised by a tenant. Can be converted into a maintenance record when resolved.
- **Maintenance record**: a logged repair on an apartment, with optional cost, optionally linked back to the ticket that spawned it. Forms part of the apartment's history timeline.
- **Condition report**: notes/photos taken at tenancy start and end (move-in/move-out).

## Roles and Permissions (enforce in Postgres RLS, not just UI)

| Action | Owner | Manager | Caretaker | Tenant |
|---|---|---|---|---|
| Delete property | ✅ | ❌ | ❌ | ❌ |
| Add/change/remove owners | ✅ | ❌ | ❌ | ❌ |
| Manage managers/caretakers | ✅ | ❌ | If `can_manage_team` | ❌ |
| Add/edit apartments, bill types | ✅ | ✅ | If `can_manage_apartments` | ❌ |
| Manage tenancies, tenants, invites | ✅ | ✅ | If `can_manage_tenancies` | ❌ |
| Record payments, mark bills paid | ✅ | ✅ | If `can_record_payments` | ❌ |
| View rent amounts/totals/receipts | ✅ | ✅ | If `can_see_money` | Own only |
| Create bills, send announcements | ✅ | ✅ | ✅ | ❌ |
| View/respond to tickets | ✅ | ✅ | ✅ | Own only |
| Create tickets | ❌ | ❌ | ❌ | ✅ |
| Log repairs | ✅ | ✅ | ✅ | ❌ |
| View repair costs | ✅ | ✅ | If `can_see_money` | ❌ |
| Reset passwords | Managers, tenants | Tenants | Tenants (if `can_manage_tenancies`) | ❌ |

Caretakers' switches are columns on `memberships`; all of them = "full access". The database checks them with `has_permission(property_id, 'money'|'payments'|'apartments'|'tenancies'|'team')`. Caretakers' own passwords are reset only by the app admin.

**Critical rule:** Every table with sensitive data must have RLS policies that check the user's role via a join/subquery on `memberships` or `tenancies` — never rely on the Flutter UI to hide actions as the only safeguard.

## Key Business Rules

1. Rent is paid in advance. `paid_until` on the tenancy determines status: Paid / Due soon (within grace period, default 7 days) / Overdue. This is computed, not manually set.
2. Payments are **immutable**. Never write an UPDATE or DELETE on the payments table from app code — corrections are a new voiding record with a reason.
3. Receipt numbers must be unique and sequential per property (use a Postgres sequence or a trigger function, not client-side counting).
4. An apartment has at most one active tenancy at a time (v1).
5. Caretakers never see money figures (rent amounts, totals, repair costs) unless the owner switches on `can_see_money` for them. (Utility bill amounts are visible to all staff.)
6. A property must always retain at least one `owner` membership — block removal of the last owner.
7. Overdue status for rent and bills is computed from dates, not a manually toggled flag (though manual override is allowed on top).

## Conventions

- Use `snake_case` for Supabase/Postgres table and column names, `camelCase` for Dart variables/methods — map between them explicitly in model classes (e.g. via `fromJson`/`toJson`), don't let raw snake_case leak into Dart code.
- Every Supabase table with a `created_by` column should be set from `supabase.auth.currentUser.id`, never trusted from client-provided input.
- Prefer Riverpod `AsyncNotifier`/`FutureProvider` for data fetched from Supabase; avoid `setState` for anything beyond purely local UI state.
- Currency amounts stored as integers (smallest unit) or `numeric` in Postgres — avoid floating point for money.
- Dates/times stored in UTC in Postgres; convert to local time only at display time using `intl`.

## What NOT to do

- Don't add in-app payments (rent/bills are recorded as paid outside the app in v1 — explicitly out of scope).
- Don't hardcode Supabase URL/keys — always read from `.env` via `flutter_dotenv`.
- Don't build generic "admin can do anything" checks — always check the specific role/permission for the specific property.
- Don't skip RLS policies "for now" — retrofitting security rules after data and UI exist is much harder than writing them alongside each table.

## Current Status

**[PLAN.md](PLAN.md) is the build roadmap and the source of truth for progress.** Check it at the start of each session to see the current phase, tick off items as they're completed, and don't skip ahead of the current phase's "Done when" check. Open decisions (e.g. the "last owner" rule) are listed at the top of PLAN.md and override this file once decided.

## Reference Docs

Full SRS and feature summary (roles, all functional requirements, data model, roadmap) is maintained separately — check the project's docs folder or the linked artifact for the authoritative spec. This file is a working-context summary for AI assistance, not the full spec.


