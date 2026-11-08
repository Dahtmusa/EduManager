# PR-D — Platform-wide modern UI and responsive QA

## Purpose
Deliver one modern, consistent and mobile-first application experience for every school tenant. This is not a marketing-page-only redesign. The shared school shell and shared responsive rules apply to every tenant that enters `#app.school-shell`; school branding is applied through shared tokens rather than school-specific forks.

## Implemented in this first PR-D slice
- Added `responsive.css`, loaded after the existing application styles.
- Scoped the new rules to `#app.school-shell` so platform-owner and non-school tenant shells are not unintentionally changed.
- Improved the mobile top bar and hamburger target, off-canvas school navigation and backdrop.
- Added safe-area padding, constrained content widths, responsive KPI cards and form grids, and contained table scrolling.
- Improved modal sizing on phones, report-card metadata grids, action-button touch targets, focus visibility and reduced-motion behaviour.
- Added tablet-specific layout adjustments and print rules.

## Required screen-size matrix
Test at each viewport width; use actual device emulation and at least one physical Android phone and one iPhone before release.

| Width | Target | Expected |
|---:|---|---|
| 320px | Small phone | No page-level horizontal overflow; cards stack; topbar actions remain usable |
| 360px | Common Android | Drawer opens/closes; controls remain tappable; tables scroll inside their own container |
| 390px | Large phone | Two-column KPI cards; readable page headings; modal actions accessible |
| 768px | Tablet portrait | Tablet layout; no clipped sidebar or form fields |
| 1024px | Tablet landscape/small laptop | Two-column content where appropriate; navigation and cards remain balanced |
| 1280px+ | Desktop | Full sidebar and spacious content layout |

## Role and workflow coverage
For each workflow, use a dedicated test school and role-appropriate account. Do not use or mutate a live school's records for visual QA unless the product owner has explicitly approved the test record.

- School administrator: dashboard, students, admissions, classes, staff, settings and school branding.
- Teacher: assigned classes, attendance, results entry, lessons and Hifz/Tahfiz where enabled.
- Bursar: fees, payment entry, approvals, receipts and finance reports.
- Parent: parent dashboard, pupil details, results and fee information available to that account.
- Owner: platform dashboard and tenant management are regression-tested separately; school-shell CSS must not alter owner layout.

## Workflow acceptance checks
- Dashboard KPI cards wrap without clipping.
- Attendance roster and results grids remain usable; wide tables scroll within `.t-wrap`, not across the whole page.
- Student and staff forms stack into one column on narrow screens; labels and validation messages remain visible.
- Fees, payment approvals and receipt actions remain reachable without horizontal page scrolling.
- Hifz/Tahfiz progress and evaluation controls remain legible and usable.
- Report cards preserve their print layout while remaining readable in the on-screen preview.
- Mobile navigation can be opened and dismissed using the menu button, backdrop and normal navigation.
- Dialogs fit within the viewport, allow scrolling and keep footer actions reachable.
- School logos, crests, mottos and configured colours do not break contrast or cause overflow.
- Keyboard focus is visible; touch controls are at least 44px where practical; reduced-motion preference is respected.

## Evidence required before merge
Attach screenshots at 390px, 768px and 1280px for:
1. Dashboard
2. Attendance
3. Results entry
4. Fees/payment workflow
5. Report-card preview

Also attach the completed viewport/role checklist, identify browser/device versions, and record any known exceptions. Automated syntax checks are not a substitute for visual/device verification.

## Dependencies and release gates
- This branch is based on PR-B.1's branch head so the Phase 1 changes are included. Reconcile onto the post-B.1 `main` and then post-B.2 baseline before merge.
- Do not merge PR-D before PR-B.2 is live. This PR must be reviewed against the tenant-isolation and Auth changes.
- This first slice establishes the shared responsive shell. Dashboard content redesign, branding controls, dark mode, results-entry polish and the three report-card templates remain part of the full PR-D scope and must be completed before PR-D is marked ready.
- No SQL, production data, secrets or Supabase/Netlify settings are changed by this responsive CSS slice.
