# Product Requirements Document: Alteryx Server Backup Process Enhancement

**Version:** 1.0  
**Date:** January 13, 2026  
**Status:** Draft  
**Author:** System Architecture Team  

---

## Executive Summary

This PRD outlines requirements for modernizing the Alteryx Server backup automation by migrating from batch scripts to PowerShell, implementing official Alteryx backup best practices, and adding support for self-managed MongoDB deployments alongside the embedded MongoDB solution. The enhanced solution will support modular backup execution, allowing operators to backup database and configuration files independently or together.

---

## Background

### Current State
- Batch-based backup automation (Alteryx-backup.bat v2.1 from 2021)
- Supports only embedded MongoDB backups via `emongodump` command
- Backs up core config files: RuntimeSettings.xml, SystemAlias.xml, SystemConnections.xml, ControllerToken
- Uses 7-Zip external dependency for compression
- Local-only backup storage (D:\Alteryx\Backups\)
- WMIC-based date formatting (deprecated in Windows 11+)
- Monolithic backup process (all-or-nothing approach)

### Problem Statement
1. Current backup process is incomplete per Alteryx official best practices
2. No support for self-managed MongoDB deployments
3. Batch script limitations (error handling, logging, maintainability)
4. Missing critical files from backup scope per Alteryx documentation
5. No remote storage integration (network shares, S3)
6. External dependencies (7-Zip, WMIC) create maintenance burden
7. Cannot backup database or configuration files independently for specific scenarios

---

## Goals & Objectives

### Primary Goals
1. **Compliance**: Align backup process with Alteryx official best practices
2. **Modernization**: Migrate to PowerShell with native cmdlets
3. **Coverage**: Support both embedded and self-managed MongoDB
4. **Flexibility**: Enable modular backup execution (DB-only, config-only, or full)
5. **Reliability**: Improve error handling, validation, and recovery
6. **Extensibility**: Enable multiple storage destinations (local, network, cloud)

### Success Metrics
- 100% coverage of Alteryx-recommended critical files
- Automated backup verification and integrity checks
- Zero external dependencies (remove 7-Zip, WMIC)
- Support for both MongoDB deployment types
- Modular execution options validated and documented
- Comprehensive error reporting and alerting capability
- Backward compatibility with existing scheduled tasks

---

## Requirements

### 1. Backup Mode Requirements

#### 1.1 Backup Execution Modes
**Priority:** P0 (Must Have)

- **REQ-1.1.1**: Support `-BackupMode` parameter with values:
  - `Full` (default): Backup MongoDB + all configuration files
  - `DatabaseOnly`: Backup only MongoDB database
  - `ConfigOnly`: Backup only configuration files (no MongoDB, no service stop)
  
- **REQ-1.1.2**: In `DatabaseOnly` mode:
  - Stop AlteryxService
  - Backup MongoDB only
  - Restart AlteryxService
  - Skip all file backups
  
- **REQ-1.1.3**: In `ConfigOnly` mode:
  - Skip service stop/start operations
  - Backup all critical files (RuntimeSettings.xml, Keys, etc.)
  - Export Controller settings (token, passwords)
  - Service remains running throughout
  
- **REQ-1.1.4**: In `Full` mode:
  - Execute complete backup workflow (current behavior)
  - Stop service → Backup MongoDB → Backup files → Restart service
  
- **REQ-1.1.5**: Archive naming convention reflects backup mode:
  - Full: `ServerBackup_Full_YYYYMMDD_HHmmss.zip`
  - DatabaseOnly: `ServerBackup_DB_YYYYMMDD_HHmmss.zip`
  - ConfigOnly: `ServerBackup_Config_YYYYMMDD_HHmmss.zip`

**Use Cases:**
- **DatabaseOnly**: Frequent DB-only backups between full backups (e.g., hourly DB snapshots)
- **ConfigOnly**: After configuration changes without DB impact (e.g., SSL updates, worker config changes)
- **Full**: Standard comprehensive backup (e.g., nightly scheduled backup)

### 2. MongoDB Backup Requirements

#### 2.1 Embedded MongoDB (Current)
**Priority:** P0 (Must Have)

- **REQ-2.1.1**: Continue support for embedded MongoDB using `AlteryxService.exe emongodump` command
- **REQ-2.1.2**: Backup location must be configurable via parameter or config file
- **REQ-2.1.3**: Implement proper service shutdown sequence per Alteryx docs:
  1. Stop Server UI node (if multi-node)
  2. Stop Worker nodes (if multi-node)
  3. Stop Controller node last
- **REQ-2.1.4**: Implement reverse startup sequence (Controller → Workers → UI)
- **REQ-2.1.5**: Verify no active workflows before service stop (`AlteryxEngineCmd.exe` process check)
- **REQ-2.1.6**: Maintain configurable service wait timeout (default 7200 seconds)
- **REQ-2.1.7**: Skip service operations when `-BackupMode ConfigOnly` is specified

