-- 0021 — Idempotent table/sequence grants for authenticated PostgREST access.
--
-- Purpose: Supabase/PostgREST refuses to expose a table when the API role has
-- no schema USAGE or table privileges, even when an RLS policy would allow the
-- row. These statements grant the table-level access PostgREST needs and leave
-- RLS as the only gatekeeper for which rows a signed-in staff member can see.
--
-- Every statement below is natively idempotent in PostgreSQL: GRANT, REVOKE,
-- GRANT ... ON ALL TABLES/SEQUENCES and ALTER DEFAULT PRIVILEGES ... GRANT may
-- all be re-run without error. No DO blocks are needed. The bundle in
-- supabase/all_owner_sql.sql repeats this exact section and is applied twice in
-- CI, so re-runnability is required.
--
-- Order matters: the broad table grant is applied first, then the two
-- activity_log revokes narrow it again (the log is append-only for clients).

-- 1. PostgREST must be able to resolve objects in the public schema.
grant usage on schema public to anon, authenticated;

-- 2. Signed-in staff get table-level CRUD; RLS still decides each row.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- 3. activity_log is written only by triggers and SECURITY DEFINER RPCs.
revoke update, delete on table public.activity_log from authenticated;

-- 4. Anonymous callers must never reach the activity log.
revoke all on table public.activity_log from anon;

-- 5. Identity/serial columns need sequence access for explicit nextval calls.
grant usage, select on all sequences in schema public to authenticated;

-- 6. Future tables and sequences created in public inherit the same access.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;

alter default privileges in schema public
  grant usage, select on sequences to authenticated;
