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

<#
.SYNOPSIS
    Initialize backup environment and load configuration

.DESCRIPTION
    Loads configuration from JSON file, validates prerequisites, detects MongoDB type,
    detects multi-node topology, and prepares execution environment

.PARAMETER BackupMode
    Execution mode (Full/DatabaseOnly/ConfigOnly)

.PARAMETER ConfigPath
    Path to JSON configuration file

.PARAMETER ParameterOverrides
    Optional hashtable of parameter overrides

.OUTPUTS
    ConfigurationObject hashtable
#>
function Initialize-BackupEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("Full", "DatabaseOnly", "ConfigOnly")]
        [string]$BackupMode = "Full",
        
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ".\config\backup-config.json",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$ParameterOverrides = @{}
    )
    
    Write-Log "Initializing backup environment..." -Level INFO
    
    # 1. Check Administrator privileges
    Write-Log "Checking administrator privileges..." -Level DEBUG
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log "ERROR: This script must be run as Administrator" -Level ERROR
        throw "Administrator privileges required"
    }
    Write-Log "Administrator privileges confirmed" -Level DEBUG
    
    # 2. Load JSON configuration file
    $config = @{}
    if (Test-Path $ConfigPath) {
        Write-Log "Loading configuration from: $ConfigPath" -Level INFO
        try {
            $jsonContent = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            
            # Convert JSON to hashtable for easier manipulation
            $config = @{
                BackupConfiguration = @{
                    DefaultBackupMode = $jsonContent.BackupConfiguration.DefaultBackupMode
                    TempDirectory = $jsonContent.BackupConfiguration.TempDirectory
                    LocalBackupPath = $jsonContent.BackupConfiguration.LocalBackupPath
                    NetworkBackupPaths = @($jsonContent.BackupConfiguration.NetworkBackupPaths)
                    LogDirectory = $jsonContent.BackupConfiguration.LogDirectory
                    RetentionDays = @{
                        Full = $jsonContent.BackupConfiguration.RetentionDays.Full
                        DatabaseOnly = $jsonContent.BackupConfiguration.RetentionDays.DatabaseOnly
                        ConfigOnly = $jsonContent.BackupConfiguration.RetentionDays.ConfigOnly
                    }
                }
                ServiceConfiguration = @{
                    MaxServiceWaitSeconds = $jsonContent.ServiceConfiguration.MaxServiceWaitSeconds
                    MaxWorkflowWaitSeconds = $jsonContent.ServiceConfiguration.MaxWorkflowWaitSeconds
                    ForceStopWorkflows = $jsonContent.ServiceConfiguration.ForceStopWorkflows
                    StopServiceForExternalDB = $jsonContent.ServiceConfiguration.StopServiceForExternalDB
                }
                MongoDBConfiguration = @{
                    Type = $jsonContent.MongoDBConfiguration.Type
                    EmbeddedMongoDB = @{
                        UseAlteryxService = $jsonContent.MongoDBConfiguration.EmbeddedMongoDB.UseAlteryxService
                    }
                    SelfManagedMongoDB = @{
                        ConnectionString = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.ConnectionString
                        Host = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.Host
                        Port = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.Port
                        Database = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.Database
                        AuthDatabase = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.AuthDatabase
                        Username = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.Username
                        UseCompression = $jsonContent.MongoDBConfiguration.SelfManagedMongoDB.UseCompression
                    }
                }
                FilesConfiguration = @{
                    BackupKeys = $jsonContent.FilesConfiguration.BackupKeys
                    BackupConfigFile = $jsonContent.FilesConfiguration.BackupConfigFile
                    BackupMongoPasswords = $jsonContent.FilesConfiguration.BackupMongoPasswords
                    IncludeMetadata = $jsonContent.FilesConfiguration.IncludeMetadata
                }
                ValidationConfiguration = @{
                    VerifyArchiveIntegrity = $jsonContent.ValidationConfiguration.VerifyArchiveIntegrity
                    CalculateChecksums = $jsonContent.ValidationConfiguration.CalculateChecksums
                    MinimumBackupSizeMB = @{
                        Full = $jsonContent.ValidationConfiguration.MinimumBackupSizeMB.Full
                        DatabaseOnly = $jsonContent.ValidationConfiguration.MinimumBackupSizeMB.DatabaseOnly
                        ConfigOnly = $jsonContent.ValidationConfiguration.MinimumBackupSizeMB.ConfigOnly
                    }
                }
            }
            Write-Log "Configuration loaded successfully" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to load configuration: $_" -Level ERROR
            throw "Configuration load error: $_"
        }
    }
    else {
        Write-Log "Configuration file not found: $ConfigPath" -Level WARNING
        Write-Log "Using default configuration values" -Level INFO
        
        # Use minimal defaults
        $config = @{
            BackupConfiguration = @{
                DefaultBackupMode = "Full"
                TempDirectory = "D:\Temp"
                LocalBackupPath = "D:\Alteryx\Backups"
                NetworkBackupPaths = @()
                LogDirectory = "D:\Alteryx\BackupLogs"
                RetentionDays = @{
                    Full = 30
                    DatabaseOnly = 14
                    ConfigOnly = 30
                }
            }
            ServiceConfiguration = @{
                MaxServiceWaitSeconds = 7200
                MaxWorkflowWaitSeconds = 3600
                ForceStopWorkflows = $false
                StopServiceForExternalDB = $false
            }
            MongoDBConfiguration = @{
                Type = "auto"
                EmbeddedMongoDB = @{
                    UseAlteryxService = $true
                }
                SelfManagedMongoDB = @{}
            }
            FilesConfiguration = @{
                BackupKeys = $true
                BackupConfigFile = $true
                BackupMongoPasswords = $true
                IncludeMetadata = $true
            }
            ValidationConfiguration = @{
                VerifyArchiveIntegrity = $true
                CalculateChecksums = $true
                MinimumBackupSizeMB = @{
                    Full = 1.0
                    DatabaseOnly = 1.0
                    ConfigOnly = 0.1
                }
            }
        }
    }
    
    # 3. Apply parameter overrides
    foreach ($key in $ParameterOverrides.Keys) {
        Write-Log "Applying parameter override: $key = $($ParameterOverrides[$key])" -Level DEBUG
        # Simple override logic - can be enhanced later
        $config.$key = $ParameterOverrides[$key]
    }
    
    # 4. Create merged configuration object
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = "BackupLog_${BackupMode}_${timestamp}.log"
    
    $mergedConfig = @{
        BackupMode = $BackupMode
        TempDirectory = [System.IO.Path]::GetFullPath($config.BackupConfiguration.TempDirectory)
        LocalBackupPath = [System.IO.Path]::GetFullPath($config.BackupConfiguration.LocalBackupPath)
        NetworkBackupPaths = $config.BackupConfiguration.NetworkBackupPaths
        LogDirectory = [System.IO.Path]::GetFullPath($config.BackupConfiguration.LogDirectory)
        LogFilePath = Join-Path $config.BackupConfiguration.LogDirectory $logFileName
        
        RetentionDays = $config.BackupConfiguration.RetentionDays
        
        MaxServiceWait = $config.ServiceConfiguration.MaxServiceWaitSeconds
        MaxWorkflowWait = $config.ServiceConfiguration.MaxWorkflowWaitSeconds
        ForceStopWorkflows = $config.ServiceConfiguration.ForceStopWorkflows
        StopServiceForExternalDB = $config.ServiceConfiguration.StopServiceForExternalDB
        
        MongoType = "embedded"  # Will be detected later
        MongoConfig = @{}
        
        IncludeKeys = $config.FilesConfiguration.BackupKeys
        IncludeConfigFile = $config.FilesConfiguration.BackupConfigFile
        IncludeMongoPasswords = $config.FilesConfiguration.BackupMongoPasswords
        IncludeMetadata = $config.FilesConfiguration.IncludeMetadata
        
        VerifyArchive = $config.ValidationConfiguration.VerifyArchiveIntegrity
        CalculateChecksums = $config.ValidationConfiguration.CalculateChecksums
        MinimumSizeMB = $config.ValidationConfiguration.MinimumBackupSizeMB[$BackupMode]
    }
    
    # 5. Create directories if missing
    $directories = @($mergedConfig.TempDirectory, $mergedConfig.LogDirectory, $mergedConfig.LocalBackupPath)
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Log "Creating directory: $dir" -Level INFO
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Log "Directory created successfully" -Level DEBUG
            }
            catch {
                Write-Log "Failed to create directory $dir : $_" -Level ERROR
                throw "Directory creation error: $_"
            }
        }
        else {
            Write-Log "Directory exists: $dir" -Level DEBUG
        }
    }
    
    # 6. Set script-level log file path
    $script:LogFilePath = $mergedConfig.LogFilePath
    Write-Log "Log file initialized: $script:LogFilePath" -Level INFO
    
    # 7. Detect MongoDB type from RuntimeSettings.xml
    $runtimeSettingsPath = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
    if (Test-Path $runtimeSettingsPath) {
        Write-Log "Detecting MongoDB type from RuntimeSettings.xml..." -Level INFO
        try {
            [xml]$runtimeSettings = Get-Content $runtimeSettingsPath
            $connectionString = $runtimeSettings.SystemSettings.Persistence.Mongo.ConnectionString
            
            Write-Log "MongoDB connection string detected" -Level DEBUG
            
            # Embedded MongoDB indicators (localhost:27018 is default embedded port)
            if ($connectionString -match "localhost:27018" -or $connectionString -match "127.0.0.1:27018") {
                $mergedConfig.MongoType = "embedded"
                Write-Log "MongoDB type: Embedded (default port 27018)" -Level INFO
            }
            else {
                $mergedConfig.MongoType = "self-managed"
                Write-Log "MongoDB type: Self-managed (custom connection string)" -Level INFO
                
                # Parse connection string for self-managed details
                # Format: mongodb://[username:password@]host:port/database
                if ($connectionString -match "mongodb://(?:([^:]+):([^@]+)@)?([^:]+):(\d+)/(.+)") {
                    $mergedConfig.MongoConfig = @{
                        Host = $matches[3]
                        Port = [int]$matches[4]
                        Database = $matches[5]
                        Username = $matches[1]  # May be null
                    }
                    Write-Log "Self-managed MongoDB: $($mergedConfig.MongoConfig.Host):$($mergedConfig.MongoConfig.Port)" -Level INFO
                }
            }
        }
        catch {
            Write-Log "Failed to parse RuntimeSettings.xml: $_" -Level WARNING
            Write-Log "Defaulting to embedded MongoDB" -Level INFO
            $mergedConfig.MongoType = "embedded"
        }
    }
    else {
        Write-Log "RuntimeSettings.xml not found at: $runtimeSettingsPath" -Level WARNING
        Write-Log "Defaulting to embedded MongoDB" -Level INFO
        $mergedConfig.MongoType = "embedded"
    }
    
    # 8. Detect multi-node topology
    if (Test-Path $runtimeSettingsPath) {
        Write-Log "Detecting multi-node topology..." -Level INFO
        try {
            [xml]$runtimeSettings = Get-Content $runtimeSettingsPath
            
            # Check for remote workers
            $workers = $runtimeSettings.SystemSettings.Controller.Workers.Worker
            $hasRemoteWorkers = $false
            if ($workers) {
                $remoteWorkers = $workers | Where-Object { $_.RemoteWorker -eq 'true' }
                $hasRemoteWorkers = ($remoteWorkers.Count -gt 0)
            }
            
            # Check for separate UI node
            $serverUI = $runtimeSettings.SystemSettings.Gallery.ServerUI
            $hasSeparateUI = $serverUI -and ($serverUI -ne $env:COMPUTERNAME)
            
            $isMultiNode = $hasRemoteWorkers -or $hasSeparateUI
            
            if ($isMultiNode) {
                Write-Log "Multi-node deployment detected" -Level INFO
                if ($hasRemoteWorkers) {
                    Write-Log "Remote workers detected" -Level INFO
                }
                if ($hasSeparateUI) {
                    Write-Log "Separate Server UI node detected" -Level INFO
                }
            }
            else {
                Write-Log "Single-node deployment" -Level INFO
            }
            
            $mergedConfig.IsMultiNode = $isMultiNode
        }
        catch {
            Write-Log "Failed to detect multi-node topology: $_" -Level WARNING
            $mergedConfig.IsMultiNode = $false
        }
    }
    else {
        $mergedConfig.IsMultiNode = $false
    }
    
    # 9. Validate disk space (2x MongoDB size for Full/DatabaseOnly)
    if ($BackupMode -in @("Full", "DatabaseOnly")) {
        Write-Log "Checking disk space in temp directory..." -Level INFO
        try {
            $tempDrive = Split-Path $mergedConfig.TempDirectory -Qualifier
            $drive = Get-PSDrive -Name $tempDrive.TrimEnd(':') -ErrorAction Stop
            $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
            Write-Log "Available space on ${tempDrive}: ${freeSpaceGB}GB" -Level INFO
            
            # Warn if less than 10GB free
            if ($freeSpaceGB -lt 10) {
                Write-Log "WARNING: Low disk space (${freeSpaceGB}GB free). Ensure sufficient space for MongoDB backup." -Level WARNING
            }
        }
        catch {
            Write-Log "Failed to check disk space: $_" -Level WARNING
        }
    }
    
    Write-Log "Environment initialization complete" -Level SUCCESS
    return $mergedConfig
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

# Initialize environment and load configuration
try {
    $script:Config = Initialize-BackupEnvironment -BackupMode $BackupMode -ConfigPath $ConfigPath
    Write-Log "Configuration loaded and validated" -Level SUCCESS
}
catch {
    Write-Log "Environment initialization failed: $_" -Level ERROR
    exit $ExitCode.GeneralError
}

# TODO: Implementation will continue in next phases
Write-Log "Phase 2 (Foundational) implementation in progress..." -Level INFO
Write-Log "MongoDB Type: $($script:Config.MongoType)" -Level INFO
Write-Log "Multi-Node: $($script:Config.IsMultiNode)" -Level INFO

Write-Log "Script completed successfully" -Level SUCCESS
exit $ExitCode.Success

#endregion
