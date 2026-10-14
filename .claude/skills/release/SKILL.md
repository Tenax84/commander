---
name: release
description: Új Commander-kiadás készítése és közzététele a GitHubon (Tenax84/commander) – verzióemelés, CHANGELOG.md-bejegyzés, README-frissítés, fordítás, MSI-telepítő és hordozható zip, commit, push, GitHub release. Használd, ha a felhasználó új kiadást, release-t, verziót, telepítőt vagy MSI-t kér, vagy azt, hogy a változások jussanak el az önfrissítéshez.
---

# Commander-kiadás

A kiadás a programba épített önfrissítő forrása (`src/platform/win/uselfupdate.pas`): induláskor a program a `Tenax84/commander` **legutóbbi, nem draft és nem prerelease** GitHub-kiadását kéri le. Ha a tag (`v<verzió>`) újabb a saját `CommanderVersion`-jénél, felajánlja a frissítést. Az MSI-vel telepített példány a `.msi` assetet, a hordozható a `.zip`-et tölti le. **Mindkét asset kell**, a nevük `Commander-<verzió>-win64.msi` és `Commander-<verzió>-win64.zip` (a frissítő a kiterjesztés és a `win64` alapján választ). Egy hibás kiadás minden felhasználóhoz eljut, ezért a lépéseket ne ugord át.

A felhasználóval magyarul kommunikálj, a commitüzenet is magyar.

## 1. Állapot felmérése

```bash
git status --short
gh release list --repo Tenax84/commander --limit 5
grep -n "CommanderVersion = " src/platform/win/uselfupdate.pas
```

- **Mindig `--repo Tenax84/commander`-rel** hívd a `gh`-t; enélkül a `gh` az upstream Double Commander repóját is választhatja.
- A **helyi `v*` tagek a Double Commanderéi** (az `upstream`-ből jönnek; pl. a helyi `v1.0.0` nem a Commander 1.0.0-ja). Az előző Commander-kiadás commitját a GitHubról kérd le:
  ```bash
  PREV=$(gh api repos/Tenax84/commander/releases/latest --jq .tag_name)
  PREV_SHA=$(gh api repos/Tenax84/commander/git/ref/tags/$PREV --jq .object.sha)
  git log --oneline $PREV_SHA..HEAD
  ```
  Ha a tag annotált (`object.type` = `tag`), a commitot a `gh api repos/Tenax84/commander/git/tags/<sha> --jq .object.sha` adja.
- A commitolatlan módosítások is a kiadás részei, ha a felhasználó nem mondja másképp. Ezeket nézd át (`git diff`), és **tematikusan, külön commitokba** tedd őket, mielőtt a kiadási commitot elkészíted.

## 2. Verziószám

Szemantikus verzió: új funkció → minor (`1.1.0` → `1.2.0`), csak javítás → patch (`1.2.0` → `1.2.1`), nagy, nem kompatibilis változás → major. Ha nem egyértelmű, javasolj egyet, és kérdezz rá.

Írd át a `CommanderVersion` konstanst a `src/platform/win/uselfupdate.pas`-ban (a fájl CRLF sorvégű, ezt őrizd meg).

## 3. CHANGELOG.md

A `CHANGELOG.md` tetejére, az előző verzió fölé kerül az új szakasz, a meglévő formában:

```markdown
## [1.2.0] – 2026-11-02

### Új
- ...
### Változott
- ...
### Javítva
- ...
```

- Csak a nem üres alszakaszokat vedd fel. A fejlécformátum (`## [<verzió>] – <dátum>`) kötött: a `make-release.ps1` ebből veszi ki a kiadási megjegyzést.
- A fájl végén lévő linklistához add hozzá: `[1.2.0]: https://github.com/Tenax84/commander/releases/tag/v1.2.0`.
- A bejegyzéseket a felhasználó szemszögéből írd (mit tapasztal, mi változott), ne commitüzenetekből másold. Forrás: `git log $PREV_SHA..HEAD`, a diffek és a `CLAUDE.md` „Saját módosítások” listája. Belső átalakítást, build- és eszközváltozást csak akkor vegyél fel, ha a felhasználó is észreveszi.
- Ha egy korábbi kiadásnak nincs szakasza, pótold a kiadás leírásából (`gh release view <tag> --repo Tenax84/commander`) és a git-előzményekből.

