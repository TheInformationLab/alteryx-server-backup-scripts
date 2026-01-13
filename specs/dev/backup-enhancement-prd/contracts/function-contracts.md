# Function Contracts: Alteryx Server Backup Enhancement

**Feature**: Modular Alteryx Server backup  
**Date**: 2026-01-13  
**Status**: Phase 1 - Contracts

---

## Overview

This document defines the function signatures (contracts) for all PowerShell functions in `Invoke-AlteryxBackup.ps1`. Each contract specifies inputs, outputs, error conditions, and side effects.

---

## 1. Initialize-BackupEnvironment

**Purpose**: Load configuration, validate prerequisites, prepare environment

### Signature
```powershell
function Initialize-BackupEnvironment {
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("Full", "DatabaseOnly", "ConfigOnly")]
        [string]$BackupMode = "Full",
        
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ".\config\backup-config.json",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$ParameterOverrides = @{}
    )
    
    # Returns: ConfigurationObject (see data-model.md section 1.2)
}
```

### Inputs
- **BackupMode**: Execution mode (Full/DatabaseOnly/ConfigOnly)
- **ConfigPath**: Path to JSON configuration file
- **ParameterOverrides**: Command-line parameters that override config file

### Outputs
**Type**: ConfigurationObject (hashtable)  
**Structure**: See data-model.md section 1.2

### Behavior
1. Check Administrator privileges (throw if not admin)
2. Load JSON config file (if exists)
3. Merge config with parameter overrides
4. Validate backup mode
5. Resolve all paths to absolute
6. Create temp/log directories if missing
7. Detect MongoDB type from RuntimeSettings.xml
8. Detect multi-node topology from RuntimeSettings.xml
9. Return merged configuration object

### Error Conditions
- **InvalidOperationException**: Not running as Administrator
- **FileNotFoundException**: ConfigPath specified but doesn't exist
- **ValidationException**: Invalid BackupMode value
- **ValidationException**: Required paths don't exist and can't be created
- **ValidationException**: Insufficient disk space in temp directory

### Side Effects
- Creates directories: TempDirectory, LogDirectory, LocalBackupPath (if missing)
- Reads file: RuntimeSettings.xml

---

## 2. Test-AlteryxServiceState

**Purpose**: Query current Alteryx Service state and detect active workflows

### Signature
```powershell
function Test-AlteryxServiceState {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ServiceName = "AlteryxService"
    )
    
    # Returns: ServiceStateInfo (see data-model.md section 3.1)
}
```

### Inputs
- **ServiceName**: Name of Windows service to query

### Outputs
**Type**: ServiceStateInfo (hashtable)

```powershell
@{
    ServiceName = "AlteryxService"
    CurrentState = "Running"  # Running, Stopped, etc.
    HasActiveWorkflows = $false
    WorkflowProcessCount = 0
}
```

### Behavior
1. Query service state via `Get-Service`
2. Query for `AlteryxEngineCmd.exe` processes via `Get-Process`
3. Return state information

### Error Conditions
- **ServiceNotFoundException**: Service doesn't exist
- **UnauthorizedAccessException**: Insufficient privileges to query service

### Side Effects
None (read-only operation)

---

## 3. Stop-AlteryxServiceSafely

**Purpose**: Safely stop AlteryxService with workflow wait and timeout protection

### Signature
```powershell
function Stop-AlteryxServiceSafely {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ServiceName = "AlteryxService",
        
        [Parameter(Mandatory=$false)]
        [int]$MaxWorkflowWaitSeconds = 3600,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxServiceWaitSeconds = 7200,
        
        [Parameter(Mandatory=$false)]
        [bool]$ForceStop = $false,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$MultiNodeInfo = $null
    )
    
    # Returns: ServiceStateInfo
}
```

### Inputs
- **ServiceName**: Service to stop
- **MaxWorkflowWaitSeconds**: Maximum time to wait for workflows to complete
- **MaxServiceWaitSeconds**: Maximum time to wait for service to stop
- **ForceStop**: Whether to force-kill workflows if timeout exceeded
- **MultiNodeInfo**: Multi-node topology (if applicable)

