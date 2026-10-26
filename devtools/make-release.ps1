# Kiadás készítése: teljes fordítás egy külön mappába (dist\Commander), a külső DLL-ek letöltése,
# majd a dist\Commander-<verzió>-win64.zip és a dist\Commander-<verzió>-win64.msi összeállítása.
# A verzió a src\platform\win\uselfupdate.pas CommanderVersion konstansából jön, a kiadási
# megjegyzés a CHANGELOG.md azonos verziójú szakaszából.
# -Publish: a v<verzió> GitHub release létrehozása a HEAD commitra (a zippel és az MSI-vel).
# A programba épített frissítő a legutóbbi release assetjeit tölti le: a hordozható
# példány a .zip-et, az MSI-vel telepített a .msi-t.
# Az MSI-hez WiX Toolset 5 kell: dotnet tool install --global wix --version 5.0.2
#                                wix extension add -g WixToolset.UI.wixext/5.0.2
# -WithMac: the release notes also list the macOS disk images (built by the GitHub Actions
# workflow .github/workflows/commander-release.yml, which also publishes the release).
param([switch]$Publish, [switch]$NoBuild, [switch]$WithMac)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location $root
$repo = 'Tenax84/commander'
$m = Select-String -Path src\platform\win\uselfupdate.pas -Pattern "CommanderVersion = '([^']+)'"
if (-not $m) { throw 'A CommanderVersion nem található.' }
$ver = $m.Matches[0].Groups[1].Value
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'Commander'
$zip = Join-Path $dist "Commander-$ver-win64.zip"
$msi = Join-Path $dist "Commander-$ver-win64.msi"
$notesFile = Join-Path $dist "release-notes-$ver.md"
"Verzió: $ver"

# Release notes: the "## [<version>]" section of CHANGELOG.md
$changelog = Get-Content CHANGELOG.md -Encoding UTF8
$start = -1; $end = $changelog.Count
for ($i = 0; $i -lt $changelog.Count; $i++) {
  if ($changelog[$i] -match '^(## |\[[^\]]+\]: )') {
    if ($start -ge 0) { $end = $i; break }
    if ($changelog[$i] -match "^## \[$([regex]::Escape($ver))\]") { $start = $i + 1 }
  }
}
if ($start -lt 0) { throw "A CHANGELOG.md-ben nincs '## [$ver]' szakasz." }
$section = ($changelog[$start..($end - 1)] -join "`n").Trim()
$install = @"
**Letöltés:**
- ``Commander-$ver-win64.msi``: telepítő (a felhasználó saját mappájába telepít, rendszergazdai jog nélkül).
- ``Commander-$ver-win64.zip``: hordozható változat; csomagold ki egy tetszőleges mappába, és indítsd el a ``Commander\Commander.exe``-t.

A már telepített program induláskor magától felajánlja a frissítést.
"@
if ($WithMac) {
  $install = $install.Replace("`r`n", "`n").Replace("`n`nA már telepített program", @"

- ``Commander-$ver-macos-arm64.dmg``: macOS, Apple Silicon (M1 és újabb) processzorra.
- ``Commander-$ver-macos-x86_64.dmg``: macOS, Intel processzorra.

A macOS-es változat nincs az Apple-nél hitelesítve. Az ``Alkalmazások`` mappába húzás után futtasd a Terminálban: ``xattr -cr /Applications/Commander.app``

A már telepített Windowsos program
"@)
}
New-Item -ItemType Directory -Force $dist | Out-Null
[IO.File]::WriteAllText($notesFile, "$section`n`n$install`n", (New-Object Text.UTF8Encoding $false))

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

# License page of the installer: LICENSE.md as plain RTF
$rtf = New-Object Text.StringBuilder
[void]$rtf.Append('{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil Segoe UI;}}\fs16 ')
foreach ($line in (Get-Content LICENSE.md -Encoding UTF8)) {
  foreach ($c in $line.ToCharArray()) {
    if ($c -eq '\' -or $c -eq '{' -or $c -eq '}') { [void]$rtf.Append('\' + $c) }
    elseif ([int]$c -gt 127) { [void]$rtf.Append("\u$([int]$c)?") }
    else { [void]$rtf.Append($c) }
  }
  [void]$rtf.Append("\par`r`n")
}
[void]$rtf.Append('}')
$licenseRtf = Join-Path $dist 'license.rtf'
[IO.File]::WriteAllText($licenseRtf, $rtf.ToString(), [Text.Encoding]::ASCII)

if (Test-Path $msi) { Remove-Item $msi -Force }
& wix build devtools\installer\Commander.wxs -arch x64 -culture hu-HU -ext WixToolset.UI.wixext `
  -d "Version=$ver" -d "SourceDir=$stage" -d "IconFile=$root\src\doublecmd.ico" -d "LicenseRtf=$licenseRtf" `
  -o $msi
if ($LASTEXITCODE -ne 0) { throw 'Az MSI összeállítása nem sikerült.' }
Remove-Item ([IO.Path]::ChangeExtension($msi, '.wixpdb')), $licenseRtf -ErrorAction SilentlyContinue
"MSI: $msi ($([math]::Round((Get-Item $msi).Length / 1MB, 1)) MB)"

if ($Publish) {
  # The local v* tags belong to the upstream Double Commander, so the tag is created
  # on GitHub for the pushed HEAD commit, and is never pushed from here
  if (git status --porcelain --untracked-files=no) { throw 'Commitolatlan módosítások vannak.' }
  $head = (git rev-parse HEAD).Trim()
  git fetch origin master --quiet
  if ((git rev-parse origin/master).Trim() -ne $head) { throw 'A HEAD nincs feltöltve az origin/master-re (git push).' }
  & gh release create "v$ver" $msi $zip --repo $repo --target $head --title "Commander $ver" --notes-file $notesFile
  if ($LASTEXITCODE -ne 0) { throw 'A release létrehozása nem sikerült.' }
}
