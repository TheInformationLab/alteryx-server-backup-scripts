# Alteryx Server Backup Scripts - AI Coding Agent Instructions

## Project Overview
Windows-based automation scripts for managing Alteryx Server backups, log rotation, and SSL certificate updates. Scripts are designed to run as scheduled tasks (via Windows Task Scheduler) during out-of-hours downtime to minimize service disruption.

**Migration in Progress**: Batch scripts are being migrated to PowerShell with modern best practices. New features should be implemented in PowerShell.

## Architecture & Components

### Batch Scripts (`batch-scripts/`)
Primary automation layer using Windows batch files for service orchestration and backup operations:

- **Alteryx-backup.bat**: Full MongoDB + config backup workflow with service lifecycle management
  - Waits for active workflows to complete before stopping service (monitors `AlteryxEngineCmd.exe`)
  - Service state management with timeout protection (`MaxServiceWait=7200` seconds default)
  - Backs up MongoDB, RuntimeSettings.xml, SystemAlias.xml, SystemConnections.xml, ControllerToken
  - Uses 7-Zip for compression (`.7z` format, historic choice—prefer native compression for new implementations)
  - Moves archives from temp (`D:\Temp\`) to local backup directory (`D:\Alteryx\Backups\`)
  - **Planned Enhancement**: Export to network shares or S3-compatible storage

- **Alteryx-backups-and-logs-cleanup.bat**: Time-based file cleanup using `FORFILES`
  - Configurable retention via `BackupLifespan` and `LogLifespan` variables (in days)
  - Operates on `D:\Alteryx\Backups\` and `D:\Alteryx\AlteryxLogs\`

- **Alteryx-log-mover.bat**: Log collection and archival without service interruption
  - Uses `ROBOCOPY` to move logs from `C:\ProgramData\Alteryx\` to temp, then compresses
  - Targets `.log`, `.dmp`, and `.csv` files with configurable age threshold (`LogAge=0` days default)

### PowerShell Scripts (`powershell/`)
Administrative automation for SSL management and XML-based log archival:

- **update-ssl-key.ps1**: SSL certificate binding automation
  - Requires Administrator privileges (checks `IsInRole(Administrator)`)
  - Uses `netsh http` commands for certificate binding to IP:port (default 0.0.0.0:443)
  - AppId constant: `{eea9431a-a3d4-4c9b-9f9a-b83916c11c67}` (Alteryx Server specific)
  - Manages AlteryxService lifecycle during certificate swap
  - **Known Issues** (from TODOs in code):
    - Certificate binding verification logic needs refinement
    - Error handling for failed cert application incomplete

- **archive-logs.ps1**: XML-driven log archival
  - Reads log paths from `C:\ProgramData\Alteryx\RuntimeSettings.xml`
  - Creates dated ZIP archives (`yyyyMMdd-HHmmss` format)
  - Excludes files modified within last `N` days (default: 1 day)
  - Archives three log types: Gallery, Engine, Controller

## Critical Patterns & Conventions

### Date/Time Stamping
All scripts use consistent WMIC-based formatting for cross-script compatibility:
```batch
FOR /f %%a IN ('WMIC OS GET LocalDateTime ^| FIND "."') DO SET DTS=%%a
SET DateTime=%DTS:~0,4%%DTS:~4,2%%DTS:~6,2%_%DTS:~8,2%%DTS:~10,2%%DTS:~12,2%
```
Format: `YYYYMMDD_HHMMSS` (e.g., `20210219_143052`)

### Service State Management Pattern
All batch scripts follow a defensive state-checking approach:
1. Check for running workflows before stopping service
2. Query service state in loop until expected state achieved
3. Timeout protection to prevent infinite loops
4. Log every state transition

### Logging Convention
- Batch scripts: Write to timestamped `.log` files with `echo >> %LogFile%` pattern
- PowerShell scripts: Use `Write-Log` function with timestamp prefix
- Log format: `YYYY-MM-DD HH:mm:ss: message` or `%date% %time% %tzone%: message`

### Path Configuration
**Critical**: All directory paths must be updated per environment at script top:
- No spaces in `BatchLogDir`, `TempDir`, `NetworkDir`, `OutputDir` paths
- Trailing slash **required** for batch script directory variables
- Common locations (currently local drives):
  - Temp: `D:\Temp\`
  - Backups: `D:\Alteryx\Backups\` (local; migration to network/S3 planned)
  - Logs: `D:\Alteryx\BackupLogs\`, `D:\Alteryx\MoveLogs\`
  - Alteryx data: `C:\ProgramData\Alteryx\`

## External Dependencies
- **7-Zip**: Required for `.7z` compression (default path: `C:\Program Files\7-Zip\7z.exe`)
  - **Migration Goal**: Replace with native PowerShell `Compress-Archive` to eliminate external dependencies
- **AlteryxService.exe**: Located at `C:\Program Files\Alteryx\bin\AlteryxService.exe`
- **WMIC**: Used for date/time formatting in batch scripts (deprecated in Windows 11+)
  - **Migration Required**: Replace with `Get-Date` in PowerShell rewrites
- **netsh**: PowerShell SSL scripts depend on `netsh http` commands
- **Windows Task Scheduler**: Scripts executed during scheduled maintenance windows

## Development Guidelines

### When Adding New Scripts
1. **Use PowerShell for all new scripts** (batch scripts are legacy, migration in progress)
2. Follow the established logging pattern with timestamped files
3. Use `Get-Date -Format "yyyyMMdd-HHmmss"` for timestamps (not WMIC)
4. Add configuration variables/parameters at top with clear comments
5. Document any new paths or dependencies
6. Use defensive service state checking if interacting with AlteryxService
7. Prefer native PowerShell cmdlets over external tools (e.g., `Compress-Archive` vs 7-Zip)

### When Modifying Backup Logic
- Test service stop/start logic with `MaxServiceWait` variations
- Verify workflow detection (`AlteryxEngineCmd.exe` process check)
- Ensure temp files are cleaned up even on error paths
- Validate archive integrity after compression changes

### Testing Approach
- Test scripts on non-production Alteryx Server first
- Monitor actual service stop/start times to calibrate `MaxServiceWait`
- Verify file permissions for network storage paths
- Check log output for each execution path (success, timeout, error)

## PowerShell Development Standards

### Logging Pattern
Use a consistent `Write-Log` function for all output (see [update-ssl-key.ps1](powershell/update-ssl-key.ps1#L54-L59)):
```powershell
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry
}
```
- Timestamp format: `yyyy-MM-dd HH:mm:ss` (ISO 8601 style)
- Severity levels: `INFO` (default), `WARNING`, `ERROR`, `SUCCESS`, `DEBUG`
- Usage: `Write-Log "Service stopped" -Level SUCCESS` or `Write-Log "Backup failed" -Level ERROR`
- Always write to both console and log file
- Log file path should be configurable via parameter with sensible default

### Parameter Management
Follow these parameter patterns for new scripts:
- Use `[Parameter()]` attributes with position and mandatory flags
- Provide default values for optional parameters (e.g., `Port = "443"`)
- Include `-LogPath` parameter for log file customization
- Add `-Help` switch with `Write-Host @"..."@` usage documentation
- Validate admin privileges early for service-impacting operations:
  ```powershell
  if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
      Write-Host "ERROR: This script must be run as an administrator."
      exit 1
  }
  ```

### Configuration File Pattern
Support optional JSON config files to reduce command-line parameter complexity:
```powershell
param(
    [string]$ConfigPath,
    [string]$BackupPath = "D:\Alteryx\Backups",
    [int]$MaxServiceWait = 7200
)

