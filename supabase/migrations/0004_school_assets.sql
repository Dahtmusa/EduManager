-- EduManager Cloud — PR-D: per-school branding assets
--
-- Two buckets, each with bucket-level enforcement of file-size and
-- allowed MIME types (so a bypass of the browser validator cannot
-- upload executable payloads or oversized files):
--
--   school-assets          (public,  2 MB cap, png/jpeg/webp/svg)
--       Logos + crests. Public GET via the bucket's public URL —
--       required for parent PIN result pages, which are anonymous.
--
--   school-assets-private  (private, 2 MB cap, png/jpeg/webp ONLY)
--       Head-teacher signatures. SVG not allowed here (SVG can carry
--       script and renders unevenly on printed cards). Read is gated
--       both by bucket privacy (no public URL works) and by RLS
--       (only admins/owners of the folder's school can select the
--       object row). Clients obtain short-lived signed URLs via
--       createSignedUrl; parents reading PIN result cards do NOT
--       receive signatures — a server-rendered flow is required
--       and belongs to a later PR.
--
-- Write rules for both buckets:
--   - Path must begin with the uploader's school code.
--   - Uploader must be a member of that school with role in
--     ('owner','admin'), OR the platform owner.
--
-- Idempotent. Safe to re-run. Rollback block at the bottom is
-- deliberately non-destructive — see the comment there.
--
-- This migration touches only storage.buckets and storage.objects.
-- It does NOT alter school_data, memberships, or audit_log.

begin;

-- =========================================================
-- 1. Buckets (idempotent, with file_size_limit + allowed_mime_types)
-- =========================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'school-assets',
  'school-assets',
  true,
  2097152,                                             -- 2 MB
  array['image/png','image/jpeg','image/webp','image/svg+xml']
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'school-assets-private',
  'school-assets-private',
  false,
  2097152,                                             -- 2 MB
  array['image/png','image/jpeg','image/webp']         -- NO SVG for signatures
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- =========================================================
-- 2. Wipe legacy + prior-slice policies so re-runs are clean
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
create policy "school-assets read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'school-assets');

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
--
-- Read is restricted to administrators of the owning school. Ordinary
-- teachers cannot download signatures even though they are members of
-- the school. Parents (anon) cannot read at all — the bucket is
-- private and the SELECT policy requires role in (owner, admin).
-- Platform owner bypass remains. Printed report cards for parents
-- are the responsibility of a later server-side rendering PR.
-- =========================================================
create policy "school-assets-private admin read"
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
          and m.role in ('owner', 'admin')
      )
    )
  );

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
-- Rollback — DELIBERATELY NON-DESTRUCTIVE
--
-- This migration is additive. Normal deployments never need a
-- rollback: rerunning this file is safe (policies are dropped and
-- recreated; bucket flags are upgraded via ON CONFLICT DO UPDATE).
--
-- If you must detach the branding system, do so IN STAGES:
--
--   Stage A (safe, reversible): strip the policies but leave the
--   buckets and every stored asset in place. The branding page in
--   the client will fail on upload but existing schools keep their
--   configured logos because the public bucket's public URLs still
--   resolve. Reverting the client code restores everything.
--
--     begin;
--     drop policy if exists "school-assets read"                   on storage.objects;
--     drop policy if exists "school-assets member insert"          on storage.objects;
--     drop policy if exists "school-assets member update"          on storage.objects;
--     drop policy if exists "school-assets member delete"          on storage.objects;
--     drop policy if exists "school-assets-private admin read"     on storage.objects;
--     drop policy if exists "school-assets-private admin insert"   on storage.objects;
--     drop policy if exists "school-assets-private admin update"   on storage.objects;
--     drop policy if exists "school-assets-private admin delete"   on storage.objects;
--     commit;
--
--   Stage B (destructive — only after Stage A and after you have
--   confirmed every school has either (a) migrated its assets
--   elsewhere or (b) is prepared to lose its configured branding):
--
--     begin;
--     -- Take an evidence dump first:
--     --   select bucket_id, name from storage.objects
--     --   where bucket_id in ('school-assets','school-assets-private');
--     delete from storage.objects
--      where bucket_id in ('school-assets','school-assets-private');
--     delete from storage.buckets
--      where id       in ('school-assets','school-assets-private');
--     commit;
--
-- Never run Stage B as a routine step. Do not include it in a
-- deploy runbook. Only perform it under an explicit product-owner
-- approval that references this comment.
