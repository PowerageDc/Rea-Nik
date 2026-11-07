@echo off
setlocal EnableDelayedExpansion

rem UTF-8 para la cola: el codepage OEM (CP850) corrompe caracteres como el
rem guion en-dash o las comillas tipograficas y el nombre deja de coincidir
rem con el del disco. La seleccion unica no pasa por archivo, solo la multiple.
chcp 65001 >nul

if "%~1"=="" exit /b 1

rem La clave vive fuera del repo, junto al script instalado. Se valida antes
rem de encolar y de tomar el lock para no dejar el lock tomado.
set "KEYFILE=%~dp0ProjectPack.key"
if not exist "%KEYFILE%" exit /b 2
set /p ZKEY=<"%KEYFILE%"

set "QDIR=%TEMP%\ProjectPack"
set "QFILE=%QDIR%\queue.txt"
set "LOCKDIR=%QDIR%\lock"

if not exist "%QDIR%" mkdir "%QDIR%" >nul 2>&1

rem Explorer puede llamar este script mas de una vez por el mismo click
rem derecho, agrupando archivos y carpetas por separado. Cada invocacion
rem encola sus items y una sola arma el zip.
for %%A in (%*) do (
    set "ITEM=%%~A"
    >>"%QFILE%" echo(!ITEM!
)

rem Lock atomico via mkdir. Si sigue tomado despues de unos 10 intentos
rem (unos 10 segundos) se asume huerfano y se limpia: esta invocacion sale sin
rem generar zip, pero la proxima ya lo encuentra libre.
set "LOCKWAIT=0"

:try_lock
mkdir "%LOCKDIR%" 2>nul
if not errorlevel 1 goto :got_lock

set /a LOCKWAIT+=1
if !LOCKWAIT! GEQ 10 (
    rmdir "%LOCKDIR%" >nul 2>&1
    exit /b 0
)
ping -n 2 127.0.0.1 >nul
goto :try_lock

:got_lock

rem Espera a que lleguen las invocaciones hermanas del mismo click.
ping -n 2 127.0.0.1 >nul

if not exist "%QFILE%" (
    rmdir "%LOCKDIR%" >nul 2>&1
    exit /b 0
)

set "SOURCES="
set "COUNT=0"
set "FIRST="

for /f "usebackq delims=" %%A in ("%QFILE%") do (
    if not defined FIRST set "FIRST=%%A"
    set /a COUNT+=1
    set "SOURCES=!SOURCES! "%%A""
)

del "%QFILE%" >nul 2>&1

for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v "{374DE290-123F-4565-9164-39C4925E467B}" 2^>nul') do set "DEST=%%B"

call set "DEST=%%DEST%%"

set "WINRAR=C:\Program Files\WinRAR\WinRAR.exe"

rem Un solo item: su propio nombre. Varios: nombre de la carpeta padre.
rem Si el item unico es una carpeta se usa el nombre completo, porque %%~n
rem trata lo posterior al ultimo punto como extension y trunca nombres como
rem "Artista ft. Otro Artista".
if not "!COUNT!"=="1" goto :name_multi

if exist "!FIRST!\" goto :name_single_dir
for %%A in ("!FIRST!") do set "NAME=%%~nA"
goto :name_done

:name_single_dir
for %%A in ("!FIRST!") do set "NAME=%%~nxA"
goto :name_done

:name_multi
for %%A in ("!FIRST!\..") do set "NAME=%%~nxA"

:name_done

rem Si el zip ya existe se borra: WinRAR en modo "a" fusiona con el existente
rem y con carpetas como fuente puede anidar contenido duplicado. Cada corrida
rem debe dejar una foto completa y actual.
if exist "%DEST%\!NAME!.zip" del "%DEST%\!NAME!.zip" >nul 2>&1

rem -r fuerza la recursion de subcarpetas. El preset RPPStems fija el formato
rem zip y debe existir en WinRAR de cada PC.
"%WINRAR%" a -r "-cpRPPStems" "-p!ZKEY!" "%DEST%\!NAME!.zip" !SOURCES!

rmdir "%LOCKDIR%" >nul 2>&1

endlocal