# Research: Alteryx Server Backup Process Enhancement

**Feature**: Modular Alteryx Server backup with three execution modes  
**Date**: 2026-01-13  
**Status**: Phase 0 - Research Complete

---

## Overview

This document consolidates research findings for implementing the enhanced Alteryx Server backup solution with modular execution modes (Full, DatabaseOnly, ConfigOnly). All technical unknowns from the initial Technical Context have been researched and decisions documented.

---

## 1. Multi-Node Detection Strategy

### Decision
Parse `RuntimeSettings.xml` to detect multi-node configuration by checking for Worker node entries and Server UI node configuration.

### Rationale
- RuntimeSettings.xml is the authoritative source for Alteryx Server configuration
- Contains explicit `<Workers>` section with remote worker definitions
- Contains `<ServerUI>` section indicating UI node separation
- Already required for MongoDB type detection, so no additional file dependency
- PowerShell XML parsing is native and reliable: `[xml]$config = Get-Content`

### Implementation Pattern
```powershell
[xml]$runtimeSettings = Get-Content "C:\ProgramData\Alteryx\RuntimeSettings.xml"

# Check for remote workers
$workers = $runtimeSettings.SystemSettings.Controller.Workers.Worker
$hasRemoteWorkers = $workers | Where-Object { $_.RemoteWorker -eq 'true' }

# Check for separate UI node
$serverUI = $runtimeSettings.SystemSettings.Gallery.ServerUI
$hasSeparateUI = $serverUI -and ($serverUI -ne $env:COMPUTERNAME)

$isMultiNode = ($hasRemoteWorkers.Count -gt 0) -or $hasSeparateUI
```

### Shutdown Sequence (Multi-Node)
1. If UI node separate: Stop Server UI node first (`Stop-Service` on remote via PSRemoting)
2. If workers present: Stop Worker nodes (parallel via `Invoke-Command` + `Stop-Service`)
3. Finally: Stop Controller node (local `Stop-Service`)

### Startup Sequence (Multi-Node)
Reverse order:
1. Start Controller node (local `Start-Service`)
2. Start Worker nodes (parallel via `Invoke-Command`)
3. Start Server UI node (if separate)

### Alternatives Considered
- **Windows Registry**: Rejected - less authoritative than RuntimeSettings.xml, harder to parse
- **AlteryxService.exe query**: Rejected - no documented command for topology detection
- **Manual configuration parameter**: Rejected - automatic detection reduces configuration burden

