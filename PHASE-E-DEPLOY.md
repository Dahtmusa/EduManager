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
Apply `supabase/migrations/0003_create_school.sql` only after PR-B.2 is live. The function:
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
7. Do not put SMTP credentials in Git, client code or this deploy document. Configure them only in the Supabase dashboard/secret settings.

The default free-tier SMTP is not an acceptable production deliverability setup for Nigerian school onboarding.

## Preview verification
- Open `/` in a fresh private browser session; confirm the marketing page renders and no Supabase `school_data` or `__master__` request occurs.
- Open `/signup`; confirm only Auth sign-up occurs before verification. Test a duplicate school code and malformed school code.
- Complete email verification; confirm `create_school` creates exactly one school row and one admin membership atomically.
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

## Deferred / dependencies
- Final real screenshots depend on PR-D; this PR ships SVG placeholders and a visual-only follow-up will replace them.
- Paystack billing and trial enforcement belong to PR-F. The pricing cards in this PR describe the intended plans and trial offer but do not charge customers.
- Existing legacy teacher/admin credential migration and removal of all plaintext legacy passwords remain subject to the agreed Auth migration/security plan. New signup does not introduce plaintext passwords into the school JSON.
- The PR-B.2 20-row security test matrix must be copied verbatim from Claude's review into `PHASE-B2-DEPLOY.md`; it was not included in the product-owner message available during this draft and must not be reconstructed from memory.