# Load config file if provided, otherwise use parameters/defaults
if ($ConfigPath -and (Test-Path $ConfigPath)) {
    Write-Log "Loading configuration from $ConfigPath" -Level INFO
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $BackupPath = if ($config.BackupPath) { $config.BackupPath } else { $BackupPath }
    $MaxServiceWait = if ($config.MaxServiceWait) { $config.MaxServiceWait } else { $MaxServiceWait }
}
```
- Config file format: JSON (easy to parse, human-readable)
- Command-line parameters override config file values
- Provide defaults for all settings
- Example config structure:
  ```json
  {
    "BackupPath": "D:\\Alteryx\\Backups",
    "TempPath": "D:\\Temp",
    "MaxServiceWait": 7200,
    "LogRetentionDays": 30
  }
  ```
- Place default config in script directory: `config.json`
- Log which config source is being used for troubleshooting

### Error Handling
- Wrap risky operations in `try/catch` blocks (see [archive-logs.ps1](powershell/archive-logs.ps1#L53-L59))
- Log errors with context: `Write-Log "Error archiving $logType: $_"`
- Exit with non-zero code on critical failures
- For service operations: implement timeout loops with counter checks (migrate from batch pattern)
- Document known issues with `# TODO:` comments for future fixes

### Service State Management
When migrating batch service logic to PowerShell:
1. Use `Get-Service -Name "AlteryxService"` for state queries
2. Implement timeout protection with configurable max wait (default 7200 seconds)
3. Check for active workflows: `Get-Process -Name "AlteryxEngineCmd" -ErrorAction SilentlyContinue`
4. Log every state transition for debugging
5. Use `Stop-Service -Force` and `Start-Service` with error handling