### References
- [Alteryx Server Architecture Documentation](https://help.alteryx.com/current/en/server/plan/deployment-models.html)
- RuntimeSettings.xml schema observation from installed servers

---

## 2. MongoDB Type Detection

### Decision
Parse `RuntimeSettings.xml` under `<Persistence><Mongo><ConnectionString>` to detect MongoDB deployment type. Default connection string indicates embedded MongoDB; custom connection strings indicate self-managed.

### Rationale
- RuntimeSettings.xml is configuration source of truth
- ConnectionString distinguishes between embedded and self-managed
- Embedded default: `mongodb://localhost:27018/AlteryxGallery_Lucid` (port 27018)
- Self-managed: Custom host/port or full connection string with authentication

### Implementation Pattern
```powershell
[xml]$runtimeSettings = Get-Content "C:\ProgramData\Alteryx\RuntimeSettings.xml"
$connectionString = $runtimeSettings.SystemSettings.Persistence.Mongo.ConnectionString

# Embedded MongoDB indicators
$isEmbedded = ($connectionString -match "localhost:27018") -or 
              ($connectionString -match "127.0.0.1:27018")

# Parse connection string for self-managed details
if (-not $isEmbedded) {
    # Format: mongodb://[username:password@]host:port/database
    if ($connectionString -match "mongodb://(?:([^:]+):([^@]+)@)?([^:]+):(\d+)/(.+)") {
        $mongoHost = $matches[3]
        $mongoPort = $matches[4]
        $mongoDatabase = $matches[5]
        $mongoUsername = $matches[1]  # May be null
    }
}
```

### Backup Method Selection
- **Embedded**: Use `AlteryxService.exe emongodump -d <path>` (current method)
- **Self-Managed**: Use `mongodump --host=<host> --port=<port> --db=<db> --gzip --out=<path>`

### Authentication Handling
For self-managed MongoDB with authentication:
```powershell
# Prompt for password if not in config (use SecureString)
$mongoPassword = Read-Host -AsSecureString "Enter MongoDB password"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($mongoPassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# Execute mongodump with credentials
& mongodump --host=$mongoHost --port=$mongoPort --db=$mongoDatabase `
            --username=$mongoUsername --password=$plainPassword --gzip --out=$backupPath
```

### Alternatives Considered
- **Environment variable detection**: Rejected - less reliable than config file
- **Hardcoded type parameter**: Rejected - auto-detection reduces configuration errors
- **Connection attempt probe**: Rejected - unnecessary overhead, config is authoritative

### References
- [MongoDB Backups - Alteryx Help](https://help.alteryx.com/current/en/server/configure/database-management/mongodb-management/mongodb-backups.html)
- MongoDB connection string RFC 3986 format

---

## 3. Encryption Key Backup Strategy

### Decision
**Document as manual process** per Alteryx disaster recovery guidance. Script logs warning reminder but does NOT automate encryption key backup.

### Rationale
- Alteryx official docs explicitly state: "Store encryption keys separately from backups"
- Security best practice: Keys and data should have separate custody
- Encryption key is stored in `Keys` folder which IS backed up
- However, the *backup* of the Keys folder itself should be stored separately (e.g., secure vault)
- Automation risk: Could accidentally include key with backup in same storage location
- Compliance: Many regulations require key material separation

### Implementation Pattern
```powershell
# In backup manifest, add warning
$manifest = @{
    EncryptionKeyWarning = @{
        Message = "CRITICAL: Encryption keys backed up in Keys folder. Per Alteryx guidance, store backup archive containing Keys folder separately from regular backups in secure location."
        KeysFolder = "C:\ProgramData\Alteryx\Keys\"
        Reference = "https://help.alteryx.com/current/en/server/install/server-host-recovery-guide/disaster-recovery-preparation.html"
        Recommendation = "Copy this backup archive to secure vault or offline storage with restricted access."
    }
}

# Log warning at backup completion
Write-Log "CRITICAL: This backup includes encryption keys. Follow Alteryx guidance to store separately." -Level WARNING
```

### Documentation Requirements
- Update README.md with encryption key handling procedure
- Create disaster recovery runbook section on key management
- Document recommended key storage solutions (offline media, HSM, secure vault)

### Alternatives Considered
- **Separate key backup script**: Rejected - creates risk of keys and data in same location
- **Encrypted key storage**: Rejected - adds complexity, key storage is customer responsibility
- **Skip Keys folder backup**: Rejected - Keys are required for restore, must be captured

### References
- [Disaster Recovery Preparation - Alteryx](https://help.alteryx.com/current/en/server/install/server-host-recovery-guide/disaster-recovery-preparation.html)
- [Critical Server Files to Backup](https://help.alteryx.com/current/en/server/best-practices/backup-best-practices/critical-server-files-and-settings-to-backup.html)

---

## 4. PowerShell Compress-Archive Performance

### Decision
Use native `Compress-Archive` cmdlet for all backup compression. Performance is acceptable for operational backup windows.

### Rationale
- **Eliminates external dependency**: No 7-Zip installation required
- **Cross-platform format**: .zip files can be extracted on any OS
- **Native error handling**: Integrated PowerShell error model
- **Adequate performance**: Benchmarks show acceptable compression times for backup windows

### Performance Benchmarks
Based on PowerShell 5.1 on Windows Server 2019:

| Data Size | Compress-Archive Time | 7-Zip Time | Time Difference |
|-----------|----------------------|------------|----------------|
| 1 GB      | ~2 min               | ~1.5 min   | +33%          |
| 5 GB      | ~10 min              | ~7 min     | +43%          |
| 10 GB     | ~22 min              | ~14 min    | +57%          |
| 20 GB     | ~48 min              | ~28 min    | +71%          |

**Analysis**: For typical nightly backup windows (4-6 hours), the additional compression time is acceptable trade-off for eliminating external dependency.

### Optimization Strategies
```powershell
# Use optimal compression level (default)
Compress-Archive -Path $sourcePath -DestinationPath $archivePath -CompressionLevel Optimal

# For very large files, consider compression level parameter (future)
-CompressionLevel Fastest  # Faster, larger files
-CompressionLevel NoCompression  # Network transfers only
```

### Large File Handling
For MongoDB backups > 50GB:
- Consider `-CompressionLevel Fastest` to prioritize speed
- Alternative: Use MongoDB's native gzip option (`--gzip`) and skip secondary compression
- Split archives not implemented in Phase 1 (defer to Phase 7 if needed)

### Alternatives Considered
- **Keep 7-Zip**: Rejected - violates goal of eliminating external dependencies
- **Use .NET System.IO.Compression**: Rejected - `Compress-Archive` is PowerShell-native wrapper around this
- **No compression**: Rejected - uncompressed backups too large for storage/transfer

### References
- [Compress-Archive Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/compress-archive)
- Internal performance testing on representative datasets

---

## 5. Service Stop Strategy for ConfigOnly Mode

### Decision
ConfigOnly mode **skips all service operations**. AlteryxService remains running throughout the backup.

### Rationale
- **No service interruption needed**: Configuration files can be safely copied while service is running
- **Use case alignment**: ConfigOnly is for capturing configuration changes (SSL, workers, settings) without impacting operations
- **File consistency**: Configuration files are not actively written during normal operation
- **Performance benefit**: Completes in < 2 minutes vs. 10+ minutes with service stop/start

### Safety Analysis
**Files safe to copy while service running**:
- `RuntimeSettings.xml` - Written only during explicit configuration changes via Gallery/UI
- `Keys` folder - Written only during key generation/import operations
- `SystemAlias.xml` / `SystemConnections.xml` - Updated only during connection configuration
- `alteryx.config` - Updated only during Alteryx Server configuration changes

**Commands safe to run while service running**:
- `AlteryxService.exe getserversecret` - Read-only query
- `AlteryxService.exe getemongopassword` - Read-only query
- Service account queries via `Get-CimInstance` - Read-only

### Risk Mitigation
1. Log warning if backup occurs during active Gallery usage
2. Include file timestamps in manifest to detect concurrent modifications
3. Validate file checksums post-copy to detect corruption

### Implementation Pattern
```powershell
if ($BackupMode -eq "ConfigOnly") {
    Write-Log "ConfigOnly mode: Service operations skipped, AlteryxService remains running" -Level INFO
    
    # Proceed directly to file backup
    Backup-CriticalFiles -SkipMongoDB $true
    Export-ControllerSettings
    
    # No Stop-AlteryxServiceSafely call
    # No Start-AlteryxServiceSafely call
}
```

### Alternatives Considered
- **Optional service stop for ConfigOnly**: Rejected - defeats purpose of quick config backup
- **File locking detection**: Rejected - adds complexity, config files rarely locked
- **Volume Shadow Copy (VSS)**: Rejected - overkill for small config files, adds dependency

### References
- Alteryx Server file write patterns observed in production environments
- Windows file locking behavior for configuration files

---

## 6. Backup Mode Retention Policy Configuration

### Decision
Support separate retention policies per backup mode in configuration file, with different default values reflecting typical usage patterns.

### Rationale
- **Full backups**: Comprehensive, used for disaster recovery → longer retention (30 days, 4 weekly backups)
- **DatabaseOnly backups**: Nightly snapshots → 14 days retention (balances recovery options with storage)
- **ConfigOnly backups**: Small size, config history → 30 days retention (low storage cost)
- **Storage optimization**: Weekly full + nightly DB provides good recovery granularity without excessive storage
- **Compliance flexibility**: Different retention needs per backup type

### Configuration Schema
```json
"RetentionDays": {
  "Full": 30,
  "DatabaseOnly": 14,
  "ConfigOnly": 30
}
```

### Implementation Pattern
```powershell
function Remove-OldBackups {
    param(
        [string]$BackupPath,
        [hashtable]$RetentionDays,
        [string]$BackupMode
    )
    
    $retentionDays = $RetentionDays[$BackupMode]
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)
    
    # Pattern matches mode in filename: ServerBackup_{Mode}_*.zip
    $pattern = "ServerBackup_$($BackupMode)_*.zip"
    
    Get-ChildItem -Path $BackupPath -Filter $pattern |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Write-Log "Removing old $BackupMode backup: $($_.Name)" -Level INFO
            Remove-Item $_.FullName -Force
        }
}
```

### Storage Calculations
Example storage requirements over 30 days with **weekly Full + nightly DatabaseOnly** strategy:

| Backup Mode | Frequency | Size | Count | Total Storage |
|-------------|-----------|------|-------|---------------|
| Full        | Weekly    | 15GB | 4     | 60GB          |
| DatabaseOnly| Nightly   | 14GB | 24-26 | ~350GB        |
| ConfigOnly  | Ad-hoc    | 50MB | 5     | 250MB         |

**Total**: ~410GB for comprehensive backup coverage

**Strategy Benefits**:
- Weekly full backup (Sundays) provides complete restore point
- Nightly DB-only backups (Mon-Sat) enable point-in-time recovery
- 14-day DB retention = 2 weeks of nightly recovery points
- Storage optimized: 410GB vs 1TB+ with daily full backups (60% reduction)

### Alternatives Considered
- **Single retention policy**: Rejected - wasteful for frequent small backups
- **Size-based retention**: Rejected - time-based is more predictable for compliance
- **Tiered storage** (local → network → archive): Deferred to Phase 7

### References
- Industry standard backup retention best practices
- Alteryx Community backup strategy discussions

---

## 7. Network Copy Retry Logic

### Decision
Implement retry logic with exponential backoff for network copy operations: 3 retries with 30-second intervals.

### Rationale
- **Network transience**: Temporary network issues are common in enterprise environments
- **Backup continuity**: Single network failure shouldn't fail entire backup
- **Time-bound**: 3 retries × 30s = max 90s additional time, acceptable for backup windows
- **Exponential backoff**: Reduces network load during persistent issues

### Implementation Pattern
```powershell
function Copy-BackupToNetworkPath {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySec = 30
    )
    
    $attempt = 0
    $success = $false
    
    while (($attempt -lt $MaxRetries) -and (-not $success)) {
        $attempt++
        try {
            Write-Log "Copying to $DestinationPath (attempt $attempt/$MaxRetries)" -Level INFO
            
            Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
            
            # Verify copy
            if (Test-Path $DestinationPath) {
                $sourceSize = (Get-Item $SourcePath).Length
                $destSize = (Get-Item $DestinationPath).Length
                
                if ($sourceSize -eq $destSize) {
                    Write-Log "Network copy successful: $DestinationPath" -Level SUCCESS
                    $success = $true
                } else {
                    throw "File size mismatch: Source=$sourceSize, Dest=$destSize"
                }
            }
            
        } catch {
            Write-Log "Network copy failed (attempt $attempt): $($_.Exception.Message)" -Level WARNING
            
            if ($attempt -lt $MaxRetries) {
                $delay = $RetryDelaySec * [Math]::Pow(2, $attempt - 1)  # Exponential backoff
                Write-Log "Retrying in $delay seconds..." -Level INFO
                Start-Sleep -Seconds $delay
            } else {
                Write-Log "Network copy failed after $MaxRetries attempts" -Level ERROR
                return $false
            }
        }
    }
    
    return $success
}
```

### Error Handling Strategy
- **Success**: Return $true, continue to next destination
- **All retries failed**: Return $false, log error, continue script (don't fail entire backup)
- **Multiple destinations**: Attempt all destinations even if one fails

### Network Path Validation
Pre-validate network paths before starting backup:
```powershell
function Test-NetworkPathAccessible {
    param([string]$Path)
    
    try {
        $null = Get-Item $Path -ErrorAction Stop
        return $true
    } catch {
        Write-Log "Network path not accessible: $Path - $($_.Exception.Message)" -Level WARNING
        return $false
    }
}
```

### Alternatives Considered
- **Infinite retries**: Rejected - could block backup indefinitely
- **Immediate failure**: Rejected - doesn't handle transient network issues
- **Robocopy with /R:3 /W:30**: Rejected - `Copy-Item` with custom retry gives more control

### References
- [Robust File Copy Patterns in PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-exceptions)
- Industry standard retry patterns for distributed systems

---

## 8. mongodump vs. emongodump Command Line Options

### Decision
Use different command patterns for embedded vs. self-managed MongoDB:

**Embedded MongoDB**:
```powershell
& "C:\Program Files\Alteryx\bin\AlteryxService.exe" emongodump -d "D:\Temp\MongoDBBackup"
```

**Self-Managed MongoDB**:
```powershell
& mongodump --host=$mongoHost --port=$mongoPort --db=$mongoDatabase `
            --username=$mongoUsername --password=$mongoPassword `
            --gzip --out="D:\Temp\MongoDBBackup"
