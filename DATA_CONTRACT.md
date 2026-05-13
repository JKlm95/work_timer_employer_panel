# Data contract — employer panel & mobile (Firestore)

Ten dokument opisuje **ścieżki dokumentów** współdzielone przez aplikację mobilną Work Timer i panel pracodawcy (`work_timer_employer_panel`). Ma ułatwić onboarding, QA i portfolio — **nie zastępuje** `firestore.rules`.

## Kolekcje i dokumenty

### `employers/{employerUid}/trackedEmployees/{trackedId}`

- **Źródło prawdy:** tak — lista „kogo śledzi” dany pracodawca.
- **Zapisuje:** panel (dodanie / usunięcie wpisu, `groupIds`, ewentualne pola z linkowania).
- **Czyta:** panel.
- **Uwaga:** imię, nazwisko, `displayName`, `employeeUid` / email w streamie są **sczytywane z `userEmailIndex`** i mergowane w UI (`TrackedEmployee.mergedWithUserEmailIndex`) — dokument `trackedEmployees` może być **cache’em** danych osobowych względem indeksu.

### `employers/{employerUid}/trackedEmployeeUids/{employeeUid}`

- **Źródło prawdy:** tak — **indeks** „pracodawca zna tego pracownika (UID)” — używany m.in. do odczytu **`users/{uid}/live/status`** i **bootstrapu** odczytu listy workspace’ów przy linkowaniu / rebuildzie.
- **Zapisuje:** panel przy linkowaniu / usuwaniu (oraz `ensureTrackedEmployeeUidAccessDocs`).
- **Czyta:** reguły Firestore; panel pośrednio przez operacje na listach.
- **Ważne:** to **nie** definiuje już zakresu wpisów czasu ani projektów widocznych w panelu — za to odpowiada **`trackedWorkspaces`** (poniżej).

### `employers/{employerUid}/trackedWorkspaces/{accessId}`

- **ID dokumentu:** `accessId = "${employeeUid}_${workspaceId}"` (np. `abc123_ws1`).
- **Źródło prawdy:** tak — **rzeczywisty zakres danych** widocznych w panelu dla danego workspace’u pracownika (wpisy, timesheet, dashboard, billing, raporty).
- **Pola (MVP panelu):** `employeeUid`, `workspaceId`, `employeeEmailLower`, `companyName`, `companySlug`, `workspaceName`, `createdAt`, `updatedAt` (timestamps serwera przy zapisie).
- **Zapisuje:** panel przy **linkowaniu** pracownika (wszystkie kwalifikujące się workspace’y dla wybranej firmy), przy **usunięciu** wpisu z listy (przeliczenie / skasowanie dostępu), oraz jawnie przez **`rebuildTrackedWorkspaceAccess`** (Ustawienia → *Rebuild workspace access*).
- **Czyta:** panel (`fetchTrackedWorkspaces`, stream); reguły Firestore do odczytu `entries` / `workspaces` pracownika w kontekście pracodawcy.
- **Kwalifikacja workspace’u:** m.in. `isSharedWithEmployer == true`, zgodność slug/domeny z kontekstem linku, opcjonalnie lista `linkedEmployerEmails` na dokumencie workspace (logika w `lib/core/utils/tracked_workspace_policy.dart`).

### `employers/{employerUid}/groups/{groupId}`

- **Źródło prawdy:** tak — grupy organizacyjne pracodawcy.
- **Zapisuje / czyta:** panel.

### `users/{employeeUid}/entries/{entryId}`

- **Źródło prawdy:** tak — wpisy czasu (mobile + ewentualnie zapis z panelu pracodawcy).
- **Czyta:** panel (raporty, dashboard, **timesheet** na karcie pracownika).
- **Zapisuje:** **mobile** (domyślnie) oraz **pracodawca** z panelu — **tylko** gdy istnieje dokument **`employers/{employerUid}/trackedWorkspaces/{employeeUid_workspaceId}`** dla `workspaceId` wpisu (patrz `firestore.rules`). Dozwolone operacje: **create** / **update** (w tym **soft delete**: `isDeleted: true`, **restore**: `isDeleted: false`). **Hard delete** (`delete`) jest zabroniony w regułach.
- **Kwota w panelu:** szacunek `duration × workspace.hourlyRate × (billingRatePercent ?? 100) / 100` dla zamkniętych wpisów (szczegóły w `lib/core/utils/entry_amount_breakdown.dart` i `ReportCalculationService.estimatedAmountByCurrency`).
- **Pola audytu (opcjonalne):** `editedAt`, `editedBy`, `createdBy`, `createdVia` — ustawiane przy zapisie z panelu (`createdVia: employer_panel`), jeśli reguły i payload to przepuszczą.

