# PR-B.2 — Tenant isolation, owner registry and verified restore

> Draft engineering scope. This document is not authorization to apply a migration to production.

## Preconditions and current state

- PR-B.1 merged to `main` at `67e5c890ebf6345e009d66de4baa0a150b326306`.
- This branch starts from post-B.1 `main`.
- PR-E's `0003_create_school.sql` has already been applied to the connected Supabase project, although PR-E remains unmerged. Its `create_school` implementation currently writes `__master__.schools[]`; this PR must reconcile that RPC with the new registry without a dual-write.
- Read-only aggregate preflight found 7 registry entries, 4 PINs and 3 batches. It found zero missing school codes/names, zero missing PIN school/code fields, zero missing batch school/ID fields and zero orphan PINs/batches. No student or tenant row contents were read.

## Security objectives

1. Make `__master__` readable only by the exact platform-owner app role. Non-owner clients must never query it.
2. Move the platform school registry into a dedicated owner-only `school_registry` table; preserve all registry metadata, including legacy subscription payloads until PR-F migrates them.
3. Move PINs and batches into `school_pins` and `school_batches`, keyed by `school_id`; RLS must prevent cross-school reads and writes.
4. Add `school_domains` and an anonymous `resolve_school(domain)` RPC with a stable null-on-miss response, fixed delay and concurrency-safe per-IP rate limit.
5. Add anonymous read-only `is_valid_pin(code, school)` with one identical JSON shape for all outcomes, current-session/current-term checks, fixed delay and independent per-IP rate limit.
6. Add authenticated `consume_pin(code, school)` with membership/entitlement checks and one audit event per call. Resolve the legacy anonymous result-checker flow before enabling consumption.
7. Add public billboard-safe `platform_meta(name,minVersion)` only; no other platform metadata is public.
8. Rewrite `doRestore` to use the database-first CAS commit helper, retain a recoverable snapshot, strip legacy plaintext passwords from imported data and only show success after revision verification.

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
- Verify restore success, forced CAS failure, rollback and plaintext-password stripping.
- Run Supabase security and performance advisors after implementation.
- Add the exact independent-review 20-row matrix when recovered; do not reconstruct it from memory.

## Design blocker — public result checker

The current result-checker screen uses admission number + PIN without Supabase Auth. `consume_pin` is explicitly authenticated and must not be weakened to anonymous. Resolve the product flow before wiring usage consumption: authenticated parent/pupil session or a separately reviewed server-side entitlement flow.

## Release order

Keep this PR draft until migration and app changes pass disposable-database tests, independent review and owner-approved production preflight. PR-D and PR-E must be reconciled against post-B.2 `main` before merge. Never apply the draft migration to production as part of implementation work.