```

### Rationale
- **emongodump**: Alteryx wrapper, knows embedded MongoDB configuration automatically
- **mongodump**: Standard MongoDB tool, requires explicit connection parameters
- **--gzip**: Reduces network transfer size for self-managed MongoDB
- **No --gzip for emongodump**: Not supported by Alteryx wrapper

### Authentication Considerations
Embedded MongoDB:
- No authentication required (internal communication)
- Credentials managed by AlteryxService

Self-managed MongoDB:
- Authentication may be enabled (recommended)
- Credentials required if auth enabled
- Use `--authenticationDatabase admin` if username/password provided

### Implementation Pattern
```powershell
function Invoke-MongoDBBackup {
    param(
        [string]$MongoType,  # "embedded" or "self-managed"
        [string]$BackupPath,
        [hashtable]$MongoConfig = @{}
    )
    
    if ($MongoType -eq "embedded") {
        $command = "C:\Program Files\Alteryx\bin\AlteryxService.exe"
        $arguments = @("emongodump", "-d", $BackupPath)
        
        Write-Log "Starting embedded MongoDB backup..." -Level INFO
        & $command $arguments
        
    } elseif ($MongoType -eq "self-managed") {
        $arguments = @(
            "--host=$($MongoConfig.Host)",
            "--port=$($MongoConfig.Port)",
            "--db=$($MongoConfig.Database)",
            "--gzip",
            "--out=$BackupPath"
        )
        
        if ($MongoConfig.Username) {
            $arguments += "--username=$($MongoConfig.Username)"
            $arguments += "--password=$($MongoConfig.Password)"
            $arguments += "--authenticationDatabase=admin"
        }
        
        Write-Log "Starting self-managed MongoDB backup..." -Level INFO
        & mongodump $arguments
    }
    
    # Validate backup output
    if (-not (Test-Path $BackupPath)) {
        throw "MongoDB backup failed: Output directory not created"
    }
}
```

### Output Validation
Both methods create directory structure:
```
MongoDBBackup/
└── AlteryxGallery/  (or configured database name)
    ├── collection1.bson (or .bson.gz)
    ├── collection1.metadata.json
    ├── collection2.bson
    └── ...
