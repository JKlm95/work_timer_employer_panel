# Work Timer — panel pracodawcy (Flutter Web)

Webowa aplikacja dla **pracodawcy / administratora**, podłączona do tego samego **Firebase** (Auth + Firestore) co mobilna aplikacja Work Timer używana przez pracowników. Panel służy do **przeglądu czasu, szacunków rozliczeniowych, statusu pracy i organizacji listy** (grupy). Nie jest systemem kadrowym ani prawnym „payroll” — UI podkreśla, że chodzi o **raport z naliczonych godzin i stawek**.

## Stack technologiczny

| Warstwa | Technologie |
|--------|-------------|
| UI | Flutter (Web), Material 3 |
| Routing | `go_router` (ShellRoute, redirect po auth) |
| Stan ekranów | `StreamBuilder` / `FutureBuilder` + serwisy Firestore (MVP) |
| Backend | Firebase Auth (email/hasło), Cloud Firestore |
| Motyw | `provider` (`ThemeController`) + `shared_preferences` (wybór jasny/ciemny/system) |

Struktura katalogów i motyw: **[`TECHNICAL.md`](TECHNICAL.md)**.

## Współpraca z aplikacją mobilną

- **Wspólny projekt Firebase** — te same kolekcje i dokumenty co mobile.
- **Indeks** `employeeWorkEmailIndex/{workEmailLower}` musi być utrzymywany przez **mobile** po ustawieniu work email na udostępnionych workspace’ach — inaczej panel nie znajdzie pracownika (komunikat „No shared workspace found for this work email.”). Opcjonalnie **`userEmailIndex`** dla imion na liście.
- **Wpisy czasu** `users/{uid}/entries` i **projekty** `users/{uid}/workspaces` są źródłem prawdy po stronie pracownika; panel je **czyta**, a w MVP **edytuje wyłącznie** `hourlyRate` / `currency` na workspace (zapis do Firestore).
- **Obecność i timer w locie** — mobile utrzymuje `users/{uid}/live/status`; panel **tylko czyta** i liczy **live amount** wyłącznie w UI (bez zapisu kwoty do bazy). Szczegóły semantyki statusów: **[`TECHNICAL.md`](TECHNICAL.md)** (sekcja Live status).

**Kontrakt ścieżek Firestore** (read/write, cache vs truth): **[`DATA_CONTRACT.md`](DATA_CONTRACT.md)**.

## Główne flow (employer)

1. **Logowanie** — Firebase Auth; po sukcesie wejście do shell (nawigacja boczna).
2. **Dashboard** — liczba śledzonych, grup, „Working now”, godziny i **Estimated amount (month)** z **zapisanych** wpisów; **Live running (est.)** z dokumentu live + stawek; skróty do pracowników i raportów.
3. **Dodanie pracownika** — pełny **work email** pracownika (jak na workspace w mobile); domena konta pracodawcy musi być zgodna z domeną work email; zapis pod `employers/{uid}/trackedEmployees` + `trackedWorkspaces` + `trackedEmployeeUids` dla reguł.
4. **Lista pracowników** — miesięczne godziny/kwoty, status z live, przejście do szczegółów.
5. **Szczegół pracownika** — projekty (workspace) dla domeny pracodawcy, edycja stawki, raport wpisów.
6. **Grupy** — organizacja listy pracowników (bez zmiany danych czasu po stronie employee).
7. **Raporty** — raport projektu i raport miesięczny z eksportem CSV.

## Checklist QA

Przed demo lub releasem: **[`QA_CHECKLIST.md`](QA_CHECKLIST.md)**.

## Kluczowe funkcje (MVP)

| Obszar | Opis |
|--------|------|
| Logowanie | Email/hasło przez Firebase Auth |
| Motyw | Jasny / ciemny / zgodny z systemem (Ustawienia) |
| Dashboard | Śledzeni, grupy, **Working now**, godziny i kwoty miesiąca, **ostatnio załadowane statystyki** (Last updated), odświeżanie danych bez reloadu strony |
| Pracownicy | Imię z indeksu / `displayName`, inicjały, email, status, dodawanie / usuwanie z listy pracodawcy |
| Szczegóły pracownika | Projekty, edycja stawki/waluty, raport |
| Raport projektu | Filtry, CSV |
| Raport miesięczny („Payroll”) | Filtry, karty, tabela, CSV |
| Grupy | Tworzenie, zmiana nazwy, usuwanie, licznik osób w grupie |

## Wymagania przed uruchomieniem

1. Projekt **Firebase** z Authentication (email/hasło) i **Cloud Firestore**.
2. W konsoli Firebase skonfiguruj Web i wygeneruj `lib/firebase_options.dart` (np. `flutterfire configure`).
3. Zastąp wartości w `firebase_options.dart` — domyślnie są placeholdery `REPLACE_ME`.

## Uruchomienie (Web)

```bash
flutter pub get
flutter run -d chrome
```

Build produkcyjny:

```bash
flutter build web
```

## Struktura repo (skrót)

- `lib/` — aplikacja (feature’y, modele, serwisy, motyw).
- `firestore.rules` — reguły pod rozwój / MVP (patrz komentarze w pliku).
- `TECHNICAL.md`, `DATA_CONTRACT.md`, `QA_CHECKLIST.md` — dokumentacja techniczna i operacyjna.

---

**Koncepcja:** panel raportowy dla pracodawcy; dane pracownika pod `users/{uid}/…`, dane organizacyjne pod `employers/{employerUid}/…`.
