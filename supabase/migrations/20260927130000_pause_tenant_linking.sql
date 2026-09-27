-- =============================================================================
-- TEMPORARY: pause tenant linking while email confirmation is switched off.
--
-- link_my_tenant_records() links tenant contacts to an account by matching
-- the account's email. With "Confirm email" off in Supabase, nobody has
-- proven they own the email they signed up with, so anyone could sign up as
-- a tenant's address and see that tenant's rent and payments.
--
-- Until confirmation is back on, the app can't call the function at all.
-- (The app's call fails quietly; nothing else depends on it.)
--
-- TO UNDO (when email confirmation is switched back on), run a new migration:
--   grant execute on function public.link_my_tenant_records() to authenticated;
-- See the checklist in PLAN.md.
-- =============================================================================

revoke execute on function public.link_my_tenant_records() from authenticated;
