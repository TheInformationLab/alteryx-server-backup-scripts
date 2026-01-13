# Quick Start Guide: Alteryx Server Backup

**Script**: `Invoke-AlteryxBackup.ps1`  
**Version**: 1.0.0  
**Last Updated**: 2026-01-13

---

## Prerequisites

- Windows Server 2016+ with Alteryx Server 2020.1+ installed
- PowerShell 5.1+
- Administrator privileges required
- Sufficient disk space (2x MongoDB size for Full/DatabaseOnly backups)

---

## Basic Usage

### Full Backup (Default)
Complete backup including MongoDB and all configuration files. Service stop required.

```powershell
# Run with defaults
.\Invoke-AlteryxBackup.ps1

# With verbose logging
.\Invoke-AlteryxBackup.ps1 -Verbose

# Specify backup mode explicitly
.\Invoke-AlteryxBackup.ps1 -BackupMode Full
```

**When to use**: Weekly comprehensive backups, pre-upgrade backups

---

### DatabaseOnly Backup
MongoDB backup only, no configuration files. Service stop required.

```powershell
.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly

# With custom retention
.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly -ConfigPath ".\config\db-only-config.json"
```

**When to use**: Nightly database snapshots between weekly full backups

---

### ConfigOnly Backup
Configuration files only, no MongoDB. **No service stop** - zero interruption.

```powershell
.\Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly

# Quick config backup after changes
.\Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly -Verbose
```

**When to use**: After SSL updates, worker configuration changes, Gallery settings changes

---

## Configuration

### Default Configuration File
Create `config/backup-config.json` in script directory:

```json
{
  "BackupConfiguration": {
    "DefaultBackupMode": "Full",
    "TempDirectory": "D:\\Temp",
    "LocalBackupPath": "D:\\Alteryx\\Backups",
    "NetworkBackupPaths": [
      "\\\\backup-server\\alteryx\\"
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
  }
}
```

### Command-Line Overrides
Parameters override config file:

```powershell
.\Invoke-AlteryxBackup.ps1 `
    -BackupMode Full `
    -TempDirectory "E:\Temp" `
    -LocalBackupPath "E:\Backups" `
    -NetworkBackupPath "\\backup-server\alteryx-prod" `
    -Verbose
```

---

## Common Scenarios

### Scenario 1: First-Time Setup

1. **Create config file**:
```powershell
Copy-Item ".\config\backup-config.example.json" ".\config\backup-config.json"
# Edit backup-config.json with your paths
```

2. **Test ConfigOnly backup** (no service impact):
```powershell
.\Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly -Verbose
```

3. **Test DatabaseOnly backup** (during maintenance window):
```powershell
.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly -Verbose
```

4. **Test Full backup** (during maintenance window):
```powershell
.\Invoke-AlteryxBackup.ps1 -BackupMode Full -Verbose
```

5. **Verify backup archive**:
```powershell
# Check backup created
Get-ChildItem "D:\Alteryx\Backups" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

# Check log file
Get-Content "D:\Alteryx\BackupLogs\BackupLog_Full_*.log" -Tail 20
```

---

### Scenario 2: Scheduled Tasks

#### Weekly Full Backup (Sunday 2:00 AM)
```powershell
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument '-ExecutionPolicy Bypass -File "D:\Scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode Full'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "02:00"

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest

Register-ScheduledTask `
    -TaskName "Alteryx Server Full Backup (Weekly)" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal
```

#### Nightly DatabaseOnly Backup (2:00 AM, Monday-Saturday)
```powershell
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument '-ExecutionPolicy Bypass -File "D:\Scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode DatabaseOnly'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday,Saturday -At "02:00"

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest

Register-ScheduledTask `
    -TaskName "Alteryx Server DB Backup (Nightly)" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal
```

#### Ad-Hoc ConfigOnly Task (Manual Trigger)
```powershell
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument '-ExecutionPolicy Bypass -File "D:\Scripts\powershell\Invoke-AlteryxBackup.ps1" -BackupMode ConfigOnly'

$trigger = New-ScheduledTaskTrigger -AtStartup  # Disabled by default

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable:$false

$task = Register-ScheduledTask `
    -TaskName "Alteryx Server Config Backup (Manual)" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings

# Disable trigger so it's manual only
$task.Triggers[0].Enabled = $false
Set-ScheduledTask -InputObject $task
```

