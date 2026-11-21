-- Minimal Supabase-compatible scaffolding for a plain PostgreSQL 16 server.
--
-- This file is TEST INFRASTRUCTURE ONLY. It is never applied to the real
-- Supabase project and is not part of the owner's schema. It recreates just the
-- platform objects the migrations assume already exist on Supabase: the
-- auth/storage/extensions schemas, the three API roles, a few auth/storage
-- helper functions and the realtime publication.
--
-- Applied by .github/workflows/ci.yml (db-test job) before either
-- supabase/all_owner_sql.sql or the numbered migrations.

create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
  alter role service_role bypassrls;
end $$;

grant usage on schema public, auth, storage, extensions
  to anon, authenticated, service_role;

-- PostgREST connects as a real login role and switches to the JWT's `role`
-- claim. On Supabase that login is `authenticator`; on a plain server we create
-- an equivalent here. It must NOT bypass RLS: membership lets PostgREST SET
-- ROLE to anon/authenticated, and the RLS policies then do the real work.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'e2e_authenticator') then
    create role e2e_authenticator nologin;
  end if;
  alter role e2e_authenticator with login password 'e2e_authenticator';
end $$;
grant anon, authenticated, service_role to e2e_authenticator;
grant usage on schema public, auth, storage, extensions to e2e_authenticator;

-- Supabase's auth.users: only the columns referenced by the migrations.
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- JWT-backed helpers. PostgREST 12 removed the per-claim request.jwt.claim.*
-- GUCs and exposes the whole payload as request.jwt.claims JSON. Supabase's
-- managed stack keeps the legacy names working, so the CI stub must accept
-- both shapes or every auth.uid()-based policy would see NULL under bare
-- PostgREST. By default uid() is NULL, exactly like an anonymous request.
create or replace function auth.uid()
returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid
$$;

create or replace function auth.role()
returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    'anon'
  )
$$;

create or replace function auth.jwt()
returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

comment on function auth.uid() is 'CI stub: reads request.jwt.claim.sub';
comment on function auth.role() is 'CI stub: reads request.jwt.claim.role';
comment on function auth.jwt() is 'CI stub: reads request.jwt.claims';

-- Test-only expose of auth.uid() so the e2e suite can assert that the signed
-- JWT subject reaches database helpers through PostgREST. Not part of owner SQL.
create or replace function public.e2e_auth_uid()
returns text language sql stable as $$
  select auth.uid()::text
$$;
revoke all on function public.e2e_auth_uid() from public;
grant execute on function public.e2e_auth_uid() to authenticated;

-- Storage scaffolding used by 0012_rls_hardening.sql and schema_check.sql.
create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null references storage.buckets(id) on delete cascade,
  name text not null,
  owner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_accessed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists objects_bucket_name_idx
  on storage.objects (bucket_id, name);

-- Supabase storage.foldername('branch/rx/file.pdf') -> {branch, rx}.
create or replace function storage.foldername(name text)
returns text[] language plpgsql immutable as $$
declare
  parts text[] := string_to_array(name, '/');
  n int := coalesce(array_length(parts, 1), 0);
begin
  if n < 2 then
    return array[]::text[];
  end if;
  return parts[1:(n - 1)];
end $$;

comment on function storage.foldername(text) is 'CI stub for supabase.storage.foldername';

-- 0017_activity_audit.sql adds public.activity_log to this publication.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'create publication supabase_realtime';
  end if;
end $$;
