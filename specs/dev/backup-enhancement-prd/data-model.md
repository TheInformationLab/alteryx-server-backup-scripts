# Data Model: Alteryx Server Backup Process Enhancement

**Feature**: Modular Alteryx Server backup with three execution modes  
**Date**: 2026-01-13  
**Status**: Phase 1 - Design

---

## Overview

This document defines the data structures, configuration models, and state representations for the enhanced Alteryx Server backup solution. Since this is an operational script (not a database-backed application), the "data model" consists of configuration schemas, backup manifest structures, and operational state objects.

---

## 1. Configuration Model

### 1.1 Backup Configuration File Schema

**File**: `config/backup-config.json`  
**Format**: JSON  
**Purpose**: Centralized configuration for all backup parameters

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "BackupConfiguration": {
      "type": "object",
      "properties": {
        "DefaultBackupMode": {
          "type": "string",
          "enum": ["Full", "DatabaseOnly", "ConfigOnly"],
          "default": "Full",
          "description": "Default backup mode if not specified via parameter"
        },
        "TempDirectory": {
          "type": "string",
          "default": "D:\\Temp",
          "description": "Staging directory for backup operations"
        },
        "LocalBackupPath": {
          "type": "string",
          "default": "D:\\Alteryx\\Backups",
          "description": "Local destination for backup archives"
        },
        "NetworkBackupPaths": {
          "type": "array",
          "items": { "type": "string" },
          "default": [],
          "description": "UNC paths or mapped drives for network backup copies"
        },
        "LogDirectory": {
          "type": "string",
          "default": "D:\\Alteryx\\BackupLogs",
          "description": "Directory for backup execution logs"
        },
        "RetentionDays": {
          "type": "object",
          "properties": {
            "Full": { "type": "integer", "default": 30 },
            "DatabaseOnly": { "type": "integer", "default": 14 },
            "ConfigOnly": { "type": "integer", "default": 30 }
          },
          "description": "Retention periods per backup mode"
        }
      },
      "required": ["TempDirectory", "LocalBackupPath", "LogDirectory"]
    },
    "ServiceConfiguration": {
      "type": "object",
      "properties": {
        "MaxServiceWaitSeconds": {
          "type": "integer",
          "default": 7200,
          "description": "Maximum time to wait for service state transitions (2 hours)"
        },
        "MaxWorkflowWaitSeconds": {
          "type": "integer",
          "default": 3600,
          "description": "Maximum time to wait for active workflows to complete (1 hour)"
        },
        "ForceStopWorkflows": {
          "type": "boolean",
          "default": false,
          "description": "Whether to force-stop workflows if timeout exceeded"
        },
        "StopServiceForExternalDB": {
          "type": "boolean",
          "default": false,
          "description": "Whether to stop AlteryxService for self-managed MongoDB backups"
        }
      }
    },
    "MongoDBConfiguration": {
      "type": "object",
      "properties": {
        "Type": {
          "type": "string",
          "enum": ["auto", "embedded", "self-managed"],
          "default": "auto",
          "description": "MongoDB deployment type (auto-detect from RuntimeSettings.xml)"
        },
        "EmbeddedMongoDB": {
          "type": "object",
          "properties": {
            "UseAlteryxService": {
              "type": "boolean",
              "default": true,
              "description": "Use AlteryxService.exe emongodump command"
            }
          }
        },
        "SelfManagedMongoDB": {
          "type": "object",
          "properties": {
            "ConnectionString": {
              "type": "string",
              "default": "",
              "description": "MongoDB connection string (e.g., mongodb://host:port/db)"
            },
            "Host": {
              "type": "string",
              "default": "",
              "description": "MongoDB host (alternative to connection string)"
            },
            "Port": {
              "type": "integer",
              "default": 27017,
              "description": "MongoDB port"
            },
            "Database": {
              "type": "string",
              "default": "AlteryxGallery",
              "description": "Database name to backup"
            },
            "AuthDatabase": {
              "type": "string",
              "default": "admin",
              "description": "Authentication database"
            },
            "Username": {
              "type": "string",
              "default": "",
              "description": "MongoDB username (if authentication enabled)"
            },
            "UseCompression": {
              "type": "boolean",
              "default": true,
              "description": "Use --gzip option for mongodump"
            }
          }
        }
      }
    },
    "FilesConfiguration": {
      "type": "object",
      "properties": {
        "BackupKeys": {
          "type": "boolean",
          "default": true,
          "description": "Include Keys folder in backup"
        },
        "BackupConfigFile": {
          "type": "boolean",
          "default": true,
          "description": "Include alteryx.config if modified"
        },
        "BackupMongoPasswords": {
          "type": "boolean",
          "default": true,
          "description": "Export MongoDB passwords from AlteryxService"
        },
        "IncludeMetadata": {
          "type": "boolean",
          "default": true,
          "description": "Generate metadata file with system info"
        }
      }
    },
    "ValidationConfiguration": {
      "type": "object",
      "properties": {
        "VerifyArchiveIntegrity": {
          "type": "boolean",
          "default": true,
          "description": "Validate archive after creation"
        },
        "CalculateChecksums": {
          "type": "boolean",
          "default": true,
          "description": "Generate SHA256 checksums for files"
        },
        "MinimumBackupSizeMB": {
          "type": "object",
          "properties": {
            "Full": { "type": "number", "default": 1.0 },
            "DatabaseOnly": { "type": "number", "default": 1.0 },
            "ConfigOnly": { "type": "number", "default": 0.1 }
          },
          "description": "Minimum expected archive sizes per mode"
        }
      }
    },
    "NotificationConfiguration": {
      "type": "object",
      "properties": {
        "Enabled": {
          "type": "boolean",
          "default": false,
          "description": "Enable email notifications (Phase 7 feature)"
        },
        "SMTPServer": { "type": "string", "default": "" },
        "SMTPPort": { "type": "integer", "default": 587 },
        "UseSSL": { "type": "boolean", "default": true },
        "FromAddress": { "type": "string", "default": "" },
        "ToAddresses": {
          "type": "array",
          "items": { "type": "string" },
          "default": []
        },
        "OnlyOnFailure": {
          "type": "boolean",
          "default": true,
          "description": "Only send email on backup failure"
        }
      }
    }
  },
  "required": ["BackupConfiguration", "ServiceConfiguration", "MongoDBConfiguration"]
}
```

### 1.2 Configuration Loading Logic

**Entity**: ConfigurationObject  
**Purpose**: Merged configuration from file + parameters

**Properties**:
```powershell
@{
    BackupMode = [string]           # "Full", "DatabaseOnly", or "ConfigOnly"
    TempDirectory = [string]        # Resolved absolute path
    LocalBackupPath = [string]      # Resolved absolute path
    NetworkBackupPaths = [string[]] # Array of network destinations
    LogDirectory = [string]         # Resolved absolute path
    LogFilePath = [string]          # Full path to this execution's log
    
    RetentionDays = @{
        Full = [int]
        DatabaseOnly = [int]
        ConfigOnly = [int]
    }
    
    MaxServiceWait = [int]          # Seconds
    MaxWorkflowWait = [int]         # Seconds
    ForceStopWorkflows = [bool]
    StopServiceForExternalDB = [bool]
    
    MongoType = [string]            # "embedded" or "self-managed"
    MongoConfig = @{                # Only populated for self-managed
        Host = [string]
        Port = [int]
        Database = [string]
        Username = [string]
        Password = [SecureString]   # Never logged
    }
    
    IncludeKeys = [bool]
    IncludeConfigFile = [bool]
    IncludeMongoPasswords = [bool]
    IncludeMetadata = [bool]
    
    VerifyArchive = [bool]
    CalculateChecksums = [bool]
    MinimumSizeMB = [double]        # Per current backup mode
}
```

**Validation Rules**:
- BackupMode must be one of: Full, DatabaseOnly, ConfigOnly
- All directory paths must be absolute
- TempDirectory must have sufficient space (2x estimated MongoDB size)
- If MongoType = "self-managed", MongoConfig must be populated
- NetworkBackupPaths must be accessible (warn if not)

---

## 2. Backup Manifest Model

### 2.1 Backup Manifest Structure

**File**: `BackupManifest.json` (inside backup archive)  
**Purpose**: Metadata and validation data for the backup

```json
{
  "BackupMetadata": {
    "BackupMode": "Full",
    "BackupTimestamp": "2026-01-14T02:00:15Z",
    "BackupCompletionTimestamp": "2026-01-14T02:42:33Z",
    "DurationSeconds": 2538,
    "BackupVersion": "1.0.0",
    "ScriptVersion": "1.0.0"
  },
  "SystemInformation": {
    "AlteryxServerVersion": "2023.1.1.247",
    "ServerHostname": "ALTERYX-PROD-01",
    "WindowsVersion": "Microsoft Windows Server 2019 Standard",
    "IsMultiNode": false,
    "NodeRole": "Controller",
    "BackupPerformedBy": "NT AUTHORITY\\SYSTEM"
  },
  "MongoDBInformation": {
    "Included": true,
    "DeploymentType": "embedded",
    "DatabaseName": "AlteryxGallery_Lucid",
    "BackupMethod": "AlteryxService.exe emongodump",
    "BackupSizeMB": 1537.25,
    "CollectionCount": 42
  },
  "BackedUpFiles": [
    {
      "FilePath": "C:\\ProgramData\\Alteryx\\RuntimeSettings.xml",
      "RelativePathInArchive": "Config\\RuntimeSettings.xml",
      "SizeBytes": 15842,
      "LastModified": "2026-01-10T14:23:11Z",
      "SHA256": "a3f5c8b9d1e2..."
    },
    {
      "FilePath": "C:\\ProgramData\\Alteryx\\Keys\\",
      "RelativePathInArchive": "Config\\Keys\\",
      "Type": "Directory",
      "FileCount": 7,
      "TotalSizeBytes": 2048,
      "SHA256": null
    }
  ],
  "ControllerSettings": {
    "ControllerTokenExported": true,
    "MongoPasswordsExported": true,
    "ServiceAccountUser": "NT AUTHORITY\\NetworkService"
  },
  "ArchiveInformation": {
    "ArchiveFileName": "ServerBackup_Full_20260114_020015.zip",
    "ArchiveSizeMB": 1523.47,
    "CompressionRatio": 0.99,
    "SHA256": "e7d4c2a1b8f6...",
    "ArchiveIntegrityVerified": true
  },
  "ValidationResults": {
    "PreBackupChecks": {
      "SufficientDiskSpace": true,
      "ServiceAccessible": true,
      "NoActiveWorkflows": true,
      "AllPathsExist": true
    },
    "PostBackupChecks": {
      "ArchiveCreated": true,
      "ArchiveSizeValid": true,
      "ChecksumGenerated": true,
      "AllFilesIncluded": true
    }
  },
  "EncryptionKeyWarning": {
    "Message": "CRITICAL: Encryption keys backed up in Keys folder. Per Alteryx guidance, store backup archive containing Keys folder separately from regular backups in secure location.",
    "KeysFolder": "C:\\ProgramData\\Alteryx\\Keys\\",
    "Reference": "https://help.alteryx.com/current/en/server/install/server-host-recovery-guide/disaster-recovery-preparation.html",
    "Recommendation": "Copy this backup archive to secure vault or offline storage with restricted access."
  },
  "Warnings": [],
  "Errors": []
}
```

### 2.2 Manifest Variations by Backup Mode

**DatabaseOnly Mode**:
- `BackupMetadata.BackupMode = "DatabaseOnly"`
- `MongoDBInformation.Included = true`
- `BackedUpFiles = []` (empty, no config files)
- `ControllerSettings = null` (not included)

**ConfigOnly Mode**:
- `BackupMetadata.BackupMode = "ConfigOnly"`
- `MongoDBInformation.Included = false`
- `BackedUpFiles = [...]` (full list of config files)
- `ControllerSettings = {...}` (included)
- `SystemInformation` includes note: "ServiceNotStopped": true

---

## 3. Operational State Models

### 3.1 Service State Object

**Entity**: ServiceStateInfo  
**Purpose**: Track AlteryxService state during backup

```powershell
@{
    ServiceName = "AlteryxService"
    InitialState = [string]         # "Running", "Stopped", etc.
    CurrentState = [string]
    TargetState = [string]          # "Stopped" or "Running"
    
    HasActiveWorkflows = [bool]
    WorkflowCheckCount = [int]
    WorkflowWaitSeconds = [int]
    
    StateChangeTimestamp = [datetime]
    StateChangeSuccess = [bool]
    StateChangeError = [string]
    
    RequiresRollback = [bool]       # True if service was stopped and must be restarted
}
```

**State Transitions**:
1. Initial: Query service state
2. Pre-Stop: Check for active workflows
3. Stopping: Issue stop command
4. Stopped: Verify stopped state
5. Starting: Issue start command
6. Started: Verify started state

### 3.2 Multi-Node State Object

**Entity**: MultiNodeInfo  
**Purpose**: Track multi-node topology for sequenced operations

```powershell
@{
    IsMultiNode = [bool]
    
    ControllerNode = @{
        Hostname = [string]
        IsLocal = [bool]
    }
    
    WorkerNodes = @(
        @{
            Hostname = [string]
            IsRemote = [bool]
            ServiceState = [string]
        }
    )
    
    ServerUINode = @{
        Hostname = [string]
        IsSeparate = [bool]
        ServiceState = [string]
    }
    
    ShutdownSequence = [string[]]   # ["ServerUI", "Worker1", "Worker2", "Controller"]
    StartupSequence = [string[]]    # ["Controller", "Worker1", "Worker2", "ServerUI"]
}
```

**Detection Logic** (from research.md):
- Parse RuntimeSettings.xml `<Workers>` section for remote workers
- Parse `<ServerUI>` section for separate UI node
- Determine if current host is Controller, Worker, or UI node

### 3.3 Backup Execution State Object

**Entity**: BackupExecutionState  
**Purpose**: Track overall backup execution progress

```powershell
@{
    ExecutionId = [guid]            # Unique ID for this execution
    BackupMode = [string]
    StartTime = [datetime]
    EndTime = [datetime]
    DurationSeconds = [int]
    
    Phase = [string]                # "Initialize", "StopService", "BackupMongoDB", "BackupFiles", "Archive", "Distribute", "Validate", "Complete"
    PhaseProgress = @{
        Current = [int]
        Total = [int]
        Percentage = [int]
    }
    
    Status = [string]               # "Running", "Success", "Failed", "Warning"
    ExitCode = [int]                # 0-6
    
    FilesBackedUp = [int]
    TotalSizeBytes = [long]
    
    Errors = @(
        @{
            Phase = [string]
            Message = [string]
            Exception = [string]
            Timestamp = [datetime]
        }
    )
    
    Warnings = @(
        @{
            Phase = [string]
            Message = [string]
            Timestamp = [datetime]
        }
    )
}
```

---

## 4. File Mapping Models

### 4.1 Critical Files Registry

**Entity**: CriticalFileDefinition  
**Purpose**: Define which files to backup per mode

```powershell
$CriticalFilesRegistry = @{
    AllModes = @(
        # Included in Full and ConfigOnly, excluded from DatabaseOnly
        @{
            SourcePath = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
            DestinationPath = "Config\RuntimeSettings.xml"
            Required = $true
            Description = "Primary Alteryx Server configuration"
        },
        @{
            SourcePath = "C:\ProgramData\Alteryx\Keys\"
            DestinationPath = "Config\Keys\"
            Type = "Directory"
            Required = $true
            Description = "Encryption keys for DCM and Shared Gallery Connections"
        },
        @{
            SourcePath = "C:\ProgramData\Alteryx\Engine\SystemAlias.xml"
            DestinationPath = "Config\SystemAlias.xml"
            Required = $false
            Description = "Shared DB Connections"
        },
        @{
            SourcePath = "C:\ProgramData\Alteryx\Engine\SystemConnections.xml"
            DestinationPath = "Config\SystemConnections.xml"
            Required = $false
            Description = "In-DB Connections"
        },
        @{
            SourcePath = "C:\Program Files\Alteryx\bin\server\config\alteryx.config"
            DestinationPath = "Config\alteryx.config"
            Required = $false
            Condition = "CheckIfModified"
            Description = "Alteryx configuration file (2020.1+)"
        }
    )
    
    ControllerSettings = @(
        # Included in Full and ConfigOnly via export commands
        @{
            Command = "AlteryxService.exe getserversecret"
            OutputFile = "ControllerToken.txt"
            DestinationPath = "Config\ControllerToken.txt"
            Required = $true
        },
        @{
            Command = "AlteryxService.exe getemongopassword"
            OutputFile = "MongoPasswords.txt"
            DestinationPath = "Config\MongoPasswords.txt"
            Required = $true
        }
    )
    
    MongoDB = @(
        # Included in Full and DatabaseOnly only
        @{
            BackupCommand = "Invoke-MongoDBBackup"
            DestinationPath = "MongoDB\"
            Required = $true
            Description = "MongoDB database dump"
        }
    )
}
```

### 4.2 Backup Mode File Matrix

| File / Command | Full | DatabaseOnly | ConfigOnly |
|----------------|------|--------------|-----------|
| MongoDB Dump | ✓ | ✓ | ✗ |
| RuntimeSettings.xml | ✓ | ✗ | ✓ |
| Keys Folder | ✓ | ✗ | ✓ |
| SystemAlias.xml | ✓ | ✗ | ✓ |
| SystemConnections.xml | ✓ | ✗ | ✓ |
| alteryx.config | ✓ | ✗ | ✓ |
| ControllerToken | ✓ | ✗ | ✓ |
| MongoPasswords | ✓ | ✗ | ✓ |
| Service Account Info | ✓ | ✗ | ✓ |
| **Service Stop** | ✓ | ✓ | ✗ |

---

## 5. Validation Models

### 5.1 Pre-Backup Validation Checklist

```powershell
@{
    DiskSpaceCheck = @{
        TempDrive = [string]
        AvailableSpaceMB = [long]
        RequiredSpaceMB = [long]
        SufficientSpace = [bool]
    }
    
    PrivilegesCheck = @{
        IsAdministrator = [bool]
        CanManageService = [bool]
    }
    
    PathsCheck = @{
        TempDirectoryExists = [bool]
        LocalBackupPathExists = [bool]
        LogDirectoryExists = [bool]
        NetworkPathsAccessible = @{
            "\\backup-server\alteryx" = [bool]
        }
    }
    
    ServiceCheck = @{
        ServiceExists = [bool]
        ServiceAccessible = [bool]
        HasActiveWorkflows = [bool]
    }
    
    MongoDBCheck = @{
        TypeDetected = [string]
        ConnectionValid = [bool]  # For self-managed
    }
    
    OverallStatus = [bool]
    FailureReasons = [string[]]
}
```

### 5.2 Post-Backup Validation Checklist

```powershell
@{
    ArchiveValidation = @{
        ArchiveExists = [bool]
        ArchiveSizeMB = [double]
        MeetsMinimumSize = [bool]
        IntegrityVerified = [bool]
        ChecksumGenerated = [bool]
        ChecksumValue = [string]
    }
    
    ContentValidation = @{
        ManifestIncluded = [bool]
        ExpectedFilesPresent = [bool]
        MissingFiles = [string[]]
    }
    
    DistributionValidation = @{
        LocalCopySuccess = [bool]
        NetworkCopiesSuccess = @{
            "\\backup-server\alteryx" = [bool]
        }
    }
    
    ServiceValidation = @{
        ServiceRestored = [bool]  # Only relevant if service was stopped
        ServiceRunning = [bool]
    }
    
    OverallStatus = [bool]
    ValidationErrors = [string[]]
    ValidationWarnings = [string[]]
}
```

---

## 6. Enumeration Types

### 6.1 Backup Mode Enum

```powershell
enum BackupMode {
    Full           # MongoDB + Config files, service stop required
    DatabaseOnly   # MongoDB only, service stop required
    ConfigOnly     # Config files only, no service stop
}
```

### 6.2 Exit Code Enum

```powershell
enum BackupExitCode {
    Success = 0
    GeneralError = 1
    ServiceTimeout = 2
    ValidationFailure = 3
    StorageError = 4
    MongoDBError = 5
    InvalidBackupMode = 6
}
```

### 6.3 Log Level Enum

```powershell
enum LogLevel {
    DEBUG
    INFO
    WARNING
    ERROR
    SUCCESS
}
```

### 6.4 MongoDB Type Enum

```powershell
enum MongoDBType {
    Embedded
    SelfManaged
}
```

---

## 7. Function Signatures (Contracts)

Detailed function signatures are provided in `/contracts/function-contracts.md`.

**Core Functions**:
1. `Initialize-BackupEnvironment` → ConfigurationObject
2. `Test-AlteryxServiceState` → ServiceStateInfo
3. `Stop-AlteryxServiceSafely` → ServiceStateInfo
4. `Start-AlteryxServiceSafely` → ServiceStateInfo
5. `Invoke-MongoDBBackup` → BackupResultObject
6. `Backup-CriticalFiles` → FileBackupResultObject
7. `Export-ControllerSettings` → ControllerSettingsResultObject
8. `New-BackupManifest` → ManifestObject
9. `Compress-BackupArchive` → ArchiveResultObject
10. `Copy-BackupToDestinations` → DistributionResultObject
11. `Test-BackupIntegrity` → ValidationResultObject
12. `Remove-OldBackups` → CleanupResultObject
13. `Write-BackupSummary` → SummaryObject

---

## 8. State Machine

### Backup Execution State Flow

```
┌──────────────┐
│ Initialize   │ ← Load config, validate prerequisites
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ StopService  │ ← Stop AlteryxService (if mode requires)
└──────┬───────┘   Skip for ConfigOnly mode
       │
       ↓
