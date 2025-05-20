# Script to update SSL certificate and bind it to the Alteryx Server port
# Based on: https://help.alteryx.com/current/en/server/configure/configure-server-ssl-tls.html

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Thumbprint, # New certificate thumbprint (no spaces)
    [Parameter(Mandatory=$false)]
    [string]$Port = "443", # Change if using a non-default port
    [Parameter(Mandatory=$false)]
    [string]$LogPath, # Optional: custom log file path
    [Parameter(Mandatory=$false)]
    [switch]$Help # Show usage/help
)

if ($Help) {
    Write-Host @"
Usage: .\update-ssl-key.ps1 <Thumbprint> [-Port <port>] [-LogPath <log file path>] [-Help]
       .\update-ssl-key.ps1 -Thumbprint <thumbprint> [-Port <port>] [-LogPath <log file path>] [-Help]

Parameters:
  <Thumbprint> (Required, Positional) Thumbprint of the new SSL certificate (no spaces).
  -Thumbprint  (Optional, Named) Thumbprint of the new SSL certificate (no spaces).
  -Port        (Optional, Named) Port number to bind the SSL certificate to. Default is 443.
  -LogPath     (Optional, Named) Path to the log file. Default is 'ssl_update.log' in the script directory.
  -Help        (Optional, Named) Show this help message and exit.

Examples:
  .\update-ssl-key.ps1 ABCDEF1234567890...
  .\update-ssl-key.ps1 ABCDEF1234567890... -Port 445
  .\update-ssl-key.ps1 -Thumbprint ABCDEF1234567890... -LogPath "C:\logs\ssl_update.log"
"@
    exit 0
}

# Set default log file name if not provided
if (-not $LogPath -or $LogPath -eq "") {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $LogPath = Join-Path $ScriptDir "ssl_update.log"
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $LogPath -Value $entry
}

# Application ID for Alteryx Server (do not change)
$AppId = "{eea9431a-a3d4-4c9b-9f9a-b83916c11c67}"

Write-Log "Starting SSL certificate update process."

Write-Log "Stopping AlteryxService..."
Stop-Service -Name "AlteryxService" -Force

# Remove old SSL binding
Write-Log "Removing old SSL certificate binding from port $Port..."
netsh http delete sslcert ipport=0.0.0.0:$Port | ForEach-Object { Write-Log $_ }

# Add new SSL binding
Write-Log "Adding new SSL certificate binding to port $Port..."
netsh http add sslcert ipport=0.0.0.0:$Port certhash=$Thumbprint appid=$AppId | ForEach-Object { Write-Log $_ }

# Show current SSL bindings
Write-Log "Current SSL certificate bindings:"
netsh http show sslcert | ForEach-Object { Write-Log $_ }

Write-Log "Starting AlteryxService..."
Start-Service -Name "AlteryxService"

Write-Log "SSL certificate update complete. Please verify Alteryx Server UI is accessible via HTTPS."
