<#
.SYNOPSIS
    Alteryx Server Backup Automation Script

.DESCRIPTION
    PowerShell script for automated backup of Alteryx Server with support for three execution modes:
    - Full: Complete backup (MongoDB + configuration files)
    - DatabaseOnly: MongoDB backup only
    - ConfigOnly: Configuration files only (no service interruption)
    
    Supports both embedded MongoDB (via AlteryxService.exe) and self-managed MongoDB deployments.

.PARAMETER BackupMode
    Backup execution mode. Options: Full, DatabaseOnly, ConfigOnly
    Default: Full

.PARAMETER ConfigPath
    Path to JSON configuration file
    Default: .\config\backup-config.json

.PARAMETER Verbose
    Enable verbose logging output

.PARAMETER Help
    Display help information

.EXAMPLE
    .\Invoke-AlteryxBackup.ps1
    Run Full backup with default configuration

.EXAMPLE
    .\Invoke-AlteryxBackup.ps1 -BackupMode DatabaseOnly
    Run database-only backup

.EXAMPLE
    .\Invoke-AlteryxBackup.ps1 -BackupMode ConfigOnly -Verbose
    Run config-only backup with verbose logging

.NOTES
    Version: 1.0.0
    Author: System Architecture Team
    Last Modified: 2026-01-13
    
    Requirements:
    - Windows Server 2016+ with Alteryx Server 2020.1+
    - PowerShell 5.1+
    - Administrator privileges
    - Sufficient disk space (2x MongoDB size for Full/DatabaseOnly backups)

.LINK
    https://help.alteryx.com/current/en/server/install/server-host-recovery-guide/disaster-recovery-preparation.html
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [ValidateSet("Full", "DatabaseOnly", "ConfigOnly")]
    [string]$BackupMode = "Full",
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\config\backup-config.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Script version
$script:ScriptVersion = "1.0.0"

# Module-level variables
$script:LogFilePath = $null
$script:ExecutionState = $null
$script:Config = $null

# Exit codes (per data-model.md section 6.2)
$ExitCode = @{
    Success = 0
    GeneralError = 1
    ServiceTimeout = 2
    ValidationFailure = 3
    StorageError = 4
    MongoDBError = 5
    InvalidBackupMode = 6
}

#region Helper Functions

<#
.SYNOPSIS
    Centralized logging function

.DESCRIPTION
    Writes timestamped log entries to both console and log file with severity levels

.PARAMETER Message
    Log message text

.PARAMETER Level
    Log severity level: DEBUG, INFO, WARNING, ERROR, SUCCESS
    Default: INFO

.PARAMETER LogPath
    Optional log file path override
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath = $script:LogFilePath
    )
    
    # Format timestamp (ISO 8601)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    
    # Console output with color coding
    switch ($Level) {
        "DEBUG"   { if ($VerbosePreference -eq 'Continue') { Write-Host $entry -ForegroundColor Gray } }
        "INFO"    { Write-Host $entry -ForegroundColor White }
        "WARNING" { Write-Host $entry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
    }
    
    # File output (best effort - don't throw on log write failures)
    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $entry -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
}

#endregion

#region Main Script

# Display help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit $ExitCode.Success
}

# Script entry point
Write-Log "=== Alteryx Server Backup Script v$script:ScriptVersion ===" -Level INFO
Write-Log "Backup Mode: $BackupMode" -Level INFO
Write-Log "Script started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO

# TODO: Implementation will continue in next phases
Write-Log "Phase 2 (Foundational) implementation in progress..." -Level INFO
Write-Log "Script completed successfully" -Level SUCCESS

exit $ExitCode.Success

#endregion
