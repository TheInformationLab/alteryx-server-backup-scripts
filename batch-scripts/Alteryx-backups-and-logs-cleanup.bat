::-----------------------------------------------------------------------------
:: Alteryx Server Backup Cleanup v1.0 - 19/02/21
:: Created By: Ian Baldwin
::-----------------------------------------------------------------------------

@echo off

::-----------------------------------------------------------------------------
:: Set variables for backup and log folders
::-----------------------------------------------------------------------------

SET BackupDir=D:\Alteryx\Backups\
SET LogsDir=D:\Alteryx\AlteryxLogs\
SET CleanupLogDir=D:\Alteryx\CleanupLogs\

::-----------------------------------------------------------------------------
:: Set lifespans for backups and logs in days
::-----------------------------------------------------------------------------

SET BackupLifespan=0
SET LogLifespan=0

::-----------------------------------------------------------------------------
:: Set Date/Time to a usable format and create cleanup log
::-----------------------------------------------------------------------------

FOR /f %%a IN ('WMIC OS GET LocalDateTime ^| FIND "."') DO SET DTS=%%a
SET DateTime=%DTS:~0,4%%DTS:~4,2%%DTS:~6,2%_%DTS:~8,2%%DTS:~10,2%%DTS:~12,2%
SET /a tztemp=%DTS:~21%/60
SET tzone=UTC%tztemp%
SET CleanupLog=%CleanupLogDir%CleanupLog%datetime%.log

echo %date% %time% %tzone%: Starting cleanup process... > %CleanupLog%
echo. >> %CleanupLog%

::-----------------------------------------------------------------------------
:: Delete old files. This section
::-----------------------------------------------------------------------------

FORFILES /p %LogsDir% /m *.7z /C "cmd /c echo @path deleted >> %CleanupLog% & del @path" /D -%LogLifespan%
FORFILES /p %BackupDir% /m *.7z /C "cmd /c echo @path deleted >> %CleanupLog% & del @path" /D -%BackupLifespan%
