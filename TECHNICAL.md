# Work Timer Employer Panel — dokumentacja techniczna (implementacja)

Ten dokument opisuje **aktualny stan kodu** panelu pracodawcy: architekturę, routing, warstwę serwisów, modele, ścieżki Firestore, strategię zapytań, reguły bezpieczeństwa i narzędzia debug. Jest uzupełnieniem **[README.md](README.md)** (produkt) oraz **[DATA_CONTRACT.md](DATA_CONTRACT.md)** (kontrakt ścieżek i „truth”).

---

## 1. Architektura katalogów (`lib/`)

```
lib/
  main.dart                 # Firebase.initializeApp, ThemeController, FirestoreService, GoRouter (opcjonalnie: EmployerEntriesDebugConfig — patrz §16)
  app.dart                  # MaterialApp.router, motywy M3 z ThemeController
  firebase_options.dart     # FlutterFire (placeholdery do podmiany)
  core/
    debug/                  # EmployerEntriesDebugConfig, LiveStatusDebugConfig
    theme/                  # app_theme.dart, theme_controller.dart
    utils/                  # domeny emaili, okresy raportów, presence, live amounts, lookup workspace (klucz złożony), chunkowanie whereIn, polityka tracked workspace, eksport web
    export/                 # warunkowy import pobierania plików (Web)
    widgets/                # empty state, loading, avatar, toolbary, badge statusu
  models/                   # encje DTO Firestore (patrz §5)
  services/
    firebase_auth_service.dart
    firestore_service.dart  # centralny dostęp Firestore (§4)
    report_calculation_service.dart
    export_service.dart
  features/
    auth/                   # logowanie
    shell/                  # MainShell — rail / drawer + child
    dashboard/
    employees/              # lista, szczegół, timesheet (widgety), add employee
    groups/
    reports/                # project_report_screen, payroll_screen
    settings/
  router/
    app_router.dart         # GoRouter + ShellRoute + redirect (§2)
    go_router_refresh.dart  # odświeżanie routera na authStateChanges
```

**Wzorzec UI (MVP):** ekrany budowane z **`StreamBuilder`** / **`FutureBuilder`** i cienką warstwą serwisów; brak globalnego state managera biznesowego (poza `ThemeController`).

---

## 2. Routing (`lib/router/app_router.dart`)

- **`GoRouterRefreshStream`** — nasłuchuje `FirebaseAuth.instance.authStateChanges()` i wymusza re-evaluację `redirect` po zalogowaniu / wylogowaniu.
- **`redirect`:** brak sesji i ścieżka ≠ `/login` → `/login`; zalogowany i `/login` → `/dashboard`.
- **`initialLocation`:** `/dashboard`.
- **`ShellRoute`** — wspólna obudowa (`MainShell`) dla tras aplikacji.
- **Trasy (path → ekran):**
  - `/login` → `LoginScreen`
  - `/dashboard` → `DashboardScreen(firestore)`
  - `/employees` → `EmployeesScreen`
  - `/employees/detail/:trackedId` → `EmployeeDetailScreen(trackedId)`
  - `/employees/detail/:trackedId/workspace/:workspaceId/report` → `ProjectReportScreen`
  - `/groups` → `GroupsScreen`
  - `/payroll` → `PayrollScreen`
  - `/settings` → `SettingsScreen`

Identyfikator w `detail/:trackedId` to **id dokumentu** `employers/.../trackedEmployees/{trackedId}`, nie zawsze równy `employeeUid`.

---

## 3. Przepływ autentykacji

1. **`Firebase.initializeApp`** + opcje z `firebase_options.dart`.
2. Użytkownik na **`LoginScreen`** — email/hasło przez Firebase Auth (implementacja w `FirebaseAuthService` / bezpośrednio w UI wg ekranu).
3. Po zalogowaniu `GoRouter` przekierowuje na **`/dashboard`**.
4. Wylogowanie ze **`SettingsScreen`** — `signOut`, router wraca na `/login`.
5. Odczyty Firestore zakładają **`request.auth.uid` pracodawcy** zgodnie z **`firestore.rules`** (właściciel dokumentów `employers/{employerUid}/...`).

---

## 4. Warstwa serwisów / `FirestoreService`

Plik: **`lib/services/firestore_service.dart`**.

**Odpowiedzialności (skrót):**

