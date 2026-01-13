# Implementation Plan: Alteryx Server Backup Process Enhancement

**Branch**: `dev/backup-enhancement-prd` | **Date**: 2026-01-13 | **Spec**: [PRD-Backup-Process-Enhancement.md](../../../PRD-Backup-Process-Enhancement.md)
**Input**: Feature specification from PRD-Backup-Process-Enhancement.md and TODO.md

**Note**: This plan implements modular backup modes (Full, DatabaseOnly, ConfigOnly) for Alteryx Server with support for both embedded and self-managed MongoDB.

## Summary

Modernize Alteryx Server backup automation by migrating from batch scripts to PowerShell with native cmdlets. Implement three backup modes: Full (MongoDB + config files), DatabaseOnly (MongoDB only, service stop required), and ConfigOnly (config files only, no service interruption). Support both embedded MongoDB via `AlteryxService.exe emongodump` and self-managed MongoDB via `mongodump`. Achieve 100% coverage of Alteryx-recommended critical files, eliminate external dependencies (7-Zip, WMIC), and enable network/cloud storage destinations with comprehensive validation and logging.

## Technical Context

**Language/Version**: PowerShell 5.1+ (Windows PowerShell for Server 2016+ compatibility)  
**Primary Dependencies**: 
- Native: `Compress-Archive`, `Get-Service`, `Copy-Item`, `Get-CimInstance`
- External: `AlteryxService.exe` (Alteryx Server binary)
- Optional: `mongodump` (only for self-managed MongoDB)

**Storage**: 
- File-based backup archives (.zip format)
- Temp staging directory (default: D:\Temp)
- Local backup storage (default: D:\Alteryx\Backups)
- Optional: Network UNC paths, mapped drives, S3/Azure (future)

**Testing**: Pester framework for unit tests, manual integration testing on non-production Alteryx Server  
**Target Platform**: Windows Server 2016+ with Alteryx Server 2020.1+  
**Project Type**: Operational automation scripts (standalone PowerShell scripts)  

**Performance Goals**: 
- Full backup: Complete within scheduled maintenance window (typically 2-6 hours depending on MongoDB size)
- DatabaseOnly backup: < 30 minutes for typical MongoDB size (< 10GB)
- ConfigOnly backup: < 2 minutes (no large data transfers)
- Archive compression: Native `Compress-Archive` performance acceptable (no performance SLA)

**Constraints**: 
- Must run as Administrator (service management required)
- Service downtime required for Full and DatabaseOnly modes (not ConfigOnly)
- **Downtime minimized**: Service restarts immediately after MongoDB backup (~15-30min downtime)
- MongoDB backup size determines temp disk space requirements (2x size minimum)
- Backup mode selection determines scope and service impact
- Cannot interrupt active workflows without timeout (default 7200s)

**Scale/Scope**: 
- Single Alteryx Server instance (multi-node support via detection)
- MongoDB databases: 1GB-50GB typical, up to 500GB edge cases
- Configuration files: ~20 files/folders, total < 100MB
- Backup frequency: Nightly Full, 4-hour DatabaseOnly, ad-hoc ConfigOnly
- Retention: 30 days Full, 7 days DatabaseOnly, 14 days ConfigOnly (configurable)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Reliability & Data Safety ✅
**Status**: PASS  
**Verification**:
- Backup modes clearly defined with service impact documented (ConfigOnly = no interruption)
- Pre-backup validation required (disk space, paths, privileges)
- Post-backup integrity checks mandated (checksums, archive validation)
- Service state verification with timeout protection in requirements
- Rollback logic specified for service management failures
- MongoDB backup validation per Alteryx official guidance included

### II. Documentation & Maintainability ✅
**Status**: PASS  
**Verification**:
- All parameters documented with examples in PRD
- Configuration file schema provided with comments
- Help text (`-Help` switch) requirement specified
- Use case scenarios documented for each backup mode
- Inline documentation requirements captured
- Migration guide from batch scripts planned

