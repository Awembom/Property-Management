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
- **Tenant**: a contact (name, phone, email) created by staff for a property. Linked to a user account later, when the tenant signs up and confirms the same email. Tenants who never use the app still work.
- **Tenancy**: links a tenant contact to an apartment. Stores rent amount, frequency, start/end dates, and a computed `paid_until` date.
- **Payment**: recorded against a tenancy. Extends `paid_until` by the number of periods paid. Immutable once created — corrections are made via a voiding entry, never an edit or delete.
- **Receipt**: auto-generated on payment creation, sequential number per property (e.g. `RCT-2026-0001`).
- **Bill**: a utility bill or task created by staff, assigned to all apartments in a property or specific ones. Each assignment tracks its own status independently.
- **Ticket**: a maintenance complaint raised by a tenant. Can be converted into a maintenance record when resolved.
- **Maintenance record**: a logged repair on an apartment, with optional cost, optionally linked back to the ticket that spawned it. Forms part of the apartment's history timeline.
- **Condition report**: notes/photos taken at tenancy start and end (move-in/move-out).

## Roles and Permissions (enforce in Postgres RLS, not just UI)

| Action | Owner | Manager | Caretaker | Tenant |
|---|---|---|---|---|
| Delete property | ✅ | ❌ | ❌ | ❌ |
| Manage members | ✅ | ❌ | ❌ | ❌ |
| Add/edit apartments | ✅ | ✅ | ❌ | ❌ |
| Manage tenancies | ✅ | ✅ | ❌ | ❌ |
| Record payments | ✅ | ✅ | Only if `can_record_payments` | ❌ |
| View rent amounts/totals | ✅ | ✅ | ❌ | Own only |
| Create bills/tasks | ✅ | ✅ | ✅ | ❌ |
| View/respond to tickets | ✅ | ✅ | ✅ | Own only |
| Create tickets | ❌ | ❌ | ❌ | ✅ |
| Log repairs | ✅ | ✅ | ✅ | ❌ |
| View repair costs | ✅ | ✅ | ❌ | ❌ |

**Critical rule:** Every table with sensitive data must have RLS policies that check the user's role via a join/subquery on `memberships` or `tenancies` — never rely on the Flutter UI to hide actions as the only safeguard.

## Key Business Rules

1. Rent is paid in advance. `paid_until` on the tenancy determines status: Paid / Due soon (within grace period, default 7 days) / Overdue. This is computed, not manually set.
2. Payments are **immutable**. Never write an UPDATE or DELETE on the payments table from app code — corrections are a new voiding record with a reason.
3. Receipt numbers must be unique and sequential per property (use a Postgres sequence or a trigger function, not client-side counting).
4. An apartment has at most one active tenancy at a time (v1).
5. Caretakers never see money figures (rent amounts, totals, repair costs) unless a permission explicitly grants it.
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


