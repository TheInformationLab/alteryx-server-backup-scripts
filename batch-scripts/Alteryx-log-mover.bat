::-----------------------------------------------------------------------------
:: Alteryx Log Mover v1.0 - 19/02/21
:: Created By: Ian Baldwin
::-----------------------------------------------------------------------------

@echo off

::-----------------------------------------------------------------------------
:: Set variables for Log location and destination paths
::-----------------------------------------------------------------------------

SET GalleryLogDir=C:\ProgramData\Alteryx\
SET BatchLogDir=D:\Alteryx\MoveLogs\
SET TempDir=D:\Temp\
SET OutputDir=D:\Alteryx\AlteryxLogs\
SET ZipUtil="C:\Program Files\7-Zip\7z.exe"

::-----------------------------------------------------------------------------
:: Set variable for age before moving
::-----------------------------------------------------------------------------

SET LogAge=0

::-----------------------------------------------------------------------------
:: Set Date/Time to a usable format, set temp destination and create move log
::-----------------------------------------------------------------------------

FOR /f %%a IN ('WMIC OS GET LocalDateTime ^| FIND "."') DO SET DTS=%%a
SET DateTime=%DTS:~0,4%%DTS:~4,2%%DTS:~6,2%_%DTS:~8,2%%DTS:~10,2%%DTS:~12,2%
SET /a tztemp=%DTS:~21%/60
SET tzone=UTC%tztemp%
SET TempDest=%TempDir%ServerLogs_%DateTime%
SET MoveLog=%BatchLogDir%MoveLog%datetime%.log

echo %date% %time% %tzone%: Starting log movement process... > %MoveLog%
echo. >> %MoveLog%

::-----------------------------------------------------------------------------
:: RoboCopy to Temp
::-----------------------------------------------------------------------------

ROBOCOPY %GalleryLogDir% %TempDest% *.log /MOV /S /MINAGE:%LogAge% >> %MoveLog%
ROBOCOPY %GalleryLogDir% %TempDest% *.dmp /MOV /S /MINAGE:%LogAge% >> %MoveLog%
ROBOCOPY %GalleryLogDir%Gallery\Logs\ %TempDest%\Gallery\Logs\ *.csv /MOV /S /MINAGE:%LogAge% >> %MoveLog%

::-----------------------------------------------------------------------------
:: This section compresses the logs to a single zip archive
::
:: Please note the command below requires 7-Zip to be installed on the server.
:: You can download 7-Zip from http://www.7-zip.org/ or change the command to
:: use the zip utility of your choice as defined in the variable above.
::-----------------------------------------------------------------------------

echo. >> %MoveLog%
echo %date% %time% %tzone%: Archiving backup... >> %MoveLog%

%ZipUtil% a %TempDest%.7z %TempDest% >> %MoveLog%

::-----------------------------------------------------------------------------
:: Move zip archive to network storage location and cleanup local files
::-----------------------------------------------------------------------------

echo. >> %MoveLog%
echo %date% %time% %tzone%: Moving archive to network storage >> %MoveLog%
echo. >> %MoveLog%

copy %TempDest%.7z %OutputDir%ServerLogs_%datetime%.7z >> %MoveLog%

del %TempDest%.7z >> %MoveLog%
rmdir /S /Q %TempDest% >> %MoveLog%

::-----------------------------------------------------------------------------
:: Done
::-----------------------------------------------------------------------------

echo. >> %MoveLog%
echo %date% %time% %tzone%: Log movement process completed >> %MoveLog%
