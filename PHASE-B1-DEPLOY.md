# PR-B.1 — Phase 1 fully-online deployment

## Scope

This deploy merges only Phase 1 from `phase-1-online-only` at commit
`2e925ef970ecacc4311f3351ee37f74b1875e79c`, plus this PR-B.1 deploy
document. The application changes are limited to the Phase 1 changes in
`index.html` and the existing `PHASE-1-DEPLOY.md`.

No PR-B.2 or PR-C work is included. No SQL, database migration,
Supabase dashboard change, environment-variable change, or production
data operation is required or authorized by this PR.

## Expected behavior change

- The browser no longer mirrors school data into `localStorage` keys
  `sms_store` or `sms_base`; the rolling `sms_bak_*` snapshot cache
  is removed.
- Existing stale school-data cache keys are removed on the next app
  load. The explicit user-requested **Download backup** export remains
  available and is distinct from browser cache storage.
- Supabase is the source of truth. A cloud read/write failure must be
  visible to the user; stale persisted browser data must not be used to
  make the app appear to have succeeded.
- There is no offline mode. Users must retry after connectivity is
  restored. In-progress, unsaved edits held only in page memory are not
  recovered after a tab is closed or refreshed.
- CAS concurrency protection remains in place.

## Preflight checklist

Before merging PR-B.1:

- [ ] Confirm this PR's base is `main` and its head is
      `phaseB1-phase1-merge`.
- [ ] Confirm the diff contains only the Phase 1 application changes
      (`index.html`, `PHASE-1-DEPLOY.md`) and this document
      (`PHASE-B1-DEPLOY.md`). No other application file may change.
- [ ] Confirm the Phase 1 source is exactly
      `2e925ef970ecacc4311f3351ee37f74b1875e79c`.
- [ ] Confirm no SQL/migration, Supabase configuration, environment
      variable, or production data change is included.
- [ ] Confirm the Netlify deploy preview is built from this PR branch
      and identify which Supabase project the preview uses before any
      write test.
- [ ] Ensure owner and BNFODIO school-admin test credentials are
      available to the authorized tester; never place credentials in
      this repository, PR comments, screenshots, or logs.
- [ ] If the preview points to production Supabase, do not perform a
      test save that changes BNFODIO data. Use a separately approved,
      non-destructive test record/environment, or limit the check to
      sign-in and read-only workflow verification.
- [ ] Confirm a current, independently verified backup/recovery path
      exists before any later production rollout. This PR itself does
      not create, alter, or restore a database backup.

## Preview verification plan

Run these checks on the Netlify deploy preview before approving merge:

1. **Owner sign-in:** Sign in as the platform owner. Confirm the owner
   dashboard loads and the existing owner workflow remains available.
2. **BNFODIO school-admin sign-in:** Sign in using the authorized
   BNFODIO school-admin account. Confirm the school dashboard and
   teacher-facing workflow load. Do not change live BNFODIO records.
3. **Local Storage cleanup:** In DevTools → Application → Local Storage,
   inspect the preview origin after a page load. Confirm
   `sms_store`, `sms_base`, and every `sms_bak_*` key are absent.
   After an approved save in a designated safe test record, inspect
   again and confirm those keys have not reappeared.
4. **Cloud failure visibility:** With a safe test session, intentionally
   interrupt network access and attempt a cloud-dependent read/save.
   Confirm the connection-lock / cloud-unavailable overlay is shown and
   the UI does not report a successful save or silently fall back to
   stale persisted data. Restore connectivity and confirm the user can
   retry. If the expected overlay does not appear, record the check as
   failed and do not approve the PR until investigated.
5. **Regression sanity:** Confirm normal online reload and save work
   after connectivity is restored. Do not test destructive restore,
   tenant creation, role changes, or billing in this PR.

Record the preview URL, browser/device, tester, timestamps, and
pass/fail evidence. Redact credentials, student information, PINs, and
other sensitive data from screenshots and logs.

## BNFODIO data-safety confirmation

- This PR changes client-side persistence behavior only.
- It does not run SQL, alter Supabase policies/schema/configuration, or
  migrate database rows.
- It does not delete, truncate, reseed, or overwrite BNFODIO data.
- BNFODIO sign-in and workflow checks must be read-only unless a
  designated safe test record and explicit test authorization are in
  place.
- The one-time browser cleanup removes only this app's
  `sms_store`, `sms_base`, and `sms_bak_*` localStorage keys on the
  visitor's device. It does not delete cloud records or the explicit
  downloaded JSON backup files.

## Rollback

If preview verification or post-merge behavior regresses:

1. Revert the PR-B.1 **merge commit** on GitHub (create a revert commit;
   do not reset or force-push `main`).
2. Allow Netlify's normal `main` deployment to publish the revert.
3. Verify the previous application version is serving and owner /
   school-admin sign-in is restored.
4. Do not run database rollback SQL: PR-B.1 has no database changes.
5. Do not restore browser cache data or overwrite BNFODIO cloud data
   as part of rollback. The prior app code may recreate its local cache
   on subsequent use; that does not authorize any cloud-data rewrite.

## Review and release gate

Claude must independently review the branch diff and this deploy plan.
The product owner must explicitly approve PR-B.1 before it is merged.
This document is a plan, not evidence that preview checks or a
production deployment have already occurred.