### `users/{employeeUid}/workspaces/{workspaceId}`

- **Źródło prawdy:** tak — projekty / stawki / slug firmy (mobile + panel w zakresie MVP).
- **Czyta:** panel — w UI pracodawcy lista projektów budowana z **`trackedWorkspaces`** (`fetchEmployeeWorkspacesForEmployer`). Reguły Firestore mogą dodatkowo dopuścić odczyt workspace’u przy `trackedEmployeeUids` + `isSharedWithEmployer` (bootstrap / legacy) — patrz `firestore.rules`.
- **Zapisuje (MVP panelu):** tylko **`hourlyRate`**, **`currency`**, **`updatedAt`** (`updateWorkspaceBilling`) — wyłącznie gdy workspace jest w **`trackedWorkspaces`**. Reszta pól z perspektywy panelu jest read-only.

### `users/{employeeUid}/live/status`

- **Źródło prawdy:** tak — **bieżący** stan timera i obecności (mobile utrzymuje dokument).
- **Czyta:** panel (presence, szacunek „live running” w UI).
- **Zapisuje:** panel **nie**.
- **Live amount:** kwoty liczone **w pamięci UI** z `live/status` + map workspace’ów — **nie są** zapisywane do Firestore (patrz `TECHNICAL.md`). Dla pracodawcy kwota „live running” jest liczona **tylko** gdy `activeWorkspaceId` jest na liście workspace’ów z `trackedWorkspaces` (zgodnie z mapą użytą na dashboardzie).

### `userEmailIndex/{emailLower}`

- **Źródło prawdy:** tak dla mapowania **email → uid** i pól profilu używanych przy linkowaniu / wyświetlaniu.
- **Zapisuje:** **mobile** (po logowaniu / aktualizacji profilu — wymaganie operacyjne).
- **Czyta:** panel (`getUserEmailIndex`, stream `trackedEmployees`).
- **Kopia / cache:** pola osobowe na `trackedEmployees` mogą być nieaktualne względem indeksu — UI preferuje indeks po merge.

## Podsumowanie: kto jest „truth”

| Obszar | Truth | Panel |
|--------|--------|--------|
| Wpisy czasu | `users/.../entries` | read + **CRUD** tylko dla workspace’ów w `trackedWorkspaces`; zapytania miesięczne przez `workspaceId` (chunk `whereIn` ≤ 10) |
| Projekty / stawki | `users/.../workspaces` | read (wg reguł) + MVP write billing **tylko** dla workspace’ów w `trackedWorkspaces` |
| Live timer / presence | `users/.../live/status` | read only (nadal przez `trackedEmployeeUids`) |
| Lista śledzonych | `employers/.../trackedEmployees` | read/write |
| Indeks UID pracownika (employer) | `employers/.../trackedEmployeeUids` | read/write — **indeks relacji**, nie filtr wpisów |
| **Zakres workspace’ów (employer)** | `employers/.../trackedWorkspaces` | read/write — **źródło prawdy dla widocznych danych** |
| Grupy | `employers/.../groups` | read/write |
| Indeks email | `userEmailIndex` | read (write: mobile) |

## Spójność z mobile

Mobile musi utrzymywać: **`userEmailIndex`**, **`live/status`** przy pracy timerem, oraz wpisy w **`entries`** i **`workspaces`** zgodnie z tym samym modelem pól, którego używa panel (m.in. `companySlug`, `isDeleted`, `start` / `end`, `hourlyRate` / `currency`, `billingRatePercent`, pola audytu jeśli używane). Dla udostępniania workspace’u pracodawcy: **`isSharedWithEmployer`** oraz opcjonalnie **`linkedEmployerEmails`** (lowercase). Panel pracodawcy może **dopisywać i poprawiać** wpisy w `entries` u śledzonych pracowników — **wyłącznie** w workspace’ach obecnych w `trackedWorkspaces` — zgodnie z `firestore.rules`.
