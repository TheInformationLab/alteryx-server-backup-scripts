# Tasks: Alteryx Server Backup Enhancement

**Input**: Design documents from `/specs/dev/backup-enhancement-prd/`  
**Prerequisites**: plan.md ✅, data-model.md ✅, contracts/ ✅, research.md ✅, quickstart.md ✅

**Tests**: Test tasks are included per constitutional requirement (Principle III: Testing Before Deployment)

**Organization**: Tasks are grouped by backup mode (user stories) to enable independent implementation and testing of each mode. Each mode represents a distinct operational capability that can be validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which backup mode/capability this task belongs to (US1, US2, US3)
- File paths use PowerShell script structure from plan.md

---

## Phase 1: Setup (Project Infrastructure)

**Purpose**: Initialize project structure and configuration

- [ ] T001 Create directory structure: `powershell/`, `config/`, `tests/unit/`, `tests/integration/`
- [ ] T002 Create default configuration file in `config/backup-config.json` with schema from data-model.md section 1.1
- [ ] T003 [P] Create example configuration file in `config/backup-config.example.json` with inline comments
- [ ] T004 [P] Install Pester testing framework: `Install-Module -Name Pester -Scope CurrentUser -Force`
- [ ] T005 Create `.gitignore` entries for backup archives, logs, and temp files

---

## Phase 2: Foundational (Core Infrastructure - BLOCKING)

**Purpose**: Core utilities and functions that ALL backup modes depend on

**⚠️ CRITICAL**: No backup mode implementation can begin until this phase is complete

- [ ] T006 Implement `Write-Log` function in `powershell/Invoke-AlteryxBackup.ps1` per contracts section 14
- [ ] T007 Implement `Initialize-BackupEnvironment` function per contracts section 1 (config loading, validation, privilege check)
- [ ] T008 [P] Implement multi-node detection logic in `Initialize-BackupEnvironment` (parse RuntimeSettings.xml Workers section)
- [ ] T009 [P] Implement MongoDB type detection logic in `Initialize-BackupEnvironment` (parse RuntimeSettings.xml ConnectionString)
- [ ] T010 Implement `Test-AlteryxServiceState` function per contracts section 2 (service state query, workflow detection)
- [ ] T011 Implement `Stop-AlteryxServiceSafely` function per contracts section 3 (workflow wait, timeout protection, multi-node sequencing)
- [ ] T012 Implement `Start-AlteryxServiceSafely` function per contracts section 4 (state verification, multi-node sequencing)
- [ ] T013 Create unit test for `Write-Log` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock file operations)
- [ ] T014 [P] Create unit test for `Initialize-BackupEnvironment` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock file reads, privilege checks)
- [ ] T015 [P] Create unit test for `Test-AlteryxServiceState` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock Get-Service, Get-Process)
- [ ] T016 [P] Create unit test for `Stop-AlteryxServiceSafely` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock service operations)
- [ ] T017 [P] Create unit test for `Start-AlteryxServiceSafely` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock service operations)

**Checkpoint**: Foundation ready - service management and configuration validated. Backup mode implementation can now proceed.

---

## Phase 3: User Story 1 - Full Backup Mode (Priority: P1) 🎯 MVP

**Goal**: Implement complete backup workflow - MongoDB + configuration files with service lifecycle management

**Independent Test**: Run `.\Invoke-AlteryxBackup.ps1 -BackupMode Full` and verify archive contains MongoDB dump + all config files from data-model.md section 4.2

### MongoDB Backup Implementation (US1)

- [ ] T018 [US1] Implement `Invoke-MongoDBBackup` function per contracts section 5 (embedded MongoDB via AlteryxService.exe emongodump)
- [ ] T019 [US1] Add embedded MongoDB command execution logic (research.md section 2 pattern)
- [ ] T020 [US1] Add MongoDB backup validation (verify .bson files, calculate size, count collections)
- [ ] T021 [US1] Create unit test for `Invoke-MongoDBBackup` (embedded mode) in `tests/unit/Invoke-AlteryxBackup.Tests.ps1`

