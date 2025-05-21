# Define the path to the XML file
$runtimexml_location="C:\ProgramData\Alteryx\RuntimeSettings.xml"

# Load the XML file
[xml]$xmlContent = Get-Content -Path $runtimexml_location

# Define the output directory for the archives
$outputDirectory = "D:\ProgramData\Alteryx\log_archives"

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory
}

# Extract the log paths from the XML content
$galleryLogPath = $xmlContent.SystemSettings.Gallery.LoggingPath
$engineLogPath = $xmlContent.SystemSettings.Engine.LogFilePath
$controllerLogFilePath = $xmlContent.SystemSettings.Controller.LoggingPath
$controllerLogPath = Split-Path -Path $controllerLogFilePath -Parent


Write-Debug $galleryLogPath
Write-Debug $engineLogPath
Write-Debug $controllerLogFilePath
Write-Debug $controllerLogPath

# Function to archive logs
function New-Archive-Logs {
    param (
        [string]$folderPath,
        [string]$mainOutputDirectory,
        [string]$logType,
        [int16]$excludeDays = 1
    )

    if (Test-Path -Path $folderPath) {
        # Create subfolder in the output directory
        $outputSubfolderPath = "$mainOutputDirectory\$logType"
        if (-not (Test-Path -Path $outputSubfolderPath)) {
            New-Item -ItemType Directory -Path $outputSubfolderPath
        }

        # Get the name of the folder to use in the archive filename
        # $folderName = Split-Path -Path $folderPath -Leaf

    
        # Define the archive filename
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $archiveFilename = "$($outputSubfolderPath)\$($timestamp)_$($logType).zip"

        # Get files to archive, excluding those modified in the last X days
        $cutoffDate = (Get-Date).AddDays(-$excludeDays)
        $filesToArchive = Get-ChildItem -Path "$folderPath\*" -Recurse | Where-Object { $_.LastWriteTime -le $cutoffDate }

        # Archive the folder
        try {
            if ($filesToArchive) {
                Compress-Archive -Path $filesToArchive.FullName -DestinationPath $archiveFilename -Force
                Write-Output "Successfully archived $logType logs to $archiveFilename"
            } else {
                Write-Output "No files to archive in $logType logs as all files are modified within the last $excludeDays days."
            }
        } catch {
            Write-Output "Error archiving $($logType): $_"
        }
    } else {
        Write-Output "Folder path $folderPath does not exist."
    }
}

# Archive the logs for each path into respective subfolders
New-Archive-Logs -folderPath $galleryLogPath -mainOutputDirectory $outputDirectory -logType "Gallery"
New-Archive-Logs -folderPath $engineLogPath -mainOutputDirectory $outputDirectory -logType "Engine"
New-Archive-Logs -folderPath $controllerLogPath -mainOutputDirectory $outputDirectory -logType "Controller"
