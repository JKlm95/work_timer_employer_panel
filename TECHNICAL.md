# Work Timer Employer Panel — dokumentacja techniczna

## Stack

| Komponent | Użycie |
|-----------|--------|
| Flutter Web | UI, routing (`go_router`) |
| Firebase Core / Auth | Inicjalizacja, logowanie pracodawcy |
| Cloud Firestore | Odczyt danych pracowników + zapis danych panelu pracodawcy |
| Architektura | Feature folders (`lib/features/…`), serwisy (`lib/services/…`), modele (`lib/models/…`) |

Stan nie jest zarządzany jednym globalnym frameworkiem — dominują **`StreamBuilder`** / **`FutureBuilder`** przy serwisie Firestore (świadome uproszczenie MVP).

## Struktura katalogów `lib/`

```
lib/
  main.dart              # Firebase.initializeApp + router
  app.dart               # MaterialApp.router + theme
  firebase_options.dart  # flutterfire configure (placeholdery domyślnie)
  core/
    theme/               # Motyw SaaS (jasny)
    utils/               # Domena emaila, slug firmy, okresy raportów
    export/              # Pobieranie plików na Web (conditional import)
    widgets/             # (placeholder na wspólne widgety)
  models/                # Workspace, WorkEntry, TrackedEmployee, EmployerGroup, UserEmailIndex
  services/
    firebase_auth_service.dart
    firestore_service.dart       # Zapytania + linkowanie pracownika
    report_calculation_service.dart
    export_service.dart          # CSV (escape komórek)
  features/
    auth/ login_screen.dart
    shell/ main_shell.dart       # Sidebar / drawer + top bar
    dashboard/
    employees/
    groups/
    reports/                     # Raport projektu + payroll
    settings/
  router/ app_router.dart        # GoRouter + ShellRoute + redirect auth
```

## Model danych Firestore (założenia)

### Aplikacja mobilna (read-only dla panelu)

- `users/{employeeUid}/workspaces/{workspaceId}` — m.in. `companySlug`, `employeeWorkEmail`, `employeeWorkEmailDomain`, `hourlyRate`, `currency`
- `users/{employeeUid}/entries/{entryId}` — wpisy czasu; `isDeleted`, `entryType`, `isBillable`, `start`/`end`

### Indeks email → UID

- `userEmailIndex/{emailLower}` → `{ uid, email, … }`

**TODO (mobile):** Ten dokument musi być tworzony/aktualizowany po logowaniu — implementacja jest po stronie aplikacji mobilnej. Frontend panelu tylko **oczekuje** kolekcji.

### Dane pracodawcy (zapis przez panel)

- `employers/{employerUid}/trackedEmployees/{id}`
- `employers/{employerUid}/groups/{groupId}`

## Logika dodawania pracownika (MVP)

1. Normalizacja maila pracownika do lowercase.
2. Normalizacja nazwy firmy do **slug** (`core/utils/company_slug_utils.dart`) — porównanie z `workspace.companySlug`.
3. Odczyt UID z `userEmailIndex`.
4. Odczyt listy workspace’ów pracownika; wybór dopasowania:
   - `employeeWorkEmail` (lower) == wpisany email
   - `companySlug` == znormalizowany slug firmy
   - `employeeWorkEmailDomain` == domena maila **zalogowanego pracodawcy**
5. Zapis rekordu w `trackedEmployees` (bez modyfikacji danych pracownika).

Komunikaty błędów są mapowane w `FirestoreService.linkEmployee` / `EmployerLinkException`.

## Obliczenia raportów (`ReportCalculationService`)

- Czas trwania z różnicy `end - start`; pomijane `isDeleted == true` i brak `end`.
- Typ wpisu **work** lub `null` traktowany jako praca (`WorkEntry.isWorkEntry`).
- Kwoty szacowane: `godziny × hourlyRate` dla wpisów billable (`isBillable` domyślnie `true` jeśli brak pola).
- Waluty **nie są konwertowane** — sumy per `PLN`, `EUR`, itd.
- Urlopy / choroby / delegacje: w raportach pokazywane jako liczniki wpisów (`splitHours`), nie jako „dni kalendarzowe” ISO.

## Eksport CSV

`ExportService` buduje CSV z ręcznym escapowaniem pól; pobranie pliku wyłącznie na **Web** (`lib/core/export/download_web.dart`). PDF — celowo **nie** zaimplementowany (TODO w tooltipach).

## Bezpieczeństwo

- Kod komentuje miejsca **wrażliwe** (odczyt `users/{uid}/…`).
- Plik `firestore.rules` jest **szkicem**: domyślnie **wyłącza** operacje (`allow read, write: if false`), żeby nie sugerować niebezpiecznej konfiguracji. Produkcja wymaga reguł ograniczających odczyt do powiązanych employer↔employee lub warstwy Cloud Functions.

## Konfiguracja Firebase Web

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Nadpisze `lib/firebase_options.dart` prawdziwymi wartościami z projektu.

## Analiza i testy

```bash
flutter analyze
flutter test
```

## Znane ograniczenia MVP

- Brak Google Sign-In (możliwy jako rozszerzenie).
- Zapytania Firestore po polu `start` zakładają indeksy kompozytowe — przy pierwszym uruchomieniu konsola Firebase może zaproponować link do utworzenia indeksu.
- Duże org.: pobieranie wpisów w zakresie miesiąca per pracownik może wymagać paginacji lub funkcji backendowych.
