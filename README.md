# Wine 11.18 suite

Thirteen previously separate repositories — each one a Windows application brought up on a
locally built, patched **Wine 11.18** — merged into a single tree. Per-project commit history
is preserved: every project keeps its original commits under its own subdirectory.

Everything here targets **Wine 11.18**.

What this does: every folder contains patches required to make that specific app fun on linux. see individual folders for details. 

## Projects

| directory | application |
| --- | --- |
| `acad-wine-main/` | AutoCAD (Wine 11.18 + 14 patches) |
| `capcut-wine/` | CapCut PC 9.5.0.4050 |
| `csp-wine/` | CLIP STUDIO PAINT 5.1.4 |
| `eos-wine/` | ETC Eos Family v3.3.10.28 |
| `hog-wine/` | Hog PC 5.2.1.31 |
| `mastercam-wine/` | Mastercam 2027 |
| `npp-darkmode-wine/` | Notepad++ dark mode (Wine bug 57555) |
| `powerbi/` | Power BI Desktop |
| `resolume-wine/` | Resolume Arena 7 |
| `revit-wine-main/` | Revit 2027 |
| `sda-wine/` | Steinberg Download Assistant 1.40.1 |
| `solidedge-wine-main/` | Solid Edge 2026 |
| `tableau-wine/` | Tableau Desktop 2026.2.3 |

## Not included: the vendored Wine source trees

The original repositories each carried a full, differently patched Wine 11.18 checkout
(`wine-11.18/`, `wine-src/`, `wine/`, `sources/` — together roughly 5.2 GB of near-duplicate
trees). Those are **not** part of this repository. Each project's `patches/`, `scripts/`,
`docs/` and `evidence/` are retained, so any of those trees can be reproduced from a pristine
Wine 11.18 source tree plus the project's own patch series.

The original repositories, including their complete Wine trees, are untouched: on disk under
`~/projects/`, and on GitHub under `ejrydhfs/`.
