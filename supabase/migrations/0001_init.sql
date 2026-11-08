-- EduManager Cloud — Phase 0: auth + RLS foundation
--
-- Idempotent. Safe to run on an existing project that already has the
-- school_data table. Creates the identity/membership tables that every
-- later migration keys off, and locks school_data behind Supabase Auth.
--
-- Run this from the Supabase dashboard (SQL editor) once. Rollback at
-- the bottom if you need it.

-- =========================================================
-- 1. Identity + membership
-- =========================================================

-- A profile row per Supabase Auth user. Created on first sign-in by a
-- trigger so the app never has to.
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles self read"  on public.profiles;
drop policy if exists "profiles self write" on public.profiles;

create policy "profiles self read"
  on public.profiles for select
  using (user_id = auth.uid());

create policy "profiles self write"
  on public.profiles for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public._handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(user_id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public._handle_new_user();


-- Which schools each user belongs to, and what role they have in each.
-- The school_id is the SCHOOL_CODE (uppercase string) — same identifier
-- school_data already uses, so no renames are needed at this phase.
create table if not exists public.memberships (
  user_id    uuid not null references auth.users(id) on delete cascade,
  school_id  text not null,
  role       text not null check (role in ('owner','admin','teacher','parent','pupil')),
  created_at timestamptz not null default now(),
  primary key (user_id, school_id)
);

create index if not exists memberships_school_idx on public.memberships(school_id);

alter table public.memberships enable row level security;

drop policy if exists "membership self read"       on public.memberships;
drop policy if exists "membership platform write"  on public.memberships;

-- A user can see their own memberships. The platform owner (identified
-- by app_metadata.role = 'owner' set in Supabase Auth) can see all.
create policy "membership self read"
  on public.memberships for select
  using (
    user_id = auth.uid()
    or coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
  );

-- Only the platform owner can grant / revoke memberships (for now).
-- Promote this later when school admins should manage their own staff.
create policy "membership platform write"
  on public.memberships for all
  using (coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner')
  with check (coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner');


-- =========================================================
-- 2. Lock down school_data
--
-- school_data is the current JSONB-blob-per-school table. Until Phase 2
-- splits it into relational tables, we gate it behind Supabase Auth:
--   - The anon role can read NOTHING.
--   - An authenticated user can read/write the row whose id matches one
--     of their memberships, PLUS the shared '__master__' registry row
--     (read-only, and never carrying credentials any more).
--   - The platform owner (app_metadata.role = 'owner') can read/write
--     every row including '__master__'.
-- =========================================================

alter table public.school_data enable row level security;

-- Drop any permissive legacy policies left over from the anon-key era.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'school_data'
  loop
    execute format('drop policy if exists %I on public.school_data', p.policyname);
  end loop;
end$$;

-- Read: own schools, or the master row, or anything if you're the owner.
create policy "school_data read"
  on public.school_data for select
  to authenticated
  using (
    id = '__master__'
    or exists (
      select 1 from public.memberships m
      where m.user_id = auth.uid() and m.school_id = public.school_data.id
    )
    or coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
  );

-- Insert: owner only. New tenants are provisioned by the platform owner.
create policy "school_data insert"
  on public.school_data for insert
  to authenticated
  with check (coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner');

-- Update: own schools (admin/teacher), or anything if owner. Nobody but
-- owner writes to '__master__'.
create policy "school_data update"
  on public.school_data for update
  to authenticated
  using (
    coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
    or (
      id <> '__master__'
      and exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = public.school_data.id
          and m.role in ('owner','admin','teacher')
      )
    )
  )
  with check (
    coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
    or (
      id <> '__master__'
      and exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = public.school_data.id
          and m.role in ('owner','admin','teacher')
      )
    )
  );

-- Delete: owner only.
create policy "school_data delete"
  on public.school_data for delete
  to authenticated
  using (coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner');


-- =========================================================
-- 3. Audit-log skeleton
--
-- Phase 2 migrations will have DB triggers write into this. Creating
-- the table up-front so the schema stays additive.
-- =========================================================

create table if not exists public.audit_log (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  school_id  text,
  user_id    uuid references auth.users(id) on delete set null,
  action     text not null,
  entity     text,
  entity_id  text,
  before     jsonb,
  after      jsonb
);

create index if not exists audit_log_school_idx on public.audit_log(school_id, at desc);

alter table public.audit_log enable row level security;

drop policy if exists "audit_log read" on public.audit_log;

create policy "audit_log read"
  on public.audit_log for select
  to authenticated
  using (
    coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
    or exists (
      select 1 from public.memberships m
      where m.user_id = auth.uid()
        and m.school_id = public.audit_log.school_id
        and m.role in ('owner','admin')
    )
  );

-- Audit rows are only ever written by SECURITY DEFINER triggers in later
-- migrations; no client-side INSERT policy on purpose.


-- =========================================================
-- Rollback (uncomment and run to undo this migration):
-- =========================================================
-- drop table if exists public.audit_log;
-- drop policy if exists "school_data read"   on public.school_data;
-- drop policy if exists "school_data insert" on public.school_data;
-- drop policy if exists "school_data update" on public.school_data;
-- drop policy if exists "school_data delete" on public.school_data;
-- alter table public.school_data disable row level security;
-- drop trigger if exists on_auth_user_created on auth.users;
-- drop function if exists public._handle_new_user();
-- drop table if exists public.memberships;
-- drop table if exists public.profiles;