┌──────────────┐
│ BackupMongoDB│ ← Execute MongoDB backup
└──────┬───────┘   Skip for ConfigOnly mode
       │
       ↓
┌──────────────┐
│ StartService │ ← Restart AlteryxService IMMEDIATELY after MongoDB backup
└──────┬───────┘   CRITICAL: Minimize downtime - all remaining operations run with service live
       │           Skip if ConfigOnly or DatabaseOnly + StopServiceForExternalDB=false
       ↓
┌──────────────┐
│ BackupFiles  │ ← Copy critical files to temp (SERVICE RUNNING)
└──────┬───────┘   Skip for DatabaseOnly mode
       │
       ↓
┌──────────────┐
│ Archive      │ ← Compress backup to .zip (SERVICE RUNNING)
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ Distribute   │ ← Copy to local/network/cloud (SERVICE RUNNING)
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ Validate     │ ← Verify archive integrity (SERVICE RUNNING)
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ Cleanup      │ ← Remove temp files, apply retention (SERVICE RUNNING)
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ Complete     │ ← Generate summary, log final status
└──────────────┘
```

**Downtime Optimization**: Service is restarted **immediately after MongoDB backup completes** (Phase: StartService) to minimize service interruption. All subsequent operations (file backup, archival, distribution, validation, cleanup) execute with the service running. This is critical for production environments.

**Error Handling**: On error at any phase:
1. Log error with context
2. If service was stopped AND error occurred before StartService phase → attempt rollback (restart service)
3. If error occurs after StartService phase → service already running, no rollback needed
4. Clean up temp files
5. Set exit code
6. Generate error report
7. Exit

---

## Summary

This data model provides the complete structure for:
- ✅ Configuration management (JSON schema + PowerShell objects)
- ✅ Backup manifest for validation and restore guidance
- ✅ Operational state tracking during execution
- ✅ File mapping per backup mode
- ✅ Pre/post validation checklists
- ✅ Type safety via enumerations
- ✅ State machine for execution flow

**Next Phase**: Generate function contracts and quickstart guide.

---

**Data Model Status**: Complete  
**Next Phase**: Contracts & Quickstart  
**Blockers**: None
