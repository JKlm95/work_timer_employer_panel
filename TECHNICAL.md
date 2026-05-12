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

**TODO (mobile):** Indeks po logowaniu. Status „Working” na MVP: wpis z `end == null` i `isDeleted != true`; jeśli mobilka zawsze ustawia `end`, docelowo `liveStatus` (TODO w kodzie).

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

## Obliczenia raportów (`ReportCalculationService`)

- Czas z `end - start`; pomijane `isDeleted` i brak `end` (poza statusem „Working”).
- Kwoty dla wpisów billable; waluty bez konwersji.

## Eksport CSV

`ExportService` + Web download. PDF — TODO w UI.

## Bezpieczeństwo

- Komentarze przy wrażliwych odczytach.
- `firestore.rules` — szkic deny-all; produkcja: reguły lub Cloud Functions.

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