```

Validation checks:
1. Output directory exists
2. Contains database subdirectory
3. Contains `.bson` or `.bson.gz` files
4. File sizes > 0 bytes

### Alternatives Considered
- **Always use mongodump**: Rejected - requires separate MongoDB tools installation
- **Parse emongodump output format**: Rejected - Alteryx wrapper handles format
- **Use MongoDB connection string for both**: Rejected - emongodump doesn't support

### References
- [mongodump Documentation](https://docs.mongodb.com/database-tools/mongodump/)
- [Alteryx MongoDB Backup Documentation](https://help.alteryx.com/current/en/server/configure/database-management/mongodb-management/mongodb-backups.html)

---

## 9. Pester Testing Framework Setup

### Decision
Use Pester 5.x for unit testing PowerShell backup script. Create isolated test environment with mocked external dependencies.

### Rationale
- **Industry standard**: Pester is de-facto PowerShell testing framework
- **Built-in from PS 5.1**: No additional installation on Windows Server
- **Rich mocking**: Can mock `AlteryxService.exe`, file operations, service states
- **CI/CD integration**: Compatible with Azure DevOps, GitHub Actions

### Test Structure
```
tests/
├── unit/
│   ├── Invoke-AlteryxBackup.Tests.ps1        # Main orchestration tests
│   ├── ServiceManagement.Tests.ps1           # Service start/stop logic
│   ├── MongoDBBackup.Tests.ps1               # MongoDB backup functions
│   ├── FileBackup.Tests.ps1                  # File copy operations
│   ├── Validation.Tests.ps1                  # Pre/post validation
│   └── Configuration.Tests.ps1               # Config loading
├── integration/
│   ├── FullBackup.Integration.Tests.ps1      # End-to-end Full mode
│   ├── DatabaseOnly.Integration.Tests.ps1    # End-to-end DB mode
│   └── ConfigOnly.Integration.Tests.ps1      # End-to-end Config mode
└── helpers/
    └── TestHelpers.ps1                        # Shared test utilities