### Configuration File Backup Implementation (US1)

- [ ] T022 [P] [US1] Implement `Backup-CriticalFiles` function per contracts section 6 (file registry iteration)
- [ ] T023 [P] [US1] Define CriticalFilesRegistry in script per data-model.md section 4.1 (RuntimeSettings.xml, Keys folder, SystemAlias.xml, etc.)
- [ ] T024 [US1] Add checksum calculation logic (SHA256) in `Backup-CriticalFiles`
- [ ] T025 [US1] Implement `Export-ControllerSettings` function per contracts section 7 (getserversecret, getemongopassword commands)
- [ ] T026 [P] [US1] Create unit test for `Backup-CriticalFiles` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock Copy-Item)
- [ ] T027 [P] [US1] Create unit test for `Export-ControllerSettings` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock external commands)

### Archive & Distribution Implementation (US1)

- [ ] T028 [US1] Implement `New-BackupManifest` function per contracts section 8 (aggregate metadata per data-model.md section 2.1)
- [ ] T029 [US1] Implement `Compress-BackupArchive` function per contracts section 9 (native Compress-Archive cmdlet)
- [ ] T030 [US1] Implement `Copy-BackupToDestinations` function per contracts section 10 (network copy with retry logic per research.md section 7)
- [ ] T031 [P] [US1] Create unit test for `New-BackupManifest` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (verify JSON structure)
- [ ] T032 [P] [US1] Create unit test for `Compress-BackupArchive` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock Compress-Archive)
- [ ] T033 [P] [US1] Create unit test for `Copy-BackupToDestinations` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock Copy-Item, test retry logic)

### Validation & Cleanup Implementation (US1)

- [ ] T034 [P] [US1] Implement `Test-BackupIntegrity` function per contracts section 11 (archive validation, checksum verification)
- [ ] T035 [P] [US1] Implement `Remove-OldBackups` function per contracts section 12 (retention policy per data-model.md section 1.1)
- [ ] T036 [US1] Implement `Write-BackupSummary` function per contracts section 13 (aggregate statistics, format output)
- [ ] T037 [P] [US1] Create unit test for `Test-BackupIntegrity` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock archive operations)
- [ ] T038 [P] [US1] Create unit test for `Remove-OldBackups` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock file deletion)
- [ ] T039 [P] [US1] Create unit test for `Write-BackupSummary` in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (verify output format)

### Full Backup Mode Orchestration (US1)

- [ ] T040 [US1] Implement main script entry point with parameter handling (`-BackupMode`, `-ConfigPath`, `-Verbose`)
- [ ] T041 [US1] Implement Full backup state machine per data-model.md section 8 (Initialize → StopService → BackupMongoDB → StartService → BackupFiles → Archive → Distribute → Validate → Cleanup → Complete)
- [ ] T042 [US1] Add error handling with rollback logic (restart service if stopped before error occurred)
- [ ] T043 [US1] Add exit codes per data-model.md section 6.2 (0-6 for monitoring integration)
- [ ] T044 [US1] Create integration test for Full mode in `tests/integration/FullBackup.Integration.Tests.ps1` (end-to-end with mocked external dependencies)

**Checkpoint**: Full backup mode complete and independently testable. This is the MVP - can deploy/validate before proceeding.

---

## Phase 4: User Story 2 - DatabaseOnly Backup Mode (Priority: P2)

**Goal**: Enable MongoDB-only backups without configuration files for frequent snapshots

**Independent Test**: Run `.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly` and verify archive contains ONLY MongoDB dump (no config files)

### DatabaseOnly Mode Implementation

- [ ] T045 [US2] Add DatabaseOnly mode conditional logic in main orchestration (skip file backup functions)
- [ ] T046 [US2] Implement DatabaseOnly state machine (Initialize → StopService → BackupMongoDB → StartService → Archive → Distribute → Validate → Cleanup → Complete)
- [ ] T047 [US2] Update archive naming for DatabaseOnly mode: `ServerBackup_DB_YYYYMMDD_HHmmss.zip`
- [ ] T048 [US2] Update manifest generation for DatabaseOnly (set MongoDBInformation.Included=true, BackedUpFiles=empty per data-model.md section 2.2)
- [ ] T049 [US2] Update retention policy logic for DatabaseOnly (14 days default per research.md section 6)
- [ ] T050 [US2] Create integration test for DatabaseOnly mode in `tests/integration/DatabaseOnly.Integration.Tests.ps1` (verify no config files in archive)

