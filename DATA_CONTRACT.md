# Data contract — employer panel & mobile (Firestore)

Ten dokument opisuje **ścieżki dokumentów** współdzielone przez aplikację mobilną Work Timer i panel pracodawcy (`work_timer_employer_panel`). Ma ułatwić onboarding, QA i portfolio — **nie zastępuje** `firestore.rules`.

## Kolekcje i dokumenty

### `employers/{employerUid}/trackedEmployees/{trackedId}`

- **Źródło prawdy:** tak — lista „kogo śledzi” dany pracodawca.
- **Zapisuje:** panel (dodanie / usunięcie wpisu, `groupIds`, ewentualne pola z linkowania).
- **Czyta:** panel.
- **Uwaga:** imię, nazwisko, `displayName`, `employeeUid` / email w streamie są **sczytywane z `userEmailIndex`** i mergowane w UI (`TrackedEmployee.mergedWithUserEmailIndex`) — dokument `trackedEmployees` może być **cache’em** danych osobowych względem indeksu.

### `employers/{employerUid}/trackedEmployeeUids/{employeeUid}`

- **Źródło prawdy:** tak — mapowanie „pracodawca ↔ pracownik” dla reguł dostępu (np. odczyt `users/{uid}/…`).
- **Zapisuje:** panel przy linkowaniu / usuwaniu (oraz `ensureTrackedEmployeeUidAccessDocs`).
- **Czyta:** reguły Firestore; panel pośrednio przez operacje na listach.

### `employers/{employerUid}/groups/{groupId}`

- **Źródło prawdy:** tak — grupy organizacyjne pracodawcy.
- **Zapisuje / czyta:** panel.

### `users/{employeeUid}/entries/{entryId}`

- **Źródło prawdy:** tak — wpisy czasu (mobile + ewentualnie zapis z panelu pracodawcy).
- **Czyta:** panel (raporty, dashboard, **timesheet** na karcie pracownika).
- **Zapisuje:** **mobile** (domyślnie) oraz **pracodawca** z panelu — **tylko** gdy istnieje `employers/{employerUid}/trackedEmployeeUids/{employeeUid}` (patrz `firestore.rules`). Dozwolone operacje: **create** / **update** (w tym **soft delete**: `isDeleted: true`, **restore**: `isDeleted: false`). **Hard delete** (`delete`) jest zabroniony w regułach.
- **Kwota w panelu:** szacunek `duration × workspace.hourlyRate × (billingRatePercent ?? 100) / 100` dla zamkniętych wpisów (szczegóły w `lib/core/utils/entry_amount_breakdown.dart` i `ReportCalculationService.estimatedAmountByCurrency`).
- **Pola audytu (opcjonalne):** `editedAt`, `editedBy`, `createdBy`, `createdVia` — ustawiane przy zapisie z panelu (`createdVia: employer_panel`), jeśli reguły i payload to przepuszczą.

### `users/{employeeUid}/workspaces/{workspaceId}`

- **Źródło prawdy:** tak — projekty / stawki / slug firmy (mobile + panel w zakresie MVP).
- **Czyta:** panel.
- **Zapisuje (MVP panelu):** tylko **`hourlyRate`**, **`currency`**, **`updatedAt`** (`updateWorkspaceBilling`). Reszta pól z perspektywy panelu jest read-only.

### `users/{employeeUid}/live/status`

- **Źródło prawdy:** tak — **bieżący** stan timera i obecności (mobile utrzymuje dokument).
- **Czyta:** panel (presence, szacunek „live running” w UI).
- **Zapisuje:** panel **nie**.
- **Live amount:** kwoty liczone **w pamięci UI** z `live/status` + map workspace’ów — **nie są** zapisywane do Firestore (patrz `TECHNICAL.md`).

### `userEmailIndex/{emailLower}`

- **Źródło prawdy:** tak dla mapowania **email → uid** i pól profilu używanych przy linkowaniu / wyświetlaniu.
- **Zapisuje:** **mobile** (po logowaniu / aktualizacji profilu — wymaganie operacyjne).
- **Czyta:** panel (`getUserEmailIndex`, stream `trackedEmployees`).
- **Kopia / cache:** pola osobowe na `trackedEmployees` mogą być nieaktualne względem indeksu — UI preferuje indeks po merge.

## Podsumowanie: kto jest „truth”

| Obszar | Truth | Panel |
|--------|--------|--------|
| Wpisy czasu | `users/.../entries` | read + **CRUD (create/update, soft delete)** dla śledzonych pracowników |
| Projekty / stawki | `users/.../workspaces` | read + MVP write billing |
| Live timer / presence | `users/.../live/status` | read only |
| Lista śledzonych | `employers/.../trackedEmployees` | read/write |
| Relacja employer–employeeUid | `employers/.../trackedEmployeeUids` | read/write |
| Grupy | `employers/.../groups` | read/write |
| Indeks email | `userEmailIndex` | read (write: mobile) |

## Spójność z mobile

Mobile musi utrzymywać: **`userEmailIndex`**, **`live/status`** przy pracy timerem, oraz wpisy w **`entries`** i **`workspaces`** zgodnie z tym samym modelem pól, którego używa panel (m.in. `companySlug`, `isDeleted`, `start` / `end`, `hourlyRate` / `currency`, `billingRatePercent`, pola audytu jeśli używane). Panel pracodawcy może **dopisywać i poprawiać** wpisy w `entries` u śledzonych pracowników — zgodnie z `firestore.rules`.
