# PR-B.2 — Tenant isolation, owner registry and verified restore

> Draft engineering scope. This document is not authorization to apply a migration to production.

## Preconditions and current state

- PR-B.1 merged to `main` at `67e5c890ebf6345e009d66de4baa0a150b326306`.
- This branch starts from post-B.1 `main`.
- PR-E's `0003_create_school.sql` has already been applied to the connected Supabase project, although PR-E remains unmerged. Its `create_school` implementation currently writes `__master__.schools[]`; this PR must reconcile that RPC with the new registry without a dual-write.
- Read-only aggregate preflight found 7 registry entries, 4 PINs and 3 batches. It found zero missing school codes/names, zero missing PIN school/code fields, zero missing batch school/ID fields and zero orphan PINs/batches. No student or tenant row contents were read.
- Product decision confirmed: preserve the public admission-number + PIN result-checker experience; parents/pupils will not be required to sign in.

## Security objectives

1. Make `__master__` readable only by the exact platform-owner app role. Non-owner clients must never query it.
2. Move the platform school registry into a dedicated owner-only `school_registry` table; preserve all registry metadata, including legacy subscription payloads until PR-F migrates them.
3. Move PINs and batches into `school_pins` and `school_batches`, keyed by `school_id`; RLS must prevent cross-school reads and writes.
4. Add `school_domains` and an anonymous `resolve_school(domain)` RPC with a stable null-on-miss response, fixed delay and concurrency-safe per-IP rate limit.
5. Keep public PIN validation available without Supabase Auth. Return one identical JSON shape for all outcomes, enforce current-session/current-term checks, fixed delay and independent per-IP rate limits.
6. Preserve public PIN consumption without weakening authorization. Do not expose a generic anonymous `consume_pin(code,school)` endpoint. Design a server-verifiable, short-lived, single-use proof/challenge issued only after successful PIN validation, scoped to the exact school and PIN, expiring quickly and atomically consumed after the result is rendered. The proof must be unforgeable, replay-resistant, and unusable across schools or PINs. Consumption must increment usage exactly once and write one non-PII audit event. Keep PIN usage itself unchanged during validation.
7. Public validation may create only the minimal short-lived challenge state required for later consumption; it must not increment PIN usage. Define cleanup/retention for expired and consumed challenges. Rate-limit challenge creation and consumption under concurrency.
8. Add public billboard-safe `platform_meta(name,minVersion)` only; no other platform metadata is public.
9. Rewrite `doRestore` to use the database-first CAS commit helper, retain a recoverable snapshot, strip legacy plaintext passwords from imported data and only show success after revision verification.

## Public result-checker contract

- User experience remains admission number + PIN, with no account creation or sign-in.
- Server-side validation establishes eligibility and issues a short-lived, opaque, single-use consumption proof only on success. Do not expose the raw PIN or reusable authorization data in the proof.
- The browser renders the result, then submits the proof to the consumption endpoint. A failed consumption must not be reported as successful usage; handle retry/idempotency explicitly so a network retry cannot double-increment.
- Consumption validates proof integrity, expiry, exact school/PIN binding, unused status and current entitlement/session/term constraints, then atomically marks proof consumed and increments usage once.
- A client-supplied school code, admission number, PIN, IP address or role is never sufficient authority by itself.
- Keep a separate audit record for validation and consumption; never log admission numbers, raw PINs or proof tokens.
- If a secure proof lifecycle cannot be implemented and tested, leave consumption disabled rather than weakening the boundary.

## Data migration safety

- Use a transaction and advisory lock.
- Preserve each existing registry, PIN and batch record with exact school ownership and payload.
- Verify forward and reverse at record level, not by counts alone.
- Reject missing IDs, duplicate composite keys, missing school references and orphan PIN/batch records.
- Fresh installation with no `__master__` row is a no-op.
- Rollback is transactional and restores original arrays; it must not silently drop migrated rows.
- Never infer ownership from array position or untrusted client values.