**Checkpoint**: DatabaseOnly mode complete and independently testable. Both Full and DatabaseOnly modes should work without interference.

---

## Phase 5: User Story 3 - ConfigOnly Backup Mode (Priority: P3)

**Goal**: Enable configuration-only backups without service stop for zero-downtime config changes

**Independent Test**: Run `.\Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly` with service running and verify no service interruption

### ConfigOnly Mode Implementation

- [ ] T051 [US3] Add ConfigOnly mode conditional logic in main orchestration (skip service stop/start, skip MongoDB backup)
- [ ] T052 [US3] Implement ConfigOnly state machine (Initialize → BackupFiles → Archive → Distribute → Validate → Cleanup → Complete - no service operations)
- [ ] T053 [US3] Update archive naming for ConfigOnly mode: `ServerBackup_Config_YYYYMMDD_HHmmss.zip`
- [ ] T054 [US3] Update manifest generation for ConfigOnly (set MongoDBInformation.Included=false, add ServiceNotStopped note per data-model.md section 2.2)
- [ ] T055 [US3] Update retention policy logic for ConfigOnly (30 days default per research.md section 6)
- [ ] T056 [US3] Create integration test for ConfigOnly mode in `tests/integration/ConfigOnly.Integration.Tests.ps1` (verify service never stopped)

**Checkpoint**: All three backup modes independently functional. Core feature complete.

---

## Phase 6: Self-Managed MongoDB Support (Priority: P2)

**Goal**: Add support for self-managed MongoDB deployments using mongodump command

**Independent Test**: Configure self-managed MongoDB connection string in RuntimeSettings.xml and run Full backup

### Self-Managed MongoDB Implementation

- [ ] T057 Add self-managed MongoDB detection in `Initialize-BackupEnvironment` (parse connection string per research.md section 2)
- [ ] T058 Add self-managed MongoDB backup path in `Invoke-MongoDBBackup` (mongodump with --host, --port, --db, --gzip flags)
- [ ] T059 Add authentication handling for self-managed MongoDB (SecureString password, --username, --authenticationDatabase parameters)
- [ ] T060 Add configuration schema support for self-managed MongoDB in config file (data-model.md section 1.1 MongoDBConfiguration.SelfManagedMongoDB)
- [ ] T061 Update quickstart.md with self-managed MongoDB setup examples
- [ ] T062 Create unit test for self-managed MongoDB backup path in `tests/unit/Invoke-AlteryxBackup.Tests.ps1` (mock mongodump command)
- [ ] T063 Create integration test for self-managed MongoDB in `tests/integration/SelfManagedMongoDB.Integration.Tests.ps1` (requires test MongoDB instance)

**Checkpoint**: Both embedded and self-managed MongoDB deployments supported.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final refinements and documentation