- **Śledzenie:** `trackedEmployeesStream`, `trackedEmployeeUids`, `fetchTrackedWorkspaces` / `trackedWorkspaceAccessStream`, `trackedWorkspaceIdsForEmployee`.
- **Linkowanie pracownika:** odczyt `employeeWorkEmailIndex`, walidacja domeny, filtrowanie workspace’ów (`tracked_workspace_policy`), zapis `trackedEmployees`, `trackedEmployeeUids`, `trackedWorkspaces` (`accessId = employeeUid_workspaceId`).
- **Workspace’y pracownika dla panelu:** `fetchEmployeeWorkspacesForEmployer` (wg `trackedWorkspaces`).
- **Wpisy:** `fetchEntriesInRangeForEmployer`, `employeeEntriesForMonthStream` (składanie wielu zapytań `whereIn` + zakres `start`), CRUD wpisów z walidacją dostępu do `workspaceId`.
- **Billing:** `updateWorkspaceBilling` — tylko dla workspace’u obecnego w `trackedWorkspaces`.
- **Live:** subskrypcja `users/{uid}/live/status` (wg reguł — typowo po `trackedEmployeeUids`).
- **Ostatnia aktywność:** `fetchLastActivityAtForEmployer` — per `workspaceId` z `trackedWorkspaces`, zapytania z `orderBy('updatedAt')` i fallbackiem (§9, indeksy).
- **Grupy:** CRUD grup, członkostwo (`applyTrackedEmployeesMembershipInGroup`, `deleteGroup` + czyszczenie martwych `groupIds`).
- **Rebuild:** `rebuildTrackedWorkspaceAccess` (Ustawienia) — odbudowa `trackedWorkspaces` z aktualnych workspace’ów i pól na `trackedEmployees`.

**Powiązane:** `ReportCalculationService` — godziny i szacowane kwoty z list wpisów + mapy workspace’ów; `ExportService` — CSV na Web.

---

## 5. Modele danych (DTO / domena)

| Model | Plik | Rola |
|--------|------|------|
| **TrackedEmployee** | `tracked_employee.dart` | Wiersz `employers/.../trackedEmployees` — `employeeUid`, emaile (work + legacy), firma, `groupIds`, merge z `UserEmailIndex` w UI. |
| **TrackedWorkspaceAccess** | `tracked_workspace_access.dart` | Wiersz `trackedWorkspaces` — `employeeUid`, `workspaceId`, metadane wyświetlania; **`docIdFor` = `employeeUid_workspaceId`**. |
| **EmployeeLiveStatus** | `employee_live_status.dart` | Dokument `users/.../live/status` — timer, online, opcjonalnie pola pod live amount. |
| **WorkEntry** | `work_entry.dart` | `users/.../entries` — `start`, `end`, `workspaceId`, `isDeleted`, typ, billable, %, audyt. |
| **Workspace** | `workspace.dart` | `users/.../workspaces` — stawka, waluta, flagi udostępnienia, work email / domena. |
| **EmployerGroup** | `employer_group.dart` | `employers/.../groups` — nazwa, timestamps (opcjonalnie legacy `colorHex`). |
| **EmployeeWorkEmailIndex** | `employee_work_email_index.dart` | Odczyt indeksu `employeeWorkEmailIndex/{workEmailLower}`. |
| **UserEmailIndex** | `user_email_index.dart` | Profil / imię dla listy — opcjonalnie. |

**Lookup workspace w UI:** `buildWorkspaceLookupByScopedKey(employeeUid, workspaces)` → mapa po kluczu **`employerWorkspaceLookupKey(employeeUid, workspaceId)`** (nie samo `workspaceId`), bo ten sam literal `workspaceId` może istnieć u różnych pracowników — patrz §8.

---

## 6. Kolekcje Firestore (ścieżki)

| Ścieżka | Zapis | Odczyt (panel) |
|---------|--------|----------------|
| **`employeeWorkEmailIndex/{workEmailLower}`** | Mobile (owner `uid`) | Panel przy dodawaniu pracownika |
| **`userEmailIndex/{emailLower}`** | Mobile | Panel — merge nazw |
| **`users/{uid}/entries/{entryId}`** | Mobile + panel (w zakresie) | Timesheet, dashboard, raporty |
| **`users/{uid}/workspaces/{workspaceId}`** | Mobile (+ billing z panelu) | Lista projektów, stawki |
| **`users/{uid}/live/status`** | Mobile | Presence, live running (UI) |
| **`users/{uid}/consents/...`** | Mobile | Reguły mogą wymagać kształtu zgód (patrz `firestore.rules`) |
| **`employers/{employerUid}/trackedEmployees/{id}`** | Panel | Lista, grupy, szczegóły |
| **`employers/{employerUid}/trackedEmployeeUids/{employeeUid}`** | Panel | Indeks relacji; m.in. `live/status` |
| **`employers/{employerUid}/trackedWorkspaces/{accessId}`** | Panel | **Zakres dostępu** do entries/workspace/billing |
| **`employers/{employerUid}/groups/{groupId}`** | Panel | Organizer — **nie** zmienia uprawnień do entries |