### Outputs
**Type**: ServiceStateInfo

```powershell
@{
    ServiceName = "AlteryxService"
    InitialState = "Running"
    CurrentState = "Stopped"
    StateChangeSuccess = $true
    StateChangeError = $null
    WorkflowWaitSeconds = 45
    RequiresRollback = $true  # Must restart on error
}
```

### Behavior
1. Check initial service state
2. If has active workflows:
   - Wait for workflows to complete (poll every 10s)
   - Timeout after MaxWorkflowWaitSeconds
   - If ForceStop=true: Kill workflow processes
3. If multi-node:
   - Stop Server UI node first (if separate)
   - Stop Worker nodes in parallel
   - Stop Controller node last
4. Else (single node):
   - Issue `Stop-Service -Force`
5. Poll service state until "Stopped" or timeout
6. Return state info

### Error Conditions
- **TimeoutException**: Workflows didn't complete within MaxWorkflowWaitSeconds
- **TimeoutException**: Service didn't stop within MaxServiceWaitSeconds
- **ServiceException**: Stop-Service failed

### Side Effects
- Stops Windows service
- May kill workflow processes (if ForceStop=true)
- May stop services on remote nodes (if multi-node)

---

## 4. Start-AlteryxServiceSafely

**Purpose**: Safely start AlteryxService with state verification

**CRITICAL**: This function should be called **immediately after MongoDB backup completes** to minimize service downtime. All subsequent backup operations (file backup, archival, distribution, validation) can proceed with the service running.

### Signature
```powershell
function Start-AlteryxServiceSafely {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ServiceName = "AlteryxService",
        
        [Parameter(Mandatory=$false)]
        [int]$MaxServiceWaitSeconds = 7200,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$MultiNodeInfo = $null
    )
    
    # Returns: ServiceStateInfo
}
```

### Inputs
- **ServiceName**: Service to start
- **MaxServiceWaitSeconds**: Maximum time to wait for service to start
- **MultiNodeInfo**: Multi-node topology (if applicable)

### Outputs
**Type**: ServiceStateInfo (same as Stop-AlteryxServiceSafely)

### Behavior
1. If multi-node:
   - Start Controller node first
   - Start Worker nodes in parallel
   - Start Server UI node last (if separate)
2. Else (single node):
   - Issue `Start-Service`
3. Poll service state until "Running" or timeout
4. Return state info

### Error Conditions
- **TimeoutException**: Service didn't start within MaxServiceWaitSeconds
- **ServiceException**: Start-Service failed

### Side Effects
- Starts Windows service
- May start services on remote nodes (if multi-node)

---

## 5. Invoke-MongoDBBackup

**Purpose**: Execute MongoDB backup (embedded or self-managed)

### Signature
```powershell
function Invoke-MongoDBBackup {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("embedded", "self-managed")]
        [string]$MongoType,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$MongoConfig = @{}
    )
    
    # Returns: BackupResultObject
}
```

### Inputs
- **MongoType**: "embedded" or "self-managed"
- **BackupPath**: Destination directory for MongoDB dump
- **MongoConfig**: Connection parameters (for self-managed)

### Outputs
**Type**: BackupResultObject

```powershell
@{
    Success = $true
    BackupPath = "D:\Temp\MongoDBBackup"
    BackupSizeMB = 1537.25
    CollectionCount = 42
    DurationSeconds = 235
    Error = $null
}
```

### Behavior
1. If MongoType = "embedded":
   - Execute `AlteryxService.exe emongodump -d $BackupPath`
2. If MongoType = "self-managed":
   - Build mongodump command with connection parameters
   - Execute `mongodump --host=... --gzip --out=$BackupPath`
3. Validate backup output (directory exists, contains .bson files)
4. Calculate backup size and collection count
5. Return result

### Error Conditions
- **MongoDBException**: Backup command failed
- **ValidationException**: Backup output invalid or empty
- **ConnectionException**: Cannot connect to self-managed MongoDB

### Side Effects
- Creates MongoDB dump files in BackupPath
- Reads MongoDB data

