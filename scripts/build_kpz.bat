@echo off
rem Build MediaManager.kpz in the repository root (Windows 10 1803+ / Windows 11).
rem Self-contained: needs only cmd.exe and tools built into Windows (tar.exe, certutil.exe);
rem no PowerShell, no Python.
rem Usage: scripts\build_kpz.bat [OutputName.kpz]
setlocal EnableExtensions EnableDelayedExpansion
set "status=1"
set "stage="
set "tmpzip="

for %%I in ("%~dp0..") do set "root=%%~fI"
set "out=%~1"
if "%out%"=="" set "out=MediaManager.kpz"
for %%I in ("%out%") do (
    if /i not "%%~xI"==".kpz" goto :badname
    if not "%%~nxI"=="%out%" goto :badname
)

set "base=Koha/Plugin/Com/Library"
rem Strict allowlist: exactly these files, nothing else from the plugin directory.
set "files=MediaManager.pm MediaManager/Controller.pm MediaManager/Health.pm MediaManager/Security.pm MediaManager/Store.pm MediaManager/breadcrumbs.tt MediaManager/configure.tt MediaManager/continue.tt MediaManager/error.tt MediaManager/layout.tt MediaManager/openapi.json MediaManager/tool.tt"
set "plugin=%root%\Koha\Plugin\Com\Library"

rem Windows' own tools by full path: another tar.exe on PATH (e.g. Git's GNU tar) cannot write zip files.
set "tar=%SystemRoot%\System32\tar.exe"
set "certutil=%SystemRoot%\System32\certutil.exe"
if not exist "%tar%" (echo build_kpz.bat: %tar% was not found ^(built into Windows 10 1803 and later^). & goto :end)
if not exist "%certutil%" (echo build_kpz.bat: %certutil% was not found. & goto :end)

rem Refuse unexpected plugin files, so nothing is packaged or left out by accident.
for %%F in ("%plugin%\MediaManager\*.pm" "%plugin%\MediaManager\*.tt" "%plugin%\MediaManager\*.json") do (
    set "known="
    for %%E in (%files%) do if /i "MediaManager/%%~nxF"=="%%E" set "known=1"
    if not defined known (echo Unexpected plugin file: MediaManager\%%~nxF & goto :end)
)

set "stage=%TEMP%\mm-kpz-%RANDOM%%RANDOM%"
set "tmpzip=%stage%.zip"
mkdir "%stage%\Koha\Plugin\Com\Library\MediaManager" || goto :end

set "count=0"
for %%E in (%files%) do (
    set "rel=%%E"
    set "rel=!rel:/=\!"
    set "src=%plugin%\!rel!"
    if not exist "!src!" (echo Missing required file: %%E & goto :end)
    for %%S in ("!src!") do if %%~zS==0 (echo Empty required file: %%E & goto :end)
    copy /b "!src!" "%stage%\Koha\Plugin\Com\Library\!rel!" >nul || goto :end
    rem Build time, NOT the source file time: Koha keeps the extracted file times, and Koha's
    rem Template Toolkit cache only recompiles a template whose file is newer than its cached copy.
    for %%D in ("%stage%\Koha\Plugin\Com\Library\!rel!") do (
        pushd "%%~dpD" && copy /b "%%~nxD"+,, >nul & popd
    )
    set "list=!list! %base%/%%E"
    set /a count+=1
)

pushd "%stage%" || goto :end
"%tar%" --format zip -c -f "%tmpzip%" %list%
set "tarstatus=%errorlevel%"
popd
if not "%tarstatus%"=="0" (echo Could not create the archive. & goto :end)

rem Verify the layout (exactly the allowlisted entries) and every entry's checksum.
set "entries=0"
for /f "delims=" %%N in ('""%tar%" -t -f "%tmpzip%""') do (
    set "known="
    for %%E in (%files%) do if "%%N"=="%base%/%%E" set "known=1"
    if not defined known (echo Invalid archive entry: %%N & goto :end)
    set /a entries+=1
)
if not "%entries%"=="%count%" (echo Invalid archive layout. & goto :end)
"%tar%" -x -O -f "%tmpzip%" >nul 2>&1 || (echo Archive verification failed. & goto :end)

move /y "%tmpzip%" "%root%\%out%" >nul || goto :end
set "hash="
for /f "skip=1 delims=" %%H in ('""%certutil%" -hashfile "%root%\%out%" SHA256"') do if not defined hash set "hash=%%H"
set "hash=%hash: =%"
echo %out%: SHA256 %hash%
set "status=0"
goto :end

:badname
echo OutputName must be a .kpz filename within this repository.

:end
if defined stage if exist "%stage%" rmdir /s /q "%stage%"
if defined tmpzip if exist "%tmpzip%" del /q "%tmpzip%"
if not "%status%"=="0" echo Build failed.
rem Keep the window open when started by double-click so the result can be read.
rem Explorer starts: cmd.exe /c ""<full path>.bat" " (two quotes after /c).
echo(%cmdcmdline%| findstr /i /c:"/c \"\"" >nul && pause
exit /b %status%
