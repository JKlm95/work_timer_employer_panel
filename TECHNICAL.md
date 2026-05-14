# Work Timer Employer Panel — dokumentacja techniczna

## Stack

| Komponent | Użycie |
|-----------|--------|
| Flutter Web | UI, routing (`go_router`) |
| Firebase Core / Auth | Inicjalizacja, logowanie pracodawcy |
| Cloud Firestore | Odczyt danych pracowników + zapis danych panelu pracodawcy + MVP: `hourlyRate` / `currency` na workspace |
| `provider` | `ThemeController` przy korzeniu aplikacji (`ChangeNotifierProvider`) |
| `shared_preferences` | Persystencja trybu motywu (light / dark / system) na Web |
| Architektura | Feature folders (`lib/features/…`), serwisy (`lib/services/…`), modele (`lib/models/…`) |

Stan ekranów nadal opiera się głównie na **`StreamBuilder`** / **`FutureBuilder`** + Firestore (MVP).

## Motyw (jasny / ciemny)

- **`lib/core/theme/app_theme.dart`** — `buildLightTheme()` i `buildDarkTheme()`: Material 3, wspólna estetyka SaaS (indygo + slate), karty, rail, tabele, pola formularzy.
- **`lib/core/theme/theme_controller.dart`** — `ThemeMode`, zapis do `SharedPreferences` pod kluczem `theme_mode`.
- **`lib/app.dart`** — `MaterialApp.router` z `theme`, `darkTheme`, `themeMode` z `ThemeController`.
- **`lib/main.dart`** — `await themeController.load()` przed `runApp`; `ChangeNotifierProvider.value` owija `WorkTimerEmployerApp`.
- **Ustawienia** — `SegmentedButton<ThemeMode>` (System / Light / Dark).

## Struktura katalogów `lib/`

```
lib/
  main.dart              # Firebase + ThemeController.load + Provider root
  app.dart               # MaterialApp.router + theme / darkTheme / themeMode
  firebase_options.dart  # flutterfire configure (placeholdery domyślnie)
  core/
    theme/               # app_theme.dart, theme_controller.dart
    utils/               # Domena emaila, slug firmy, okresy raportów, nazwy pracowników
    export/              # Pobieranie plików na Web (conditional import)
    widgets/             # m.in. WorkStatusBadge
  models/                # Workspace, WorkEntry, TrackedEmployee, EmployerGroup, UserEmailIndex, EmployeeWorkEmailIndex
  services/
    firebase_auth_service.dart
    firestore_service.dart       # Zapytania, linkowanie, billing workspace, presence
    report_calculation_service.dart
    export_service.dart          # CSV (escape komórek)
  features/
    auth/ login_screen.dart
    shell/ main_shell.dart       # Sidebar / drawer + top bar (kolory ze scheme)
    dashboard/
    employees/
    groups/
    reports/                     # Raport projektu + payroll
    settings/                    # Motyw + wylogowanie
  router/ app_router.dart        # GoRouter + ShellRoute + redirect auth
```

## Model danych Firestore (założenia)

### Aplikacja mobilna

- `users/{employeeUid}/workspaces/{workspaceId}` — m.in. `companySlug`, `companyName`, `employeeWorkEmail`, `employeeWorkEmailDomain`, `hourlyRate`, `currency`, `isArchived`, **`isSharedWithEmployer`**
- `users/{employeeUid}/entries/{entryId}` — wpisy czasu; `isDeleted`, `entryType`, `isBillable`, `start`/`end`

### Indeks work email → UID + workspace ids

- `employeeWorkEmailIndex/{workEmailLower}` → `{ uid, workEmailLower, domain, workspaceIds[], updatedAt? }`

**Wymaganie (mobile):** indeks musi być utrzymywany po ustawieniu work email na udostępnionych workspace’ach — bez tego panel nie znajdzie pracownika po work email (komunikat „No shared workspace found for this work email.”).

### Indeks email → UID (profil)

- `userEmailIndex/{emailLower}` → `{ uid, email, displayName?, … }`

**Wymaganie (mobile):** opcjonalnie dla imion na liście — `trackedEmployees` merge w UI.

## Live status (`users/{employeeUid}/live/status`)

Panel czyta **jeden dokument** na pracownika:

`users/{employeeUid}/live/status`

Mobilka utrzymuje ten dokument (timer, heartbeat, opcjonalnie stawka na sesji). Panel **nie zapisuje** do tej ścieżki.