**Run manual task**:
```powershell
Start-ScheduledTask -TaskName "Alteryx Server Config Backup (Manual)"
```

---

### Scenario 3: Pre-Upgrade Backup

Before upgrading Alteryx Server:

```powershell
# 1. Full backup to multiple locations
.\Invoke-AlteryxBackup.ps1 `
    -BackupMode Full `
    -NetworkBackupPath @("\\backup-server\alteryx-prod", "\\dr-server\alteryx-archive") `
    -Verbose

# 2. Verify backup created
$latestBackup = Get-ChildItem "D:\Alteryx\Backups\ServerBackup_Full_*.zip" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

Write-Host "Latest backup: $($latestBackup.FullName)"
Write-Host "Backup size: $([math]::Round($latestBackup.Length / 1MB, 2)) MB"
Write-Host "Backup time: $($latestBackup.LastWriteTime)"

# 3. Test archive integrity
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($latestBackup.FullName)
Write-Host "Archive entries: $($archive.Entries.Count)"
$archive.Dispose()

Write-Host "✓ Backup verified. Safe to proceed with upgrade."
```

---

### Scenario 4: Self-Managed MongoDB

If using external MongoDB (not embedded):

**Update config file**:
```json
{
  "MongoDBConfiguration": {
    "Type": "self-managed",
    "SelfManagedMongoDB": {
      "Host": "mongo-server.company.com",
      "Port": 27017,
      "Database": "AlteryxGallery",
      "Username": "alteryx_backup",
      "UseCompression": true
    }
  }
}
```

**Run backup** (will prompt for password):
```powershell
.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly
# Enter password when prompted (not logged)
```

**Or use parameter**:
```powershell
$securePassword = Read-Host -AsSecureString "Enter MongoDB password"
.\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly -MongoPassword $securePassword
```

---

## Backup Outputs

### Archive Naming Convention
```
ServerBackup_{Mode}_{Date}_{Time}.zip

Examples:
- ServerBackup_Full_20260114_020015.zip
- ServerBackup_DB_20260114_060230.zip
- ServerBackup_Config_20260114_143052.zip
```

### Archive Contents

**Full Mode**:
```
ServerBackup_Full_20260114_020015.zip
├── BackupManifest.json
├── MongoDB/
│   └── AlteryxGallery/
│       ├── collection1.bson
│       ├── collection2.bson
│       └── ...
└── Config/
    ├── RuntimeSettings.xml
    ├── Keys/
    │   ├── key1.dat
    │   └── ...
    ├── SystemAlias.xml
    ├── SystemConnections.xml
    ├── alteryx.config
    ├── ControllerToken.txt
    └── MongoPasswords.txt
```

**DatabaseOnly Mode**:
```
ServerBackup_DB_20260114_060230.zip
├── BackupManifest.json
└── MongoDB/
    └── AlteryxGallery/
        ├── collection1.bson
        └── ...
```

**ConfigOnly Mode**:
```
ServerBackup_Config_20260114_143052.zip
├── BackupManifest.json
└── Config/
    ├── RuntimeSettings.xml
    ├── Keys/
    ├── SystemAlias.xml
    ├── SystemConnections.xml
    ├── alteryx.config
    ├── ControllerToken.txt
    └── MongoPasswords.txt
```

---

## Log Files

### Location
```
D:\Alteryx\BackupLogs\BackupLog_{Mode}_{Date}_{Time}.log
```

### Log Format
```
[2026-01-14 02:00:15] [INFO] Starting Alteryx Server backup in Full mode
[2026-01-14 02:00:16] [INFO] Configuration loaded from config/backup-config.json
[2026-01-14 02:00:17] [INFO] MongoDB type detected: embedded
[2026-01-14 02:00:18] [INFO] No active workflows detected
[2026-01-14 02:00:19] [INFO] Stopping AlteryxService...
[2026-01-14 02:00:45] [SUCCESS] Service stopped successfully
[2026-01-14 02:00:46] [INFO] Starting MongoDB backup...
[2026-01-14 02:15:32] [SUCCESS] MongoDB backup complete: 1537.25 MB
[2026-01-14 02:15:33] [INFO] Backing up critical files...
[2026-01-14 02:16:12] [SUCCESS] Backed up 12 files (2.48 MB)
[2026-01-14 02:16:13] [INFO] Creating backup archive...
[2026-01-14 02:39:45] [SUCCESS] Archive created: ServerBackup_Full_20260114_020015.zip (1523.47 MB)
[2026-01-14 02:39:46] [INFO] Starting AlteryxService...
[2026-01-14 02:40:22] [SUCCESS] Service started successfully
[2026-01-14 02:40:23] [SUCCESS] Backup completed successfully in 40m 8s
```

### Check Last Backup Status
```powershell
# Get latest log
$latestLog = Get-ChildItem "D:\Alteryx\BackupLogs\BackupLog_*.log" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

