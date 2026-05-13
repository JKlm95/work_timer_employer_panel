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
  models/                # Workspace, WorkEntry, TrackedEmployee, EmployerGroup, UserEmailIndex
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

- `users/{employeeUid}/workspaces/{workspaceId}` — m.in. `companySlug`, `employeeWorkEmail`, `employeeWorkEmailDomain`, `hourlyRate`, `currency`, `isArchived`
- `users/{employeeUid}/entries/{entryId}` — wpisy czasu; `isDeleted`, `entryType`, `isBillable`, `start`/`end`

### Indeks email → UID

- `userEmailIndex/{emailLower}` → `{ uid, email, displayName?, … }`

**Wymaganie (mobile):** indeks musi być utrzymywany po logowaniu — bez tego linkowanie po emailu nie zadziała.

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
- **Nie jest** zapisywane do Firestore i **nie zastępuje** kwot z zamkniętych wpisów (`entries`) na karcie „Estimated amount (month)”.

### Legacy / hasOpenTimer

Starsze heurystyki oparte o otwarty wpis (`end == null`) są **dodatkiem** (np. `hasOpenTimerStream`); prezencja w UI opiera się na **`live/status`**.

### Dane pracodawcy

- `employers/{employerUid}/trackedEmployees/{id}`
- `employers/{employerUid}/groups/{groupId}`

### Dozwolone zapisy MVP w danych „pracownika”

- Tylko **`updateWorkspaceBilling`** na `users/{uid}/workspaces/{id}` (`hourlyRate`, `currency`, `updatedAt`). Reszta danych pracownika — read-only z panelu.

## Logika dodawania pracownika (MVP)

1. Normalizacja maila pracownika do lowercase.
2. Normalizacja nazwy firmy do **slug** (`core/utils/company_slug_utils.dart`).
3. Odczyt UID z `userEmailIndex`.
4. Dopasowanie workspace (email + slug + domena pracodawcy).
5. Zapis w `trackedEmployees`.

## Wpisy czasu — timesheet pracodawcy

- Na ekranie **szczegółów pracownika** (`EmployeeDetailScreen`) panel pokazuje **timesheet miesięczny**: filtry, sortowanie, podsumowanie oraz **dodawanie / edycja / soft delete / przywracanie** wpisów w `users/{employeeUid}/entries/{entryId}`.
- **Usuwanie** = wyłącznie **soft delete** (`isDeleted: true`, `updatedAt`), bez hard `delete` w Firestore.
- **Kwoty** w tabeli i w `ReportCalculationService.estimatedAmountByCurrency` (dla wpisów `work` billable) liczą się jako:  
  `godziny × hourlyRate workspace × billingRatePercent / 100` (brak stawki → „No rate” / „—” w UI).
- **Eksporty CSV/PDF** nie są częścią tego modułu timesheet (osobne ekrany raportów bez zmian w zakresie eksportu z tego zadania).

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
