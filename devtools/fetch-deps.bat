@echo off
rem A run\ mappából hiányzó külső (a repóból nem fordítható) fájlok letöltése.
rem Forrás: a hivatalos Double Commander kiadás zip-je; ebből csak a külső fájlokat vesszük ki.
rem Használat: devtools\fetch-deps.bat [run mappa]
setlocal EnableDelayedExpansion
chcp 65001 >nul

set DC_VER=1.2.9
set DC_ZIP=doublecmd-%DC_VER%.x86_64-win64.zip
set DC_URL=https://github.com/doublecmd/doublecmd/releases/download/v%DC_VER%/%DC_ZIP%
set DC_SHA256=e8472c0105dbde55db4ffbdbd190eab65e9da0375596454995fae4a1fc128dee

rem 7z.dll, bz2.dll, liblzma.dll, libzstd.dll: sevenzip/zip plugin; unrar.dll: unrar plugin
rem libssh2.dll: sftp; libpcre2-8.dll: regex search; lua5.1.dll: Lua scripts
rem winpty.dll, winpty-agent.exe: built-in terminal; 7z.sfx: self-extracting archives
set DEPS=7z.dll 7z.sfx bz2.dll liblzma.dll libpcre2-8.dll libssh2.dll libzstd.dll lua5.1.dll unrar.dll winpty.dll winpty-agent.exe

if "%~1"=="" (set RUN_DIR=%~dp0..\run) else (set RUN_DIR=%~1)
if not exist "%RUN_DIR%" mkdir "%RUN_DIR%"
for %%I in ("%RUN_DIR%") do set RUN_DIR=%%~fI

set MISSING=
for %%F in (%DEPS%) do if not exist "%RUN_DIR%\%%F" set MISSING=!MISSING! doublecmd/%%F

rem Empty doublecmd.inf = portable mode (settings stay in run\settings)
if not exist "%RUN_DIR%\settings" mkdir "%RUN_DIR%\settings"
if not exist "%RUN_DIR%\settings\doublecmd.inf" type nul > "%RUN_DIR%\settings\doublecmd.inf"

if "%MISSING%"=="" (
  echo Minden külső fájl megvan: %RUN_DIR%
  exit /b 0
)
echo Hiányzik:%MISSING%

set TMP_DIR=%TEMP%\dc-deps-%RANDOM%%RANDOM%
mkdir "%TMP_DIR%" || exit /b 1

echo Letöltés: %DC_URL%
"%SystemRoot%\System32\curl.exe" -fL --retry 3 -o "%TMP_DIR%\%DC_ZIP%" "%DC_URL%"
if errorlevel 1 (echo HIBA: a letöltés nem sikerült. & goto :fail)

set HASH=
for /f "skip=1 delims=" %%H in ('certutil -hashfile "%TMP_DIR%\%DC_ZIP%" SHA256') do if not defined HASH set HASH=%%H
set HASH=%HASH: =%
if /i not "%HASH%"=="%DC_SHA256%" (echo HIBA: hibás SHA256: %HASH% & goto :fail)

"%SystemRoot%\System32\tar.exe" -xf "%TMP_DIR%\%DC_ZIP%" -C "%TMP_DIR%"%MISSING%
if errorlevel 1 (echo HIBA: a kicsomagolás nem sikerült. & goto :fail)

for %%F in (%DEPS%) do if not exist "%RUN_DIR%\%%F" (
  copy /Y "%TMP_DIR%\doublecmd\%%F" "%RUN_DIR%\" >nul || goto :fail
  echo   + %%F
)
rd /S /Q "%TMP_DIR%"
echo Kész: %RUN_DIR%
exit /b 0

:fail
rd /S /Q "%TMP_DIR%" 2>nul
exit /b 1