### III. Testing Before Deployment ✅
**Status**: PASS  
**Verification**:
- Unit testing with Pester framework required (Phase 1)
- Integration testing on non-production server required (Phase 2)
- Test restore procedures for each backup mode mandatory (Phase 2)
- Scheduled task testing specified (Phase 2)
- Pilot deployment phase with parallel batch/PowerShell execution (Phase 5)
- 30-day monitoring period before full rollout

### IV. Modularity & Separation of Concerns ✅
**Status**: PASS  
**Verification**:
- Single script with clearly defined functions for each concern
- Service management functions separated
- MongoDB backup logic isolated
- File backup operations distinct
- Validation functions independent
- Logging utilities reusable
- Optional module structure for future enhancement documented

### V. Operational Excellence ✅
**Status**: PASS  
**Verification**:
- Comprehensive logging requirements (start, operations, errors, completion)
- ISO 8601 timestamp format specified
- Log levels defined (DEBUG, INFO, WARNING, ERROR, SUCCESS)
- Exit codes standardized (0-6 with specific meanings)
- Backup manifest with metadata required
- Mode-specific log filenames for tracking
- Metrics capture (size, duration, file counts)

### Operational Requirements Compliance ✅
**Status**: PASS  
**Verification**:
- All paths/timeouts configurable via parameters or config file
- Service state verification before/after operations required
- Workflow completion check before service stop
- MongoDB dump completion verification specified
- Archive validation before cleanup mandated
- Network copy verification included

### Security Requirements ✅
**Status**: PASS  
**Verification**:
- Administrator privilege validation required
- SecureString for MongoDB passwords specified
- No credential logging in requirements
- SSL thumbprint validation for certificate operations (existing script)
- Sensitive data handling documented

**GATE STATUS**: ✅ **PASS** - All constitutional principles satisfied. Proceed to Phase 0.

---

## Phase 0: Research Complete ✅

All technical unknowns have been researched and documented in [research.md](research.md):

1. ✅ Multi-node detection strategy via RuntimeSettings.xml parsing
2. ✅ MongoDB type detection from connection string analysis
3. ✅ Encryption key backup documented as manual process per Alteryx guidance
4. ✅ Compress-Archive performance benchmarked and deemed acceptable
5. ✅ ConfigOnly mode service handling - skip stop/start operations
6. ✅ Retention policies designed with separate periods per backup mode
7. ✅ Network retry logic with exponential backoff (3 retries, 30s base)
8. ✅ MongoDB backup commands differentiated for embedded vs self-managed
9. ✅ Pester testing framework selected with mocking strategy
10. ✅ Windows Task Scheduler integration with SYSTEM account and exit codes

**Status**: All blockers resolved. No NEEDS CLARIFICATION items remaining.

---

## Phase 1: Design & Contracts Complete ✅

Design artifacts generated:

1. ✅ **Data Model** ([data-model.md](data-model.md)):
   - Configuration schema (JSON + PowerShell objects)
   - Backup manifest structure with mode variations
   - Operational state models (service state, multi-node info, execution state)
   - File mapping registry per backup mode
   - Pre/post validation checklists
   - Enumerations for type safety
   - State machine for execution flow

2. ✅ **Function Contracts** ([contracts/function-contracts.md](contracts/function-contracts.md)):
   - 14 core function signatures with full specifications
   - Input/output types aligned with data model
   - Error conditions and side effects documented
   - Behavior descriptions for each function

3. ✅ **Quickstart Guide** ([quickstart.md](quickstart.md)):
   - Basic usage examples for all three backup modes
   - Configuration file setup
   - Common scenarios (first-time setup, scheduled tasks, pre-upgrade)
   - Self-managed MongoDB configuration
   - Troubleshooting guide
   - Backup mode comparison matrix

4. ✅ **Agent Context Updated**:
   - GitHub Copilot instructions updated with PowerShell 5.1+ context
   - Project type: Operational automation scripts

**Status**: Design complete and validated against constitution.

---

## Post-Design Constitution Re-Check ✅