Szczegóły pól i „truth”: **[DATA_CONTRACT.md](DATA_CONTRACT.md)**.

---

## 7. Flow linkowania pracownika (work email)

1. Normalizacja work email (trim, lowercase).
2. Domena pracodawcy z **Firebase Auth** (`email` konta) — fragment po `@`, lowercase.
3. Odczyt **`employeeWorkEmailIndex/{workEmailLower}`** — brak dokumentu → komunikat o braku udostępnionego workspace dla tego adresu.
4. Porównanie **`index.domain`** z domeną pracodawcy — konflikt → komunikat o innej firmie / domenie.
5. Pusta **`workspaceIds`** → brak udostępnionych projektów dla indeksu.
6. Pobranie **`users/{uid}/workspaces/{id}`** dla id z indeksu; filtrowanie **`workspaceQualifiesForEmployerPanel`** (m.in. `isSharedWithEmployer`, zgodność work email i domeny).
7. Utworzenie **`trackedEmployeeUids/{employeeUid}`**.
8. Zapis / merge **`trackedEmployees`** (w tym `employeeWorkEmailLower` / `employeeWorkEmailDomain`).
9. Utworzenie dokumentów **`trackedWorkspaces`** z **`accessId = "${employeeUid}_${workspaceId}"`** dla każdego zakwalifikowanego workspace’u.

**Operacyjnie:** bez utrzymania **`employeeWorkEmailIndex`** przez mobile panel nie znajdzie pracownika po samym work email.

---

## 8. Model dostępu: per-workspace i klucz złożony

- **Reguły** używają **`employerHasTrackedWorkspace(employeeUid, workspaceId)`** — sprawdzają istnienie dokumentu **`trackedWorkspaces/{employeeUid_workspaceId}`** (konkatenacja UID + `_` + `workspaceId`).
- **`workspaceId` na wpisie** musi być **dokładnie** tym samym stringiem co segment w id dokumentu `trackedWorkspaces` (łącznie z ewentualnymi „dziwnymi” id typu `default` u różnych użytkowników).
- **Dlaczego nie mapować po samym `workspaceId`:** u dwóch pracowników **ten sam** `workspaceId` (np. slug dokumentu domyślnego) to **inne** projekty. Mapy w pamięci (`buildWorkspaceLookupByScopedKey`, `workspaceForEmployerEntry`) używają klucza **`employeeUid` + `workspaceId`**, żeby uniknąć kolizji.

**Grupy:** `groupIds` na `trackedEmployees` to **wyłącznie UI** — nie skracają i nie rozszerzają listy `trackedWorkspaces`.

---

## 9. Strategia zapytań o wpisy (`entries`)

**Zakres czasu (miesiąc / raport):** zapytania employer-side filtrują pole **`start`** w przedziale **[`period.start`, `period.endInclusive`]** (inkluzywnie). Wpisy, które **zaczynają się** poza miesiącem, a kończą w środku, **nie wracają** z tego query (kontrakt „start in month”, nie overlap po `end`).

**Workspace:** `where('workspaceId', whereIn: chunk)` — **`whereIn` max 10** wartości na zapytanie (`kFirestoreWhereIn` w `employer_workspace_query_utils.dart`). Większy zbiór **`trackedWorkspaceIds`** jest **dzielony na chunki**; wyniki są **mergowane** i deduplikowane po `entryId` w `fetchEntriesInRangeForEmployer`.

**Stream miesiąca (`employeeEntriesForMonthStream`):** dla bieżącego zbioru `trackedWorkspaces` składane są **równoległe** strumienie per chunk; emit to posortowana lista po `start`.

**Indeks złożony (wymagany w praktyce):** kolekcja `users/{uid}/entries` z polami **`workspaceId`** + **`start`** (równość / zakres jak w query). Brak indeksu → błąd Firestore **`failed-precondition`** z linkiem do konsoli.

**Inne zapytania (last activity):** per `workspaceId` równość + `isDeleted` + `orderBy('updatedAt', descending: true)` (fallback: `orderBy('start', descending: true)`) — mogą wymagać **osobnych** indeksów złożonych (`workspaceId` + `isDeleted` + `updatedAt` itd.).

---

## 10. Statystyki dashboardu

