##-----------------------------------------------------------------------------
#
## Alteryx Log Mover v1.0 - 19/02/21
#
## Created By: Ian Baldwin
#
##-----------------------------------------------------------------------------
#

#
##-----------------------------------------------------------------------------
#
## Set variables for Log location and destination paths
#
##-----------------------------------------------------------------------------
#

#
$GalleryLogDir = "C:\ProgramData\Alteryx\"
#
$BatchLogDir = "D:\Alteryx\MoveLogs\"
#
$TempDir = "D:\Temp\"
#
$OutputDir = "D:\Alteryx\AlteryxLogs\"
#
$ZipUtil = "C:\Program Files\7-Zip\7z.exe"
#

#
##-----------------------------------------------------------------------------
#
## Set variable for age before moving
#
##-----------------------------------------------------------------------------
#

#
$LogAge = 0
#

#
##-----------------------------------------------------------------------------
#
## Set Date/Time to a usable format, set temp destination and create move log
#
##-----------------------------------------------------------------------------
#

#
$DateTime = (Get-Date -Format "yyyyMMdd_HHmmss")
#
$TempDest = $TempDir + "ServerLogs_" + $DateTime
#
$MoveLog = $BatchLogDir + "MoveLog_" + $DateTime + ".log"
#

#
Add-Content -Path $MoveLog -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") Starting log movement process..."
#
Add-Content -Path $MoveLog -Value ""
#

#
##-----------------------------------------------------------------------------
#
## RoboCopy to Temp
#
##-----------------------------------------------------------------------------
#

#
Robocopy.exe $GalleryLogDir $TempDest *.log /MOV /S /MINAGE:$LogAge | Add-Content -Path $MoveLog
#
Robocopy.exe $GalleryLogDir $TempDest *.dmp /MOV /S /MINAGE:$LogAge | Add-Content -Path $MoveLog
#
Robocopy.exe $GalleryLogDir\Gallery\Logs $TempDest\Gallery\Logs *.csv /MOV /S /MINAGE:$LogAge | Add-Content -Path $MoveLog
#

#
##-----------------------------------------------------------------------------
#
## This section compresses the logs to a single zip archive
#
##
#