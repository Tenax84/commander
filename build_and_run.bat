@echo off
rem A főprogram fordítása (devtools\build-dc.ps1 -Clean), a run\ mappa összeállítása, majd a run\Commander.exe indítása.
rem Kapcsolók nélkül csak akkor fordít, ha a legutóbbi fordítás óta módosult valamelyik forrásfájl (devtools\needs-build.ps1).
rem Ha a run\Commander.exe fut, fordítás előtt bezárja, különben a fordítás nem tudná bemásolni az új exe-t.
rem Használat: build_and_run.bat [további build-dc.ps1 kapcsolók, pl. -Mode all; ilyenkor mindig fordít]
setlocal
chcp 65001 >nul
cd /d "%~dp0"

if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File devtools\needs-build.ps1
  if errorlevel 1 goto :norebuild
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Get-Process Commander -ErrorAction SilentlyContinue | ? Path -like '%~dp0run\*';" ^
  "foreach ($x in $p) { [void]$x.CloseMainWindow(); if (-not $x.WaitForExit(10000)) { Write-Host 'A run\Commander.exe nem zárult be, zárd be kézzel.'; exit 1 } }; exit 0"
if errorlevel 1 goto :fail

powershell -NoProfile -ExecutionPolicy Bypass -File devtools\build-dc.ps1 -Clean %*
if errorlevel 1 goto :fail

:run
start "" "%~dp0run\Commander.exe"
exit /b 0

:norebuild
rem Nincs mit fordítani: csak akkor indítja el, ha még nem fut.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "if (Get-Process Commander -ErrorAction SilentlyContinue | ? Path -like '%~dp0run\*') { Write-Host 'A run\Commander.exe már fut.'; exit 1 }; exit 0"
if errorlevel 1 exit /b 0
goto :run

:fail
echo.
echo HIBA, a program nem indul el.
pause
exit /b 1
