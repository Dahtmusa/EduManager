# PR-E — Landing + Onboarding + Demo

> **WARNING — Do not merge before PR-B.2 is live and the Supabase migration below has been reviewed and applied to the intended environment.** The new signup flow depends on the post-B.2 membership/RLS and public RPC architecture. If this PR is merged without the migration and email provider configuration, school registration will fail after email verification. Do not test signup against production unless the product owner has explicitly authorised a designated test school code and cleanup plan.

## Scope
- Public marketing homepage at `/`, with navigation, hero and dual CTAs, proof strip, benefits, six feature sections, four onboarding steps, three Naira pricing cards, demo CTA, FAQ and contact footer.
- Plain HTML/CSS/JavaScript in the existing single `index.html`; no build step or framework.
- `/signup` uses Supabase Auth sign-up and email verification, then calls the atomic `create_school` RPC.
- `/demo` loads static fictional data from `demo_seed.json`; no Supabase read/write is performed by the demo.
- `supabase/migrations/0003_create_school.sql` creates the atomic onboarding RPC.
- Hand-drawn SVG product previews are placeholders until PR-D supplies real screenshots.

## Routing contract
Routing is decided before application boot:
- `/` with no query parameters on the canonical Netlify/marketing host: marketing shell; no Supabase client query, no `__master__` pull, no `school_data` pull.
- `/signup`: signup shell; Supabase Auth only until verified signup invokes `create_school`.
- `/demo`: client-state demo shell; static seed file only; no Supabase cloud reads or writes.
- `/app`, `?s=CODE`, legacy `/CODE` and custom-domain root: existing app boot.
- Custom-domain root resolves through `resolve_school(domain)`; it must not read `MASTER.schools` in the browser.

## Database migration
**Cross-PR decision — option (c):** PR-E remains a draft until PR-B.2 is live. PR-B.2 moves the school registry out of `__master__.schools[]`; therefore this PR must not be merged with the current migration's legacy `__master__` registry write. Do not add a compatibility dual-write in either PR. After PR-B.2 merges, create a dedicated follow-up commit on `phaseE-landing-onboarding-demo` (commit message: `PR-E follow-up: target the PR-B.2 school registry`) that rewrites `0003_create_school.sql` to insert the school registry entry into the exact dedicated registry table/API introduced by B.2, removes all `__master__` reads/writes from this migration, rebases the branch onto the post-B.2 `main`, and updates this section with the final schema/API names. Re-review and re-run the migration tests before applying it. The current migration is not approved for application or merge.

Apply `supabase/migrations/0003_create_school.sql` only after PR-B.2 is live and the required follow-up commit above is complete. The public RPC is a SECURITY INVOKER wrapper; its SECURITY DEFINER implementation lives in the unexposed `private` schema with a pinned search path and an explicit authenticated-user check. The function:
- Requires an authenticated, email-verified user.
- Normalises and validates school code and name.
- Creates the `school_data` row and `memberships` admin row in one transaction.
- Seeds four removable starter classes and stores no plaintext password.
- Adds the school registry entry for the platform owner.
- Is executable by authenticated users only; no direct table access is granted to anon.

Rollback SQL is included at the bottom of the migration. Before dropping the function, confirm no pending signup or new school creation is relying on it. Do not delete tenant rows as part of rollback.

## SMTP deliverability — production release gate
**Do not merge this PR to production until the product owner configures a transactional email provider** (Mailgun, Resend or SendGrid) for Supabase Auth and validates a sender domain:
1. Choose and configure the provider in Supabase Auth SMTP settings.
2. Publish the provider's required SPF and DKIM DNS records on the validated sender domain.
3. Verify the DNS records with the provider and wait for sender/domain verification.
4. Configure the verified sender name and address in Supabase Auth.
5. Send a real test verification email to at least one Gmail and one Outlook mailbox; check inbox delivery, spam placement, link correctness and redirect to `/signup?verified=1`.
6. Confirm the verified link returns a usable Auth session or that the sign-in completion path works.
7. Before preview testing, in Supabase dashboard → Authentication → URL Configuration → Redirect URLs, whitelist both exact callback URLs:
   - `https://<preview-host>/signup?verified=1`
   - `https://<production-host>/signup?verified=1`
   Otherwise verification emails may redirect to the Site URL and lose the `?verified=1` flag, breaking the provisioning completion route.
8. Capture and attach to the PR the email provider's delivery-log entry confirming successful inbox delivery to a Nigerian routing recipient (for example, a `.com.ng` mailbox or a Gmail recipient accessed/routed in Nigeria). General Gmail/Outlook delivery alone is not evidence of Nigerian routing deliverability.
9. Do not put SMTP credentials in Git, client code or this deploy document. Configure them only in the Supabase dashboard/secret settings.

