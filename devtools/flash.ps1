# Minimalizálás -> visszaállítás közben gyors képernyőfelvételt készít, és megszámolja a fekete pixeleket.
# Mode 0: SC_RESTORE (mint a tálcakattintás), 1: ShowWindow(SW_RESTORE), 2: ShowWindow(SW_SHOWNOACTIVATE)
param([string]$OutDir=(Join-Path $PSScriptRoot '..\screenshots'),[string]$Name='doublecmd',[int]$Runs=3,[int]$Frames=60,[string]$Tag='',[int]$Mode=0,[switch]$All)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices; using System.Diagnostics; using System.Collections.Generic;
public class Flash {
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h,int a,out int v,int cb);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 public static string Run(IntPtr h, int frames, int mode, string outPrefix, bool all) {
  RECT r; GetWindowRect(h, out r);
  int w=r.R-r.L, ht=r.B-r.T;
  PostMessage(h,0x0112,(IntPtr)0xF020,IntPtr.Zero); // SC_MINIMIZE
  System.Threading.Thread.Sleep(1500);
  var bmps = new List<Bitmap>(); var times = new List<long>(); var cloak = new List<int>();
  var sw = Stopwatch.StartNew();
  if (mode==1) ShowWindow(h,9); else if (mode==2) ShowWindow(h,4);
  else PostMessage(h,0x0112,(IntPtr)0xF120,IntPtr.Zero);
  for (int i=0;i<frames;i++) {
   int c; DwmGetWindowAttribute(h,14,out c,4); cloak.Add(c);
   var b = new Bitmap(w,ht,PixelFormat.Format32bppArgb);
   using (var g = Graphics.FromImage(b)) g.CopyFromScreen(r.L,r.T,0,0,new Size(w,ht));
   bmps.Add(b); times.Add(sw.ElapsedMilliseconds);
  }
  var sb = new System.Text.StringBuilder(); double worst=0; int worstI=-1;
  for (int i=0;i<bmps.Count;i++) {
   var b=bmps[i]; var d=b.LockBits(new Rectangle(0,0,w,ht),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
   int n=w*ht; int[] px=new int[n]; Marshal.Copy(d.Scan0,px,0,n); b.UnlockBits(d);
   long blk=0; for(int k=0;k<n;k++){ int p=px[k]; if(((p>>16)&255)<12 && ((p>>8)&255)<12 && (p&255)<12) blk++; }
   double f=100.0*blk/n; sb.AppendFormat("{0,4}ms {1,6:F2}% cloaked={2}\n",times[i],f,cloak[i]);
   if(f>worst){worst=f;worstI=i;}
   if (all && i<8) b.Save(outPrefix+"_f"+i+".png");
  }
  if (worstI>=0) bmps[worstI].Save(outPrefix+"_worst.png");
  foreach(var b in bmps) b.Dispose();
  return string.Format("WORST {0:F2}% @frame {1}\n",worst,worstI)+sb.ToString();
 }
}
"@
[Flash]::SetProcessDPIAware() | Out-Null
$p = Get-Process $Name | ? MainWindowHandle -ne 0 | select -First 1
for ($i=1; $i -le $Runs; $i++) {
  $out = [Flash]::Run($p.MainWindowHandle, $Frames, $Mode, (Join-Path $OutDir "flash_$Name$Tag`_$i"), $All.IsPresent)
  ($out -split "`n")[0]
  if ($i -eq 1) { ($out -split "`n")[1..10] }
  Start-Sleep -Milliseconds 800
}