### Code Style
- **Function naming**: Use approved PowerShell verbs (`Get-`, `New-`, `Set-`, `Remove-`)
- **Variable naming**: PascalCase for parameters, camelCase for local variables
- **Date formatting**: Always use `Get-Date -Format "yyyyMMdd-HHmmss"` for file timestamps
- **Path handling**: Use `Join-Path` and `Split-Path` instead of string concatenation
- **Configuration**: Extract magic values to parameters or variables at script top

### XML Configuration Parsing
For scripts reading Alteryx config (see [archive-logs.ps1](powershell/archive-logs.ps1#L8-L15)):
```powershell
[xml]$xmlContent = Get-Content -Path $runtimeXmlLocation
$galleryLogPath = $xmlContent.SystemSettings.Gallery.LoggingPath
```
- Cast to `[xml]` for XPath-style navigation
- Validate XML path existence before accessing properties
- Common config file: `C:\ProgramData\Alteryx\RuntimeSettings.xml`

### Compression Best Practices
- Use native `Compress-Archive` cmdlet (no 7-Zip dependency)
- Archive filename format: `yyyyMMdd-HHmmss_<type>.zip`
- Filter files by age using `Where-Object { $_.LastWriteTime -le $cutoffDate }`
- Always use `-Force` parameter to overwrite existing archives
- Validate source files exist before compression: `if ($filesToArchive) { ... }`

### Migration from Batch Scripts
When converting batch files to PowerShell:
1. Replace WMIC date logic with `Get-Date`
2. Convert `SET` variables to `param()` blocks
3. Replace `SC query/start/stop` with `Get-Service`/`Start-Service`/`Stop-Service`
4. Use `Remove-Item -Recurse` instead of `rmdir /S /Q`
5. Replace `ROBOCOPY` with `Copy-Item` or `Move-Item` cmdlets
6. Convert `FORFILES` cleanup to `Get-ChildItem | Where-Object` filtering
7. Maintain existing log format for consistency during transition

## Known Limitations & Roadmap

### Current Limitations
- WMIC dependency in batch scripts (deprecated in Windows 11+; addressed in PowerShell migration)
- Hard-coded AppId in SSL script (Alteryx Server specific, intentional)
- SSL certificate verification incomplete (see TODOs in update-ssl-key.ps1)
- 7-Zip external dependency (migration to native compression planned)
- Local-only backup storage (network/S3 export planned)
- Single-threaded execution (no parallel backup operations)

### Planned Enhancements
- **Migrate all batch scripts to PowerShell** with current best practices
- **Email notifications**: Add SMTP alerting for backup success/failure
- **Remote storage**: Export backups to network shares or S3-compatible storage
- **Native compression**: Remove 7-Zip dependency, use `Compress-Archive`
- **Modern date/time handling**: Replace WMIC with `Get-Date` throughout
