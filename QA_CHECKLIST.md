# QA checklist — employer panel (MVP)

Krótka lista regresji przed demo / portfolio. Zakłada działający Firebase (Auth + Firestore) i zdeployowaną mobilkę zapisującą dane zgodnie z [`DATA_CONTRACT.md`](DATA_CONTRACT.md).

## Auth i pracownicy

- [ ] **Logowanie employer** — email/hasło, po zalogowaniu shell (sidebar + treść).
- [ ] **Dodanie pracownika po e-mailu** — poprawna domena + firma/slug; sukces → wpis na liście; błąd → czytelny komunikat („Employee not found” gdy brak indeksu).
- [ ] **Profil pracownika** — wejście w szczegóły z listy: nazwa, firma, grupy, presence, ostatnia aktywność, karty projektów.

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
