# PR-D — Platform-wide modern UI and responsive QA

## Purpose
Deliver one modern, consistent and mobile-first application experience for every school tenant. The shared school shell and shared responsive rules apply to every tenant that enters `#app.school-shell`; school branding layers on top via per-school tokens, not per-school CSS forks.

## Status — delivered in this branch

### Slice 1 (commits `c1c6e90`, `438fcde`, `12aa096`)
- `responsive.css` created and wired via `<link>` in `index.html`.
- Mobile top bar, hamburger target, off-canvas sidebar + backdrop.
- Safe-area padding, constrained content widths, responsive KPI cards, table scroll containment.
- Tablet layout rules, 320/360/390/768/1024/1280 breakpoints structurally supported in CSS.

### Slice 2 (this commit, claude)
- **Fixed Blocker 1** from independent review: modal/toast rules were scoped under `#app.school-shell` but those elements live outside `#app`. Rules are now gated on `body.school-mode` and apply correctly.
- **Fixed Blocker 2** from independent review: `.topbar .right .btn` and `.menu-toggle` raised to 44px min-height on mobile (was 36px / 42px). WCAG 2.5.5 target size minimum met consistently.
- **Added `vh` fallbacks** above every `dvh` value for older iOS Safari and legacy Chromium on Android.
- **Per-school branding token system**:
  - CSS custom properties `--brand-primary`, `--brand-primary-dark`, `--brand-primary-tint`, `--brand-accent`, `--brand-ink`, `--brand-surface`, `--brand-font`, etc. declared on `#app.school-shell` with sensible defaults (current EduManager green).
  - `applySchoolBranding()` JS function in `index.html` reads `DB.settings.branding` on `enterApp()` and writes tokens as inline styles + sets `data-brand-font` attribute + sets `body.dark` / `body.light` from `branding.darkMode`. Includes `_shadeHex()` helper for auto-deriving dark/tint variants from a single primary colour.
  - Four font presets: `inter` (default), `serif` (Lora), `quranic` (Scheherazade), `rounded` (Nunito).
- **Dark mode**:
  - Opt-in via `body.dark`; auto when `prefers-color-scheme: dark` AND user has not set `body.light`.
  - Card / stat / modal / input / sidebar tokens all re-declared under dark mode.
  - Owner shell deliberately untouched.