---

## 6. Backup-CriticalFiles

**Purpose**: Copy critical Alteryx configuration files to temp directory

### Signature
```powershell
function Backup-CriticalFiles {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TempDirectory,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$FilesRegistry,  # From data-model.md section 4.1
        
        [Parameter(Mandatory=$false)]
        [bool]$CalculateChecksums = $true
    )
    
    # Returns: FileBackupResultObject
}
```

### Inputs
- **TempDirectory**: Staging directory
- **FilesRegistry**: CriticalFileDefinition array
- **CalculateChecksums**: Whether to generate SHA256 checksums

### Outputs
**Type**: FileBackupResultObject

```powershell
@{
    Success = $true
    FilesBackedUp = 12
    TotalSizeBytes = 2547920
    BackedUpFiles = @(
        @{
            SourcePath = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
            DestinationPath = "D:\Temp\BackupStaging\Config\RuntimeSettings.xml"
            SizeBytes = 15842
            SHA256 = "a3f5c8b9..."
        }
    )
    Warnings = @()
    Errors = @()
}
```

### Behavior
1. Iterate through FilesRegistry
2. For each file/directory:
   - Check if exists (warn if required=false and missing)
   - Copy to TempDirectory with relative path
   - Calculate checksum if requested
   - Add to BackedUpFiles list
3. Return result summary

### Error Conditions
- **FileNotFoundException**: Required file missing
- **IOException**: Copy operation failed
- **UnauthorizedAccessException**: Insufficient permissions

### Side Effects
- Copies files to TempDirectory
- Reads file contents (for checksums)

---

## 7. Export-ControllerSettings

**Purpose**: Export Controller Token and MongoDB passwords via AlteryxService commands

### Signature
```powershell
function Export-ControllerSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TempDirectory,
        
        [Parameter(Mandatory=$false)]
        [string]$AlteryxServicePath = "C:\Program Files\Alteryx\bin\AlteryxService.exe"
    )
    
    # Returns: ControllerSettingsResultObject
}
```

### Inputs
- **TempDirectory**: Destination for exported settings
- **AlteryxServicePath**: Path to AlteryxService.exe

### Outputs
**Type**: ControllerSettingsResultObject

```powershell
@{
    Success = $true
    ControllerToken = "abc123..."  # Content, not path
    MongoPasswords = "Admin: xyz789...\nNon-Admin: def456..."
    ServiceAccountUser = "NT AUTHORITY\NetworkService"
    ExportedFiles = @(
        "D:\Temp\BackupStaging\Config\ControllerToken.txt",
        "D:\Temp\BackupStaging\Config\MongoPasswords.txt"
    )
}
```

### Behavior
1. Execute `AlteryxService.exe getserversecret` → ControllerToken.txt
2. Execute `AlteryxService.exe getemongopassword` → MongoPasswords.txt
3. Query service account via `Get-CimInstance Win32_Service`
4. Save all outputs to TempDirectory
5. Return results

### Error Conditions
- **CommandException**: AlteryxService.exe command failed
- **FileNotFoundException**: AlteryxService.exe not found

### Side Effects
- Executes external commands
- Writes files to TempDirectory
- Queries service configuration

---

## 8. New-BackupManifest

**Purpose**: Generate backup manifest JSON with metadata and checksums

### Signature
```powershell
function New-BackupManifest {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$BackupConfig,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$BackupResults,  # From previous functions
        
        [Parameter(Mandatory=$true)]
        [datetime]$StartTime,
        
        [Parameter(Mandatory=$true)]
        [datetime]$EndTime
    )
    
    # Returns: ManifestObject (hashtable, will be serialized to JSON)
}
```

### Inputs
- **BackupConfig**: Configuration object from Initialize-BackupEnvironment
- **BackupResults**: Aggregated results from Invoke-MongoDBBackup, Backup-CriticalFiles, etc.
- **StartTime**: Backup start timestamp
- **EndTime**: Backup completion timestamp

### Outputs
**Type**: ManifestObject (see data-model.md section 2.1)