- **`DashboardScreen._loadDashboardSnapshot`** — dla każdego `TrackedEmployee`: **`fetchEntriesInRangeForEmployer`** (domyślnie **`preferServer: true`** w kodzie snapshotu), potem **`fetchEmployeeWorkspacesForEmployer`**, lookup mapy workspace’ów, **filtrowanie po stronie klienta:** odrzucenie `isDeleted`, brak `end`, oraz **`workspaceForEmployerEntry == null`**; sumy godzin i kwot z **`ReportCalculationService`**.
- **Odświeżanie:** przycisk / powody odświeżenia (timer debounce / stream) — szczegół implementacji w `dashboard_screen.dart`; znacznik **„Last updated”** po udanym przeładowaniu snapshotu.
- **Błędy:** try/catch w snapshotcie — w debug log; UI powinien degradować zamiast „czerwonego ekranu” (patrz QA).

**Stream vs fetch:** lista pracowników i live mogą używać strumieni; **miesięczne agregaty** w tym flow opierają się na **jednorazowym fetchu** wpisów w zakresie miesiąca (nie ciągły stream wszystkich wpisów dashboardu).

---

## 11. Live status i live amount

- **Źródło:** `users/{employeeUid}/live/status` (read-only z panelu).
- **Presence:** `employee_presence_utils.dart` — mapowanie pól modelu na **Working / Paused / Online / Offline / Unknown** (progi czasu dla „online”).
- **Live running (szacunek):** `live_running_amounts.dart` — wyłącznie **w pamięci UI**; **nie zapisuje** kwoty do Firestore.
- **Gate `activeWorkspaceId`:** przy przekazaniu mapy dozwolonych workspace’ów kwota **nie jest** liczona, gdy aktywny workspace timera **nie** należy do zestawu śledzonych — unikamy podglądu stawek dla prywatnych / nieshared projektów.
- **Legacy:** dodatkowe strumienie typu otwarty wpis mogą istnieć jako wsparcie; prezencja w UI opiera się na **`live/status`**.

**Opcjonalne logi:** `LiveStatusDebugConfig.verboseLiveLogs` w `main.dart` (wyłączone domyślnie).

---

## 12. Timesheet — CRUD, soft delete, audyt

- **Ekran:** szczegóły pracownika → panel timesheet (`EmployeeTimesheetPanel`) z **`employeeEntriesForMonthStream`** (zakres + `trackedWorkspaces`).
- **Create / update:** zapis do `users/{uid}/entries` z polami zgodnymi z regułami; typowe **`createdVia: employer_panel`**, **`createdBy`**, przy edycji **`editedAt` / `editedBy`** (jeśli reguły i payload).
- **Soft delete:** `isDeleted: true` + `updatedAt`; **restore:** `isDeleted: false`.
- **Walidacja:** m.in. `start < end`, workspace z listy udostępnionej.
- **Filtry UI:** `filterTimesheetEntries` + **`explainTimesheetFilterReject`** (`timesheet_entry_utils.dart`) — powód odrzucenia przy debug trace.

---

## 13. Grupy

- **Many-to-many:** `trackedEmployees.groupIds` — tablica id dokumentów `groups`.
- **Ekran Groups:** łączy `trackedWorkspaces`, `trackedEmployees`, `groups` — w rozwinięciu grupy tylko pracownicy z realnym dostępem workspace.
- **Ungrouped:** brak ważnego przypisania do istniejącej grupy.
- **Uprawnienia:** grupy **nie** są sprawdzane w `firestore.rules` dla `entries` / `workspaces` — wyłącznie **`employerHasTrackedWorkspace`**.

---

## 14. Firestore rules — założenia

Plik: **`firestore.rules`**.

- **Employer** jest „właścicielem” tylko własnego **`employers/{request.auth.uid}/...`**.
- **Odczyt wpisów pracownika** przez pracodawcę: `employerHasTrackedWorkspace(uid, resource.data.workspaceId)` na istniejącym dokumencie.
- **Zapis wpisów przez pracodawcę:** funkcje **`employerEntryCreateValid` / `employerEntryUpdateValid`** (m.in. zgodność `workspaceId` z `trackedWorkspaces`, kształt pól).
- **`employeeWorkEmailIndex`:** zapis tylko gdy **`request.auth.uid == resource.uid`** (indeks należy do pracownika) — pracodawca **czyta**, nie tworzy indeksu za employee.
- **Workspace read:** dodatkowa ścieżka bootstrap (`employerTracksUser` + `isSharedWithEmployer`) w regułach — szczegół w pliku; **faktyczny zakres produktu** i tak opiera się na synchronizacji **`trackedWorkspaces`**.
- **Zgody prawne:** ścieżki pod `users/{uid}/consents/...` i funkcje kształtu — mobile może musieć spełnić wymagania przed zapisem danych (patrz reguły).

