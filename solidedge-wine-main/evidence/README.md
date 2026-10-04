# Evidence collected from the runs

| file | what it shows |
|---|---|
| `se-3d-partviewer.png` | Solid Edge 2026's 3D viewport under Wine: `Solid Edge 2D Drafting 2026 - PartViewer - [t.par[Read-Only]]`, shaded model, PathFinder, PMI callouts |
| `se-2d-draft-document.png` | a Draft document open: ribbon `File/Home/Tables/Inspect/Tools/View`, drawing sheet with title block, status bar |
| `se-webview2-start-page.png` | the WebView2 start page rendering (intro banner, tutorial cards, Create New tiles, Quick UI Tour) |
| `se-license-activated.png` | the licensing tool's "Product installation completed successfully." after the activation-code flow |
| `se-titlebar-x-enabled.png` | 5x zoom of the caption: the X is enabled and closes the application (FINDINGS M14) |
| `test-dwmapi.log`, `test-uiautomationcore.log` | the two module test runs: 54 tests / 0 failures and 8187 tests / 0 failures |

Longer evidence: `logs/runs/` (per-run stderr + sampled screenshots), `logs/drive/` (the
timestamped interaction logs), `logs/tests/` (suite output), `logs/prefix/` (installer logs),
`logs/dwmprobe_windows.txt` vs `logs/dwmprobe_wine.txt` (the differential probe pair).
