# PixelStudio Godot character bridge

Double-click [Open PixelStudio.bat](../../Open%20PixelStudio.bat) in the repository root.
The helper serves the existing PixelStudio editor on loopback and opens the basic cop walk.
See [the editor workflow](EDITOR-README.md) for posing, supported clips, maps and limitations.

The shipped adapter supports the native `godot/enemies/enemy_painter.gd` basic cop:
walk (8 frames), idle (4), and attack (3). It captures drawing stages into 18 full-canvas
layers, retaining occluded artwork, joint pivots, parent links, and baton grip directions.
The normal game scripts remain untouched. Each export compares the assembled frames with
the original painter and refuses an export if even one RGBA pixel differs.

`bridge.py` copies the required drawing dependencies into a temporary Godot project.
`instrument()` adds named capture boundaries to that copy. `capture_canvas.gd` records
per-part pixels while preserving the combined original canvas, assigning outer outline
pixels to their originating part. `export_character.gd` writes PixelStudio v2 projects.
The editor imports them through its normal project loader. The small editor extension
adds the dialog and keeps weapon anchors attached to transformed baton layers.

```powershell
python tools/pixelstudio/bridge.py --open
python tools/pixelstudio/bridge.py --export walk
python -m unittest discover -s tools/pixelstudio -p test_bridge.py -v
```

`--godot PATH`, `--editor FOLDER`, `--project FOLDER`, and `--port PORT` override defaults.
Exports are written under `export/pixelstudio/`. The HTTP service binds only to loopback,
checks request host/origin and uses a session token for export requests. It serves only
the editor and its extension; project files are not exposed as a general file server.

`prepare_editor.py` stages the small changes to the sibling editor: source metadata
round-tripping, validated attachment angles on layer poses, and the extension script.
The installer checks hashes of the source files and keeps backups before copying.
Additional character systems require an adapter; arbitrary GDScript is not interpreted
by the browser. Saving back into gameplay is outside this import workflow.

## Match physical normals to an edited cop

`match_cop_normals.py` uses NumPy and Pillow. It re-exports the original per-part physical
height fields, verifies that the source drawings still match, applies the saved PixelStudio
poses with the editor's nearest-neighbor rasterization, and derives OpenGL normals with the
game's clamped Sobel filter. It writes a new layered project with per-frame normal overrides,
leaves the supplied file untouched, and writes the selected game clip to `godot/art/enemies/cop/`.

```powershell
python tools/pixelstudio/match_cop_normals.py PATH_TO_PROJECT --animation walk
```

Supported clips are `idle`, `walk`, and `attack`. Repainted source pixels require new authored
relief; the tool refuses to guess heights from color. The delivered normal maps are matched to
the saved poses. After further puppet transforms, rerun the command to match them again.
The original artist file is preserved alongside the corrected project. The bridge follows
the game's `source_project` metadata to reopen the current edited layered source instead of
returning to the original procedural pose. Regenerating relief still uses the procedural source.