Produkcja: reguły wymagają przeglądu pod konkretny model zgód i organizacji.

---

## 15. Indeksy złożone

Repozytorium **nie zawiera** gotowego `firestore.indexes.json` — indeksy tworzy się w **Firebase Console** lub z linku z błędu **`failed-precondition`**.

**Typowe indeksy do rozważenia (subkolekcja `entries` u danego `users/{uid}`):**

| Pola (kierunek) | Kontekst |
|-----------------|------------|
| `workspaceId` ASC, `start` ASC, `__name__` ASC | Miesięczne zapytania: `whereIn` + zakres na `start` |
| `workspaceId` ASC, `isDeleted` ASC, `updatedAt` DESC | Ostatnia aktywność (employer) |
| `workspaceId` ASC, `start` DESC | Fallback last activity bez `updatedAt` |
| `isDeleted` ASC, `updatedAt` DESC | `fetchLastActivityAt` (owner) |

Kierunki **ASC/DESC** musą **dokładnie** pasować do zapytania (`orderBy` + filtry). Firebase podpowie brakujący indeks w komunikacie błędu.

---

## 16. Narzędzia debug

- **`EmployerEntriesDebugConfig`** (`lib/core/debug/employer_entries_debug_config.dart`): `verboseTrace`, `focusEmployeeUid`, `focusEntryId`. Szczegółowe logi ścieżki wpisów w **`fetchEntriesInRangeForEmployer`**, **`employeeEntriesForMonthStream`**, **`DashboardScreen._loadDashboardSnapshot`**, **`EmployeeTimesheetPanel`** — **tylko gdy `kDebugMode` i włączony trace** (patrz getter `traceDetailed` w pliku).
- **`LiveStatusDebugConfig`** — osobno dla snapshotów live (domyślnie wyłączone).

**Repozytarium:** w **`lib/main.dart`** mogą być **tymczasowo** ustawione stałe UID / entryId — **usuń lub zastąp `--dart-define` / lokalnym plikiem** przed publicznym release lub udostępnieniem buildu poza zaufanym kręgiem.

---

## 17. Testy (`test/`)

Uruchomienie: `flutter test`.

Przykładowe obszary pokryte testami jednostkowymi:

- `employer_workspace_lookup_test.dart` — klucz złożony lookup.
- `employer_workspace_query_utils_test.dart` — chunkowanie `whereIn`.
- `tracked_workspace_policy_test.dart` — kwalifikacja workspace dla panelu.
- `work_email_employer_access_test.dart` — logika email / domena.
- `employee_presence_utils_test.dart`, `employee_live_status_test.dart` — presence.
- `live_running_amounts_test.dart` — live amount i gate workspace.
- `timesheet_entry_utils_test.dart` — `filterTimesheetEntries` i sortowanie.
- `entry_amount_breakdown_test.dart`, `report_calculation_service` (jeśli testowany przez import), `employer_entry_soft_patch_test.dart`, `employer_group_ids_utils_test.dart`, `tracked_employee_display_test.dart`, itd.

---

## 18. Znane ograniczenia

- Brak Google Sign-In w MVP.
- Skalowanie: wiele chunków `whereIn`, brak paginacji na dużych listach wpisów w jednym miesiącu.
- Agregacje miesięczne na dashboardzie — kosztowne przy wielu pracownikach (N× fetch).
- PDF z raportów — niewdrożony lub TODO względem CSV.
- Reguły i indeksy muszą być utrzymywane ręcznie w deployu Firebase.

---

## 19. Możliwe usprawnienia (techniczne)

- Cloud Functions dla atomowego linkowania i walidacji po stronie serwera.
- Indeks **`firestore.indexes.json`** w repo + `firebase deploy --only firestore:indexes`.
- Warstwa cache / deduplikacja zapytań dashboardu.
- Paginacja timesheetu i server-side sumy.
- Rozszerzenie testów integracyjnych z emulatorem Firestore.

---

## Powiązane dokumenty

- **[README.md](README.md)** — opis produktu.
- **[DATA_CONTRACT.md](DATA_CONTRACT.md)** — kontrakt ścieżek i zapisów.
- **[QA_CHECKLIST.md](QA_CHECKLIST.md)** — checklist regresji.

## Konfiguracja i jakość kodu

```bash
flutterfire configure   # lib/firebase_options.dart
flutter analyze
flutter test
```

Motyw M3, wspólne widgety layoutu: **`lib/core/theme/app_theme.dart`**, **`app_layout.dart`**, **`app_empty_state.dart`**, **`app_pulse_loading.dart`** — patrz poprzednie opisy w historii commitów / kodzie źródłowym.
