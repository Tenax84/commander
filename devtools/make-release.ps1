# Kiadás készítése: teljes fordítás egy külön mappába (dist\Commander), a külső DLL-ek letöltése,
# majd a dist\Commander-<verzió>-win64.zip összeállítása. A verzió a src\platform\win\uselfupdate.pas
# CommanderVersion konstansából jön. -Publish: GitHub release (v<verzió>) létrehozása a zippel.
# A programba épített frissítő a legutóbbi release .zip fájlját tölti le.
param([switch]$Publish, [switch]$NoBuild, [string]$NotesFile)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location $root
$m = Select-String -Path src\platform\win\uselfupdate.pas -Pattern "CommanderVersion = '([^']+)'"
if (-not $m) { throw 'A CommanderVersion nem található.' }
$ver = $m.Matches[0].Groups[1].Value
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'Commander'
$zip = Join-Path $dist "Commander-$ver-win64.zip"
"Verzió: $ver"

if (-not $NoBuild) {
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  & (Join-Path $PSScriptRoot 'build-dc.ps1') -Mode all -Clean -RunDir $stage
  if (-not (Test-Path "$stage\Commander.exe")) { throw 'A fordítás nem sikerült.' }
  # curl writes its progress to stderr, which must not stop the script
  $ErrorActionPreference = 'Continue'
  & cmd /c "`"$PSScriptRoot\fetch-deps.bat`" `"$stage`""
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw 'A külső fájlok letöltése nem sikerült.' }
}
if (Test-Path $zip) { Remove-Item $zip -Force }
# tar.exe (bsdtar) writes standard zip entries with forward slashes
& "$env:SystemRoot\System32\tar.exe" -a -c -f $zip -C $dist Commander
if ($LASTEXITCODE -ne 0) { throw 'A zip összeállítása nem sikerült.' }
"ZIP: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"

if ($Publish) {
  $notes = @('--generate-notes')
  if ($NotesFile) { $notes = @('--notes-file', $NotesFile) }
  & gh release create "v$ver" $zip --repo Tenax84/commander --title "Commander $ver" @notes
  if ($LASTEXITCODE -ne 0) { throw 'A release létrehozása nem sikerült.' }
}
