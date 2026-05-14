# Work Timer Employer Panel — Flutter Web dashboard

## Short description

**Work Timer Employer Panel** is a **Flutter Web** admin dashboard for employers and team leads. It connects to the same Firebase project as the **Work Timer** mobile app used by employees. The panel is for **reviewing time, presence, shared workspaces, team groups, and billing estimates** — it is **not** a legal payroll or HR compliance system; amounts and hours are **indicative** based on stored rates and entries.

## Problem / why this exists

- Employers need visibility **only into workspaces the employee has explicitly shared**, not the whole account.
- Time and project data **live under the employee’s** Firestore user subtree; the panel **reads (and selectively writes)** within a narrow, rule-enforced scope.
- The dashboard replaces **manual spreadsheets** for “who is working now”, monthly hours, rough costs, and team organization — without claiming to be accounting-grade payroll.

## Key features

- **Firebase Auth** — email/password sign-in for the employer account.
- **Employee lookup by work email** — add a tracked employee using the same work email the employee configured on shared workspaces in mobile.
- **Domain matching** — the employer’s Firebase Auth email domain must match the employee’s `employeeWorkEmailDomain` on qualifying workspaces (company boundary).
- **`trackedWorkspaces` as the real access scope** — every query and write path for entries and billing is gated on employer documents `employers/{employerUid}/trackedWorkspaces/{employeeUid_workspaceId}`.
- **Dashboard** — tracked headcount, groups summary, “Working now”, **Estimated amount (month)** from **closed** entries, **Live running (est.)** from live status + rates (UI-only), shortcuts into employees and reports.
- **Live status** — **Working / Paused / Online / Offline** (and safe fallbacks) from `users/{uid}/live/status`.
- **Live running estimate** — in-memory only; hidden when the timer’s `activeWorkspaceId` is not in the employer’s tracked workspace set.
- **Employee list** — names (from optional `userEmailIndex`), presence, monthly hints, navigation to detail.
- **Employee detail** — shared workspaces, billing edit (rate/currency), monthly timesheet, project report link.
- **Timesheet** — month navigator, filters, sort, summary, **CRUD on entries** where rules allow.
- **Soft delete / restore** — entries use `isDeleted`; no hard delete from the panel.
- **Estimated amount** — duration × rate × billing percent (see technical docs).
- **Workspace billing edit** — MVP write: `hourlyRate` / `currency` on `users/{uid}/workspaces/{id}` only if tracked.
- **Groups** — many-to-many membership via `groupIds` on `trackedEmployees`; **organizer only**, not a permission system.
- **Ungrouped** — employees with tracked access but no valid group assignment in the Groups UI.
- **Group filter on Employees** — UI-only filter (All / Ungrouped / specific group).
- **Reports** — **project report** (per workspace, CSV) and **monthly “payroll” style report** (`PayrollScreen`, filters + CSV); naming is UI convenience, not legal payroll.
- **Firestore rules** — employer reads/writes scoped to tracked paths; see `firestore.rules`.
- **Composite indexes** — monthly entry queries use `workspaceId` + `start` with `whereIn` (chunked); Firebase may require a composite index (console link on `failed-precondition`).

## How it works with the mobile app

1. The **mobile app** maintains **`employeeWorkEmailIndex/{workEmailLower}`** (uid, domain, `workspaceIds[]`) when the employee sets a work email on workspaces shared with the employer.
2. The **employer** enters the employee’s **full work email** in “Add employee”.
3. The panel checks that the **employer account email domain** matches **`employeeWorkEmailDomain`** on each candidate workspace (and shared flags).
4. On success, the panel writes **`trackedEmployeeUids`**, **`trackedEmployees`**, and one **`trackedWorkspaces`** document per allowed `(employeeUid, workspaceId)` pair (`accessId = employeeUid_workspaceId`).
5. All **entries**, **workspaces** (listing/billing), and **live status** reads in the panel are constrained to that **tracked** scope by **Firestore rules** and client queries (`whereIn` on allowed `workspaceId`s).

## Access model (mental model)

| Concept | Role |
|--------|------|
| **`trackedEmployeeUids/{employeeUid}`** | “I know this employee” — index for listing and **live/status** access; **not** the scope for time entries by itself. |
| **`trackedWorkspaces/{employeeUid_workspaceId}`** | **Real permission scope** — if it’s not here, the employer doesn’t see that workspace’s entries or billing in the panel. |
| **`groups`** + **`trackedEmployees.groupIds`** | **Organizer UI only** — filters and sections; **no** effect on Firestore read rules for entries. |
| **`users/.../entries`** | Visible **only** when `workspaceId` matches a tracked workspace row for that employee under this employer. |

## Tech stack

| Layer | Choice |
|--------|--------|
| UI | **Flutter Web**, **Material 3** |
| Routing | **go_router** (`ShellRoute`, auth redirect) |
| State (MVP) | **StreamBuilder** / **FutureBuilder** + service layer |
| Backend | **Firebase Auth**, **Cloud Firestore** |
| Theme | **provider** (`ThemeController`) + **shared_preferences** |
| Indexes | Firestore **composite** indexes for `entries` queries (see **TECHNICAL.md**) |
| Quality | **flutter analyze**, **flutter test** |

## Project status

- **MVP / beta-quality** — suitable for internal dogfooding and staged rollout, not a finished enterprise product.
- **Local development** — `flutter run -d chrome` against a real Firebase project with rules deployed.
- **Deploy** — static **`flutter build web`** output can be hosted on **Firebase Hosting** (or any static host); configure `firebase_options.dart` via FlutterFire.
- **Not legal payroll** — do not use output as sole basis for statutory payroll without your own compliance review.

## Roadmap / possible next steps

- **Firebase Hosting** — CI/CD, preview channels, environment-specific Firebase options.
- **Remove hardcoded debug trace** from `lib/main.dart` (`EmployerEntriesDebugConfig`) before any public or production-facing branch — use local-only toggles or `--dart-define` instead.
- **Invite / approval flow** — employee-initiated consent instead of only employer-side add-by-email.
- **Stronger organization model** — companies, seats, SSO (future).
- **Audit trail** — richer history for employer-edited entries (beyond current optional fields).
- **Export templates** — scheduled exports, PDF layouts.
- **Roles** — owner / manager / viewer with rule-level enforcement.
- **Production monitoring** — Crashlytics / Analytics / structured logging.
- **Cloud Functions** — server-side validation, email lookup hardening, aggregation at scale.
- **Reporting** — accruals, PTO, multi-currency policies (product decision).

## Screenshots

Screenshots will be added here.

Suggested paths (add files when ready):

- `docs/screenshots/dashboard.png`
- `docs/screenshots/employees.png`
- `docs/screenshots/employee-detail.png`
- `docs/screenshots/timesheet.png`
- `docs/screenshots/groups.png`

---

**Further reading:** **[TECHNICAL.md](TECHNICAL.md)** (implementation detail), **[DATA_CONTRACT.md](DATA_CONTRACT.md)** (paths & truth tables), **[QA_CHECKLIST.md](QA_CHECKLIST.md)** (manual regression list).