- **Three report-card templates**: `.report.tpl-classic`, `.report.tpl-modern`, `.report.tpl-islamic`. Each uses the per-school brand tokens for colour, so one template serves every school. Classic uses Lora serif + double borders; Modern uses a green header band + gradient; Islamic uses Scheherazade + a basmala header + gold inner border. All three preserve the existing `.report` element so the old print layout stays selectable as the untouched default (no breaking change to BNFODIO's already-issued reports).
- `supabase/migrations/0004_school_assets.sql` — **Supabase Storage bucket migration** for `school-assets`. Idempotent. Any authenticated user can read (logos are not secret); only members with role `owner` or `admin` can write to their own school's folder (path convention `school-assets/{SCHOOL_CODE}/...`); platform owner can write any folder. Policies use `storage.foldername(name)[1]` to extract the school code from the path. Rollback block included.

### Slice 3 (this commit, claude)
- **Branding settings page** (`vBranding`) available to school admins and the owner via the sidebar entry `🎨 Branding`. Non-admins see a not-available message rather than the form.
- Form fields: primary colour picker, accent colour picker, font preset dropdown (Inter/Serif/Qur'anic/Rounded), dark-mode preference (Auto/Off/On), logo upload, crest upload, head-teacher signature upload.
- **Live preview**: colour/font/dark-mode changes re-apply tokens via `applySchoolBranding` on every input event, before saving. The `.brand-preview` CSS block from slice 2 renders the result above the form.
- **File validation**: max 2 MB per file; allowed MIME types PNG / JPG / WEBP / SVG (SVG only for logo + crest). Errors surface via `toast(err,true)` and are mirrored into a `#brandStatus` label.
- **Storage uploads**: logos + crests → `school-assets` (public) using `upsert:true`; signatures → `school-assets-private` (private) with `cacheControl:'0'`. Public URLs are captured via `getPublicUrl` and cache-busted with a `?v=<timestamp>` query so a re-upload is visible immediately. Signature path is stored as a bucket path, NOT a URL — code fetches a short-lived signed URL via `brandSignedSignatureUrl(path, ttl)` when a report card needs to render the signature.
- **Persistence**: on save, `DB.settings.branding` is updated and committed via the existing `cloudCommit(SCHOOL_CODE)` flow (preserves all unrelated settings). On reload, `enterApp` reads it back and `applySchoolBranding` reapplies before anything renders.
- **Access guard**: `_canEditBranding()` restricts the page to `USER.role === 'admin'` or `'owner'`. Combined with Storage RLS from `0004_school_assets.sql`, uploads from a teacher (or a school-A admin targeting a school-B folder) are denied server-side regardless of the client gate.
- **Migration revised in place**: `supabase/migrations/0004_school_assets.sql` now provisions two buckets — `school-assets` (public, for logos + crests) and `school-assets-private` (private, for signatures). Previous slice-2 version had a public-read policy on a private bucket, which did not match the `createSignedUrl`-free flow logos actually use. Both buckets' write policies still enforce path-matches-school and role ∈ {owner, admin}. Idempotent; rollback block updated to drop both buckets.

### Slice 4 (this commit, claude) — review fixes + results polish + KPI redesign

**Review fixes addressing GPT-6's eight findings on slice 3:**

1. `enterApp` logo-reset order fixed. `applySchoolBranding` now runs AFTER `#topLogo` is set to its default, so the saved uploaded logo wins on every login.
2. Bucket-level file-size and allowed-MIME enforcement added to `0004_school_assets.sql`:
   - `school-assets`: `file_size_limit = 2097152`, `allowed_mime_types = ['image/png','image/jpeg','image/webp','image/svg+xml']`.
   - `school-assets-private`: `file_size_limit = 2097152`, `allowed_mime_types = ['image/png','image/jpeg','image/webp']` — **SVG rejected server-side** for signatures.
3. Private-signature read tightened to administrators of the owning school (`role in ('owner','admin')`). Ordinary teachers no longer download signatures via the Storage API even though they are members of the school. Platform owner bypass retained.
4. Parent PIN report rendering of signatures is **explicitly deferred to a server-rendered flow** in a later PR. The migration's doc-comment and this QA doc both state that parents viewing a PIN result page do NOT receive a signature URL; the current schema prevents any anonymous-reachable signing path.
5. Client validation split per field: SVG allowed for logo + crest only, rejected for signature. `BRAND_IMG_TYPES_PUBLIC` vs `BRAND_IMG_TYPES_SIG` constants; signature `<input>` `accept` attribute tightened. Bucket-level MIME list is the authoritative gate; the client is defence in depth.
6. Orphan-asset handling: `brandSave` now uses **versioned paths** (`logo-<base36-timestamp>.png`, etc.) so a half-saved upload cannot overwrite the currently-referenced asset. On `cloudCommit` failure, `DB.settings.branding` is reverted in memory and a message tells the user the previous branding has been restored. The just-uploaded files become orphans in Storage; a best-effort cleanup also removes the previously-active files **only when** the new save succeeds.
7. Migration rollback block is now **preservation-first** with a two-stage procedure (Stage A strips policies but keeps every object; Stage B is destructive and explicitly requires product-owner approval). The default comment says re-running the migration is safe and is preferred to any rollback.
8. Automated tests added at `tests/branding.test.mjs` covering `_shadeHex`, `_brandPathFor`, and `_fileExt`. Run with `node tests/branding.test.mjs`. Tests passed locally in this slice.

**Slice 4 feature deliverables:**

- **Modern KPI card styling**: `.stat` elevation, hover, uppercase label, tabular-numeric number, optional `.stat-ic` icon slot. Uses the per-school brand tokens so each tenant's KPI numbers inherit its primary colour.
- **Results-entry sticky headers**: `.t-wrap table thead th { position: sticky; top: 0 }` scoped under `#app.school-shell`. Column headers remain visible when scrolling a long class roster.
- **Arrow-key navigation between score cells**: installed once globally via `window._scoreNavInstalled`. Handles `ArrowUp` / `ArrowDown` / `ArrowLeft` / `ArrowRight` / `Enter`. Left/Right do not hijack until the caret is at the edge of the input value (so normal typing still edits the value). Enter advances the same as Right. Existing `onchange` → `setScore` behaviour and `cloudCommit` save path are untouched.
- `.score-in` input restyled for consistent width, focus ring (accent colour), and 44px min-height on mobile.

### Not yet delivered (deferred to further slices)
- **Full dashboard content redesign** — this slice modernised the shared `.stat` card used across dashboards, but the specific arrangement of activity sections, charts, and attention lists in `vDashboard` / `vTdash` is unchanged. The new `.stat-ic` slot is available for the dashboard redesign to use without further CSS work.
- **Real screenshots** — not produced in this slice.
- **Role-based QA execution** — not executed in this slice.

### Automated vs manual check split (addresses finding 8)

**Automated (run on every PR update):**
- `node tests/branding.test.mjs` — pure-function helpers.
- `node -e "..."` JS parse check of the full `index.html` (as used in this commit).
- Local CSS parse via your editor/linter.

**Manual preview checks still required before merge:**

| Check | How to run |
|---|---|
| Logo persists after login | Sign in as admin of a school with a saved logo; confirm the top-bar logo is the uploaded image, not the graduation cap. |
| Bucket MIME enforcement | Attempt to upload a `.gif` to `school-assets` via DevTools console: `await supa.storage.from('school-assets').upload('BNFODIO/x.gif', new Blob(['x'], {type:'image/gif'}))`. Expect bucket-level rejection. |
| Bucket size enforcement | Attempt to upload a 3 MB PNG; expect bucket-level rejection. |
| SVG rejected on signature server-side | `await supa.storage.from('school-assets-private').upload('BNFODIO/s.svg', new Blob(['<svg/>'], {type:'image/svg+xml'}))`. Expect bucket-level rejection. |
| Teacher cannot read signature | Sign in as teacher. `await supa.storage.from('school-assets-private').createSignedUrl(path, 60)`. Expect error / null. |
| Cross-school upload denied | Admin of school A attempts upload to school B folder. Expect RLS denial. |
| cloudCommit failure recovery | Simulate failure (DevTools throttle offline, click Save). Expect "Save failed … previous branding restored." UI still shows the previous branding. |
| Arrow-key nav in results | Open Results for a class. Tab into CA1 of the first pupil. Press Right / Down repeatedly. Focus advances cell-by-cell without hijacking value edits. |
| Sticky header | Scroll down in a long class; column headers remain visible. |
| 320 / 390 / 768 / 1280 viewport | DevTools responsive mode. Branding page, Results page, Dashboard page each render without horizontal overflow. |
| Dark mode | Toggle `body.dark` or set branding → darkMode = 'on'. Modal, inputs, cards re-colour without lost contrast. |

Record each manual check with device/browser, date, and pass/fail evidence before marking the merge gate green.

## Required screen-size matrix
Test at each viewport width; use actual device emulation and at least one physical Android phone and one iPhone before release.

| Width | Target | Expected | CSS scope |
|---:|---|---|---|
| 320px | Small phone | No horizontal overflow; cards stack | `@media (max-width: 340px)` + base |
| 360px | Common Android | Drawer opens/closes; tables scroll inside `.t-wrap` | `@media (max-width: 760px)` |
| 390px | Large phone | Two-column KPI cards; readable headings; modal actions reachable | `@media (max-width: 390px)` |
| 768px | Tablet portrait | Tablet layout; no clipped sidebar/forms | `@media (min-width: 761px) and (max-width: 1100px)` |
| 1024px | Tablet landscape / small laptop | Two-column content where appropriate | Same tablet range |
| 1280px+ | Desktop | Full sidebar, spacious content | Unmedia'd base |

## Role and workflow coverage
For each workflow, use a dedicated test school and role-appropriate account. Do not use or mutate a live school's records for visual QA unless the product owner has explicitly approved the test record.

- School administrator: dashboard, students, admissions, classes, staff, settings, school branding.
- Teacher: assigned classes, attendance, results entry, lessons, Hifz/Tahfiz where enabled.
- Bursar: fees, payment entry, approvals, receipts, finance reports.
- Parent: parent dashboard, pupil details, results, fees.
- Owner: platform dashboard and tenant management are regression-tested separately; `#app.school-shell` CSS must not alter the owner layout.

## Workflow acceptance checks
- Dashboard KPI cards wrap without clipping.
- Attendance roster and results grids remain usable; wide tables scroll within `.t-wrap`, not across the whole page.
- Student and staff forms stack into one column on narrow screens; labels and validation messages remain visible.
- Fees, payment approvals and receipt actions remain reachable without horizontal page scrolling.
- Hifz/Tahfiz progress and evaluation controls remain legible and usable.
- Report cards preserve their print layout while remaining readable in the on-screen preview; `.tpl-classic`, `.tpl-modern`, `.tpl-islamic` all render.
- Mobile navigation can be opened/dismissed via menu button, backdrop, and normal navigation.
- Dialogs fit within the viewport, scroll inside themselves, and keep footer actions reachable.
- School logos, crests, mottos and configured colours do not break contrast or cause overflow.
- Keyboard focus is visible; touch controls are at least 44px where practical; reduced-motion preference is respected.
- Dark mode flips card/input/modal backgrounds without losing readable contrast; `prefers-color-scheme: dark` is auto-applied unless `body.light` is set.

## Evidence required before merge
Attach screenshots at 390px, 768px and 1280px for:

1. Dashboard
2. Attendance
3. Results entry
4. Fees / payment workflow
5. Report-card preview (one per template: Classic, Modern, Islamic)

Also attach the completed viewport/role checklist, identify browser/device versions, and record any known exceptions.

## QA execution status — HONEST
- **Automated syntax checks**: CSS parses locally without errors.
- **Device QA**: NOT YET EXECUTED. No real device testing has been performed by the agent on this branch.
- **Role QA**: NOT YET EXECUTED. No role-specific sessions have been captured.
- **Screenshots**: NOT YET PRODUCED. No screenshots exist in this PR.
- **Live preview**: NOT YET BUILT. The product owner / GPT-6 will need to deploy this branch to a Netlify preview and run the matrix above against it, or a subsequent commit must capture screenshots.

Do not mark any row in the matrix "pass" until it has actually been executed. The code changes in this slice are structural and should pass most checks, but cannot be claimed as verified without the preview tests.

## Dependencies and release gates
- This branch is based on PR-B.1's branch head so the Phase 1 changes are included. Reconcile onto the post-B.1 `main`, and then the post-B.2 baseline, before merge.
- Do not merge PR-D before PR-B.2 is live.
- `supabase/migrations/0004_school_assets.sql` is additive and can be applied before or after PR-B.2, but the production-owner must apply it in the Supabase SQL editor manually before any school attempts to upload branding assets. No application code depends on the bucket existing until the branding settings UI lands.
- No SQL, production data, secrets or Supabase/Netlify settings are changed by application code in this branch. Storage bucket creation is manual SQL with rollback.

## Known limitations recorded
- `storage.foldername(name)[1]` relies on path segments; uploads that do not follow the `{SCHOOL_CODE}/...` convention will be denied. Clients MUST upload to `{SCHOOL_CODE}/logo.*` etc.
- Colour-token derivation via `_shadeHex` is a mathematical lighten/darken, not a design-system match. A very dark primary may produce a near-black `--brand-primary-dark`; UI should fall back to the default accent for disabled/hover states on such schools.
- Dark-mode rules currently cover card/input/modal/sidebar surfaces; some per-module custom backgrounds (Qur'an level cards, incident colour badges) will need follow-up when they are redesigned.
- The three report-card templates share typography families with system fallbacks; schools that want bespoke fonts should host their own files and point the `--brand-font` CSS variable manually (not yet exposed in the UI).