### I. Reliability & Data Safety ✅
**Validation**:
- Pre/post validation checklists defined in data model (section 5)
- Service state verification patterns in function contracts
- Rollback logic specified in Stop-AlteryxServiceSafely contract
- MongoDB backup validation in Invoke-MongoDBBackup contract
- Archive integrity testing in Test-BackupIntegrity contract
- Manifest includes checksums and validation results

**Verdict**: ✅ PASS - Defensive programming patterns embedded in design

### II. Documentation & Maintainability ✅
**Validation**:
- Comprehensive function contracts with behavior descriptions
- Quickstart guide with common scenarios
- Configuration schema fully documented
- Inline documentation requirements captured in contracts
- Parameter descriptions in all function signatures
- Help text pattern specified in quickstart

**Verdict**: ✅ PASS - Documentation-first approach evident throughout

### III. Testing Before Deployment ✅
**Validation**:
- Pester testing framework selected (research.md section 9)
- Mocking strategy defined for external dependencies
- Unit test structure specified (tests/unit/, tests/integration/)
- Integration testing approach documented
- Test restore procedures in quickstart guide

**Verdict**: ✅ PASS - Testing strategy comprehensive and practical

### IV. Modularity & Separation of Concerns ✅
**Validation**:
- 14 distinct functions with single responsibilities
- Service management separated from backup operations
- MongoDB backup isolated from file backup
- Validation functions independent
- Logging utilities reusable
- Clear function boundaries in contracts

**Verdict**: ✅ PASS - Modular design maintained

### V. Operational Excellence ✅
**Validation**:
- Write-Log function contract with timestamp and level support
- Backup manifest captures comprehensive metadata
- Exit codes standardized (0-6 with specific meanings)
- Log file naming includes backup mode
- Execution state tracking in data model (section 3.3)
- Summary report generation specified

**Verdict**: ✅ PASS - Operational requirements met

**FINAL GATE STATUS**: ✅ **PASS** - Design maintains full constitutional compliance. Ready for implementation.

## Project Structure

### Documentation (this feature)

```text
specs/dev/backup-enhancement-prd/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Technology decisions and patterns
├── data-model.md        # Phase 1 output - Backup entities and configurations
├── quickstart.md        # Phase 1 output - Quick start guide for operators
├── contracts/           # Phase 1 output - Configuration schema, function signatures
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Operational scripts structure (single project)
powershell/
├── Invoke-AlteryxBackup.ps1      # Main backup orchestration script
├── archive-logs.ps1               # Existing log archival script
├── update-ssl-key.ps1             # Existing SSL certificate script
├── test-update-ssl-key.ps1        # Existing SSL test script
└── Modules/                       # Future enhancement: modular functions
    ├── AlteryxService.psm1        # Service management functions
    ├── MongoDBBackup.psm1         # MongoDB backup functions
    ├── FileBackup.psm1            # File copy/archive functions
    ├── Validation.psm1            # Pre/post validation functions
    └── Logger.psm1                # Logging utilities

config/
├── backup-config.json             # Default configuration
└── backup-config.example.json     # Example with comments

tests/
├── unit/
│   ├── Invoke-AlteryxBackup.Tests.ps1
│   ├── ServiceManagement.Tests.ps1
│   ├── MongoDBBackup.Tests.ps1
│   └── FileBackup.Tests.ps1
└── integration/
    ├── FullBackup.Integration.Tests.ps1
    ├── DatabaseOnly.Integration.Tests.ps1
    └── ConfigOnly.Integration.Tests.ps1

batch-scripts/
├── Alteryx-backup.bat             # Existing batch script (to be deprecated)
├── Alteryx-backups-and-logs-cleanup.bat
└── Alteryx-log-mover.bat
```

**Structure Decision**: Single operational scripts project. Functions will be defined within the main script initially, with optional modularization into `.psm1` modules as a future Phase 7 enhancement. This maintains simplicity while supporting the constitutional principle of modularity through clear function boundaries.

## Complexity Tracking

**No violations detected.** All constitutional principles are satisfied without requiring exceptions or complexity justifications. The design follows operational script best practices with clear modularity through function separation.