## Required verification

- Full owner / school A / school B / multi-membership / zero-membership / anonymous matrix.
- Verify anon cannot SELECT `__master__`, registry, PIN or batch tables directly.
- Verify owner can manage all schools; school A cannot read or mutate school B.
- Verify RPC response shape and timing for every outcome, IP rate limits under concurrent calls, audit coverage and current-term PIN rules.
- Test forged, expired, replayed, wrong-school, wrong-PIN and concurrently submitted proofs; verify exactly one usage increment and stable retry behavior.
- Verify restore success, forced CAS failure, rollback and plaintext-password stripping.
- Run Supabase security and performance advisors after implementation.
- Add the exact independent-review 20-row matrix when recovered; do not reconstruct it from memory.

## Release order

Keep this PR draft until migration and app changes pass disposable-database tests, independent review and owner-approved production preflight. PR-D and PR-E must be reconciled against post-B.2 `main` before merge. Never apply the draft migration to production as part of implementation work.


## Source-code inventory (verified against post-B.1 `index.html`)

The application is a single 1 MB HTML file. A source scan found 119 lines containing `MASTER`, `__master__` or cloud-pull references. This is a broad refactor, not a safe one-line RLS change.

### Confirmed non-owner access paths to remove

- The regular non-owner `manualSync()` path explicitly calls `cloudPull('__master__')`.
- The common application boot path loads `__master__` with retries before it resolves the tenant code, then derives custom-domain school lookup and minimum app version from that payload.
- The non-owner online-reconnect handler flushes `__master__`.
- The non-owner result checker reads `MASTER.pins`, increments `pin.uses` in browser memory and calls `saveMaster()`. This is an insecure client-authoritative consumption path and must be replaced by the public validation/proof lifecycle above.
- The same global `MASTER` object feeds platform-owner screens and many tenant-facing flows. These uses must be separated into owner-only registry/platform state, school-scoped PIN/batch state and explicitly public metadata; simply hiding the owner navigation is not access control.

### Owner-only code surface

The owner dashboard and management modules read/write `MASTER.schools`, `MASTER.pins`, `MASTER.batches`, and `MASTER.platform`. The references span school CRUD, pharmacy, auto-parts, family and POS-agent management, billing-history fields (`sub`), PIN generation/reporting, platform settings and version floor. Preserve all supported tenant types and every legacy `sub` payload during registry migration; do not silently drop non-school business records.

### Restore findings

- The post-B.1 browser snapshot helpers return no rolling snapshots; `listBackups()` returns an empty array. Therefore the old `doRestore(code,idx)` UI path cannot provide a usable restore source in this release.
- The uploaded JSON restore handler currently replaces in-memory `STORE`/`BASE` and performs an unchecked direct `upsert`; it reports success without checking the Supabase error or verifying the resulting revision. This is the active restore defect to fix.
- The restore replacement must be implemented against the existing CAS helper and a recoverable pre-restore export/snapshot. Strip `users[].password` before committing imported data. Preserve the existing download-backup export. Do not treat an empty local snapshot list as a cloud backup.

### Implementation order

1. Add and test the dedicated registry/PIN/batch schema and transactional migration on a disposable database, including the already-applied PR-E RPC dependency.
2. Refactor owner boot and owner CRUD to use the new registry API, preserving all legacy fields and supported tenant types.
3. Change non-owner boot, manual sync and reconnect so they never request `__master__`; resolve custom domains via `resolve_school`, and obtain only billboard-safe version metadata from `platform_meta`.
4. Replace public result-checker client-side PIN reads/usage mutation with the reviewed validation and single-use proof lifecycle.
5. Repair uploaded JSON restore with password stripping, CAS, pre-restore recovery and verified success/error handling.
6. Run static checks and disposable-database integration tests before any preview or production operation.

No application code or production database schema was changed by this inventory update.