- [ ] T064 [P] Add `-Help` parameter with usage documentation (quickstart.md patterns)
- [ ] T065 [P] Add verbose logging throughout all functions (Write-Log with DEBUG level)
- [ ] T066 Add comment-based help at script top (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` blocks)
- [ ] T067 Create migration guide from batch scripts in `docs/migration-guide.md`
- [ ] T068 Create operator troubleshooting guide in `docs/troubleshooting.md`
- [ ] T069 Update main README.md with PowerShell script usage and examples
- [ ] T070 [P] Code review and refactoring for PowerShell best practices
- [ ] T071 [P] Performance testing with large MongoDB databases (>50GB)
- [ ] T072 Validate all examples in quickstart.md execute successfully
- [ ] T073 Create Windows Task Scheduler XML templates for all three backup modes in `config/scheduled-tasks/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all backup mode implementations
- **User Story 1 - Full Backup (Phase 3)**: Depends on Foundational completion
  - This is the MVP - most complex mode, establishes all patterns
- **User Story 2 - DatabaseOnly (Phase 4)**: Depends on Foundational + Full backup completion
  - Reuses MongoDB backup functions from US1
  - Simplifies orchestration by skipping file backup
- **User Story 3 - ConfigOnly (Phase 5)**: Depends on Foundational + Full backup completion
  - Reuses file backup functions from US1
  - Simplifies orchestration by skipping service management
- **Self-Managed MongoDB (Phase 6)**: Depends on Full backup completion
  - Extends Invoke-MongoDBBackup with additional backup path
- **Polish (Phase 7)**: Depends on all desired features being complete

### User Story Dependencies

- **Full Backup (US1)**: Can start after Foundational phase - No dependencies on other modes
- **DatabaseOnly (US2)**: Depends on Foundational + MongoDB backup function from US1
- **ConfigOnly (US3)**: Depends on Foundational + file backup functions from US1
- **Self-Managed MongoDB**: Extends US1, US2 capabilities

### Within Each User Story

**User Story 1 (Full Backup)**:
1. MongoDB backup functions first (T018-T021)
2. File backup functions in parallel (T022-T027)
3. Archive & distribution functions (T028-T033)
4. Validation & cleanup functions in parallel (T034-T039)
5. Orchestration and integration (T040-T044)

**User Story 2 (DatabaseOnly)**:
- Reuses MongoDB backup from US1
- Adds mode-specific orchestration (T045-T050)

**User Story 3 (ConfigOnly)**:
- Reuses file backup from US1
- Adds mode-specific orchestration (T051-T056)

### Parallel Opportunities

**Phase 1 (Setup)**:
- T003 and T004 can run in parallel (example config, Pester install)

**Phase 2 (Foundational)**:
- T008 and T009 can run in parallel (multi-node detection, MongoDB type detection - both in Initialize-BackupEnvironment)
- T013-T017 tests can all run in parallel (different test contexts)

**Phase 3 (US1)**:
- T022 and T023 can run in parallel (Backup-CriticalFiles function, CriticalFilesRegistry definition)
- T026 and T027 tests can run in parallel (different functions)
- T031, T032, T033 tests can run in parallel (different functions)
- T034 and T035 can run in parallel (Test-BackupIntegrity, Remove-OldBackups - different concerns)
- T037, T038, T039 tests can run in parallel (different functions)

**Phase 7 (Polish)**:
- T064 and T065 can run in parallel (help parameter, verbose logging)
- T070 and T071 can run in parallel (code review, performance testing)

---

## Parallel Example: User Story 1 - File Backup Functions

```bash
# Launch file backup functions in parallel:
Task: "Implement Backup-CriticalFiles function in powershell/Invoke-AlteryxBackup.ps1"
Task: "Define CriticalFilesRegistry in powershell/Invoke-AlteryxBackup.ps1"

# Then launch their tests in parallel:
Task: "Create unit test for Backup-CriticalFiles in tests/unit/"
Task: "Create unit test for Export-ControllerSettings in tests/unit/"
```

---

## Parallel Example: Phase 2 - Foundation Tests

```bash
# All foundational unit tests can run in parallel:
Task: "Create unit test for Write-Log"
Task: "Create unit test for Initialize-BackupEnvironment"
Task: "Create unit test for Test-AlteryxServiceState"
Task: "Create unit test for Stop-AlteryxServiceSafely"
Task: "Create unit test for Start-AlteryxServiceSafely"
```

---

## Implementation Strategy

### MVP First (Full Backup Mode Only)

1. Complete Phase 1: Setup → Project structure ready
2. Complete Phase 2: Foundational → Core utilities validated
3. Complete Phase 3: User Story 1 (Full Backup) → Complete operational script
4. **STOP and VALIDATE**: 
   - Run Full backup on test server
   - Verify all files captured per data-model.md section 4.2
   - Test restore procedure with backup archive
   - Validate service lifecycle management
5. Deploy Full backup mode to production (MVP complete!)

### Incremental Delivery

1. Phase 1 + 2 → Foundation ready (utilities, service management)
2. Phase 3 → Full Backup Mode operational (MVP! Most common use case)
3. Phase 4 → DatabaseOnly Mode operational (frequent snapshot capability added)
4. Phase 5 → ConfigOnly Mode operational (zero-downtime config backups added)
5. Phase 6 → Self-Managed MongoDB support (broader deployment compatibility)
6. Phase 7 → Polish (production-ready with all docs and templates)

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (critical shared infrastructure)
2. Once Foundational is done:
   - **Developer A**: User Story 1 (Full Backup) - priority focus
   - **Developer B**: Can start on self-managed MongoDB research/prototyping (Phase 6)
   - **Developer C**: Can prepare documentation templates (Phase 7)
3. After US1 complete:
   - **Developer A**: User Story 2 (DatabaseOnly)
   - **Developer B**: User Story 3 (ConfigOnly)
   - **Developer C**: Self-managed MongoDB integration
4. Final polish and integration together

---

## Task Counts & Metrics

### Total Tasks: 73

**By Phase**:
- Phase 1 (Setup): 5 tasks
- Phase 2 (Foundational): 12 tasks (includes 5 unit tests)
- Phase 3 (US1 - Full Backup): 27 tasks (includes 12 unit tests + 1 integration test)
- Phase 4 (US2 - DatabaseOnly): 6 tasks (includes 1 integration test)
- Phase 5 (US3 - ConfigOnly): 6 tasks (includes 1 integration test)
- Phase 6 (Self-Managed MongoDB): 7 tasks (includes 2 tests)
- Phase 7 (Polish): 10 tasks

**By Category**:
- Infrastructure/Setup: 5 tasks
- Core Implementation: 37 tasks
- Unit Tests: 17 tasks
- Integration Tests: 4 tasks
- Documentation/Polish: 10 tasks

**Parallel Opportunities**: 23 tasks marked [P] can run in parallel (31.5% of tasks)

### Test Coverage

- **Unit Tests**: 17 tasks covering all 14 core functions from contracts
- **Integration Tests**: 4 tasks covering all 3 backup modes + self-managed MongoDB
- **Test-Driven Development**: Tests created alongside or before implementation per constitution principle III

### MVP Scope

**MVP = Phase 1 + Phase 2 + Phase 3 = 44 tasks (60% of total)**

This delivers a fully functional Full Backup mode with:
- ✅ Service lifecycle management
- ✅ Embedded MongoDB backup
- ✅ All critical configuration files
- ✅ Network distribution
- ✅ Validation and retention
- ✅ Comprehensive logging
- ✅ Unit and integration tests

**Post-MVP enhancements add 29 additional tasks (40%) for**:
- DatabaseOnly mode (frequent snapshots)
- ConfigOnly mode (zero-downtime config backups)
- Self-managed MongoDB support
- Documentation and polish

---

## Format Validation

✅ **All tasks follow checklist format**: `- [ ] [TaskID] [P?] [Story?] Description with file path`

**Format Compliance**:
- ✅ Every task starts with `- [ ]` (markdown checkbox)
- ✅ Every task has sequential Task ID (T001-T073)
- ✅ [P] marker only on parallelizable tasks (23 tasks)
- ✅ [Story] label on user story tasks only (US1: 27 tasks, US2: 6 tasks, US3: 6 tasks)
- ✅ No story labels on Setup, Foundational, or Polish phases
- ✅ Every task includes specific file paths or clear action descriptions
- ✅ Tasks organized by user story for independent implementation

---

## Notes

- Tasks follow operational script patterns (single PowerShell file, not web app structure)
- Test tasks included per constitutional requirement (Principle III)
- Backup modes treated as "user stories" for independent implementation
- Service management functions are foundational (block all modes)
- File paths reflect PowerShell script structure from plan.md
- Integration tests require non-production Alteryx Server for validation
- Self-managed MongoDB tests require test MongoDB instance setup
- Constitutional compliance maintained throughout (reliability, testing, modularity)