### Behavior
1. Aggregate backup metadata
2. Capture system information (Alteryx version, hostname, etc.)
3. Include MongoDB information (if applicable)
4. List all backed up files with checksums
5. Add encryption key warning
6. Return manifest object

### Error Conditions
None (best-effort metadata capture, missing fields logged as warnings)

### Side Effects
- Queries system information (WMI, registry)
- Reads Alteryx installation details

---

## 9. Compress-BackupArchive

**Purpose**: Compress backup staging directory to .zip archive

### Signature
```powershell
function Compress-BackupArchive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,  # Temp staging directory
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,  # Local backup path
        
        [Parameter(Mandatory=$true)]
        [string]$BackupMode,
        
        [Parameter(Mandatory=$false)]
        [string]$CompressionLevel = "Optimal",
        
        [Parameter(Mandatory=$false)]
        [bool]$CalculateChecksum = $true
    )
    
    # Returns: ArchiveResultObject
}
```

### Inputs
- **SourcePath**: Staging directory with backup files
- **DestinationPath**: Destination directory for archive
- **BackupMode**: For filename generation
- **CompressionLevel**: Optimal, Fastest, or NoCompression
- **CalculateChecksum**: Whether to generate SHA256 for archive

### Outputs
**Type**: ArchiveResultObject

```powershell
@{
    Success = $true
    ArchiveFileName = "ServerBackup_Full_20260114_020015.zip"
    ArchiveFullPath = "D:\Alteryx\Backups\ServerBackup_Full_20260114_020015.zip"
    ArchiveSizeMB = 1523.47
    CompressionRatio = 0.99
    SHA256 = "e7d4c2a1b8f6..."
    DurationSeconds = 187
}
```

### Behavior
1. Generate archive filename with timestamp and mode
2. Execute `Compress-Archive` with specified compression level
3. Calculate archive checksum if requested
4. Calculate compression ratio
5. Return result

### Error Conditions
- **IOException**: Archive creation failed
- **DiskFullException**: Insufficient disk space

### Side Effects
- Creates .zip archive file
- Reads source files

---

## 10. Copy-BackupToDestinations

**Purpose**: Copy backup archive to network/cloud destinations with retry logic

### Signature
```powershell
function Copy-BackupToDestinations {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,  # Local archive path
        
        [Parameter(Mandatory=$true)]
        [string[]]$Destinations,  # Network UNC paths
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$RetryDelaySec = 30
    )
    
    # Returns: DistributionResultObject
}
```

### Inputs
- **SourcePath**: Local archive file
- **Destinations**: Array of network paths
- **MaxRetries**: Retry attempts per destination
- **RetryDelaySec**: Base delay between retries (exponential backoff)

### Outputs
**Type**: DistributionResultObject

```powershell
@{
    SourcePath = "D:\Alteryx\Backups\ServerBackup_Full_20260114_020015.zip"
    DestinationResults = @{
        "\\backup-server\alteryx\" = @{
            Success = $true
            Attempts = 1
            FinalPath = "\\backup-server\alteryx\ServerBackup_Full_20260114_020015.zip"
        }
        "\\dr-server\backups\" = @{
            Success = $false
            Attempts = 3
            Error = "Network path not accessible"
        }
    }
    SuccessCount = 1
    FailureCount = 1
}
```

### Behavior
1. For each destination:
   - Attempt copy with `Copy-Item`
   - Verify copy (file size match)
   - On failure: Retry with exponential backoff
   - Log each attempt
2. Return aggregated results

### Error Conditions
- Does NOT throw - captures errors per destination
- Logs errors but continues to next destination

### Side Effects
- Copies files to network locations
- Multiple network read/write operations

---

## 11. Test-BackupIntegrity

**Purpose**: Validate backup archive integrity and contents

### Signature
```powershell
function Test-BackupIntegrity {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,
        
        [Parameter(Mandatory=$true)]
        [double]$MinimumSizeMB,
        
        [Parameter(Mandatory=$false)]
        [string]$ExpectedChecksum = $null
    )
    
    # Returns: ValidationResultObject
}
```