The default free-tier SMTP is not an acceptable production deliverability setup for Nigerian school onboarding.

## Preview verification
- Open `/` in a fresh private browser session; confirm the marketing page renders and no Supabase `school_data` or `__master__` request occurs.
- Open `/signup`; confirm only Auth sign-up occurs before verification. Test a duplicate school code and malformed school code.
- Complete email verification; confirm `create_school` creates exactly one school row and one admin membership atomically.
- **T1 — Duplicate signup race:** in two independent sessions, submit the same unused school code simultaneously. Exactly one school is created; the losing session receives the clean `School code is unavailable` message, never a raw PostgreSQL unique-constraint error.
- **T2 — Cross-device verification:** sign up on device A, open the verification link on device B, confirm the fallback sign-in form appears, then sign in on device B and verify provisioning completes once.
- **T3 — Repeat verification:** after successful provisioning, open the same verification link again. `create_school` must return `{already_created:true}` and redirect to `/?s=CODE` without creating a second school or membership.
- **T4 — Zero-membership state:** in a disposable preview tenant, after Auth signup but before successful RPC provisioning, remove the membership row using an authorised test-only database session and reload. The app must not render an admin view or grant access to any school. Restore/clean up the test fixture after evidence is captured.
- Confirm the new admin can enter the new school via Supabase Auth membership and that no password is written into `school_data.data.users[]`.
- Confirm four starter classes appear and the Remove sample data action uses a verified cloud commit; force a save failure and confirm sample data remains.
- Open `/demo`; confirm 30 fictional pupils, four classes, partial mid-term results and Hifz progress appear. Toggle attendance, reload, and confirm the demo resets. Verify no Supabase table/RPC requests originate from demo.
- Leave demo idle for 30 minutes in a controlled test and confirm its in-memory edits reset.
- Test keyboard-only navigation, visible focus, form labels/errors, contrast, touch targets, screen-reader status and reduced-motion behavior against WCAG 2.2 AA.
- Verify custom-domain resolution uses `resolve_school`, and that public marketing on the canonical host does not invoke it.
- Verify the placeholder SVG previews are clearly labelled as illustrative; replace them with real PR-D screenshots in a visual-only follow-up after PR-D lands.

## Deploy order
1. Review and apply the additive onboarding migration to the intended preview Supabase project after PR-B.2 is live.
2. Configure preview SMTP and verify sender/domain deliverability.
3. Deploy the PR-E branch to Netlify preview.
4. Complete the preview tests above.
5. Obtain Claude's independent review and explicit product-owner approval.
6. Before production merge, configure production SMTP and run a test-send.
7. Merge PR-E; Netlify auto-deploys. No manual production SQL is permitted unless the product owner follows the reviewed migration procedure.

## Rollback
1. Revert the PR-E merge commit and wait for Netlify to publish the previous application code.
2. Do not delete schools or memberships created while the PR was live.
3. Only after confirming the old code is live, revoke execution and drop the `create_school` RPC using the migration's rollback block if the product owner approves.
4. Keep all created tenant rows and membership records intact for reconciliation; no destructive tenant cleanup is included.
5. Schools and memberships created while PR-E was live remain valid after application rollback. Their admins can still sign in through Supabase Auth and their `school_data` rows persist. They cannot self-provision additional schools after the `create_school` RPC is dropped. Decide per incident whether to leave the RPC in place (safer for continuity) or drop it as part of rollback (cleaner); do not drop it automatically.

## Deferred / dependencies
- Final real screenshots depend on PR-D; this PR ships SVG placeholders and a visual-only follow-up will replace them.
- Paystack billing and trial enforcement belong to PR-F. The pricing cards in this PR describe the intended plans and trial offer but do not charge customers.
- Existing legacy teacher/admin credential migration and removal of all plaintext legacy passwords remain subject to the agreed Auth migration/security plan. New signup does not introduce plaintext passwords into the school JSON.
- The PR-B.2 20-row security test matrix must be copied verbatim from Claude's review into `PHASE-B2-DEPLOY.md`; it was not included in the product-owner message available during this draft and must not be reconstructed from memory.
- **Registry follow-up is mandatory:** the exact next PR-E follow-up commit after B.2 is `PR-E follow-up: target the PR-B.2 school registry`. It must replace the current `__master__.schools[]` write with the dedicated registry mechanism created by B.2 before this PR can leave draft status.
