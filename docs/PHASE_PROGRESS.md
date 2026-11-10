# FloodRelief — Phase Progress

_Last updated: 2026-11-10_

This project is developed in phases. The list below reflects what is actually
implemented and verified in the repository, not a roadmap wish-list. A phase is
only marked **Complete** when `flutter analyze` is clean and the related tests
pass.

## Status at a glance

| Phase | Name | State |
| --- | --- | --- |
| 1 | Foundation: models, storage, device identity | Complete |
| 2 | SOS creation, priority engine, offline persistence | Complete |
| 3 | Bluetooth mesh: packets, routing, acknowledgements | Complete (simulated mesh verified) |
| 4 | Rescue operations: dashboard, assignment, status lifecycle | Complete |
| 5 | Field modules: flood reports, help requests, shelters, contacts, alerts | Complete |
| 6 | Rescue team registry + operator identity | Complete |
| 7 | Production readiness / verification | In progress |
| 8 | Physical multi-device BLE validation | Pending |

**Overall completion: ~85%.** The remaining 15% is hardware verification and
optional integrations, not missing core screens.

## Phase details

### Phase 4 — Rescue operations (complete)

- Rescue operator sign-in selects a registered team.
- Dashboard lists every SOS with priority, status, affected-people counts,
  filtering (All / Active / My team / Pending / Acknowledged / In progress),
  sorting (newest / highest priority) and a team availability strip.
- SOS details supports the full status machine:
  `Pending → Acknowledged → Rescue Assigned → In Progress → Resolved`.
- Assignment records the chosen team. The assigned team is preserved through
  start and resolve, so the audit trail never loses who responded.
- The signed-in operator's real team is recorded on acknowledgement, start and
  resolve (no hard-coded placeholder in the audit history).
- A timeline shows every transition with actor, team and note.

### Phase 6 — Rescue team registry (complete)

- `RescueTeamService` validates and persists teams.
- `RescueTeamsScreen` supports add, edit and availability changes
  (Available / Responding / In the field / Unavailable).
- Teams are reachable from the rescue dashboard, Settings → Rescue operations,
  and the empty rescue-login state.
- A fresh install can register a team and sign in as an operator without any
  seeded demo data.
- Team IDs follow `TEAM-XXXXXX` and `RescueTeam` equality is by `teamId`.

### Phase 7 — Production readiness (in progress)

Done:

- Analytic-clean codebase (`flutter analyze`).
- Unit + widget test coverage for the SOS lifecycle across both roles.
- Repository injection at bootstrap so widget tests never block on Hive I/O.
- Honest empty/loading/error states on every list screen.
- Startup failure surfaces (`StartupErrorApp`, `BootGate` retry).

Remaining:

- Run the full test suite in CI on every change.
- Verify the app on a physical Android device (permissions, GPS accuracy,
  battery use during a scan).
- Decide whether the optional backend sync contract is in scope for this
  release.

### Phase 8 — Physical multi-device BLE (pending)

The routing, dedupe and acknowledgement logic is exercised through the
simulated mesh. Relaying an SOS between two real phones has not been verified on
physical hardware and must not be claimed as production-proven until it is.
