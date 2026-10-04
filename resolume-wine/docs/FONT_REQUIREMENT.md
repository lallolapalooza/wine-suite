# Fonts — the fix that unblocks Resolume Arena 7 on Wine

## Symptom
Under Wine, Arena starts, initialises its OpenGL renderer, and then stops, leaving a **black
735×245 JUCE window titled `Resolume`** (plus four 12 px drop-shadow border windows) and a message
loop that idles forever. Its own log ends at:

```
INFO: Enumerate fonts
INFO: Find default fonts
INFO: Default fonts not available
```

On Windows, the same phase continues:

```
INFO: Find default fonts
INFO: Create Application Object      <-- Wine never reaches this
INFO: Setting up default composition settings.
```

## Root cause
Arena picks a default UI font by asking for the **font families** `("Arial", "Regular")` and
`("Verdana", "Regular")`. The table it walks sits at `Arena.exe` VA `0x142f4fa00` and is consumed by
the helper at `0x140fd87f0`:

```
entry[0] 0x142ed4258 len=5 -> 'Arial'
entry[1] 0x142ebf770 len=7 -> 'Regular'
entry[2] 0x142ebf8b8 len=7 -> 'Verdana'
entry[3] 0x142ebf770 len=7 -> 'Regular'
```

`EnumFontFamiliesEx` therefore has to report those family names. Wine **substitutes** them when a
font is *created*, but does not report them when fonts are *enumerated* unless a font with that family
name is actually installed in the prefix.

Measured with `tools/winapi/fontprobe.c` (before the fix):

```
CreateFont("Arial")   -> GetTextFace "Liberation Sans"     <- substitution works...
CreateFont("Verdana") -> GetTextFace "Liberation Sans"
total families=2498 interesting=23                         <- ...but no "Arial"/"Verdana" family
  FOUND family "Liberation Sans" / "DejaVu Sans" / "Tahoma" / "MS Sans Serif"
```

`CreateFont` succeeds (so a naive implementation would not notice), but JUCE's family enumeration
does not see `Arial` or `Verdana`, the lookup returns null, and Arena logs
`Default fonts not available` and gives up.

This is not a Wine defect in the "wrong value" sense — on Windows these fonts are part of the OS, so
the app can rely on them; a Wine prefix that never had them installed simply does not have them. The
fix is therefore to install them, exactly as `winetricks corefonts` would.

## Fix
Install a set of Windows core fonts into the prefix:

```sh
source env.sh
tools/install_corefonts.sh                 # copies state/tmp/fonts/*.ttf (or vmshare/corefonts.zip)
tools/install_corefonts.sh --check         # re-runs fontprobe and reports
```

`tools/mkprefix.sh` calls it automatically after `wineboot`, so a freshly created prefix gets it too.

Font source (not redistributed here): the TTFs were copied out of the **same Windows guest this
project uses as its reference** — `C:\Windows\Fonts` → `corefonts.zip` → the HTTP channel — covering
Arial, Arial Bold/Italic/Bold-Italic, Verdana (+ Bold/Italic/Bold-Italic), Times New Roman,
Courier New, Georgia, Trebuchet MS, Impact, Comic Sans MS, Segoe UI (+ Bold), Calibri, Consolas and
Microsoft Sans Serif (20 files, 12.8 MB). Any licensed copies work; `winetricks corefonts` is an
alternative.

They land in `<prefix>/drive_c/windows/Fonts/`, which Wine's font enumeration scans.

## Verification (after the fix)
```
CreateFont("Arial")   -> GetTextFace "Arial"
CreateFont("Verdana") -> GetTextFace "Verdana"
FOUND family "Arial" ...
FOUND family "Verdana" ...
```

## Notes on reading Arena's progress
Arena's log file is **buffered**: it can stay at three lines for minutes and then flush in a burst,
and unflushed lines are lost when the process is killed. Do not use the log tail as the app's true
position — the X window list is the reliable signal:

| window | meaning |
|---|---|
| `JUCEWindow` (113×2, hidden) | JUCE's message window — very early |
| `Resolume` 735×245 + four 12 px borders | the blocking dialog (shown when the app gives up) |
| `Resapi offscreen window` (111×64, ×3) | Resolume's renderer is up — well past font lookup |
| `ResapiHiddenMessageWindowName<pid>.<tid>` | the ResAPI event window |
| `Resolume Arena - Example (1280 x 720, 8bpc)` ~1296×768 | **the real UI** (what Windows shows) |