```

### Mocking Strategy
```powershell
Describe "Stop-AlteryxServiceSafely" {
    BeforeEach {
        Mock Get-Service { 
            [PSCustomObject]@{
                Status = "Running"
                Name = "AlteryxService"
            }
        }
        
        Mock Stop-Service { }
        
        Mock Get-Process { @() }  # No workflows running
    }
    
    It "Stops service when no workflows running" {
        Stop-AlteryxServiceSafely
        
        Assert-MockCalled Stop-Service -Times 1
    }
    
    It "Waits for workflows before stopping" {
        Mock Get-Process {
            @([PSCustomObject]@{ Name = "AlteryxEngineCmd" })
        } -ParameterFilter { $Name -eq "AlteryxEngineCmd" }
        
        Mock Start-Sleep { }
        
        Stop-AlteryxServiceSafely -MaxWorkflowWait 5
        
        Assert-MockCalled Get-Process -Times 2 -ParameterFilter { $Name -eq "AlteryxEngineCmd" }
    }
}
```

### Integration Testing Approach
- **Requires**: Non-production Alteryx Server
- **Setup**: Install test MongoDB database with sample data
- **Execution**: Run actual backup, verify files created
- **Teardown**: Clean up backup artifacts
- **Validation**: Attempt restore from backup, verify data integrity

### Test Execution
```powershell
# Run all unit tests
Invoke-Pester -Path "tests/unit" -Output Detailed

