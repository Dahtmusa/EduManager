-- EduManager Cloud — PR-D: per-school branding assets bucket
--
-- Idempotent. Creates a public-read, member-write Storage bucket
-- `school-assets` for logos, crests, head-teacher signatures.
-- Images are referenced by URL from school_data.data.settings.branding,
-- NEVER embedded as base64 in the JSON row.
--
-- Path convention (enforced by the policies below):
--   school-assets/{SCHOOL_CODE}/logo.<ext>
--   school-assets/{SCHOOL_CODE}/crest.<ext>
--   school-assets/{SCHOOL_CODE}/signature.<ext>
--
-- Any authenticated user reads any school's asset (logos are not secret).
-- Only members of a school with role in ('owner','admin') can write to
-- that school's folder. Platform owner can write any folder.
--
-- This migration touches only storage.objects policies; it does NOT alter
-- school_data, memberships, or audit_log. Safe to run before or after
-- PR-B.2.

begin;

-- 1. Create the bucket (idempotent). `public` = false because policies
--    below handle read access; this prevents accidental anon writes.
insert into storage.buckets (id, name, public)
values ('school-assets', 'school-assets', false)
on conflict (id) do nothing;

-- 2. Wipe any legacy policies on this bucket so re-runs are clean.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like 'school-assets%'
  loop
    execute format('drop policy if exists %I on storage.objects', p.policyname);
  end loop;
end$$;

-- 3. Read: any authenticated user may download any school's assets.
--    This is intentional — logos and crests are meant to appear on a
--    school's public-facing report cards and parent PIN result pages.
create policy "school-assets read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'school-assets');

-- 4. Write (insert / update / delete): a user may touch an object only
--    when its path begins with `<school_code>/` and they have an
--    appropriate membership in that school, OR they are the platform
--    owner.
--
--    storage.foldername(name) returns a text[] of the path segments;
--    the first segment is the school code.
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

commit;

-- Rollback (reverses this migration; run only if you intend to remove
-- the branding system entirely and are prepared for existing schools
-- to lose their configured logos/crests/signatures):
--
-- begin;
-- drop policy if exists "school-assets read"          on storage.objects;
-- drop policy if exists "school-assets member insert" on storage.objects;
-- drop policy if exists "school-assets member update" on storage.objects;
-- drop policy if exists "school-assets member delete" on storage.objects;
-- delete from storage.objects where bucket_id = 'school-assets';
-- delete from storage.buckets where id = 'school-assets';
-- commit;
