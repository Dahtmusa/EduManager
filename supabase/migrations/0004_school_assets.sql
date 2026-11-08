-- EduManager Cloud — PR-D: per-school branding assets
--
-- Revision in slice 3: split public from private assets.
--   Bucket "school-assets"         (PUBLIC)   — logos + crests.
--                                              Anyone on the internet can
--                                              GET these via the bucket's
--                                              public URL. Appropriate
--                                              because logos/crests are
--                                              intentionally public (they
--                                              appear on report cards that
--                                              parents view anonymously
--                                              via a result-check PIN).
--   Bucket "school-assets-private" (PRIVATE)  — head-teacher signatures.
--                                              Read only via a signed URL
--                                              created by an authenticated
--                                              session that is a member of
--                                              the owning school. Prevents
--                                              trivial scraping of
--                                              signatures for forgery.
--
-- Write rules are identical for both buckets:
--   - Path must begin with the uploader's school code.
--   - Uploader must be a member of that school with role in
--     ('owner','admin'), OR the platform owner (app_metadata.role=owner).
--
-- Idempotent. Safe to re-run. Rollback block at the bottom.
--
-- This migration touches only storage.buckets and storage.objects
-- policies. It does NOT alter school_data, memberships, or audit_log.
-- Can run before or after PR-B.2.

begin;

-- =========================================================
-- 1. Buckets (idempotent)
-- =========================================================

-- Public bucket: logos + crests. `public = true` gives every object a
-- directly-cacheable public URL (needed for parent PIN result pages
-- where the viewer is anonymous).
insert into storage.buckets (id, name, public)
values ('school-assets', 'school-assets', true)
on conflict (id) do update set public = excluded.public;

-- Private bucket: signatures. `public = false` means ordinary public
-- URLs don't work; clients must call createSignedUrl for each read.
insert into storage.buckets (id, name, public)
values ('school-assets-private', 'school-assets-private', false)
on conflict (id) do update set public = excluded.public;


-- =========================================================
-- 2. Wipe legacy and prior-slice policies so re-runs are clean
-- =========================================================
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (policyname like 'school-assets%'
           or policyname like 'school-assets-private%')
  loop
    execute format('drop policy if exists %I on storage.objects', p.policyname);
  end loop;
end$$;


-- =========================================================
-- 3. PUBLIC bucket (school-assets) — logos, crests
-- =========================================================

-- Read: unauthenticated (anon) and authenticated both allowed. This is
-- the whole point of a public bucket; the Storage layer already allows
-- anonymous GET via the public URL, but declaring an explicit SELECT
-- policy keeps RLS consistent and makes intent audit-able.
create policy "school-assets read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'school-assets');

-- Write (insert/update/delete): must be a member of the folder's school
-- with role owner|admin, OR the platform owner.
create policy "school-assets member insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'school-assets'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  );

create policy "school-assets member update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'school-assets'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  )
  with check (
    bucket_id = 'school-assets'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  );

create policy "school-assets member delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'school-assets'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  );


-- =========================================================
-- 4. PRIVATE bucket (school-assets-private) — signatures
-- =========================================================

-- Read: only authenticated users who are a member of the folder's
-- school can SELECT the object row. For a non-public bucket, any URL
-- fetch still requires a signed URL created by the owning session, so
-- an app that calls createSignedUrl effectively gates at both the
-- policy layer and the signing layer.
create policy "school-assets-private member read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'school-assets-private'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
      )
    )
  );

-- Write: same role requirement as the public bucket (owner|admin of
-- the owning school, or platform owner).
create policy "school-assets-private admin insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'school-assets-private'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  );

create policy "school-assets-private admin update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'school-assets-private'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  )
  with check (
    bucket_id = 'school-assets-private'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  );

create policy "school-assets-private admin delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'school-assets-private'
    and (
      coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'owner'
      or exists (
        select 1 from public.memberships m
        where m.user_id = auth.uid()
          and m.school_id = (storage.foldername(name))[1]
          and m.role in ('owner', 'admin')
      )
    )
  );

commit;

-- =========================================================
-- Rollback (reverses this migration; removes every stored asset and
-- every school's configured logo/crest/signature):
--
-- begin;
-- drop policy if exists "school-assets read"                   on storage.objects;
-- drop policy if exists "school-assets member insert"          on storage.objects;
-- drop policy if exists "school-assets member update"          on storage.objects;
-- drop policy if exists "school-assets member delete"          on storage.objects;
-- drop policy if exists "school-assets-private member read"    on storage.objects;
-- drop policy if exists "school-assets-private admin insert"   on storage.objects;
-- drop policy if exists "school-assets-private admin update"   on storage.objects;
-- drop policy if exists "school-assets-private admin delete"   on storage.objects;
-- delete from storage.objects where bucket_id in ('school-assets','school-assets-private');
-- delete from storage.buckets where id in ('school-assets','school-assets-private');
-- commit;
