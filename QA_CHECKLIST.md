# QA checklist — employer panel (MVP)

Krótka lista regresji przed releasem lub demo. Zakłada działający Firebase (Auth + Firestore) i zdeployowaną mobilkę zapisującą dane zgodnie z [`DATA_CONTRACT.md`](DATA_CONTRACT.md).

## Grupy (panel)

- [ ] **Zakładka Groups** — lista grup z rozwinięciem, liczba pracowników, **Manage members** (checkboxy), rename, delete z dialogiem (tekst: usuwanie nie kasuje pracowników ani wpisów; checkbox „Remove this group from employees” domyślnie włączony).
- [ ] **Ungrouped** — pracownicy z `trackedWorkspaces` bez ważnego przypisania do istniejącej grupy; pusty stan: „All employees are assigned to groups”.
- [ ] **Widoczność w grupach** — pracownik bez żadnego `trackedWorkspaces` nie pojawia się w sekcjach grup / Ungrouped na ekranie Groups (organizer respektuje realny zakres dostępu).
- [ ] **Employees — filtr Group** — All groups / Ungrouped / konkretna grupa; nie zmienia dostępu do danych (tylko lista UI).
- [ ] **Duplikat nazwy grupy** (case-insensitive) — komunikat przy create/rename.
- [ ] **Przypisanie z arkusza „Assign groups”** (szczegóły pracownika) — zapis `groupIds` z odfiltrowaniem nieistniejących id grup.

## Auth i pracownicy

- [ ] **Logowanie employer** — email/hasło, po zalogowaniu shell (sidebar + treść).
- [ ] **Dodanie pracownika po work email** — ten sam adres co na udostępnionym workspace w mobile; domena konta pracodawcy musi pasować; sukces → wpis na liście; brak `employeeWorkEmailIndex` → *No shared workspace found for this work email.*; brak pasujących workspace’ów → komunikaty z `EmployerLinkException` (m.in. *No shared workspace for your company domain.*).
- [ ] **Profil pracownika** — wejście w szczegóły z listy: nazwa, firma, grupy, presence, ostatnia aktywność (tylko wpisy z **udostępnionych** workspace’ów), karty projektów tylko z **`trackedWorkspaces`**.

## Timesheet (szczegóły pracownika)

- [ ] **Miesiąc** — przełącznik miesiąca ładuje wpisy z `users/{uid}/entries` (stream); loading / empty („No entries in this month”).
- [ ] **Filtry** — workspace, typ wpisu, billable, „Show deleted”, wyszukiwarka po tytule zadania / notatce; pusty wynik → „No entries match current filters”.
- [ ] **Sortowanie** — newest / oldest / duration / amount działa bez przeładowania strony.
- [ ] **Kwota** — przy braku `hourlyRate` lub workspace: „No rate” / „—”; tooltip z powodem; breakdown typu `8h × 50 PLN × 80% = 320 PLN` gdy dane kompletne.
- [ ] **Podsumowanie** — suma czasu, billable / non-billable, szacunek po walutach, breakdown po `entryType` i `billingRatePercent`.
- [ ] **Dodaj wpis** — formularz (workspace, data, start/end, typ, %, billable, task, note); walidacja `start < end`; zapis → snackbar; błąd → snackbar, brak czerwonego ekranu.
- [ ] **Edycja** — zmiana pól i zapis; `editedAt` / `editedBy` jeśli reguły na to pozwalają.
- [ ] **Soft delete** — potwierdzenie dialogiem; wpis znika z widoku domyślnego; z „Show deleted” widoczny + **Restore** przywraca.
- [ ] **Brak workspace’ów** — komunikat *No shared workspaces available for this employee.* i brak crasha przy dodawaniu wpisu.

## Udostępnione workspace’y (`trackedWorkspaces`)

- [ ] **Dwóch pracodawców / dwie firmy** — employer A widzi tylko workspace A, employer B tylko B (wpisy i sumy się nie mieszają).
- [ ] **Prywatny workspace** — nie widać na liście projektów; wpisy z niego nie wchodzą w godziny / kwoty / last activity.
- [ ] **CRUD** — picker workspace’ów tylko z udostępnionych; próba zapisu do innego workspace (np. manipulacja) kończy się błędem z serwisu / reguł.
- [ ] **Live running** — przy timerze na **niedostępnym** `activeWorkspaceId` brak kwoty w „Live running (est.)”; przy timerze na udostępnionym — kwota zgodna ze stawką.
- [ ] **Po rebuildzie danych** — lista projektów i sumy na dashboardzie odzwierciedlają aktualne `trackedWorkspaces` (bez pełnego reinstall).

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

## Ustawienia

- [ ] **Rebuild workspace access** — przycisk w Settings uruchamia migrację ręczną; po wykonaniu widoczny komunikat z wynikiem lub błędem.

## Opcjonalnie

- [ ] Motyw: System / Light / Dark i persystencja po odświeżeniu.
- [ ] Eksport CSV z raportu — plik się pobiera.
