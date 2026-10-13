param([string]$OutDir=(Join-Path $PSScriptRoot '..\screenshots'),[int]$W=1400,[int]$H=900,[string[]]$Names=@('TOTALCMD64','Commander'),[string]$Suffix='')
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x,int y,int cx,int cy,uint f);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[W]::SetProcessDPIAware() | Out-Null
foreach ($n in $Names) {
  $p = Get-Process $n | ? MainWindowHandle -ne 0 | select -First 1
  $hwnd = $p.MainWindowHandle
  [W]::ShowWindow($hwnd,9) | Out-Null
  [W]::SetWindowPos($hwnd,[IntPtr]::Zero,50,50,$W,$H,0x0040) | Out-Null
  [W]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 800
  $bmp = New-Object System.Drawing.Bitmap -ArgumentList ([int]$W),([int]$H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $dc = $g.GetHdc(); [W]::PrintWindow($hwnd,$dc,2) | Out-Null; $g.ReleaseHdc($dc)
  $bmp.Save((Join-Path $OutDir "$n$Suffix.png")); $g.Dispose(); $bmp.Dispose()
}
