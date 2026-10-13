# Exit code 0 if a rebuild is needed, 1 if run\Commander.exe is newer than every source file.
# Compares modification times only (no hashing), so it takes well under a second.
param([string]$Exe = (Join-Path $PSScriptRoot '..\run\Commander.exe'))
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path $Exe)) { 'Nincs run\Commander.exe, fordítás kell.'; exit 0 }
$built = [IO.File]::GetLastWriteTimeUtc((Resolve-Path $Exe))
# Build outputs living inside the source tree
$skipDir = '[\\/](lib|units|backup)[\\/]'
$skipExt = '.ppu','.o','.a','.or','.compiled','.exe','.dll','.wcx','.wdx','.wfx','.wlx','.dbg','.old','.res'
$items = 'src','components','plugins','language','pixmaps','default','highlighters'
foreach ($d in $items) {
  foreach ($f in [IO.Directory]::EnumerateFiles((Join-Path $root $d), '*', 'AllDirectories')) {
    if ($f -match $skipDir -or $skipExt -contains [IO.Path]::GetExtension($f)) { continue }
    if ([IO.File]::GetLastWriteTimeUtc($f) -gt $built) { "Módosult: $($f.Substring($root.Length + 1))"; exit 0 }
  }
}
foreach ($f in 'devtools\build-dc.ps1','doublecmd.help','pinyin.tbl') {
  if ([IO.File]::GetLastWriteTimeUtc((Join-Path $root $f)) -gt $built) { "Módosult: $f"; exit 0 }
}
'Nincs változás a legutóbbi fordítás óta.'
exit 1