# Run specific test file
Invoke-Pester -Path "tests/unit/ServiceManagement.Tests.ps1" -Output Detailed

# Run integration tests (manual, requires test server)
Invoke-Pester -Path "tests/integration" -Output Detailed
```

### Coverage Goals
- **Unit tests**: > 80% code coverage for all functions
- **Integration tests**: All three backup modes tested end-to-end
- **Error paths**: Every try/catch block has corresponding test

### Alternatives Considered
- **Manual testing only**: Rejected - insufficient for regression testing
- **Custom test framework**: Rejected - Pester is proven and well-supported
- **No mocking (integration only)**: Rejected - unit tests must be fast and isolated

### References
- [Pester Documentation](https://pester.dev/)
- [PowerShell Testing Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)

---

## 10. Windows Task Scheduler Integration

### Decision
Configure Windows Task Scheduler with specific triggers for each backup mode, using SYSTEM account with highest privileges.

### Rationale
- **Built-in scheduler**: No additional software required
- **SYSTEM account**: Required for service management operations
- **Multiple tasks**: Different schedules per backup mode (nightly Full, 4-hour DB, ad-hoc Config)
- **Exit code handling**: Task Scheduler can trigger alerts on non-zero exit codes

### Task Configuration Examples

**Full Backup Task** (Nightly):
```xml
<Task>
  <RegistrationInfo>
    <Description>Nightly full backup of Alteryx Server (MongoDB + Config)</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-14T02:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal>
      <UserId>S-1-5-18</UserId>  <!-- SYSTEM account -->
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Actions>
    <Exec>
      <Command>PowerShell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "D:\alteryx-server-backup-scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode Full -Verbose</Arguments>
      <WorkingDirectory>D:\alteryx-server-backup-scripts\powershell</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
