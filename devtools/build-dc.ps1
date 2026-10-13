# Double Commander fordítása Lazarus 4.8 / FPC 3.2.2-vel, majd a run mappa összeállítása (install\windows\install.bat mintájára).
# Mindig -Clean kapcsolóval futtasd: a részleges újrafordításnál az FPC 3.2.2 belső hibával leállhat.
# -Mode: components | plugins | doublecmd | all
param([string]$Mode = 'doublecmd', [string]$BuildMode = 'DarkWin', [switch]$Clean,
      [string]$RunDir = (Join-Path $PSScriptRoot '..\run'), [switch]$NoDeploy)
$ErrorActionPreference = 'Stop'
$env:PATH = "C:\lazarus;C:\lazarus\fpc\3.2.2\bin\x86_64-win64;$env:PATH"
$src = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $src
function Laz([string]$p, [string[]]$more = @()) {
  $extra = @(); if ($Clean) { $extra += '-B' }
  & C:\lazarus\lazbuild.exe -q @extra $p @more
  if ($LASTEXITCODE -ne 0) { throw "lazbuild failed: $p" }
}
if ($Mode -in 'components','all') {
  foreach ($p in 'chsdet\chsdet.lpk','multithreadprocs\multithreadprocslaz.lpk','kascrypt\kascrypt.lpk',
                 'doublecmd\doublecmd_common.lpk','Image32\Image32.lpk','KASToolBar\kascomp.lpk',
                 'viewer\viewerpackage.lpk','gifview\gifview.lpk','synunihighlighter\synuni.lpk',
                 'virtualterminal\virtualterminal.lpk') { Laz "components\$p" }
}
# Plugin name -> project file (relative to plugins\)
$plugins = [ordered]@{
  'wcx\base64\base64.wcx'       = 'wcx\base64\src\base64wcx.lpi'
  'wcx\rpm\rpm.wcx'             = 'wcx\rpm\src\rpm.lpi'
  'wcx\sevenzip\sevenzip.wcx'   = 'wcx\sevenzip\src\sevenzipwcx.lpi'
  'wcx\unrar\unrar.wcx'         = 'wcx\unrar\src\unrar.lpi'
  'wcx\zip\zip.wcx'             = 'wcx\zip\src\zip.lpi'
  'wdx\rpm_wdx\rpm_wdx.wdx'     = 'wdx\rpm_wdx\src\rpm_wdx.lpi'
  'wdx\deb_wdx\deb_wdx.wdx'     = 'wdx\deb_wdx\src\deb_wdx.lpi'
  'wdx\audioinfo\audioinfo.wdx' = 'wdx\audioinfo\src\AudioInfo.lpi'
  'wfx\ftp\ftp.wfx'             = 'wfx\ftp\src\ftp.lpi'
  'wlx\wmp\wmp.wlx'             = 'wlx\wmp\src\wmp.lpi'
  'wlx\preview\preview.wlx'     = 'wlx\preview\src\preview.lpi'
  'wlx\richview\richview.wlx'   = 'wlx\richview\src\richview.lpi'
}
if ($Mode -in 'plugins','all') {
  foreach ($p in $plugins.Values) { Laz "plugins\$p" }
}
if ($Mode -in 'doublecmd','all') {
  if (Test-Path Commander.exe) { Remove-Item Commander.exe.old -ErrorAction SilentlyContinue; Rename-Item Commander.exe Commander.exe.old }
  Laz 'src\doublecmd.lpi' "--bm=$BuildMode"
}
"BUILD OK"
if ($NoDeploy) { return }

# Assemble the portable run directory. Existing files (settings, external DLLs) are kept.
if (Get-Process Commander -ErrorAction SilentlyContinue |
    ? Path -like "$([IO.Path]::GetFullPath($RunDir))*") {
  Write-Warning "A run\Commander.exe fut, nem másolom be. Zárd be, és futtasd újra (-Mode none)."
  return
}
New-Item -ItemType Directory -Force $RunDir, "$RunDir\doc" | Out-Null
$RunDir = Resolve-Path $RunDir
foreach ($d in 'default','language','pixmaps','highlighters') {
  robocopy $d "$RunDir\$d" /E /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $d" }
}
Copy-Item doc\*.txt "$RunDir\doc" -Force
Copy-Item doublecmd.help, pinyin.tbl $RunDir -Force
# Windows looks for <exe name>.VisualElementsManifest.xml
Copy-Item install\windows\doublecmd.visualelementsmanifest.xml "$RunDir\Commander.visualelementsmanifest.xml" -Force
if (Test-Path Commander.exe) { Copy-Item Commander.exe $RunDir -Force }
foreach ($p in $plugins.Keys) {
  $dst = Join-Path $RunDir "plugins\$(Split-Path $p)"
  New-Item -ItemType Directory -Force $dst | Out-Null
  if (Test-Path "plugins\$p") { Copy-Item "plugins\$p" $dst -Force }
  $s = "plugins\$(Split-Path $p)\language"
  if (Test-Path $s) { robocopy $s "$dst\language" /E /NFL /NDL /NJH /NJS /NP | Out-Null }
}
robocopy plugins\wdx\scripts "$RunDir\plugins\wdx\scripts" /E /NFL /NDL /NJH /NJS /NP | Out-Null
Copy-Item plugins\wdx\audioinfo\audioinfo.lng "$RunDir\plugins\wdx\audioinfo" -Force
$global:LASTEXITCODE = 0
"DEPLOYED -> $RunDir"