## 4. README.md

Nézd át, hogy az új funkciók megjelennek-e a „Változások a Double Commanderhez képest” részben, és hogy a letöltési, frissítési és kiadási leírás még pontos-e. Ha a változás érinti, a `CLAUDE.md` „Saját módosítások” listáját is frissítsd.

## 5. Commit és push

```bash
git add -A   # előtte ellenőrizd, hogy nincs-e benne nem odavaló fájl
git commit -m "Commander <verzió>: ..."   # a végén a Co-Authored-By sor
git push origin master
```

A `make-release.ps1 -Publish` leáll, ha commitolatlan módosítás van, vagy ha a HEAD nincs feltöltve az `origin/master`-re.

## 6. Fordítás, csomagolás, közzététel

Előfeltétel: Lazarus 4.8 a `C:\lazarus`-ban, és WiX Toolset 5 a UI-kiterjesztéssel (`wix --version`; ha hiányzik: `dotnet tool install --global wix --version 5.0.2`, `wix extension add -g WixToolset.UI.wixext/5.0.2`).

Először közzététel nélkül:

```powershell
devtools\make-release.ps1
```

Ez kb. 2 perc: `-Mode all -Clean` fordítás a `dist\Commander` mappába, külső DLL-ek letöltése, `dist\Commander-<verzió>-win64.zip`, `dist\Commander-<verzió>-win64.msi` (forrás: `devtools\installer\Commander.wxs`), és a `dist\release-notes-<verzió>.md`. Hosszú futás esetén az AI Center háttér-helperével indítsd.

Ellenőrzés a közzététel előtt:
- mindkét fájl létrejött, a méretük kb. 11 MB (msi) és 15 MB (zip);
- a `dist\release-notes-<verzió>.md` a CHANGELOG új szakaszát tartalmazza;
- ha a telepítő vagy a frissítő változott: telepítsd csendesen (`msiexec /i <msi> /qn`), indítsd el a `%LOCALAPPDATA%\Programs\Commander\Commander.exe`-t, majd távolítsd el (`msiexec /x <msi> /qn`). Utána töröld a próbatelepítés `settings\` maradványát. A frissítő a `COMMANDER_UPDATE_URL` környezeti változóval helyi szerverről is tesztelhető (lásd README). A párbeszédablak gombjait `WM_COMMAND`/`BN_CLICKED` üzenettel nyomd meg a szülőablaknak küldve, ne billentyűleütéssel: a felhasználó ugyanazon a gépen dolgozik.

Majd a közzététel:

```powershell
devtools\make-release.ps1 -Publish -NoBuild
```

Ez a `v<verzió>` taget a GitHubon hozza létre a HEAD commitra (`gh release create --target`), feltölti az MSI-t és a zipet, a megjegyzés a `release-notes` fájl lesz. **Helyi taget ne hozz létre, és ne told fel** (`git push --tags` tilos): ütközne a Double Commander tagjeivel.

## 7. Ellenőrzés

```bash
gh release view v<verzió> --repo Tenax84/commander --json tagName,isDraft,isPrerelease,assets --jq '{tagName,isDraft,isPrerelease,assets:[.assets[].name]}'
curl -s https://api.github.com/repos/Tenax84/commander/releases/latest | grep -E '"tag_name"|browser_download_url'
```

A `releases/latest` az új taget adja, mindkét asset szerepel, és a kiadás nem draft és nem prerelease. Ha a repó privát lenne, az API 404-et ad, és a frissítés csendben elmarad; a repónak publikusnak kell maradnia.

A végén írd meg a felhasználónak a kiadás linkjét, a verziót, a changelog lényegét, és hogy mit teszteltél.
