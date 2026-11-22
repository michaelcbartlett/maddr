Open E:\repos\video to frames\index.html in your browser.
Click Load project and choose cop-walk.pixelstudio from this folder.
Press Play to preview the eight-frame walk. Select Cop artwork to edit pixels,
or Overlay to draw additions. Save project downloads your edited .pixelstudio.

This is the basic cop's current right-facing walk, exported from the Godot
painter. Frames are 66 x 66 including the game's one-pixel outline padding.
Playback is 7.2 FPS, matching enemy.walk += dt * 8 and int(enemy.walk * 0.9).
Each frame includes the original normal map. Select Normal map to edit it;
Reset map on Normal removes that override if you want regenerated normals.
The artwork is editable frame by frame; body parts are not separate layers.
Editing this project does not automatically change the game's procedural art.

Alternatives: Open the eight cop_walk_01.png through cop_walk_08.png together,
or Import sprite sheet with cop-walk-sheet.png, 66 x 66 cells, 8 frames.
The *_n.png images are matching normal maps, not animation frames.

Regenerate from the repository root with:
Godot --headless --path godot --script ../export/cop-walk/export_cop_walk.gd
