# PixelStudio Godot character bridge

## Native 128px sprite replacements

The new base cop comes from `export/pixelstudio/base-cop/BASE_COP_frames.zip`.
Reinstall with `python tools/pixelstudio/import_base_cop.py` (or pass the ZIP path).
Its twenty 128x96 frames play at 24 fps: 1–3 start running, 4–17 loop,
18–20 stop running, installed as `run_start`, `run`, and `run_stop`.
The first standing frame supplies idle until a dedicated idle arrives.
The separate walking export is preserved in `export/pixelstudio/base-cop-walking/`.
Install it with `python tools/pixelstudio/import_base_cop.py PATH_TO_BASE_COP_WALKING_frames.zip`:
frames 1–3 are `walk_start`, 4–31 are the 28-frame `walk` loop, and 32–34 are `walk_stop`.
The full 33-frame strike is in `export/pixelstudio/base-cop-strike/`; install with
`python tools/pixelstudio/import_base_cop.py PATH_TO_BASE_COP_STRIKE_frames.zip`.
It replaces `attack`, plays once at 24 fps, and contacts on frames 13 and 25 (zero-based
`hit_frames: [12, 24]` in the clip metadata). Enemy attack timing and drawing share that
1.375 second clock, including recovery. Base attack damage is divided between the two
contacts, each checked for range. The supplied artwork, including its edge clipping, is retained.
Normal movement uses walking; rendering can select the retained running sequence with
`enemy.gfx.move_gait = "run"`. Both sequences remain at 24 fps regardless of movement speed.
The atlas keeps the native pixels and each clip's foot origin, allowing 128px replacements
alongside the older 66px placeholder clips. No half scaling is applied. Gameplay movement
and hitboxes are unchanged. This ZIP has no authored maps or sockets: it uses neutral normals
and approximate effect anchors until those are supplied. Reactions remain placeholders.

Double-click [Open PixelStudio.bat](../../Open%20PixelStudio.bat) in the repository root.
The helper serves the existing PixelStudio editor on loopback and opens the basic cop walk.
See [the editor workflow](EDITOR-README.md) for posing, supported clips, maps and limitations.

For the scientist, use [Open Doctor Melee.bat](../../Open%20Doctor%20Melee.bat). The same Video to Frames
editor opens an editable doctor with separate upper arms, forearms, hands and weapons. Its character
picker offers primary sword, primary knife, dual swords and dual knives. The body remains paintable;
each weapon is parented to the corresponding hand, and its rotation pivot is the fist grip.
Projects and instructions are in `export/pixelstudio/doctor-melee/`. The doctor helper uses port 8767,
so an existing cop editing session on 8766 can stay open.

**Every character in `godot/enemies/enemy_painter.gd`** opens from the *Open Godot character*
picker: all 25 kinds (police, civilians, heroes, dogs, drones, vehicles) and every state they
bake (walk, idle, attack, panic, hurt, stunned, frozen, death, plus hero moves). The list is read
from the painter itself, so new kinds/states appear automatically. Open one directly with
`http://127.0.0.1:8766/?godot=hero_vex&animation=attack`.

Humanoid clips open as linked puppets: up to 20 full-canvas layers (cape, back hair, arms,
legs, torso, head, hair, face, hat, held prop) with joint pivots and parent links, retaining
occluded artwork. Each puppet is checked against the original painter; if the parts can't
reproduce the game pixel-for-pixel (dogs, drones, machines, death tumbles, frozen poses,
the riot cop's translucent shield, Surge's blink streak) the clip opens instead as one flat,
fully paintable layer. The normal game scripts remain untouched.

### Putting an edit into the game

Save the project in PixelStudio, then:

```powershell
python tools/pixelstudio/match_cop_normals.py PATH_TO_SAVED.pixelstudio
```

It works for any character (the name is historical); the character and animation are read from
the project (override with `--character` / `--animation`). It writes
`godot/art/enemies/<kind>/<kind>_<state>.png`, `_n.png` (normal map) and `.json` (anchors, fps),
and lists the clip in `godot/art/enemies/edited.json`, which `enemies/edited_art.gd` reads when
baking sprite sheets. Reopening that character in the picker then loads your edited project.
Moved parts carry their original relief; repainted pixels keep the relief at that spot; newly
painted pixels borrow the nearest original relief in the same layer. Keep frame count, canvas
size and hold=1 per frame, and paint on the character layers (not base/overlay).
To revert a clip, delete its files and its entry in `edited.json`.

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

Every character clip is supported. Heights are never guessed from color: new pixels take the
nearest original relief in their layer (see above). The delivered normal maps are matched to
the saved poses. After further puppet transforms, rerun the command to match them again.
The original artist file is preserved alongside the corrected project. The bridge follows
the game's `source_project` metadata to reopen the current edited layered source instead of
returning to the original procedural pose. Regenerating relief still uses the procedural source.

## Scientist body skin

`python tools/pixelstudio/import_scientist.py` turns `export/pixelstudio/scientist/scientist.pixelstudio` into
`godot/character/art/scientist/` (body sheet, height map, anchors). The game swaps the villain's body pixels for
these while the gun arms, effects and x-ray still come from the renderer. After re-running, import the PNGs
(`Godot --headless --path godot --import`). Set `body_skin = ""` in `art_renderer.gd` to return to the procedural villain.