### Mapowanie na UI (presence)

Logika w `lib/core/utils/employee_presence_utils.dart` (`resolveWorkPresence`):

| UI (badge) | Warunki (uproszczenie) |
|------------|-------------------------|
| **Working** | `timerState` (case-insensitive) = `running` |
| **Paused** | `timerState` = `paused` |
| **Online** | stan „idle” (w tym brak / pusty `timerState` traktowany jak `idle`), `isOnline == true` oraz **świeży** `lastSeenAt` lub `updatedAt` (poniżej progu `kOnlineLastSeenThreshold`, domyślnie 2 min) |
| **Offline** | brak dokumentu (null z streamu), `isOnline == false`, albo brak / przestarzały heartbeat (`lastSeenAt` / `updatedAt`) |
| **Unknown** | m.in. ładowanie pierwszej emisji streamu, błąd streamu, albo `isOnline == null` przy świeżym czasie — UI nie zgaduje „online” |

Szczegóły pól modelu: `lib/models/employee_live_status.dart`.

### Live amount (szacunek w locie)

- Liczone w **`lib/core/utils/live_running_amounts.dart`** (`computeLiveRunningMoneySummary`) wyłącznie w **pamięci UI** z aktualnego `EmployeeLiveStatus` + mapy workspace’ów (stawka z live doc lub z `users/.../workspaces`).
- Dla panelu pracodawcy: jeśli przekazano mapę **`allowedWorkspaceIdsByEmployeeUid`** (dashboard), kwota jest liczona **tylko** gdy `activeWorkspaceId` ∈ dozwolonych ID — timer na prywatnym / innym workspace nie pokazuje kwoty w „Live running (est.)”.
- **Nie jest** zapisywane do Firestore i **nie zastępuje** kwot z zamkniętych wpisów (`entries`) na karcie „Estimated amount (month)”.

### Legacy / hasOpenTimer

Starsze heurystyki oparte o otwarty wpis (`end == null`) są **dodatkiem** (np. `hasOpenTimerStream`); prezencja w UI opiera się na **`live/status`**.

### Dane pracodawcy

- `employers/{employerUid}/trackedEmployees/{id}`
- `employers/{employerUid}/trackedEmployeeUids/{employeeUid}` — **indeks** „znam UID” (m.in. `live/status`); nie jest już jedynym gate’em do `entries`.
- `employers/{employerUid}/trackedWorkspaces/{accessId}` — **`accessId = employeeUid_workspaceId`**; **rzeczywisty zakres** widocznych workspace’ów i wpisów w panelu.
- `employers/{employerUid}/groups/{groupId}`

**Firestore indeksy:** zapytania miesięczne o wpisy u pracodawcy używają `where('workspaceId', whereIn: …)` (max 10 ID na zapytanie) + `start` — w konsoli Firebase dodaj indeks złożony na `entries`: `workspaceId` + `start` (zakres), jeśli deploy zwróci link do utworzenia indeksu.

## Ustawienia — Rebuild workspace access

- Ekran **Settings** zawiera akcję **Rebuild workspace access** (`FirestoreService.rebuildTrackedWorkspaceAccess`): dla każdego `trackedEmployees` odbudowuje zestaw dokumentów `trackedWorkspaces` wg pól **work email / domena** zapisanych na wierszu śledzenia i aktualnych dokumentów `users/.../workspaces` (`tracked_workspace_policy.dart`). **Brak automatycznej migracji** przy starcie aplikacji — tylko jawny przycisk.

### Dozwolone zapisy MVP w danych „pracownika”

- Tylko **`updateWorkspaceBilling`** na `users/{uid}/workspaces/{id}` (`hourlyRate`, `currency`, `updatedAt`) — **po sprawdzeniu** `trackedWorkspaces`. Reszta danych pracownika — read-only z panelu.

## Logika dodawania pracownika (work email)

1. Normalizacja work email (trim + lowercase) i walidacja formatu.
2. Domena pracodawcy z **Firebase Auth** (`email` konta) — część po `@`, lowercase.
3. Odczyt `employeeWorkEmailIndex/{workEmailLower}` — brak dokumentu → komunikat *No shared workspace found for this work email.*
4. Porównanie `index.domain` z domeną pracodawcy — niespójność → *This workspace belongs to a different company domain.*
5. Pusta lista `workspaceIds` → *This work email has no shared workspaces.*
6. Pobranie dokumentów `users/{uid}/workspaces/{id}` dla id z indeksu; filtrowanie **`workspaceQualifiesForEmployerPanel`** (shared + `employeeWorkEmail` + `employeeWorkEmailDomain`) — brak wyników → *No shared workspace for your company domain.*
7. Utworzenie / utrzymanie `trackedEmployeeUids/{uid}`.
8. Zapis `trackedEmployees` (m.in. `employeeWorkEmailLower`, `employeeWorkEmailDomain`; imiona z `userEmailIndex` jeśli dostępny).
9. Utworzenie dokumentów **`trackedWorkspaces`** dla wszystkich pasujących workspace’ów (`accessId = employeeUid_workspaceId`).

