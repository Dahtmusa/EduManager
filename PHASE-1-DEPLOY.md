# Phase 1 — fully online

The app no longer keeps a copy of school data on the device. It behaves like any ordinary website:

- Every page load reads from the cloud. If the cloud is unreachable, the user sees the existing "Could not reach the cloud" screen instead of stale cached data.
- Every save goes straight to Supabase. "✓ Saved" only shows after the server confirms.
- No more `localStorage` mirror of `STORE` / `BASE`.
- No more rolling on-device snapshots. Explicit "Download backup" (user clicks the button, browser saves a dated JSON file to disk) still works — that is not a cache, it's an explicit export.

The CAS concurrency protection is **kept** — it prevents two teachers from clobbering each other's class saves. That was never the problem; the problem was stale device data, which is now gone.

## What this fixes

- The "saved but blank" bug class, permanently. A saved result cannot contradict the server because the browser no longer holds its own copy.
- Teachers can never see out-of-date data after you edit on the owner dashboard. One reload = fresh.
- RLS from Phase 0 is now actually meaningful — before this PR, a user with a stale cache could render data they no longer had permission to see.

## What it costs — be honest with users

- **No offline mode.** If the network drops mid-save, the save fails and the user retries. This is what you asked for.
- **Work in progress isn't recovered on refresh.** If a teacher types half a column of scores and closes the tab without saving, those keystrokes are gone. (Phase 0 already changed the score inputs so every keystroke writes into `DB` as soon as it's typed — but `DB` is in-memory for the lifetime of that tab. Saving to the cloud is the moment it becomes persistent.)
- First page load after this deploys will be slightly slower for users who previously had a cached `STORE` — they now fetch everything fresh. Subsequent loads are the same.

## Deploy

1. Merge this PR.
2. Netlify auto-deploys `main`.
3. The one-time `localStorage.removeItem('sms_store')` / `sms_base` / `sms_bak_*` in the new `index.html` runs on every visitor's next load, so any old cache on existing devices is cleaned up automatically. No action required from teachers.

That's it. No SQL to run, no Supabase dashboard work.

## Verify on the preview before merging

Open the Netlify deploy preview for this PR:

1. Open the app in your browser's dev tools → **Application → Local Storage**.
2. Before this deploy you'd have seen `sms_store`, `sms_base`, maybe `sms_bak_DEMO` etc.
3. After this deploy, load the preview — those keys should be gone, and they should not come back when you save a result.

If you also want to confirm fresh fetches: open DevTools → Network tab → reload → you should see POST / GET requests to `wuasxzkqojxadblaohzb.supabase.co` on every nav, not served from memory.

## Rollback

If anything misbehaves: revert the merge commit on GitHub. Netlify re-deploys the previous build and the localStorage mirror is back. Nothing in Supabase was changed by this PR.

## What's **not** in this PR

- Teacher / admin logins still use the legacy per-school user list (not Supabase Auth). The pure-online change was the user's priority; the Auth migration is its own PR because it needs email addresses collected for every teacher.
- The JSONB blob is still the storage model. Phase 2 breaks it into relational tables (`results`, `payments`, …) one feature at a time.
