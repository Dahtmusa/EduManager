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

### Not yet delivered (deferred to further slices)
- **Dashboard content redesign** — only sizing/responsiveness is in; the KPI card shape and activity-section hierarchy are unchanged. Still needs explicit visual work.
- **Results-entry UX polish** — keystroke-write already landed in Phase 0; sticky table headers and arrow-key cell navigation are still to do (CSS exists for mobile but JS wiring is outstanding).
- **Branding settings page UI** — the token system and storage bucket are ready, but the owner-side / admin-side form that lets a user upload a logo and pick a colour is not yet in this branch. CSS scaffolding for a `.brand-preview` block is included so that page has a styled home when it lands.
- **Real screenshots** — see "Screenshots and evidence" below. This slice has not produced any.
- **Role-based QA execution** — see "QA execution status" below. This slice has not executed the matrix against a running preview.

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