**Migracja:** istniejące `trackedEmployees` bez `employeeWorkEmailLower` używają w rebuildzie fallbacku `employeeEmailLower` (legacy). Warto użyć **Rebuild workspace access** po aktualizacji mobile.

## Wpisy czasu — timesheet pracodawcy

- Na ekranie **szczegółów pracownika** (`EmployeeDetailScreen`) panel pokazuje **timesheet miesięczny**: filtry, sortowanie, podsumowanie oraz **dodawanie / edycja / soft delete / przywracanie** wpisów w `users/{employeeUid}/entries/{entryId}` — **tylko** dla `workspaceId` obecnych w `trackedWorkspaces` (stream składa zapytania per chunk `whereIn`).
- **Usuwanie** = wyłącznie **soft delete** (`isDeleted: true`, `updatedAt`), bez hard `delete` w Firestore.
- **Kwoty** w tabeli i w `ReportCalculationService.estimatedAmountByCurrency` (dla wpisów `work` billable) liczą się jako:  
  `godziny × hourlyRate workspace × billingRatePercent / 100` (brak stawki → „No rate” / „—” w UI).
- **Eksporty CSV/PDF** nie są częścią tego modułu timesheet (osobne ekrany raportów bez zmian w zakresie eksportu z tego zadania).

## UI — wspólne komponenty (employer panel)

Lekkie widgety i stałe layoutu (bez nowych zależności), używane przy empty/loading i nagłówkach:

| Plik | Rola |
|------|------|
| `lib/core/theme/app_layout.dart` | `AppLayout` — odstępy strony, sekcji, promienie, `outlineSide` dla obramowań. |
| `lib/core/widgets/app_empty_state.dart` | Ikona + tytuł + opcjonalny podtytuł (`detailSelectable` dla błędów z zaznaczalnym tekstem). |
| `lib/core/widgets/app_pulse_loading.dart` | `AppPulseLoading` — pulsujące prostokąty zamiast gołego spinnera. |
| `lib/core/widgets/app_pinned_toolbar.dart` | `AppPinnedToolbarDelegate` (pinned sliver), `AppToolbarSurface` (pasek z dolną krawędzią). |
| `lib/core/widgets/employee_avatar.dart` | `EmployeeAvatar` — inicjały + deterministyczny kolor tła z `seed` (np. `employeeUid`). |
| `lib/features/employees/widgets/timesheet_entry_badges.dart` | `TimesheetEntryBadges` — chipy typu / % / billable / deleted / edited w timesheecie. |

Motyw (`app_theme.dart`): doprecyzowane `chipTheme` i `snackBarTheme` (floating, zaokrąglenia).

## Obliczenia raportów (`ReportCalculationService`)

- Czas z `end - start`; pomijane `isDeleted` i brak `end` (poza statusem „Working”).
- Kwoty dla wpisów billable: `duration × hourlyRate × (billingRatePercent ?? 100) / 100`; waluty bez konwersji.

## Eksport CSV

`ExportService` + Web download. PDF — TODO w UI.

## Bezpieczeństwo

- Komentarze przy wrażliwych odczytach.
- `firestore.rules` — szkic pod MVP; produkcja: zawężenie reguł (patrz nagłówek komentarza w pliku rules).
- Pełniejszy opis ścieżek i read/write: **[`DATA_CONTRACT.md`](DATA_CONTRACT.md)**.
- Lista kontrolna przed demo: **[`QA_CHECKLIST.md`](QA_CHECKLIST.md)**.

## Konfiguracja Firebase Web

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

## Analiza i testy

```bash
flutter analyze
flutter test
```

## Znane ograniczenia MVP

- Brak Google Sign-In (opcjonalnie później).
- Indeksy Firestore pod zapytania z `orderBy` / `where` — konsola może zaproponować link.
- Duże org.: paginacja / backend dla agregacji.
