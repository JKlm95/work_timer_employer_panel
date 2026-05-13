# QA checklist — employer panel (MVP)

Krótka lista regresji przed demo / portfolio. Zakłada działający Firebase (Auth + Firestore) i zdeployowaną mobilkę zapisującą dane zgodnie z [`DATA_CONTRACT.md`](DATA_CONTRACT.md).

## Auth i pracownicy

- [ ] **Logowanie employer** — email/hasło, po zalogowaniu shell (sidebar + treść).
- [ ] **Dodanie pracownika po e-mailu** — poprawna domena + firma/slug; sukces → wpis na liście; błąd → czytelny komunikat („Employee not found” gdy brak indeksu).
- [ ] **Profil pracownika** — wejście w szczegóły z listy: nazwa, firma, grupy, presence, ostatnia aktywność, karty projektów.

## Timesheet (szczegóły pracownika)

- [ ] **Miesiąc** — przełącznik miesiąca ładuje wpisy z `users/{uid}/entries` (stream); loading / empty („No entries in this month”).
- [ ] **Filtry** — workspace, typ wpisu, billable, „Show deleted”, wyszukiwarka po tytule zadania / notatce; pusty wynik → „No entries match current filters”.
- [ ] **Sortowanie** — newest / oldest / duration / amount działa bez przeładowania strony.
- [ ] **Kwota** — przy braku `hourlyRate` lub workspace: „No rate” / „—”; tooltip z powodem; breakdown typu `8h × 50 PLN × 80% = 320 PLN` gdy dane kompletne.
- [ ] **Podsumowanie** — suma czasu, billable / non-billable, szacunek po walutach, breakdown po `entryType` i `billingRatePercent`.
- [ ] **Dodaj wpis** — formularz (workspace, data, start/end, typ, %, billable, task, note); walidacja `start < end`; zapis → snackbar; błąd → snackbar, brak czerwonego ekranu.
- [ ] **Edycja** — zmiana pól i zapis; `editedAt` / `editedBy` jeśli reguły na to pozwalają.
- [ ] **Soft delete** — potwierdzenie dialogiem; wpis znika z widoku domyślnego; z „Show deleted” widoczny + **Restore** przywraca.
- [ ] **Brak workspace’ów** — sensowny komunikat („This employee has no workspaces”) i brak crasha przy dodawaniu wpisu.

## Live status (mobile ↔ web)

- [ ] **Start timera na mobile** → na web badge **Working** (`timerState` = running).
- [ ] **Pause** → **Paused**.
- [ ] **Stop** → **Online** (idle + świeży heartbeat) lub **Offline** zgodnie z `lastSeen` / `isOnline` (patrz `TECHNICAL.md`).

## Dashboard i kwoty

- [ ] **Po stopie** — zaktualizowany **Estimated amount (month)** (zapisane `entries`, bez pełnego reloadu strony; ewentualnie do ~45 s lub po strumieniu/debounce).
- [ ] **Refresh data** — ponowne pobranie statystyk **bez** przeładowania strony; spinner na przycisku; **Last updated** aktualizuje się po każdym udanym odświeżeniu statystyk (także auto / stream entries).
- [ ] **Brak czerwonego ekranu** na dashboardzie przy typowym ładowaniu / błędzie streamu (komunikat inline / banner zamiast całej strony na czerwono).

## Stany brzegowe

- [ ] **Brak danych / empty** — brak pracowników, brak grup: sensowne empty states + CTA (Add / Create).
- [ ] **Brak wpisów w wybranym miesiącu** — godziny / kwoty „0” lub „—”, bez crasha.
- [ ] **Pracownik bez stawki** — **No rate** / brak kwoty przy live running; brak crasha przy raportach.
- [ ] **Unknown** — przy błędzie streamu live lub `isOnline: null` badge nie wywala UI (np. **Unknown**).

## Opcjonalnie

- [ ] Motyw: System / Light / Dark i persystencja po odświeżeniu.
- [ ] Eksport CSV z raportu — plik się pobiera.
