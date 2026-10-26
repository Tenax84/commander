# Commander

A **Commander** a [Double Commander](https://github.com/doublecmd/doublecmd) (DC) Windowsra szánt forkja. Kinézetben és kezelésben a Total Commanderhez igazodik: TC-s színek, ikonok, eszköztárak, formátumok és billentyűkiosztás, a DC összes funkciójával együtt.

> A projekt nem áll kapcsolatban a Total Commanderrel és a Ghisler Software GmbH-val, és nem is támogatják. A „Total Commander” név a jogtulajdonos védjegye; itt csak arra utal, hogy melyik programhoz hasonlít a kinézet. A program a Double Commanderen alapul, és annak licence (GNU GPL 2) alatt érhető el.

## Letöltés és telepítés

A legutóbbi kiadás a [Releases](https://github.com/Tenax84/commander/releases/latest) oldalon érhető el, a verziók változásai a [CHANGELOG.md](CHANGELOG.md)-ben olvashatók. Windowsra (64 bites) két formában tölthető le:

- **Telepítő** (`Commander-<verzió>-win64.msi`): a programot a felhasználó saját mappájába (`%LOCALAPPDATA%\Programs\Commander`) telepíti, rendszergazdai jog nélkül. Start menü- és asztali parancsikont is létrehoz, és a Programok és szolgáltatások között eltávolítható. Eltávolításkor a beállítások (`settings\`) megmaradnak.
- **Hordozható változat** (`Commander-<verzió>-win64.zip`): csomagold ki egy tetszőleges mappába (például `C:\Commander` vagy `D:\Programok\Commander`), és indítsd el a `Commander.exe`-t.

Windowson a beállításokat a program mindkét esetben a saját mappájának `settings\` almappájában tárolja.

A konfigurációs fájlok neve ugyanaz, mint a DC-ben (`doublecmd.xml`, `shortcuts.scf` stb.), így egy meglévő DC-beállítás átmásolható a `settings\` mappába.

**macOS-re** az 1.2.0-nál újabb kiadásoktól lemezkép is van: `Commander-<verzió>-macos-arm64.dmg` (Apple Silicon) és `Commander-<verzió>-macos-x86_64.dmg` (Intel). Nyisd meg a lemezképet, és húzd a `Commander.app`-ot az Alkalmazások mappába. A csomag nincs az Apple-nél hitelesítve, ezért első indítás előtt futtasd a Terminálban: `xattr -cr /Applications/Commander.app` (enélkül a macOS 15-től a Rendszerbeállítások → Adatvédelem és biztonság → „Megnyitás mindenképp” gombbal lehet elindítani; a régebbi macOS-eken a Finderben jobb gomb → Megnyitás is elég). A fájlkezeléshez érdemes a `Commander.app`-nak teljes lemezhozzáférést adni (Rendszerbeállítások → Adatvédelem és biztonság → Teljes lemezhozzáférés). Az automatikus frissítés macOS-en is működik: a program letölti a gépnek megfelelő lemezképet, és kilépéskor lecseréli a `Commander.app`-ot (ha az nem írható, megnyitja a lemezképet a kézi telepítéshez). A macOS-es változatot még nem próbáltuk ki valódi gépen.

## Automatikus frissítés

Indításkor a program a háttérben megnézi, hogy van-e újabb kiadás a GitHub Releases oldalon. Ha van, megkérdezi, hogy telepítse-e:

- **Igen:** letölti az új verziót.
  - Az MSI-vel telepített program az új kiadás MSI-jét tölti le. Ezután azonnal újraindítható: a program bezárul, a telepítő lefut, és a program újraindul. Ha most nem indítod újra, a frissítés a program bezárásakor települ.
  - A hordozható példány a zipet tölti le, kicsomagolja a program mappájába, majd felajánlja az újraindítást. A futó exe-t és a betöltött DLL-eket nem lehet felülírni, ezért ezeket a frissítő átnevezi (`*.updold`), és a következő induláskor törli. Ha a program mappája írásvédett (például a `C:\Program Files` alatt van), a frissítés hibaüzenettel leáll.
- **Nem:** a következő indításkor újra rákérdez.
- **Kihagyás:** erre a verzióra többet nem figyelmeztet.

A frissítő a `settings\` mappához nem nyúl.

## Változások a Double Commanderhez képest

### Megjelenés

- **Programnév:** a felületen „Commander” szerepel, az exe neve `Commander.exe`. A program ikonja egy TC-szerű kék hajlékonylemez.
- **Világos téma** minden esetben, indítóképernyő nélkül.
- **TC-s ikontéma** (`tcstyle`) a felső eszköztárhoz; az összes többi ikont a DC alaptémájától örökli. A felső eszköztáron a TC alapértelmezett gombjai vannak, a középső eszköztár be van kapcsolva.
- **Eszköztárak és keretek:** fehér hátterű eszköztárak elválasztó vonalakkal, a menüsor jobb szélén a „Súgó”, a „Lapok” és a „Kedvencek” menü helyett „Start” menü. A fülsor csak akkor látszik, ha egynél több fül van nyitva; amíg rejtve van, a panel körül nincs keret.
- **Meghajtósor és útvonal:** a meghajtóválasztó TC-szerű lenyíló mező, mellette a szabad hely, előtte a `[kötetcímke]` balra igazítva. A meghajtóbetű kisbetűs (`c:\`), az útvonal után `*.*` maszk áll, az útvonal-fejléc TC-s színeket kap.
- **Fájllista:** 9 pontos normál betű, 16 px-es ikonok, világoskék kurzor fekete betűvel és kurzorkerettel. A Név oszlop kitölti a panelt, a mappák elöl állnak, és a rejtett és rendszerfájlok is látszanak.
- **Formátumok:** a méretek bájtban vagy k-ban jelennek meg, a dátum `yyyy.mm.dd hh:nn` formátumú, az attribútumok `rahs` formában (`-a--`) látszanak, a mappák mérete helyén `<DIR>` áll.
- **Funkcióbillentyű-sor:** `F3 Nézőke` formájú feliratok, egyforma széles gombok, F9 gomb nélkül.
- **Magyar fordítás:** TC-s szóhasználat (Fájl, Kijelölés, Nézet, Nézőke stb.).

### Kezelés

- **Gépelés:** a sima gépelés a parancssorba kerül, az Alt+betű gyorskeresést indít, mint a TC-ben. A Ctrl+E az előző parancsot hívja elő.
- **Alt+F4:** kilépés a programból.
- **Fájlműveleti hibák:** alapértelmezés szerint a program átugorja a hibás fájlt, és a művelet folytatódik.
- **Mappák rögzítése a meghajtósoron:** ha egy mappát a fájlpanelről vagy más programból a meghajtósorra húzol, a meghajtók után gombot kap (a két panel meghajtósora közös). A gombok húzással áthelyezhetők; ha egyet lehúzol a meghajtósorról, eltűnik. Az FTP-kapcsolatok (Hálózat → FTP) és a kapcsolatokon belüli mappák is rögzíthetők így; a gombra kattintva a program megnyitja a kapcsolatot.
- **Hálózati útvonalak:** egy elérhetetlen gép vagy megosztás nem fagyasztja le a felületet. A lista a háttérben töltődik be, előtte egy kb. 2 másodperces próba ellenőrzi, hogy a gép elérhető-e. A hiba üzenetablak helyett a panel közepén jelenik meg, és betöltés közben is vissza lehet lépni (Backspace, `..`, Esc). A megosztás gyökeréről a `..` a gép megosztáslistájára lép.
- **Nincs fekete villanás**, amikor a program minimalizált állapotból visszaáll.
- **FTP-kapcsolatok átvétele a Total Commanderből:** a Hálózat → FTP alatt az `<Importálás Total Commanderből>` elem beolvassa a TC `wcx_ftp.ini` fájlját, és átveszi a kapcsolatokat a jelszavakkal együtt. A TC mesterjelszavával védett jelszavakat nem lehet átvenni, ezeket a program csatlakozáskor kéri.

## Fordítás

Szükséges hozzá: [Lazarus](https://www.lazarus-ide.org/) 4.8 (FPC 3.2.2, x86_64-win64) a `C:\lazarus` mappában.

```powershell
devtools\fetch-deps.bat                     # külső DLL-ek (7z, unrar, lua stb.) a run\ mappába
devtools\build-dc.ps1 -Mode all -Clean      # komponensek, pluginek és a főprogram; a run\ mappa összeállítása
run\Commander.exe
```

Mindig a `-Clean` kapcsolóval fordíts, mert részleges újrafordításnál az FPC 3.2.2 belső hibával leállhat.

### Kiadás

Az MSI-hez [WiX Toolset](https://wixtoolset.org/) 5 kell:

```powershell
dotnet tool install --global wix --version 5.0.2
wix extension add -g WixToolset.UI.wixext/5.0.2
```

1. Írd át a verziószámot (`CommanderVersion`) a `src\platform\win\uselfupdate.pas` fájlban, és írd meg a `CHANGELOG.md` új `## [<verzió>] – <dátum>` szakaszát.
2. Commitold, és töltsd fel (`git push origin master`).
3. Indítsd el a **Commander release** GitHub Actions workflow-t (`gh workflow run commander-release.yml --repo Tenax84/commander`, vagy a GitHubon az Actions fülön). Ez lefordítja a programot Windowsra és macOS-re, elkészíti a `Commander-<verzió>-win64.msi` telepítőt, a `Commander-<verzió>-win64.zip` hordozható változatot és a `Commander-<verzió>-macos-arm64.dmg` / `-macos-x86_64.dmg` lemezképet, majd a feltöltött commitra létrehozza a `v<verzió>` GitHub-kiadást. A kiadási megjegyzés a `CHANGELOG.md` azonos verziójú szakasza. A programba épített frissítő Windowson az MSI-t vagy a zipet, macOS-en a gép architektúrájának megfelelő DMG-t tölti le.

Helyben a `devtools\make-release.ps1` ugyanígy elkészíti a Windowsos fájlokat a `dist\` mappába (próbatelepítéshez); `-Publish` kapcsolóval a kiadást is létrehozza, de csak a Windowsos fájlokkal. A macOS-es csomagot a `devtools/macos/build-mac.sh` készíti.

Claude Code-ban a `/release` skill (`.claude/skills/release/SKILL.md`) a teljes folyamatot elvégzi, a changelog és a README frissítésével együtt.

A helyi `v*` tagek a Double Commanderéi (az `upstream`-ből jönnek), ezért a Commander kiadási tagjei csak a GitHubon (`origin`) jönnek létre; a szkript nem tolja fel őket.

A frissítő helyi szerverrel is tesztelhető: a `COMMANDER_UPDATE_URL` környezeti változóban megadott címről olvassa a kiadás adatait (a GitHub API `releases/latest` válaszának formátumában).

## Licenc

GNU General Public License 2 (lásd [LICENSE.md](LICENSE.md)). A Double Commander szerzői és közreműködői a program Névjegy ablakában vannak felsorolva.