### Inputs
- **ArchivePath**: Path to .zip archive
- **MinimumSizeMB**: Minimum expected size (based on backup mode)
- **ExpectedChecksum**: SHA256 checksum to verify against

### Outputs
**Type**: ValidationResultObject (see data-model.md section 5.2)

### Behavior
1. Verify archive exists
2. Check archive size >= MinimumSizeMB
3. Test archive can be opened (`Test-Path`, `Get-Item`)
4. If ExpectedChecksum provided: Calculate and compare
5. Extract manifest and validate structure
6. Return validation result

### Error Conditions
- Does NOT throw - returns validation failures in result object

### Side Effects
- Reads archive file
- May extract manifest to temp location

---

## 12. Remove-OldBackups

**Purpose**: Apply retention policy to cleanup old backups

### Signature
```powershell
function Remove-OldBackups {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$RetentionDays,  # Per mode
        
        [Parameter(Mandatory=$true)]
        [string]$BackupMode
    )
    
    # Returns: CleanupResultObject
}
```

### Inputs
- **BackupPath**: Directory containing backups
- **RetentionDays**: Retention periods per mode
- **BackupMode**: Current backup mode (determines pattern match)

### Outputs
**Type**: CleanupResultObject

```powershell
@{
    BackupMode = "Full"
    RetentionDays = 30
    FilesScanned = 45
    FilesDeleted = 12
    SpaceFreedMB = 18547.32
    DeletedFiles = @(
        @{
            FileName = "ServerBackup_Full_20251210_020015.zip"
            SizeMB = 1523.47
            Age = 35
        }
    )
}
```

### Behavior
1. Calculate cutoff date based on RetentionDays[BackupMode]
2. Find files matching pattern: `ServerBackup_{BackupMode}_*.zip`
3. Filter files older than cutoff date
4. Delete each file
5. Return cleanup summary

### Error Conditions
- Does NOT throw - logs errors per file but continues

### Side Effects
- Deletes backup archive files

---

## 13. Write-BackupSummary

**Purpose**: Generate final backup summary report

### Signature
```powershell
function Write-BackupSummary {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$BackupState,  # BackupExecutionState object
        
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )
    
    # Returns: SummaryObject
}
```

### Inputs
- **BackupState**: Complete execution state (from data-model.md section 3.3)
- **LogPath**: Path to log file

### Outputs
**Type**: SummaryObject

```powershell
@{
    BackupMode = "Full"
    Status = "Success"
    StartTime = [datetime]
    EndTime = [datetime]
    DurationSeconds = 2538
    DurationFormatted = "42m 18s"
    
    FilesBackedUp = 12
    TotalSizeGB = 1.52
    ArchiveSizeGB = 1.50
    CompressionRatio = 0.99
    
    DestinationsCopied = 2
    DestinationsFailed = 0
    
    Warnings = 0
    Errors = 0
    
    LogFile = "D:\Alteryx\BackupLogs\BackupLog_Full_20260114_020015.log"
}
```

### Behavior
1. Aggregate all statistics from BackupState
2. Format durations and sizes for readability
3. Log summary to console and log file
4. Return summary object

### Error Conditions
None (best-effort summary generation)

### Side Effects
- Writes to log file

---

## 14. Write-Log

**Purpose**: Centralized logging function

### Signature
```powershell
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath = $script:LogFilePath  # Module-level variable
    )
}
```

### Inputs
- **Message**: Log message text
- **Level**: Log severity level
- **LogPath**: Log file path

### Outputs
None (void)

### Behavior
1. Format log entry with timestamp and level
2. Write to console (with color coding by level)
3. Append to log file
4. Ensure log file exists

### Error Conditions
- Logs errors to console if file write fails (doesn't throw)

### Side Effects
- Writes to console
- Appends to log file

---

## Summary

All 14 core functions have been specified with:
- ✅ Full parameter signatures
- ✅ Input/output types
- ✅ Behavior descriptions
- ✅ Error conditions
- ✅ Side effects

These contracts align with the data model and will guide the implementation phase.

---

**Contracts Status**: Complete  
**Next**: Quickstart Guide  
**Blockers**: None
