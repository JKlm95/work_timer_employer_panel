# Work Timer — panel pracodawcy (Flutter Web)

Webowa aplikacja dla **pracodawcy / administratora**, która podłącza się pod ten sam backend **Firebase** co mobilna aplikacja Work Timer używana przez pracowników. Panel służy do **raportów i organizacji** (śledzeni pracownicy, grupy, raporty). **Wpisy czasu i projekty pracownika** nie są edytowane z poziomu panelu — z wyjątkiem MVP: **stawka godzinowa i waluta** na dokumencie workspace w Firestore (źródło prawdy dla mobilki).

## Po co to jest

- **Pracownicy** w aplikacji mobilnej prowadzą projekty, czas, notatki, rozliczenia billable/non-billable i stawki.
- **Ty jako pracodawca** widzisz zestawienia godzin i szacowane kwoty (wg stawek z projektu), status pracy (MVP: otwarty wpis bez `end`), ostatnią aktywność, grupujesz ludzi w **grupy** i eksportujesz raporty do **CSV**.
- **Wygląd:** jasny i ciemny motyw (Ustawienia → Appearance), spójna paleta indygo / slate, zapis wyboru w przeglądarce (`shared_preferences`).

To nie jest system kadrowy ani prawny „payroll” — UI podkreśla, że chodzi o **raport z naliczonych godzin i stawek**.

## Kluczowe funkcje (MVP)

| Obszar | Opis |
|--------|------|
| Logowanie | Email/hasło przez Firebase Auth |
| Motyw | Jasny / ciemny / zgodny z systemem (Ustawienia) |
| Dashboard | Śledzeni, grupy, **pracują teraz**, godziny i szacunki w miesiącu, skrót do payroll |
| Pracownicy | Imię z `displayName`, inicjały, email, status, dodawanie / usuwanie z listy pracodawcy |
| Szczegóły pracownika | Projekty (w tym archiwalne — tylko podgląd), edycja stawki/waluty, raport |
| Raport projektu | Filtry, CSV, edycja stawki z paska |
| Raport miesięczny („Payroll”) | Filtry, karty podsumowań, tabela, CSV |
| Grupy | Tworzenie, zmiana nazwy, usuwanie, licznik osób w grupie |

## Wymagania przed uruchomieniem

1. Projekt **Firebase** z włączonym Authentication (email/hasło) i **Cloud Firestore**.
2. W konsoli Firebase skonfiguruj opcje Web i wygeneruj `firebase_options.dart` (np. `flutterfire configure`).
3. Zastąp wartości w `lib/firebase_options.dart` — domyślnie są placeholdery `REPLACE_ME`.

## Uruchomienie (Web)

```bash
flutter pub get
flutter run -d chrome
```

Build produkcyjny:

```bash
flutter build web
```

## Ważne uzgodnienie z aplikacją mobilną

Indeks **`userEmailIndex/{emailLower}`** musi być utrzymywany przez aplikację mobilną po logowaniu / aktualizacji profilu — bez tego panel nie znajdzie pracownika po adresie email (komunikat „Employee not found”). Szczegóły struktury danych i reguł dostępu są w **`TECHNICAL.md`**.

## Struktura repo (skrót)

- `lib/` — kod aplikacji (feature’y, modele, serwisy, motyw).
- `firestore.rules` — **szkic** reguł (na MVP wyłącza dostęp — do zastąpienia regułami produkcyjnymi lub Cloud Functions).

---

**Autorzy koncepcji:** panel pod raporty dla pracodawcy; dane pracownika pod `users/{uid}/…`, dane organizacyjne pracodawcy pod `employers/{employerUid}/…`.
