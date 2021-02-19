::-----------------------------------------------------------------------------
::
:: AlteryxServer Backup Script v.2.1 - 19/02/21
:: Updated by: Ian Baldwin
:: Base script by: Kevin Powney
::
:: Service start and stop checks adapted from example code by Eric Falsken
::
::-----------------------------------------------------------------------------

@echo off

::-----------------------------------------------------------------------------
:: Set variables for Log, Temp, Network, and Application Paths
::
:: Please update these values as appropriate for your environment. Note
:: that spaces should be avoided in the LogDir, TempDir, and NetworkDir paths.
:: The trailing slash is also required for these paths.
::-----------------------------------------------------------------------------

SET LogDir=D:\Alteryx\BackupLogs\
SET TempDir=D:\Temp\
SET NetworkDir=D:\Alteryx\Backups\
SET AlteryxService="C:\Program Files\Alteryx\bin\AlteryxService.exe"
SET ZipUtil="C:\Program Files\7-Zip\7z.exe"

:: Set the maximium time to wait for the service to start or stop in whole seconds. Default value is 2 hours.
SET MaxServiceWait=7200

::-----------------------------------------------------------------------------
:: Set Date/Time to a usable format and create log
::-----------------------------------------------------------------------------

FOR /f %%a IN ('WMIC OS GET LocalDateTime ^| FIND "."') DO SET DTS=%%a
SET DateTime=%DTS:~0,4%%DTS:~4,2%%DTS:~6,2%_%DTS:~8,2%%DTS:~10,2%%DTS:~12,2%
SET /a tztemp=%DTS:~21%/60
SET tzone=UTC%tztemp%
SET BackupLog=%LogDir%BackupLog%datetime%.log

echo %date% %time% %tzone%: Starting backup process... > %BackupLog%
echo. >> %BackupLog%

::-----------------------------------------------------------------------------
:: Stop Alteryx Service
::-----------------------------------------------------------------------------

echo %date% %time% %tzone%: Stopping Alteryx Service... >> %BackupLog%
echo. >> %BackupLog%

SET COUNT=0

:StopInitState
SC query AlteryxService | FIND "STATE" | FIND "RUNNING" >> %BackupLog%
IF errorlevel 0 IF NOT errorlevel 1 GOTO StopService
SC query AlteryxService | FIND "STATE" | FIND "STOPPED" >> %BackupLog%
IF errorlevel 0 IF NOT errorlevel 1 GOTO StopedService
SC query AlteryxService | FIND "STATE" | FIND "PAUSED" >> %BackupLog%
IF errorlevel 0 IF NOT errorlevel 1 GOTO SystemError
echo %date% %time% %tzone%: Service State is changing, waiting for service to resolve its state before making changes >> %BackupLog%
SC query AlteryxService | Find "STATE"
timeout /t 1 /nobreak >NUL
SET /A COUNT=%COUNT%+1
IF "%COUNT%" == "%MaxServiceWait%" GOTO SystemError
GOTO StopInitState

:StopService
SET COUNT=0
SC stop AlteryxService >> %BackupLog%
GOTO StoppingService

:StopServiceDelay
echo %date% %time% %tzone%: Waiting for AlteryService to stop >> %BackupLog%
timeout /t 1 /nobreak >NUL
SET /A COUNT=%COUNT%+1
IF "%COUNT%" == "%MaxServiceWait%" GOTO SystemError

:StoppingService
SC query AlteryxService | FIND "STATE" | FIND "STOPPED" >> %BackupLog%
IF errorlevel 1 GOTO StopServiceDelay

:StopedService
echo %date% %time% %tzone%: AlteryService is stopped >> %BackupLog%

::-----------------------------------------------------------------------------
:: Backup MongoDB to local temp directory.
::-----------------------------------------------------------------------------

echo. >> %BackupLog%
echo %date% %time% %tzone%: Starting MongoDB Backup... >> %BackupLog%
echo. >> %BackupLog%

%AlteryxService% emongodump=%TempDir%ServerBackup_%datetime%\Mongo >> %BackupLog%

::-----------------------------------------------------------------------------
:: Backup Config files to local temp directory.
::-----------------------------------------------------------------------------

echo: >> %BackupLog%
echo %date% %time% %tzone%: Backing up settings, connections, and aliases... >> %BackupLog%