**Reference:** [MongoDB Backups - Alteryx Help](https://help.alteryx.com/current/en/server/configure/database-management/mongodb-management/mongodb-backups.html)

#### 2.2 Self-Managed MongoDB (New)
**Priority:** P1 (Should Have)

- **REQ-2.2.1**: Support MongoDB backup via native MongoDB tools (`mongodump` CLI)
- **REQ-2.2.2**: Accept MongoDB connection parameters:
  - Host/IP address
  - Port
  - Authentication database
  - Username (if auth enabled)
  - Password (secure handling via SecureString)
  - Connection string (alternative to discrete parameters)
- **REQ-2.2.3**: Support MongoDB connection string format (e.g., `mongodb://user:pass@host:port/db`)
- **REQ-2.2.4**: Auto-detect MongoDB deployment type:
  - Check if using embedded MongoDB (default AlteryxService data path)
  - Or self-managed MongoDB (custom connection string in RuntimeSettings.xml)
- **REQ-2.2.5**: For self-managed MongoDB, optionally skip AlteryxService stop (configurable parameter `-StopServiceForExternalDB`)
- **REQ-2.2.6**: Validate MongoDB connectivity before backup execution
- **REQ-2.2.7**: Use `mongodump` with `--gzip` option for compressed output

**Implementation Note:** Check `RuntimeSettings.xml` under `<Persistence><Mongo><ConnectionString>` to determine if using self-managed MongoDB.

### 3. Critical Files Backup Requirements

#### 3.1 All Nodes Files
**Priority:** P0 (Must Have)

Per Alteryx best practices, backup these files on every node (included in `ConfigOnly` and `Full` modes):

- **REQ-3.1.1**: RuntimeSettings.xml  
  Path: `C:\ProgramData\Alteryx\RuntimeSettings.xml`

- **REQ-3.1.2**: Keys Folder (entire directory)  
  Path: `C:\ProgramData\Alteryx\Keys\`  
  **Critical**: Contains encryption keys for DCM and Shared Gallery Connections

- **REQ-3.1.3**: Configuration File (if modified)  
  Path (2020.1+): `C:\Program Files\Alteryx\bin\server\config\alteryx.config`  
  Path (≤2019.4): `C:\Program Files\Alteryx\bin\config\alteryx.config`  
  **Logic**: Check file modification date; only backup if != installation date

- **REQ-3.1.4**: Service Log On User (capture settings)  
  **Action**: Export service account information to metadata file  
  **Method**: Query `Get-CimInstance Win32_Service -Filter "Name='AlteryxService'"` for StartName property

#### 3.2 Controller Node Files
**Priority:** P0 (Must Have)

Included in `ConfigOnly` and `Full` modes:

- **REQ-3.2.1**: Controller Token  
  **Command**: `AlteryxService.exe getserversecret`  
  **Output**: Save to `ControllerToken.txt` (current behavior maintained)

- **REQ-3.2.2**: MongoDB Passwords (Admin and Non-Admin)  
  **Command**: `AlteryxService.exe getemongopassword`  
  **Output**: Save to `MongoPasswords.txt`  
  **Note**: Currently missing from backup process

- **REQ-3.2.3**: Encryption Key (disaster recovery)  
  **Documentation**: Reference Alteryx [Disaster Recovery Preparation](https://help.alteryx.com/current/en/server/install/server-host-recovery-guide/disaster-recovery-preparation.html)  
  **Action**: Document requirement in backup logs; key must be stored separately per Alteryx guidance

#### 3.3 Worker Node Files
**Priority:** P1 (Should Have)

Included in `ConfigOnly` and `Full` modes:

- **REQ-3.3.1**: SystemAlias.xml (Shared DB Connections)  
  Path: `C:\ProgramData\Alteryx\Engine\SystemAlias.xml`  
  **Current Status**: Already backed up ✓

- **REQ-3.3.2**: SystemConnections.xml (In-DB Connections)  
  Path: `C:\ProgramData\Alteryx\Engine\SystemConnections.xml`  
  **Current Status**: Already backed up ✓

- **REQ-3.3.3**: Run As User Settings (capture metadata)  
  **Action**: Document from System Settings > Worker > Run As to metadata file

#### 3.4 Additional Metadata
**Priority:** P2 (Nice to Have)

Document these settings in a metadata file for disaster recovery (all backup modes):

- **REQ-3.4.1**: Alteryx Server version number
- **REQ-3.4.2**: Backup mode used (Full/DatabaseOnly/ConfigOnly)
- **REQ-3.4.3**: License key information (obfuscated, reference only)
- **REQ-3.4.4**: Installed ODBC drivers list
- **REQ-3.4.5**: Configured DSN list
- **REQ-3.4.6**: Installed Connectors list
- **REQ-3.4.7**: Python environment packages (if applicable)
- **REQ-3.4.8**: Active Directory groups with permissions

**Reference:** [Critical Server Files and Settings to Backup](https://help.alteryx.com/current/en/server/best-practices/backup-best-practices/critical-server-files-and-settings-to-backup.html)

### 4. Compression and Archival Requirements

#### 4.1 Archive Format
**Priority:** P0 (Must Have)

- **REQ-4.1.1**: Use native PowerShell `Compress-Archive` cmdlet (remove 7-Zip dependency)
- **REQ-4.1.2**: Output format: `.zip` (standard, cross-platform compatible)
- **REQ-4.1.3**: Filename convention: `ServerBackup_{Mode}_YYYYMMDD_HHmmss.zip` where Mode = Full|DB|Config
- **REQ-4.1.4**: Include backup manifest file inside archive:
  - Backup timestamp
  - Backup mode (Full/DatabaseOnly/ConfigOnly)
  - Alteryx Server version
  - MongoDB type (embedded/self-managed) and whether DB was backed up
  - List of backed up files with checksums (SHA256)
  - Script version
  - Execution status

#### 4.2 Compression Options
**Priority:** P1 (Should Have)

- **REQ-4.2.1**: Use optimal compression level (default)
- **REQ-4.2.2**: Support configurable compression level via parameter
- **REQ-4.2.3**: For MongoDB backups > 2GB, consider split archives or alternative compression

### 5. Storage and Distribution Requirements

#### 5.1 Local Storage
**Priority:** P0 (Must Have)

- **REQ-5.1.1**: Maintain current local backup path: `D:\Alteryx\Backups\` (configurable)
- **REQ-5.1.2**: Use temp directory for staging: `D:\Temp\` (configurable)
- **REQ-5.1.3**: Cleanup temp directory after successful archive move
- **REQ-5.1.4**: Maintain file retention policy (default: 30 days, configurable)
- **REQ-5.1.5**: Support separate retention policies by backup mode (e.g., keep DB-only backups 7 days, full backups 30 days)

#### 5.2 Network Storage
**Priority:** P1 (Should Have)

- **REQ-5.2.1**: Support UNC path destinations (e.g., `\\backup-server\alteryx\`)
- **REQ-5.2.2**: Support mapped drive destinations
- **REQ-5.2.3**: Validate network path accessibility before backup start
- **REQ-5.2.4**: Implement retry logic for network copy failures (3 retries, 30s interval)
- **REQ-5.2.5**: Support multiple network destinations (copy to multiple locations)

#### 5.3 Cloud Storage (Future)
**Priority:** P2 (Nice to Have)

- **REQ-5.3.1**: Support S3-compatible storage endpoints
- **REQ-5.3.2**: Support Azure Blob Storage
- **REQ-5.3.3**: Implement secure credential management for cloud uploads
- **REQ-5.3.4**: Use multi-part upload for large archives (>100MB)

### 6. Validation and Verification Requirements

#### 6.1 Pre-Backup Validation
**Priority:** P0 (Must Have)

- **REQ-6.1.1**: Verify sufficient disk space in temp directory (estimate: 2x MongoDB size for DB backups)
- **REQ-6.1.2**: Verify AlteryxService exists and is accessible
- **REQ-6.1.3**: Verify all critical file paths exist before backup start (based on backup mode)
- **REQ-6.1.4**: Check for running workflows (wait or timeout per config) - skip if `ConfigOnly` mode
- **REQ-6.1.5**: Validate script is running with Administrator privileges
- **REQ-6.1.6**: Validate backup mode parameter value

#### 6.2 Post-Backup Validation
**Priority:** P0 (Must Have)

- **REQ-6.2.1**: Verify archive file created successfully
- **REQ-6.2.2**: Calculate and store archive checksum (SHA256)
- **REQ-6.2.3**: Verify archive size > minimum threshold (varies by mode: DB > 1MB, Config > 100KB)
- **REQ-6.2.4**: Test archive integrity with `Test-Path` or validate zip structure
- **REQ-6.2.5**: Verify all expected files present in archive (check manifest)
- **REQ-6.2.6**: For MongoDB restores: Parse `mongoRestore.log` for success indicators per Alteryx guidance:
  - Confirm: `#### document(s) restored successfully, 0 document(s) failed to restore`
  - Search for: `error`, `critical`, `fatal`, `failed` (excluding success message)

### 7. Logging and Monitoring Requirements

#### 7.1 Logging Standards
**Priority:** P0 (Must Have)

- **REQ-7.1.1**: Follow PowerShell logging pattern with `Write-Log` function
- **REQ-7.1.2**: Log levels: DEBUG, INFO, WARNING, ERROR, SUCCESS
- **REQ-7.1.3**: Timestamp format: `yyyy-MM-dd HH:mm:ss` (ISO 8601)
- **REQ-7.1.4**: Log filename: `BackupLog_{Mode}_YYYYMMDD_HHmmss.log` (includes backup mode)
- **REQ-7.1.5**: Log directory: Configurable (default: `D:\Alteryx\BackupLogs\`)
- **REQ-7.1.6**: Write to both console and log file simultaneously

#### 7.2 Log Content Requirements
**Priority:** P0 (Must Have)

Log all significant events:
- **REQ-7.2.1**: Backup start timestamp and mode (Full/DatabaseOnly/ConfigOnly)
- **REQ-7.2.2**: Configuration parameters used
- **REQ-7.2.3**: MongoDB type detected (if applicable to backup mode)
- **REQ-7.2.4**: Service state transitions (stopping, stopped, starting, started) - only if service stop required
- **REQ-7.2.5**: Each file/folder backup operation
- **REQ-7.2.6**: Archive creation and compression
- **REQ-7.2.7**: Storage operations (local, network, cloud)
- **REQ-7.2.8**: Validation results
- **REQ-7.2.9**: Backup completion timestamp
- **REQ-7.2.10**: Total execution duration
- **REQ-7.2.11**: Final backup size
- **REQ-7.2.12**: Exit status (SUCCESS/FAILURE with error details)

#### 7.3 Error Handling
**Priority:** P0 (Must Have)

- **REQ-7.3.1**: Wrap all operations in try/catch blocks
- **REQ-7.3.2**: Log full exception details on error (Message, StackTrace, InnerException)
- **REQ-7.3.3**: Implement rollback logic on critical failures (restart service if stopped)
- **REQ-7.3.4**: Exit with non-zero code on any failure
- **REQ-7.3.5**: Return exit codes:
  - `0` = Success
  - `1` = General error
  - `2` = Service timeout
  - `3` = Validation failure
  - `4` = Storage error
  - `5` = MongoDB error
  - `6` = Invalid backup mode parameter

#### 7.4 Alerting (Future)
**Priority:** P2 (Nice to Have)

- **REQ-7.4.1**: Email notification on backup failure
- **REQ-7.4.2**: Email notification on backup success (optional, configurable)
- **REQ-7.4.3**: Support SMTP authentication
- **REQ-7.4.4**: Include log excerpt in email body
- **REQ-7.4.5**: Attach full log file to email (optional)

### 8. Configuration Management Requirements

#### 8.1 Configuration File
**Priority:** P1 (Should Have)

Support JSON configuration file for all parameters:

```json
{
  "BackupConfiguration": {
    "DefaultBackupMode": "Full",
    "TempDirectory": "D:\\Temp",
    "LocalBackupPath": "D:\\Alteryx\\Backups",
    "NetworkBackupPaths": [
      "\\\\backup-server\\alteryx\\",
      "\\\\dr-server\\alteryx-backup\\"
    ],
    "LogDirectory": "D:\\Alteryx\\BackupLogs",
    "RetentionDays": {
      "Full": 30,
      "DatabaseOnly": 7,
      "ConfigOnly": 14
    }
  },
  "ServiceConfiguration": {
    "MaxServiceWaitSeconds": 7200,
    "MaxWorkflowWaitSeconds": 3600,
    "ForceStopWorkflows": false,
    "StopServiceForExternalDB": false
  },
  "MongoDBConfiguration": {
    "Type": "auto",
    "EmbeddedMongoDB": {
      "UseAlteryxService": true
    },
    "SelfManagedMongoDB": {
      "ConnectionString": "",
      "Host": "",
      "Port": 27017,
      "Database": "AlteryxGallery",
      "AuthDatabase": "admin",
      "Username": "",
      "UseCompression": true
    }
  },
  "FilesConfiguration": {
    "BackupKeys": true,
    "BackupConfigFile": true,
    "BackupMongoPasswords": true,
    "IncludeMetadata": true
  },
  "ValidationConfiguration": {
    "VerifyArchiveIntegrity": true,
    "CalculateChecksums": true,
    "MinimumBackupSizeMB": {
      "Full": 1,
      "DatabaseOnly": 1,
      "ConfigOnly": 0.1
    }
  },
  "NotificationConfiguration": {
    "Enabled": false,
    "SMTPServer": "",
    "SMTPPort": 587,
    "UseSSL": true,
    "FromAddress": "",
    "ToAddresses": [],
    "OnlyOnFailure": true
  }
}
```

- **REQ-8.1.1**: Load config from default path: `./config/backup-config.json`
- **REQ-8.1.2**: Support `-ConfigPath` parameter to override default
- **REQ-8.1.3**: Command-line parameters override config file values
- **REQ-8.1.4**: Validate all config values before execution
- **REQ-8.1.5**: Document config schema with examples

#### 8.2 Parameter Management
**Priority:** P0 (Must Have)

All configuration should be available via command-line parameters:

```powershell
# Full backup (default)
.\Invoke-AlteryxBackup.ps1

# Database-only backup
.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly

# Config-only backup
.\Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly

# Full backup with all parameters
.\Invoke-AlteryxBackup.ps1 `
    -BackupMode Full `
    -ConfigPath "C:\Config\backup-config.json" `
    -TempDirectory "D:\Temp" `
    -LocalBackupPath "D:\Alteryx\Backups" `
    -NetworkBackupPath "\\backup-server\alteryx" `
    -LogDirectory "D:\Alteryx\BackupLogs" `
    -MongoDBType "embedded" `
    -MaxServiceWait 7200 `
    -RetentionDays 30 `
    -Verbose `
    -WhatIf
```

- **REQ-8.2.1**: Use `[Parameter()]` attributes for all parameters
- **REQ-8.2.2**: Provide sensible defaults for all optional parameters
- **REQ-8.2.3**: Support `-WhatIf` for dry-run mode
- **REQ-8.2.4**: Support `-Verbose` for detailed output
- **REQ-8.2.5**: Support `-Help` switch with usage documentation
- **REQ-8.2.6**: Validate `-BackupMode` parameter accepts only: Full, DatabaseOnly, ConfigOnly

### 9. Migration and Compatibility Requirements

#### 9.1 Backward Compatibility
**Priority:** P0 (Must Have)

- **REQ-9.1.1**: New PowerShell script must be callable from existing batch script
- **REQ-9.1.2**: Maintain existing log directory structure
- **REQ-9.1.3**: Support existing scheduled task integration
- **REQ-9.1.4**: Maintain existing backup filename format (configurable)
- **REQ-9.1.5**: Exit codes compatible with Task Scheduler error handling
- **REQ-9.1.6**: Default behavior (no parameters) matches current batch script behavior (full backup)

#### 9.2 Migration Path
**Priority:** P1 (Should Have)

- **REQ-9.2.1**: Provide migration script to convert batch variables to JSON config
- **REQ-9.2.2**: Document side-by-side testing procedure
- **REQ-9.2.3**: Create rollback procedure documentation
- **REQ-9.2.4**: Provide comparison report of batch vs PowerShell outputs

#### 9.3 Documentation Requirements
**Priority:** P0 (Must Have)

- **REQ-9.3.1**: Update README.md with PowerShell script usage
- **REQ-9.3.2**: Document all parameters with examples for each backup mode
- **REQ-9.3.3**: Provide configuration file examples for common scenarios
- **REQ-9.3.4**: Document MongoDB type detection logic
- **REQ-9.3.5**: Document disaster recovery procedures
- **REQ-9.3.6**: Create troubleshooting guide
- **REQ-9.3.7**: Document scheduled task setup for Windows Task Scheduler
- **REQ-9.3.8**: Provide use case examples for each backup mode

---

## Technical Specifications

### Script Architecture

#### Primary Script: `Invoke-AlteryxBackup.ps1`
- **Language:** PowerShell 5.1+ (Windows PowerShell compatibility)
- **Privileges:** Must run as Administrator
- **Location:** `powershell/Invoke-AlteryxBackup.ps1`

#### Module Structure (Optional Future Enhancement)
```
powershell/
├── Invoke-AlteryxBackup.ps1        # Main orchestration script
├── Modules/
│   ├── AlteryxService.psm1         # Service management functions
│   ├── MongoDBBackup.psm1          # MongoDB backup functions
│   ├── FileBackup.psm1             # File copy/archive functions
│   ├── Validation.psm1             # Pre/post validation functions
│   └── Logger.psm1                 # Logging utilities
├── config/
│   ├── backup-config.json          # Default configuration
│   └── backup-config.example.json  # Example with comments
└── README.md                       # PowerShell scripts documentation
```

### Function Specifications

#### Core Functions

**1. Initialize-BackupEnvironment**
- Validate Administrator privileges
- Validate backup mode parameter
- Load configuration (file + parameters)
- Validate all paths and prerequisites based on backup mode
- Create temp/log directories if missing
- Return configuration object

**2. Test-AlteryxServiceState**
- Check for running workflows (`AlteryxEngineCmd.exe`)
- Query service state
- Return service status object

**3. Stop-AlteryxServiceSafely**
- Skip if backup mode is ConfigOnly
- Wait for workflows to complete (with timeout)
- Implement multi-node shutdown sequence (if detected)
- Monitor service state with timeout protection
- Log all state transitions

**4. Start-AlteryxServiceSafely**
- Skip if backup mode is ConfigOnly
- Implement multi-node startup sequence
- Monitor service state with timeout protection
- Verify service started successfully

**5. Invoke-MongoDBBackup**
- Skip if backup mode is ConfigOnly
- Auto-detect MongoDB type from RuntimeSettings.xml
- Execute appropriate backup method:
  - Embedded: `AlteryxService.exe emongodump`
  - Self-managed: `mongodump` with connection parameters
- Validate backup output
- Return backup path

**6. Backup-CriticalFiles**
- Skip if backup mode is DatabaseOnly
- Copy all critical files per requirements section 3
- Maintain directory structure in temp folder
- Log each file operation
- Handle missing files gracefully (warn, don't fail)

**7. Export-ControllerSettings**
- Skip if backup mode is DatabaseOnly
- Execute `getserversecret` command
- Execute `getemongopassword` command
- Query service account information
- Save to individual text files

**8. New-BackupManifest**
- Generate manifest JSON file with metadata
- Include backup mode in manifest
- Calculate file checksums (SHA256) for files that were backed up
- Include configuration snapshot
- Return manifest object

**9. Compress-BackupArchive**
- Use `Compress-Archive` cmdlet
- Apply filename convention with backup mode suffix
- Generate checksum for archive
- Return archive path and checksum

**10. Copy-BackupToDestinations**
- Copy to local backup path
- Copy to network paths (with retry logic)
- Copy to cloud storage (future)
- Validate each copy operation

**11. Test-BackupIntegrity**
- Verify archive exists and size > minimum (based on backup mode)
- Validate archive can be opened
- Compare manifest checksums
- Return validation result

**12. Remove-OldBackups**
- Apply retention policy to local/network paths (by backup mode if configured)
- Log deleted files
- Handle errors gracefully

**13. Write-BackupSummary**
- Generate summary report including backup mode
- Include all metrics (size, duration, file counts)
- Log final status
- Return summary object

### Error Handling Strategy

Implement defensive error handling at each stage:

```powershell
try {
    # Operation
    Write-Log "Starting operation X in $BackupMode mode" -Level INFO
    
    $result = Invoke-Operation
    
    if ($result.Success) {
        Write-Log "Operation X completed" -Level SUCCESS
    } else {
        Write-Log "Operation X failed: $($result.Error)" -Level WARNING
    }
    
} catch {
    Write-Log "Critical error in operation X: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    
    # Rollback if needed
    if ($serviceWasStopped) {
        Start-AlteryxServiceSafely
    }
    
    exit 1
}
```

---

## Testing Requirements

### Unit Testing
**Priority:** P1 (Should Have)

- Test each function independently with Pester framework
- Mock external commands (AlteryxService.exe, mongodump)
- Test error handling paths
- Test parameter validation including backup mode validation
- Test each backup mode independently

### Integration Testing
**Priority:** P0 (Must Have)

- Test full backup workflow on non-production server
- **Test all backup modes**:
  - Full mode: Complete workflow
  - DatabaseOnly mode: Verify files not backed up, service stops/starts
  - ConfigOnly mode: Verify MongoDB not backed up, service stays running
- Test with embedded MongoDB
- Test with self-managed MongoDB (if available)
- Test service stop/start with various timeouts
- Test network path failures and retries
- Test insufficient disk space scenario
- Test with active workflows running (for modes that require service stop)

### Validation Testing
**Priority:** P0 (Must Have)

- Perform test restore from each backup mode:
  - Full backup: Complete restore
  - DatabaseOnly backup: MongoDB restore only
  - ConfigOnly backup: File restoration only
- Verify all expected files present based on mode
- Validate checksums match
- Test MongoDB restore procedure per Alteryx docs
- Verify service starts successfully post-restore

### Scheduled Task Testing
**Priority:** P0 (Must Have)

- Test execution via Windows Task Scheduler for each backup mode
- Test with SYSTEM account
- Test with service account
- Verify logging works when running unattended
- Verify exit codes trigger Task Scheduler alerts
- Test multiple scheduled tasks for different modes (e.g., hourly DB backups, nightly full backups)

---

## Use Case Scenarios

### Scenario 1: Standard Daily Full Backup
**Schedule:** Nightly at 2:00 AM  
**Mode:** Full  
**Purpose:** Comprehensive backup including MongoDB and all configuration files  
**Command:** `Invoke-AlteryxBackup.ps1` (default mode)

### Scenario 2: Frequent Database Snapshots
**Schedule:** Every 4 hours during business hours  
**Mode:** DatabaseOnly  
**Purpose:** Capture database state frequently without configuration overhead  
**Command:** `Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly -RetentionDays 7`

### Scenario 3: Post-Configuration Change Backup
**Schedule:** Ad-hoc after SSL/configuration changes  
**Mode:** ConfigOnly  
**Purpose:** Backup configuration changes without interrupting service or backing up large MongoDB  
**Command:** `Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly`

### Scenario 4: Pre-Upgrade Full Backup
**Schedule:** Manual execution before Server upgrade  
**Mode:** Full  
**Purpose:** Complete backup before major system changes  
**Command:** `Invoke-AlteryxBackup.ps1 -BackupMode Full -NetworkBackupPath "\\backup-server\pre-upgrade\"`

---

## Rollout Plan

### Phase 1: Development (Weeks 1-2)
- Create `Invoke-AlteryxBackup.ps1` script with backup mode support
- Implement Full, DatabaseOnly, and ConfigOnly modes
- Implement embedded MongoDB support
- Implement all critical file backups per Section 3
- Implement logging and error handling
- Create configuration file schema
- Write unit tests

### Phase 2: Testing (Week 3)
- Integration testing on development server
- Test each backup mode independently
- Perform test backup and restore for each mode
- Validate all files captured correctly by mode
- Performance testing (measure execution time by mode)
- Document any issues or deviations

### Phase 3: Self-Managed MongoDB Support (Week 4)
- Implement auto-detection logic
- Add `mongodump` integration
- Test with self-managed MongoDB instance
- Update documentation

### Phase 4: Advanced Features (Week 5)
- Network storage support with retry logic
- Backup validation enhancements
- Metadata capture
- Separate retention policies by mode
- Create migration script from batch to PowerShell

### Phase 5: Pilot Deployment (Week 6)
- Deploy to production alongside existing batch script
- Run both scripts in parallel for comparison
- Test multiple scheduled tasks (e.g., nightly Full + 4-hour DatabaseOnly)
- Monitor results and logs
- Collect feedback

### Phase 6: Production Rollout (Week 7)
- Update scheduled tasks to use PowerShell script
- Configure appropriate backup modes per schedule
- Deprecate batch script (keep as backup)
- Update documentation
- Train team on new process and backup modes

### Phase 7: Future Enhancements (Weeks 8+)
- Email alerting integration
- Cloud storage support (S3, Azure Blob)
- Performance optimizations
- Enhanced validation and reporting

---

## Dependencies

### External Tools
- **PowerShell 5.1+** (Windows PowerShell) - Built into Windows Server
- **AlteryxService.exe** - Alteryx Server installation
- **mongodump** (optional) - Required only for self-managed MongoDB

### Removed Dependencies
- ~~7-Zip~~ - Replaced with native `Compress-Archive`
- ~~WMIC~~ - Replaced with `Get-Date` and `Get-CimInstance`
- ~~ROBOCOPY~~ - Replaced with `Copy-Item` cmdlet

### PowerShell Modules
- **PSModulePath** - Standard modules (no additional installs required)
- **Pester** (optional) - For unit testing during development

---

## Security Considerations

### Credential Management
- **REQ-SEC-1**: Store MongoDB passwords using SecureString in memory
- **REQ-SEC-2**: Never log passwords or connection strings with credentials
- **REQ-SEC-3**: Support credential retrieval from Windows Credential Manager
- **REQ-SEC-4**: Document secure configuration practices

### Access Control
- **REQ-SEC-5**: Script must run as Administrator (validate on startup)
- **REQ-SEC-6**: Backup archives should inherit NTFS permissions from destination folder
- **REQ-SEC-7**: Log files should have restricted permissions (Administrators only)
- **REQ-SEC-8**: Config files with credentials should have restricted ACLs

### Network Security
- **REQ-SEC-9**: Support SMB3 for network transfers (encrypted by default)
- **REQ-SEC-10**: Validate SSL/TLS for cloud storage connections
- **REQ-SEC-11**: Support authentication for network shares

### Compliance
- **REQ-SEC-12**: Backup archives contain sensitive data (encryption recommended)
- **REQ-SEC-13**: Document data retention policies by backup mode
- **REQ-SEC-14**: Log all backup operations for audit trail

---

## Open Questions

1. **Multi-Node Detection**: How should the script detect if Alteryx Server is configured in multi-node mode?
   - **Proposed**: Parse RuntimeSettings.xml for Worker node configurations
   
2. **Encryption Key Backup**: Alteryx docs state encryption keys must be stored separately. Should this be automated or documented as manual process?
   - **Proposed**: Document as manual process per Alteryx disaster recovery guidance

3. **Cloud Storage Priority**: Should cloud storage support be included in Phase 1 or deferred to Phase 7?
   - **Proposed**: Defer to Phase 7 to focus on core functionality and backup modes

4. **Notification Method**: Email, Windows Event Log, both, or pluggable notification system?
   - **Proposed**: Windows Event Log in Phase 1, Email in Phase 7

5. **Parallel Execution**: Should file copies to multiple destinations run in parallel?
   - **Proposed**: Yes, use PowerShell jobs for parallel network copies

6. **Version Compatibility**: What minimum Alteryx Server version should be supported?
   - **Proposed**: Support 2020.1+ (aligns with current RuntimeSettings.xml path)

7. **Backup Mode Combinations**: Should the script support combinations like "DB + Keys only"?
   - **Proposed**: Start with three discrete modes, evaluate custom combinations based on feedback

---

## Success Criteria

The project will be considered successful when:

1. ✅ All P0 requirements implemented and tested
2. ✅ All three backup modes (Full, DatabaseOnly, ConfigOnly) fully functional
3. ✅ Backup process captures 100% of Alteryx-recommended critical files (per mode)
4. ✅ Support for both embedded and self-managed MongoDB
5. ✅ Zero external dependencies (7-Zip, WMIC removed)
6. ✅ Test restore from each backup mode completes successfully
7. ✅ Production deployment with zero service interruption issues
8. ✅ Documentation complete and approved for all backup modes
9. ✅ Scheduled tasks running successfully for 30 days without failures
10. ✅ Backward compatibility maintained with existing scheduled tasks
11. ✅ Performance: backup completion within expected time windows by mode
12. ✅ Use case scenarios validated and documented

---

## Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Service timeout during backup | Medium | High | Implement configurable timeout with fallback logic |
| Network path unavailable during backup | Medium | Medium | Implement retry logic and continue with other destinations |
| MongoDB backup corruption | Low | Critical | Implement validation per Alteryx docs (parse mongoRestore.log) |
| PowerShell script compatibility issues | Low | Medium | Test on multiple Windows Server versions (2016, 2019, 2022) |
| Self-managed MongoDB connection failures | Medium | Medium | Implement connection validation before service stop |
| Insufficient disk space mid-backup | Low | High | Pre-validate disk space requirements before starting |
| Breaking change from batch to PowerShell | Medium | High | Run both scripts in parallel during pilot phase |
| Missing critical files in backup | Low | Critical | Use validation checks against Alteryx official checklist |
| ConfigOnly mode fails to capture live data | Low | Medium | Document limitations, validate against service state |
| Confusion about which backup mode to use | Medium | Low | Comprehensive documentation with use case examples |

---

## Appendix

### A. Reference Links
- [MongoDB Backups - Alteryx Help](https://help.alteryx.com/current/en/server/configure/database-management/mongodb-management/mongodb-backups.html)
- [Critical Server Files and Settings to Backup](https://help.alteryx.com/current/en/server/best-practices/backup-best-practices/critical-server-files-and-settings-to-backup.html)
- [Alteryx Server Backup and Recovery Part 2: Procedures](https://community.alteryx.com/t5/Alteryx-Server-Knowledge-Base/Alteryx-Server-Backup-and-Recovery-Part-2-Procedures/ta-p/22642)
- [Disaster Recovery Preparation](https://help.alteryx.com/current/en/server/install/server-host-recovery-guide/disaster-recovery-preparation.html)

### B. Backup Mode Comparison Matrix

| Feature | Full | DatabaseOnly | ConfigOnly |
|---------|------|--------------|------------|
| MongoDB Backup | ✓ | ✓ | ✗ |
| Configuration Files | ✓ | ✗ | ✓ |
| Keys Folder | ✓ | ✗ | ✓ |
| Controller Settings | ✓ | ✗ | ✓ |
| Service Stop Required | ✓ | ✓ | ✗ |
| Service Interruption | Yes | Yes | No |
| Typical Size | Large | Large | Small |
| Typical Duration | Long | Medium | Short |
| Use Case | Nightly backup | Frequent snapshots | Config changes |
| Recommended Frequency | Daily | 2-4 hours | Ad-hoc |
| Recommended Retention | 30 days | 7 days | 14 days |

### C. Glossary
- **Embedded MongoDB**: MongoDB instance installed and managed by Alteryx Server installer
- **Self-Managed MongoDB**: MongoDB instance installed and configured independently of Alteryx Server
- **Controller Node**: Alteryx Server node that hosts the MongoDB database and manages workflow scheduling
- **Worker Node**: Alteryx Server node that executes workflows
- **Server UI Node**: Alteryx Server node that hosts the Gallery web interface
- **RuntimeSettings.xml**: Primary Alteryx Server configuration file
- **DCM**: Data Connection Manager - Alteryx feature for managing data source connections
- **UNC Path**: Universal Naming Convention path for network resources (\\server\share)
- **Backup Mode**: Operational mode determining scope of backup (Full, DatabaseOnly, ConfigOnly)

### D. Version History
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-13 | System | Initial draft with modular backup mode support |

---

## Document Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner | TBD | | |
| Technical Lead | TBD | | |
| Operations Lead | TBD | | |
| Security Review | TBD | | |

---

**End of Document**
