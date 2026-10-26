# Változásnapló

A Commander kiadásainak változásai. A verziószám a Commanderé, nem a Double Commanderé; a kiadások a [GitHub Releases](https://github.com/Tenax84/commander/releases) oldalon érhetők el.

## [1.3.0] – 2026-10-26

### Új

- **macOS-es változat:** Apple Siliconra (`Commander-1.3.0-macos-arm64.dmg`) és Intelre (`Commander-1.3.0-macos-x86_64.dmg`) is van lemezkép. Saját ikonnal, automatikus frissítéssel, a hálózati kötetek (SMB, AFP, NFS, WebDAV) háttérbeli betöltésével és a fájl parancssorba illesztésével. Valódi Macen még nem próbáltuk ki.
- **Fájl beillesztése a parancssorba:** ha a vágólapon fájl van (pl. az Intézőben másoltad), a parancssorba beillesztve (Ctrl+V, Shift+Insert, helyi menü) a fájl teljes útvonala kerül. Több fájlnál szóközzel elválasztva, a szóközt tartalmazó útvonalak idézőjelben.

### Változott

- **Parancssori `cd`:** a relatív útvonalat (`alma\korte`, `..\x`, `.\x`) az aktív panel mappájához képest értelmezi, a `\mappa` alakot az aktív panel meghajtóján. Ha a célpont fájl, a program a mappájába lép, és kijelöli a fájlt.

## [1.2.0] – 2026-10-14

### Új

- **FTP-kapcsolatok a meghajtósoron:** az FTP plugin gyökeréből (Hálózat → FTP) egy kapcsolatot a meghajtósorra húzva gombot kap, ugyanúgy, mint a rögzített mappák. A gombra kattintva a program megnyitja a kapcsolatot (szükség esetén bekéri a jelszót). Egy kapcsolaton belüli mappa is rögzíthető, ilyenkor a gomb egyenesen oda lép. A gombok húzással áthelyezhetők, és a sorról lehúzva eltűnnek.

### Változott

- Ha egy FTP-n belüli mappát egy meghajtógombra ejtesz, a program a meghajtósorra rögzíti, és nem másolja a meghajtóra (ahogy a helyi mappáknál is).

## [1.1.0] – 2026-10-14

### Új

- **MSI-telepítő** (`Commander-<verzió>-win64.msi`): a programot a felhasználó saját mappájába (`%LOCALAPPDATA%\Programs\Commander`) telepíti, rendszergazdai jog nélkül, Start menü- és asztali parancsikonnal. A hordozható zip továbbra is elérhető.
- **FTP-kapcsolatok átvétele a Total Commanderből:** az FTP plugin gyökerében (Hálózat → FTP) az `<Importálás Total Commanderből>` elem beolvassa a TC `wcx_ftp.ini` fájlját, és átveszi a kapcsolatokat: név, gép és port, kezdőmappa, felhasználónév, jelszó, passzív mód, névtelen belépés, `ftps://`. A TC mesterjelszavával védett jelszavakat nem tudja átvenni, ezeket csatlakozáskor kéri. A már létező nevű kapcsolatokat kihagyja.

### Változott

- **Automatikus frissítés MSI-vel:** az MSI-vel telepített program a frissítést az új kiadás MSI-jével telepíti. Letöltés után azonnal újraindítható, vagy a program bezárásakor települ. A hordozható példány továbbra is a zipből frissül.
- Az FTP plugin gyökerében az „Add connection” és a „Quick connection” elem magyarul jelenik meg („Új kapcsolat”, „Gyors kapcsolat”).

### Javítva

- Ha egy lassan betöltődő listát (Hálózat, Ez a gép, Lomtár, WSL) a betöltés közben elhagytál, egy „aborting file source operation” hibaablak jelent meg.

## [1.0.0] – 2026-10-13

A Commander első kiadása: a Double Commander 1.3.0 alpha (fejlesztői ág) Windowsos forkja, Total Commander-szerű kinézettel és kezeléssel. A külső DLL-ek (7-Zip, UnRAR, Lua stb.) a hivatalos Double Commander 1.2.9 csomagból származnak.

### Megjelenés

- A felületen „Commander” szerepel, az exe neve `Commander.exe`, a program ikonja TC-szerű kék hajlékonylemez.
- Világos téma minden esetben, indítóképernyő nélkül.
- TC-s ikontéma (`tcstyle`) és a TC alapértelmezett gombjai a felső eszköztáron; a középső eszköztár be van kapcsolva.
- Fehér hátterű eszköztárak elválasztó vonalakkal; „Start” menü, a „Súgó” a menüsor jobb szélén. A fülsor csak egynél több fülnél látszik.
- TC-szerű meghajtóválasztó, `[kötetcímke]` és szabad hely, kisbetűs meghajtóbetű, `*.*` maszk az útvonal után, TC-színű útvonal-fejléc.
- Fájllista: 9 pontos betű, 16 px-es ikonok, világoskék kurzor fekete betűvel, a Név oszlop kitölti a panelt, a rejtett és rendszerfájlok is látszanak.
- Formátumok: méret bájtban vagy k-ban, `yyyy.mm.dd hh:nn` dátum, `rahs` attribútumok, `<DIR>` a mappáknál.
- Funkcióbillentyű-sor `F3 Nézőke` formájú feliratokkal, F9 gomb nélkül.
- Magyar fordítás TC-s szóhasználattal (Fájl, Kijelölés, Nézet, Nézőke stb.).

### Kezelés

- A gépelés a parancssorba kerül, az Alt+betű gyorskeresést indít, a Ctrl+E az előző parancsot hívja elő, az Alt+F4 kilép.
- Fájlműveleti hibánál a program alapértelmezés szerint átugorja a hibás fájlt.
- Mappák rögzítése a meghajtósoron húzással; a gombok áthelyezhetők és lehúzással eltávolíthatók.
- Elérhetetlen hálózati gép vagy megosztás nem fagyasztja le a felületet: a lista a háttérben töltődik be, a hiba a panel közepén jelenik meg, betöltés közben is vissza lehet lépni.
- Nincs fekete villanás minimalizált állapotból visszaállításkor.
- Automatikus frissítés: induláskor a program megnézi, van-e újabb kiadás a GitHubon, és kérésre telepíti.

[1.3.0]: https://github.com/Tenax84/commander/releases/tag/v1.3.0
[1.2.0]: https://github.com/Tenax84/commander/releases/tag/v1.2.0
[1.1.0]: https://github.com/Tenax84/commander/releases/tag/v1.1.0
[1.0.0]: https://github.com/Tenax84/commander/releases/tag/v1.0.0
