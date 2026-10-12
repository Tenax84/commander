# CLAUDE.md

A Double Commander (https://github.com/doublecmd/doublecmd) Windows-os forkja. A cél, hogy kinézetben és viselkedésben a Total Commanderhez hasonlítson. A kommunikáció és a commitüzenetek nyelve magyar; a kódkommentek angolul vannak, az upstream stílusát követve.

## Mappaszerkezet

A repó a `D:\Tenax84\commander` mappa. Benne olyan helyi mappák is vannak, amelyeket a .gitignore kizár:

| Mappa | Tartalom |
|---|---|
| `run\` | Hordozható futtatási könyvtár: a hivatalos v1.2.9 bináris csomag másolata, benne a saját buildünk (`doublecmd.exe`) és a `settings\` mappa a hordozható konfigurációval. Itt teszteljük a programot. |
| `screenshots\` | A képernyőképek és villanásmérések kimenete (TC kontra DC). |

## Fordítás

Szükséges hozzá: Lazarus 4.8 a `C:\lazarus` mappában (FPC 3.2.2, x86_64-win64).

```powershell
devtools\build-dc.ps1 -Clean              # főprogram, DarkWin build mode, kb. 30 mp
devtools\build-dc.ps1 -Mode all -Clean    # a komponens-csomagokkal együtt (első fordításnál kell)
```

- **Mindig `-Clean` kapcsolóval fordíts.** Részleges újrafordításnál az FPC 3.2.2 belső hibával (internal error) leállhat.
- A szkript sikeres fordítás után bemásolja a `doublecmd.exe`-t és a `language\doublecmd.hu.po`-t a `run\` mappába. Ha a `run\doublecmd.exe` éppen fut, a másolást kihagyja; ezt a `-NoDeploy` kapcsolóval is el lehet kerülni.
- Fordítás közben a régi exe `doublecmd.exe.old` néven megmarad. Ez, a `units\` és a `components\*\lib\` mappa a .gitignore-ban van.

## Tesztelés

Automatizált tesztek nincsenek. Úgy ellenőrzünk, hogy a programot a Total Commanderrel egymás mellett futtatjuk, és összehasonlítjuk őket:

- `devtools\shot.ps1 -Suffix _vN`: mindkét ablakot (`TOTALCMD64`, `doublecmd`) azonos méretre (1400×900) állítja, és a `screenshots\` mappába menti őket.
- `devtools\flash.ps1 -Name doublecmd [-Mode 0|1|2] [-All]`: minimalizálja, majd visszaállítja az ablakot, és közben 20 ms-onként képernyőképet készít a fekete pixelek arányáról. Ezzel mérjük a visszaállításkori villanást.

A kezdőértékekben végzett módosítások csak tiszta konfigurációval látszanak. Ha a `run\settings\` mappában már van mentett `doublecmd.xml`, az felülírja őket, ezért teszteléskor töröld vagy nevezd át.

## Saját módosítások (az upstreamhez képest)

A TC-szerű megjelenés nagyrészt **kezdőérték-változtatás**, nem új funkció:

- `src/uglobs.pas`: méretformátumok (bájt, illetve k), betű 9 pt normál, 16 px-es ikonok, kurzorkeret, középső eszköztár bekapcsolva, a fülsor csak több fülnél látszik, `yyyy.mm.dd hh:nn` dátumformátum, Alt+F4 a kilépéshez, a Név oszlop kitölti a panelt.
- `src/platform/uearlyconfig.pas`: `gAppMode = 3`, vagyis kényszerített világos téma.
- `src/ucolors.pas`: világoskék kurzor fekete betűvel, az útvonal-fejléc TC-színekkel.
- `src/ufilefunctions.pas`: `rahs` attribútum-formátum (`-a--`).
- `src/fileviews/ufileviewheader.pas`: `*.*` maszk az útvonal után.
- `src/fmain.pas`/`.lfm`: `[kötetcímke]` a szabad hely előtt, balra igazítva; F-gombok `F3 Nézőke` formában, F9 gomb nélkül.
- `src/ulng.pas`, `language/doublecmd.hu.po`: TC-s magyar szóhasználat (Fájl, Kijelölés, Nézet, `<DIR>` stb.).
- `src/platform/win/urestoreflicker.pas` (új): kiküszöböli a minimalizálásból visszaállításkor jelentkező fekete villanást. A főablak WndProc-ját subclassolja; visszaállításkor DWM-cloakkal elrejti az ablakot, szinkron kirajzol mindent, és csak utána jeleníti meg (legfeljebb 300 ms múlva). Az `fmain.pas` telepíti, csak Windowson.

Módosításnál vedd figyelembe:
- Az upstream kódot minimálisan módosítsd, és a TC-specifikus részeket jelöld egy `// Total Commander style` kommenttel. Így az upstream frissítésekor könnyebb összefésülni.
- A platformfüggő kódot tedd `{$IFDEF MSWINDOWS}` blokkba.
- Tartsd meg a fájlok kódolását: egyes `.pas` fájlok (pl. `fmain.pas`) UTF-8 BOM-mal kezdődnek, és CRLF sorvégeket használnak. A `.po` fájlok sorvége LF (lásd `.gitattributes`).
- A felhasználónak szóló szövegek az `ulng.pas`-ba (resourcestring) és a `.po` fájlba kerülnek.

## Git

- `origin`: a privát fork (`Tenax84/commander`). `upstream`: https://github.com/doublecmd/doublecmd.
- Upstream frissítése: `git fetch upstream` után `git merge upstream/master`.

## Nyitott feladatok (TC-hez képest)

1. A felső és a középső eszköztár gombjai és ikonjai eltérnek a TC-étől.
2. Menüsor: a „Lapok” és a „Kedvencek” menü felesleges, a „Start” menü hiányzik, a „Súgó” nincs a jobb szélen.
3. Meghajtósor: jobbra a `* \ .. ~ <` gombok látszanak; a TC-ben csak a `\ ..` van.
4. A meghajtóbetű nagybetűs (`C:\`), a TC-ben kisbetűs (`c:\`); a „vissza” ikon zöld nyíl.
