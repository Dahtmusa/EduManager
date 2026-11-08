# Phase 0 — deploy guide

This PR starts the move to a professional multi-tenant architecture:

- The **platform owner** signs in only via Supabase Auth. The owner password is no longer stored in any row that ships to clients.
- A new `supabase/migrations/0001_init.sql` creates `profiles`, `memberships`, and `audit_log`, and puts the existing `school_data` table behind Row Level Security.
- `__master__` is scrubbed of any leftover `owner.password` / `owner.username` on every load, so even a historical row that still carries one is never exposed to a client.

No feature in the UI changes for teachers or parents. BNFODIO (and any other live school) keep signing in exactly as before. **Do not merge this PR until the steps below are done**, or owner sign-in will break.

## Deploy order (strict)

### 1. Run the SQL migration

Supabase dashboard → SQL Editor → paste the contents of `supabase/migrations/0001_init.sql` → **Run**. It is idempotent; running twice is safe.

### 2. Create the platform-owner Auth user

Supabase dashboard → **Authentication → Users → Add user → Create new user**.

- Email: your real platform-owner email.
- Password: pick a strong one. You will type this to sign in.
- Auto-confirm: **yes**.

Then, in the same user's row, open **Raw user meta data / app_metadata** and set:

```json
{ "role": "owner" }
```

(This is `app_metadata`, not `user_metadata`. The SQL policies check `app_metadata.role`.)

Optionally set `user_metadata.name` to "Your Name" so the top bar shows it.

### 3. Verify owner sign-in on a preview deploy

Open the Netlify deploy preview for this PR, go to the owner login page, and sign in with the **email** from step 2. You should land in the owner dashboard. If sign-in fails, double-check step 2 — the most common mistake is putting `role: "owner"` into `user_metadata` instead of `app_metadata`.

### 4. (Optional, recommended) Scrub the live `__master__` row

The code now strips `platform.owner.password` on every load, so clients can no longer see it. To also remove it at rest in the database, run this once in the Supabase SQL editor:

```sql
update public.school_data
set data = jsonb_set(
  data #- '{platform,owner,password}' #- '{platform,owner,username}',
  '{}', data #- '{platform,owner,password}' #- '{platform,owner,username}' -> ''
)
where id = '__master__';
```

### 5. Merge

Once step 3 works on the preview, merge this PR. Netlify auto-deploys `main`.

### 6. Rotate the anon key (recommended, not required)

Supabase dashboard → **Project settings → API → Reset anon key**. Paste the new key into `index.html` (`SUPABASE_KEY`) and push. The old key is now dead; anyone who scraped it from a previous version of the site can no longer reach anything, because RLS now denies the anon role on every row.

## What this PR does **not** do

- Does **not** migrate teacher or admin logins to Supabase Auth. Those remain on the legacy per-school user list for now. That's Phase 1.
- Does **not** rip out the `localStorage` mirror or the CAS merge. Doing that in the same PR as the auth cutover is too risky mid-term. That's Phase 1 too.
- Does **not** create per-feature relational tables (`results`, `payments`, …). That's Phase 2.

## Rollback

If anything breaks:

1. Revert the merge commit in Git — Netlify re-deploys the previous build.
2. In Supabase, run the rollback block at the bottom of `supabase/migrations/0001_init.sql` to drop RLS and the new tables. `school_data` returns to the "anon reads everything" state it had before.

Keep the owner Auth user you created — nothing is lost.