# Show summary (last 10 lines)
Get-Content $latestLog.FullName -Tail 10

# Check for errors
$errors = Get-Content $latestLog.FullName | Select-String "ERROR"
if ($errors) {
    Write-Host "⚠ Errors found:" -ForegroundColor Yellow
    $errors
} else {
    Write-Host "✓ No errors in latest backup" -ForegroundColor Green
}
```

---

## Exit Codes

Script returns exit codes for Task Scheduler integration:

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | None |
| 1 | General error | Check log file |
| 2 | Service timeout | Increase timeout or investigate |
| 3 | Validation failure | Check archive integrity |
| 4 | Storage error | Check disk space / network paths |
| 5 | MongoDB error | Check MongoDB connection |
| 6 | Invalid backup mode | Fix parameter value |

**Check exit code in scheduled task**:
1. Open Task Scheduler
2. Find task → History tab
3. Look for Event ID 201 (Task completed)
4. Check "Result" column (0x0 = success, 0x1 = exit code 1, etc.)

---

## Troubleshooting

### "Not running as Administrator"
**Solution**: Run PowerShell as Administrator or update scheduled task to use "Highest" privileges

### "Service timeout"
**Cause**: Active workflows didn't complete in time  
**Solution**: Increase `MaxWorkflowWaitSeconds` in config, or stop workflows manually before backup

### "Insufficient disk space"
**Cause**: Not enough space in temp directory  
**Solution**: Clean up temp directory or use different temp path with more space

### "Network path not accessible"
**Cause**: Network destination unreachable  
**Solution**: Script will retry 3 times then continue - check network connectivity, verify path exists

### "MongoDB backup failed"
**Cause**: MongoDB connection issue or AlteryxService.exe not found  
**Solution**: 
- Verify AlteryxService.exe exists at `C:\Program Files\Alteryx\bin\AlteryxService.exe`
- For self-managed MongoDB: Check connection string and credentials

---

## Backup Mode Comparison

| Feature | Full | DatabaseOnly | ConfigOnly |
|---------|------|--------------|-----------|
| MongoDB Backup | ✓ | ✓ | ✗ |
| Config Files | ✓ | ✗ | ✓ |
| Service Stop | ✓ | ✓ | ✗ |
| Downtime | **~15-30min** | **~15-30min** | **No** |
| Total Duration | Long (30-60min) | Medium (15-30min) | Fast (<2min) |
| Downtime Note | Service restarts after MongoDB backup; remaining operations run with service live | Service restarts after MongoDB backup | Zero interruption |
| Typical Size | Large (1-50GB) | Large (1-50GB) | Small (<100MB) |
| Best For | Weekly comprehensive, pre-upgrade | Nightly snapshots | Config changes |

---

## Next Steps

1. **Create configuration file**: Copy and edit `config/backup-config.example.json`
2. **Test ConfigOnly backup**: Zero-impact test run
3. **Test DatabaseOnly backup**: During maintenance window
4. **Test Full backup**: During maintenance window
5. **Set up scheduled tasks**: Weekly Full (Sundays) + Nightly DatabaseOnly (Mon-Sat)
6. **Monitor for 2 weeks**: Check logs and archive sizes
7. **Document restore procedure**: Test restore in non-production environment

---

## Support

- **Documentation**: See `README.md` for detailed information
- **Logs**: Check `D:\Alteryx\BackupLogs\` for execution logs
- **Troubleshooting**: See PRD Section 9.3.6 for comprehensive troubleshooting guide

---

**Quick Start Guide Version**: 1.0.0  
**Last Updated**: 2026-01-13