echo: >> %BackupLog%
echo RuntimeSettings.xml >> %BackupLog%
copy %ProgramData%\Alteryx\RuntimeSettings.xml %TempDir%ServerBackup_%datetime%\RuntimeSettings.xml >> %BackupLog%
echo: >> %BackupLog%
echo SystemAlias.xml >> %BackupLog%
copy %ProgramData%\Alteryx\Engine\SystemAlias.xml %TempDir%ServerBackup_%datetime%\SystemAlias.xml >> %BackupLog%
echo: >> %BackupLog%
echo SystemConnections.xml >> %BackupLog%
copy %ProgramData%\Alteryx\Engine\SystemConnections.xml %TempDir%ServerBackup_%datetime%\SystemConnections.xml >> %BackupLog%
%AlteryxService% getserversecret > %TempDir%ServerBackup_%datetime%\ControllerToken.txt

::-----------------------------------------------------------------------------
:: Restart Alteryx Service
::-----------------------------------------------------------------------------

echo. >> %BackupLog%
echo %date% %time% %tzone%: Restarting Alteryx Service... >> %BackupLog%
echo. >> %BackupLog%

SET COUNT=0

:StartInitState
SC query AlteryxService | FIND "STATE" | FIND "STOPPED" >> %BackupLog%
IF errorlevel 0 IF NOT errorlevel 1 GOTO StartService
SC query AlteryxService | FIND "STATE" | FIND "RUNNING" >> %BackupLog%
IF errorlevel 0 IF NOT errorlevel 1 GOTO StartedService
SC query AlteryxService | FIND "STATE" | FIND "PAUSED" >> %BackupLog%
IF errorlevel 0 IF NOT errorlevel 1 GOTO SystemError
echo %date% %time% %tzone%: Service State is changing, waiting for service to resolve its state before making changes >> %BackupLog%
SC query AlteryxService | Find "STATE"
timeout /t 1 /nobreak >NUL
SET /A COUNT=%COUNT%+1
IF "%COUNT%" == "%MaxServiceWait%" GOTO SystemError
GOTO StartInitState

:StartService
SET COUNT=0
SC start AlteryxService >> %BackupLog%
GOTO StartingService

:StartServiceDelay
echo %date% %time% %tzone%: Waiting for AlteryxService to start >> %BackupLog%
timeout /t 1 /nobreak >NUL
SET /A COUNT=%COUNT%+1
IF "%COUNT%" == "%MaxServiceWait%" GOTO SystemError

:StartingService
SC query AlteryxService | FIND "STATE" | FIND "RUNNING" >> %BackupLog%
IF errorlevel 1 GOTO StartServiceDelay

:StartedService
echo %date% %time% %tzone%: AlteryxService is started >> %BackupLog%

::-----------------------------------------------------------------------------
:: This section compresses the backup to a single zip archive
::
:: Please note the command below requires 7-Zip to be installed on the server.
:: You can download 7-Zip from http://www.7-zip.org/ or change the command to
:: use the zip utility of your choice as defined in the variable above.
::-----------------------------------------------------------------------------

echo. >> %BackupLog%
echo %date% %time% %tzone%: Archiving backup... >> %BackupLog%

%ZipUtil% a %TempDir%ServerBackup_%datetime%.7z %TempDir%ServerBackup_%datetime% >> %BackupLog%

::-----------------------------------------------------------------------------
:: Move zip archive to network storage location and cleanup local files
::-----------------------------------------------------------------------------

echo. >> %BackupLog%
echo %date% %time% %tzone%: Moving archive to network storage >> %BackupLog%
echo. >> %BackupLog%

copy %TempDir%ServerBackup_%datetime%.7z %NetworkDir%ServerBackup_%datetime%.7z >> %BackupLog%

del %TempDir%ServerBackup_%datetime%.7z >> %BackupLog%
rmdir /S /Q %TempDir%ServerBackup_%datetime% >> %BackupLog%

::-----------------------------------------------------------------------------
:: Done
::-----------------------------------------------------------------------------

echo. >> %BackupLog%
echo %date% %time% %tzone%: Backup process completed >> %BackupLog%
GOTO :EOF

:SystemError
echo. >> %BackupLog%
echo %date% %time% %tzone%: Error starting or stopping service. Service is not accessible, is offline, or did not respond to the start or stop request within the designated time frame. >> %BackupLog%
