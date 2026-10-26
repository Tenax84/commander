# CLAUDE.md

A Double Commander (https://github.com/doublecmd/doublecmd) Windows-os forkja. A cél, hogy kinézetben és viselkedésben a Total Commanderhez hasonlítson. A kommunikáció és a commitüzenetek nyelve magyar; a kódkommentek angolul vannak, az upstream stílusát követve.

## Mappaszerkezet

A repó a `D:\Tenax84\commander` mappa. Benne olyan helyi mappák is vannak, amelyeket a .gitignore kizár:

| Mappa | Tartalom |
|---|---|
| `run\` | Hordozható futtatási könyvtár: a hivatalos v1.2.9 bináris csomag másolata, benne a saját buildünk (`Commander.exe`) és a `settings\` mappa a hordozható konfigurációval. Itt teszteljük a programot. |
| `screenshots\` | A képernyőképek és villanásmérések kimenete (TC kontra DC). |
| `dist\` | A `devtools\make-release.ps1` (és macOS-en a `devtools/macos/build-mac.sh`) kimenete: `Commander\` (a kiadás mappája), `Commander-<verzió>-win64.zip`, `Commander-<verzió>-win64.msi` és `release-notes-<verzió>.md`. |

## Fordítás

Szükséges hozzá: Lazarus 4.8 a `C:\lazarus` mappában (FPC 3.2.2, x86_64-win64).

```powershell
devtools\build-dc.ps1 -Clean              # főprogram, DarkWin build mode, kb. 30 mp
devtools\build-dc.ps1 -Mode all -Clean    # komponensek + pluginek + főprogram (első fordításnál kell), kb. 1 perc
```

`-Mode` lehet `components`, `plugins`, `doublecmd` vagy `all`. Új gépen: `devtools\fetch-deps.bat`, utána `devtools\build-dc.ps1 -Mode all -Clean`, és a `run\Commander.exe` indítható.

- `build_and_run.bat`: kapcsolók nélkül előbb a `devtools\needs-build.ps1`-gyel ellenőrzi (kb. 0,5 mp alatt, a fájlok módosítási ideje alapján), hogy a `src\`, `components\`, `plugins\`, `language\` stb. mappákban módosult-e valami a `run\Commander.exe` óta. Ha nem, nem fordít, csak elindítja a programot, ha még nem fut. Kapcsolóval (pl. `-Mode all`) mindig fordít. Fordításkor bezárja a futó `run\Commander.exe`-t, lefuttatja a `devtools\build-dc.ps1 -Clean`-t (a további kapcsolókat, pl. `-Mode all`, továbbadja), majd elindítja a `run\Commander.exe`-t. Hiba esetén megáll, és nem indítja el a programot.
- `devtools\fetch-deps.bat`: a `run\` mappába letölti a repóból nem fordítható külső fájlokat (7z/unrar/lua/pcre2/libssh2 DLL-ek, 7z.sfx, winpty) a hivatalos v1.2.9 zip-ből (SHA256-tal ellenőrizve), és létrehozza a hordozható módot jelző `settings\doublecmd.inf`-et. Csak a hiányzókat tölti le.
- **Mindig `-Clean` kapcsolóval fordíts.** Részleges újrafordításnál az FPC 3.2.2 belső hibával (internal error) leállhat.
- A szkript sikeres fordítás után összeállítja a `run\` mappát az `install\windows\install.bat` mintájára: exe, pluginek, `language\`, `pixmaps\`, `default\`, `highlighters\`, `doc\` stb. A `settings\` mappát és a külső DLL-eket nem bántja. Ha a `run\Commander.exe` éppen fut, a másolást kihagyja; ezt a `-NoDeploy` kapcsolóval is el lehet kerülni.
- Fordítás közben a régi exe `Commander.exe.old` néven megmarad. Ez, a `units\`, a `dist\` és a `components\*\lib\` mappa a .gitignore-ban van.
- `devtools\make-release.ps1 [-Publish] [-NoBuild]`: kiadás készítése; a teljes folyamatot (verzióemelés, `CHANGELOG.md`, README, commit, push, közzététel) a `/release` skill (`.claude/skills/release/SKILL.md`) írja le. A verziót a `src\platform\win\uselfupdate.pas` `CommanderVersion` konstansából, a kiadási megjegyzést a `CHANGELOG.md` `## [<verzió>]` szakaszából veszi. A `dist\Commander` mappába fordít (`-Mode all -Clean`), letölti a külső DLL-eket, elkészíti a `dist\Commander-<verzió>-win64.zip`-et (benne egy `Commander\` mappa) és a WiX 5-tel a `dist\Commander-<verzió>-win64.msi`-t (`devtools\installer\Commander.wxs`). `-Publish` esetén a GitHubon a HEAD commitra létrehozza a `v<verzió>` kiadást mindkét fájllal; ehhez a munkakönyvtárnak tisztának, a HEAD-nek feltöltöttnek kell lennie. **A helyi `v*` tagek a DC-éi** (upstream), ezért a Commander tagjei csak az `origin`-on léteznek; helyi taget ne hozz létre, és ne told fel. A `gh`-t mindig `--repo Tenax84/commander`-rel hívd.
- `.github/workflows/commander-release.yml` (GitHub Actions, kézi indítás: `gh workflow run commander-release.yml --repo Tenax84/commander [-f publish=false]`): a kiadás elsődleges útja. Windows-jobja Lazarus 4.8-cal a `make-release.ps1 -WithMac`-et futtatja (MSI + zip), a macOS-es (macos-15, FPC 3.2.4-rc2, Lazarus main forrásból, mint az upstream snapshotoknál) a `devtools/macos/build-mac.sh aarch64|x86_64`-gyel két DMG-t készít (`Commander-<verzió>-macos-arm64.dmg`, `-macos-x86_64.dmg`; a bundle `Commander.app`, benne a bináris neve továbbra is `doublecmd`, a DMG háttere és `install.txt`-je a `devtools/macos/dmg/`-ből jön). A `publish` job a négy fájllal egyszerre hozza létre a `v<verzió>` kiadást a futtatott commitra. A `build-dc.ps1` a Lazarust a `LAZARUS_DIR`-ből, a `C:\lazarus`-ból vagy a PATH-ról veszi. Az upstream workflow-k (`build-release`, `build-snapshot`, `Publish to WinGet`) a forkon le vannak tiltva (`gh workflow disable`).

## Tesztelés

Automatizált tesztek nincsenek. Úgy ellenőrzünk, hogy a programot a Total Commanderrel egymás mellett futtatjuk, és összehasonlítjuk őket:

- `devtools\shot.ps1 -Suffix _vN`: mindkét ablakot (`TOTALCMD64`, `Commander`) azonos méretre (1400×900) állítja, és a `screenshots\` mappába menti őket.
- `devtools\flash.ps1 -Name Commander [-Mode 0|1|2] [-All]`: minimalizálja, majd visszaállítja az ablakot, és közben 20 ms-onként képernyőképet készít a fekete pixelek arányáról. Ezzel mérjük a visszaállításkori villanást.

A kezdőértékekben végzett módosítások csak tiszta konfigurációval látszanak. Ha a `run\settings\` mappában már van mentett `doublecmd.xml`, az felülírja őket, ezért teszteléskor töröld vagy nevezd át.

## Saját módosítások (az upstreamhez képest)

A TC-szerű megjelenés nagyrészt **kezdőérték-változtatás**, nem új funkció:

- `src/uglobs.pas`: méretformátumok (bájt, illetve k), betű 9 pt normál, 16 px-es ikonok, kurzorkeret, középső eszköztár bekapcsolva, a fülsor csak több fülnél látszik, `yyyy.mm.dd hh:nn` dátumformátum, Alt+F4 a kilépéshez, a Név oszlop kitölti a panelt.
- `src/platform/uearlyconfig.pas`: `gAppMode = 3`, vagyis kényszerített világos téma; `gSplashForm = False`, vagyis nincs indítóképernyő.
- `src/ucolors.pas`: világoskék kurzor fekete betűvel, az útvonal-fejléc TC-színekkel.
- `src/ufilefunctions.pas`: `rahs` attribútum-formátum (`-a--`).
- `src/fileviews/ufileviewheader.pas`: `*.*` maszk az útvonal után.
- `src/fmain.pas`/`.lfm`: `[kötetcímke]` a szabad hely előtt, balra igazítva; F-gombok `F3 Nézőke` formában, F9 gomb nélkül.
- `src/ulng.pas`, `language/doublecmd.hu.po`: TC-s magyar szóhasználat (Fájl, Kijelölés, Nézet, `<DIR>` stb.).
- `pixmaps/tcstyle/` (új ikontéma): TC-szerű ikonok a felső eszköztár gombjaihoz (Codexszel generálva), minden más ikont a `dctheme`-től örököl (`Inherits=dctheme`). Az `uglobs.pas`-ban ez az alapértelmezett ikontéma.
- Programnév: a felhasználónak látható helyeken „Commander” a „Double Commander” helyett (ablakcím, `Application.Title`, a `doublecmd.lpi` verzióinformációja, Névjegy, üzenetablakok, `ulng.pas`, `doublecmd.hu.po`). Az exe neve `Commander.exe` (a `doublecmd.lpi` minden build módjában `..\Commander` a cél; a `run\Commander.visualelementsmanifest.xml` az `install\windows\doublecmd.visualelementsmanifest.xml` másolata). A konfigurációs fájlok, a projektfájlok és a belső azonosítók neve (`doublecmd*`) nem változott, ahogy a DC weboldalára mutató menüpont és a macOS-es szöveg sem. A többi nyelvi `.po` fájlban még „Double Commander” szerepel.
- `src/doublecmd.ico`: TC-szerű kék hajlékonylemez (Codexszel generálva, 16–256 px). Minden méretet BMP-ként kell tárolni, mert a PNG-tömörítésű bejegyzéseket az LCL nem tudja beolvasni („Bitmap with unknown compression”). A `doublecmd.res` fordításkor ebből készül. macOS-re ebből készült (Pillow-val) a `devtools/macos/Commander.icns` (a `build-mac.sh` a bundle `doublecmd.icns`-e helyére másolja) és a DMG kötetikonja (`devtools/macos/dmg/.VolumeIcon.icns`).
- `src/fmain.pas` (`ExecuteCommandFromEdit`): a parancssori `cd` relatív útvonalat (`sub\x`, `..\x`, `.\x`) az aktív panel mappájához képest oldja fel, a `\mappa` alakot pedig az aktív panel meghajtóján. Windowson az `mbSetCurrentDir` nem változtatja meg a folyamat munkakönyvtárát, ezért az `mbExpandFileName` magában a program mappájából indulna. Ha a `cd` célpontja fájl, a program a mappájába lép, és a fájlt a lemezen lévő valódi nevével (kis- és nagybetűtől függetlenül) jelöli ki.
- `src/fmain.pas` (`edtCommandWindowProc`), `src/platform/uClipboard.pas` (`ClipboardGetFileNames`): ha a vágólapon fájl van (és nincs szöveg), a parancssorba beillesztéskor (Ctrl+V, Shift+Insert, helyi menü) a fájl teljes útvonala kerül; több fájlnál szóközzel elválasztva, a szóközt tartalmazókat idézőjelbe téve. macOS-en is (`LM_PASTE` a Cocoa field editorból; a `ClipboardGetFileNames` az `NSFilenamesPboardType`-ot olvassa, és mivel a Finder a fájlnevet szövegként is felteszi, ott a fájl elsőbbséget kap).
- `src/platform/win/urestoreflicker.pas` (új): kiküszöböli a minimalizálásból visszaállításkor jelentkező fekete villanást. A főablak WndProc-ját subclassolja; visszaállításkor DWM-cloakkal elrejti az ablakot, szinkron kirajzol mindent, és csak utána jeleníti meg (legfeljebb 300 ms múlva). Az `fmain.pas` telepíti, csak Windowson.
- `src/platform/win/unetpathprobe.pas` (új): a hálózati útvonalakat (UNC, leképezett meghajtó) a fő szál nem éri el, így elérhetetlen gépnél sem fagy be a felület. A panel azonnal átvált, a lista a háttérben töltődik be. Előtte egy kb. 2 mp-es TCP-próba fut a gép 445-ös és 139-es portjára, az elérhetetlen megosztásokat/gépeket pedig a program egy ideig megjegyzi. Betöltéskor a panel fehér marad, és a közepén a „Fájllista betöltése...” felirat látszik (homokóra nélkül). A hiba üzenetablak helyett a panel közepén jelenik meg (`TFileView.PanelMessage`, `TFileViewBaseGrid.Paint`). A fájlrendszer-figyelő csak akkor indul el hálózati útvonalon, ha az elérhető. Ha a betöltés 0,5 mp-nél tovább tart, a panelen csak a `..` sor marad (`TFileView.ShowUpDirOnly`); hiba esetén is ott van (`TFileListBuilder`). Betöltés közben is vissza lehet lépni (Backspace, Enter a `..`-on, dupla kattintás a panelen, Esc az előző mappára): ez megszakítja a háttérmunkát (`NetCancelThread`: a TCP-próba leáll, a folyamatban lévő fájlrendszer-hívást `CancelSynchronousIo` szakítja meg), a panel pedig új háttérszálat kap, ha az előző betöltés beragadt (`TFileView.MakeFileSourceFileList`). A megosztás gyökeréről (`\\gép\megosztás\`) a `..` a gép megosztáslistájára (`\\gép\`, hálózati fájlforrás) lép, akkor is, ha a megosztás nem érhető el (`TFileView.ChangePathToParent`). macOS-es megfelelője az azonos interfészű `src/platform/unix/darwin/unetpathprobe.pas`: a hálózati köteteket (smbfs, afpfs, nfs, webdav) a `getfsstat(MNT_NOWAIT)` csatolási táblájából ismeri fel, a TCP-próba a fájlrendszer portjára (445/139, 548, 2049, 80/443) megy; a beragadt fájlrendszer-hívást nem tudja megszakítani, ilyenkor a panel új szálat kap. A közös helyeken `{$IF DEFINED(MSWINDOWS) or DEFINED(DARWIN)}` a feltétel.
- `plugins/wfx/ftp/src/ftptcimport.pas` (új): az FTP plugin gyökerében (`wfx://FTP`) az `<Importálás Total Commanderből>` elem (csak Windowson) beolvassa a TC `wcx_ftp.ini`-jét. A helyét a registryből (`HKCU`/`HKLM\Software\Ghisler\Total Commander`: `FtpIniName`, `IniFileName`, `InstallDir`), illetve a `%COMMANDER_PATH%`, `%APPDATA%\GHISLER`, `C:\totalcmd` mappákból keresi, és beviteli ablakban felkínálja. A TC-s jelszó-obfuszkációt visszafejti (Delphi `Random` alapú, a Metasploit `total_commander` modul alapján). A mesterjelszóval védett (`!`-lel kezdődő) jelszavak nem vihetők át. A már létező nevű kapcsolatokat kihagyja.
- `src/platform/win/uselfupdate.pas` (új): önfrissítés a GitHub Releases alapján. Indításkor (`doublecmd.lpr`, a `frmMain.Show` után; a unit a uses-lista végén van, mert a függőségei az `Interfaces` előtt nem inicializálódhatnak) egy háttérszál WinINettel lekéri a `Tenax84/commander` legutóbbi kiadását (`api.github.com/.../releases/latest`). Ha a tag (`v1.2.3`) újabb a `CommanderVersion`-nél, rákérdez (Igen / Nem / Kihagyás; a kihagyott verzió a `settings\update-skip.txt`-be kerül). Ha a programot az MSI telepítette (a `HKCU\Software\Tenax84\Commander` `InstallDir` értéke a program mappája), a `.msi` assetet tölti le a `%TEMP%\Commander-update` mappába, és egy rejtett PowerShell a program kilépése után `msiexec /i … /passive`-vel telepíti (újraindítással, vagy „Nem” esetén a program bezárásakor). Egyébként a `.zip` assetet tölti le, a `%TEMP%\Commander-update` mappába csomagolja ki, és a program mappájába másolja. A `settings\` mappát kihagyja; a használatban lévő fájlokat `*.updold` névre nevezi át, ezeket az `update-old.txt` alapján a következő induláskor törli. Újraindításkor egy rejtett PowerShell megvárja a régi folyamat kilépését, és elindítja az új exe-t. A `COMMANDER_UPDATE_URL` környezeti változóval a kiadás adatai helyi szerverről is olvashatók (teszteléshez; a gombok a szülőablaknak küldött `WM_COMMAND`/`BN_CLICKED` üzenettel nyomhatók meg, a `BM_CLICK` nem működik, a `WM_LBUTTONDOWN/UP` pedig nem megbízható). A Névjegyben a DC-verzió mellett `(Commander x.y.z)` látszik. **A repónak publikusnak kell lennie**, különben az API 404-et ad, és a frissítő csendben nem csinál semmit. macOS-en a `src/platform/unix/darwin/uselfupdate.pas` fut (a `CommanderVersion` ott függvény: a bundle `Info.plist`-jének `CFBundleShortVersionString`-je, amit a `build-mac.sh` a Windowsos konstansból állít be; csak `com.tenax84.commander` azonosítójú bundle-ben aktív). `curl`-lel tölti le a gép architektúrájának megfelelő `-macos-arm64.dmg`/`-macos-x86_64.dmg` assetet, `hdiutil`-lal csatolja, `ditto`-val kimásolja a `.app`-ot, és egy `/bin/sh` szkript a program kilépése után lecseréli a bundle-t (újraindításkor `open`). Ha a bundle nem írható vagy transzlokálva fut, csak megnyitja a DMG-t.
- `devtools/installer/Commander.wxs` (új): WiX 5 MSI-telepítő. Felhasználónkénti telepítés a `%LOCALAPPDATA%\Programs\Commander` mappába (nincs UAC, a mappa írható, így a `settings\doublecmd.inf` miatt hordozható módban fut), Start menü- és asztali parancsikonnal. Rögzített `UpgradeCode`, `MajorUpgrade`: az újabb MSI eltávolítja a régit. A felhasználó beállításait (`settings\*.xml` stb.) eltávolításkor és frissítéskor sem törli.

Módosításnál vedd figyelembe:
- Az upstream kódot minimálisan módosítsd, és a TC-specifikus részeket jelöld egy `// Total Commander style` kommenttel. Így az upstream frissítésekor könnyebb összefésülni.
- A platformfüggő kódot tedd `{$IFDEF MSWINDOWS}` blokkba.
- Tartsd meg a fájlok kódolását: egyes `.pas` fájlok (pl. `fmain.pas`) UTF-8 BOM-mal kezdődnek, és CRLF sorvégeket használnak. A `.po` fájlok sorvége LF (lásd `.gitattributes`).
- A felhasználónak szóló szövegek az `ulng.pas`-ba (resourcestring) és a `.po` fájlba kerülnek.

## Git

- `origin`: a fork (`Tenax84/commander`). `upstream`: https://github.com/doublecmd/doublecmd.
- Upstream frissítése: `git fetch upstream` után `git merge upstream/master`.

## Nyitott feladatok (TC-hez képest)

1. A középső eszköztár ikonjai eltérnek a TC-étől; a felső eszköztáron a `cm_NetworkDisconnect` még a DC-s ikont használja.
2. Menüsor: a „Lapok” és a „Kedvencek” menü felesleges, a „Start” menü hiányzik, a „Súgó” nincs a jobb szélen.
3. Meghajtósor: jobbra a `* \ .. ~ <` gombok látszanak; a TC-ben csak a `\ ..` van.
4. A meghajtóbetű nagybetűs (`C:\`), a TC-ben kisbetűs (`c:\`); a „vissza” ikon zöld nyíl.