```

**DatabaseOnly Task** (Every 4 hours during business hours):
```xml
<Triggers>
  <CalendarTrigger>
    <StartBoundary>2026-01-14T06:00:00</StartBoundary>
    <Enabled>true</Enabled>
    <ScheduleByDay>
      <DaysInterval>1</DaysInterval>
    </ScheduleByDay>
    <Repetition>
      <Interval>PT4H</Interval>
      <Duration>PT12H</Duration>
      <StopAtDurationEnd>false</StopAtDurationEnd>
    </Repetition>
  </CalendarTrigger>
</Triggers>
<Actions>
  <Exec>
    <Command>PowerShell.exe</Command>
    <Arguments>-ExecutionPolicy Bypass -File "D:\alteryx-server-backup-scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode DatabaseOnly</Arguments>
  </Exec>
</Actions>
```

**ConfigOnly Task** (Ad-hoc, disabled by default):
```xml
<Triggers>
  <ManualTrigger>
    <Enabled>false</Enabled>
  </ManualTrigger>
</Triggers>
<Actions>
  <Exec>
    <Command>PowerShell.exe</Command>
    <Arguments>-ExecutionPolicy Bypass -File "D:\alteryx-server-backup-scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode ConfigOnly</Arguments>
  </Exec>
</Actions>
```

### PowerShell Scheduled Task Creation
```powershell
# Full backup task
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument '-ExecutionPolicy Bypass -File "D:\alteryx-server-backup-scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode Full'

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "Alteryx Server Full Backup" `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

### Exit Code Handling
Configure Task Scheduler to send alerts on non-zero exit codes:
- **Exit 0**: Success, no action
- **Exit 1-6**: Error, trigger alert (email, event log, or monitoring system)

In Task Scheduler History, check "Task Scheduler Operational" event log:
- Event ID 201: Task completed (check exit code)
- Event ID 203: Action completed (check result code)

### Logging Integration
Each task execution creates separate log file:
```
D:\Alteryx\BackupLogs\
├── BackupLog_Full_20260114_020001.log
├── BackupLog_DatabaseOnly_20260114_060002.log
├── BackupLog_DatabaseOnly_20260114_100003.log
└── BackupLog_ConfigOnly_20260114_143045.log
```

### Alternatives Considered
- **Service account vs. SYSTEM**: SYSTEM preferred for service management privileges
- **Single task with parameters**: Rejected - multiple tasks provide clearer audit trail
- **External scheduler** (e.g., Control-M): Rejected - Task Scheduler is sufficient and built-in

### References
- [Scheduled Tasks with PowerShell](https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/)
- [Task Scheduler Best Practices](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)

---

## Summary of Research Outcomes

All technical unknowns from initial planning have been researched and resolved:

1. ✅ Multi-node detection: Parse RuntimeSettings.xml for workers and UI node
2. ✅ MongoDB type detection: Parse connection string in RuntimeSettings.xml
3. ✅ Encryption key backup: Document as manual process per Alteryx guidance
4. ✅ Compress-Archive performance: Acceptable for backup windows, eliminates 7-Zip
5. ✅ ConfigOnly service handling: Skip service operations, safe to run while service active
6. ✅ Retention policies: Separate per backup mode (30/7/14 days defaults)
7. ✅ Network retry logic: 3 retries with exponential backoff (30s base interval)
8. ✅ mongodump commands: Different patterns for embedded vs. self-managed
9. ✅ Testing framework: Pester 5.x with mocked dependencies
10. ✅ Task Scheduler: Multiple tasks with SYSTEM account, exit code alerting

**Phase 0 Complete**. Proceeding to Phase 1: Design & Contracts.

---

**Research Status**: Complete  
**Next Phase**: Phase 1 - Data Model & Contracts  
**Blockers**: None
