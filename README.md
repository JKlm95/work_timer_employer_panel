# Work Timer — panel pracodawcy (Flutter Web)

Webowa aplikacja dla **pracodawcy / administratora**, która podłącza się pod ten sam backend **Firebase** co mobilna aplikacja Work Timer używana przez pracowników. Panel jest **wyłącznie do odczytu** danych czasu pracy — nie edytuje wpisów ani projektów pracownika.

## Po co to jest

- **Pracownicy** w aplikacji mobilnej prowadzą projekty, czas, notatki, rozliczenia billable/non-billable i stawki.
- **Ty jako pracodawca** widzisz zestawienia godzin i szacowane kwoty (wg stawek z projektu), grupujesz ludzi w **grupy** wygodne dla siebie i eksportujesz raporty do **CSV**.

To nie jest system kadrowy ani prawny „payroll” — UI podkreśla, że chodzi o **raport z naliczonych godzin i stawek**.

## Kluczowe funkcje (MVP)

| Obszar | Opis |
|--------|------|
| Logowanie | Email/hasło przez Firebase Auth |
| Dashboard | Liczba śledzonych osób, grup, godziny i szacunki w bieżącym miesiącu |
| Pracownicy | Dodanie po **mailu służbowym** i **nazwie firmy** (dopasowanie do workspace w Firestore), lista, grupy, szczegóły |
| Raport projektu | Zakres dat, typ wpisu, billable, tabela wpisów, eksport CSV |
| Raport miesięczny („Payroll”) | Filtry: miesiąc, grupa, osoba, waluta, tylko billable — tabela + podsumowanie + CSV |
| Grupy | Tworzenie / edycja / usuwanie — tylko po stronie pracodawcy |

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

- `lib/` — kod aplikacji (feature’y, modele, serwisy).
- `firestore.rules` — **szkic** reguł (na MVP wyłącza dostęp — do zastąpienia regułami produkcyjnymi lub Cloud Functions).

---

**Autorzy koncepcji:** panel pod read-only raporty dla pracodawcy; dane pracownika pozostają pod `users/{uid}/…`, dane organizacyjne pracodawcy pod `employers/{employerUid}/…`.
