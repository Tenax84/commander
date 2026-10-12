# Double Commander fordítása Lazarus 4.8 / FPC 3.2.2-vel, majd az exe és a magyar fordítás bemásolása a run mappába.
# Mindig -Clean kapcsolóval futtasd: a részleges újrafordításnál az FPC 3.2.2 belső hibával leállhat.
param([string]$Mode = 'doublecmd', [string]$BuildMode = 'DarkWin', [switch]$Clean,
      [string]$RunDir = (Join-Path $PSScriptRoot '..\run'), [switch]$NoDeploy)
$ErrorActionPreference = 'Stop'
$env:PATH = "C:\lazarus;C:\lazarus\fpc\3.2.2\bin\x86_64-win64;$env:PATH"
$src = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $src
function Laz([string]$p) {
  & C:\lazarus\lazbuild.exe -q $p
  if ($LASTEXITCODE -ne 0) { throw "lazbuild failed: $p" }
}
if ($Mode -in 'components','all') {
  foreach ($p in 'chsdet\chsdet.lpk','multithreadprocs\multithreadprocslaz.lpk','kascrypt\kascrypt.lpk',
                 'doublecmd\doublecmd_common.lpk','Image32\Image32.lpk','KASToolBar\kascomp.lpk',
                 'viewer\viewerpackage.lpk','gifview\gifview.lpk','synunihighlighter\synuni.lpk',
                 'virtualterminal\virtualterminal.lpk') { Laz "components\$p" }
}
if ($Mode -in 'doublecmd','all') {
  if (Test-Path doublecmd.exe) { Remove-Item doublecmd.exe.old -ErrorAction SilentlyContinue; Rename-Item doublecmd.exe doublecmd.exe.old }
  $extra = @(); if ($Clean) { $extra += '-B' }
  & C:\lazarus\lazbuild.exe -q @extra src\doublecmd.lpi "--bm=$BuildMode"
  if ($LASTEXITCODE -ne 0) { throw "lazbuild doublecmd failed" }
  if (-not $NoDeploy -and (Test-Path $RunDir)) {
    if (Get-Process doublecmd -ErrorAction SilentlyContinue | ? Path -like "$((Resolve-Path $RunDir).Path)*") {
      Write-Warning "A run\doublecmd.exe fut, nem másolom be. Zárd be, és futtasd újra (vagy másold kézzel)."
    } else {
      Copy-Item doublecmd.exe $RunDir -Force
      Copy-Item language\doublecmd.hu.po (Join-Path $RunDir 'language') -Force
      "DEPLOYED -> $RunDir"
    }
  }
}
"BUILD OK"
