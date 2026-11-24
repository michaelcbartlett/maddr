# Enemy, NPC and boss art

For roster roles, progression and behavior references during the rebuild, see the
[Brotato enemy reference notes](../REFERENCE_NOTES.md#enemy-roster-reference-2026-11-23).

The basic cop's **idle**, **walk**, and **baton attack** use the edited PixelStudio clips in
`art/enemies/cop/`, through `cop_edited_art.gd`. Their normal maps are rebuilt from each original
body part's physical height profile after applying the saved artist poses; their joint anchors
follow the edited parts. The foot origin is unchanged. The cop's other states and the other
enemies keep their procedural artwork. The sheet cache includes hashes of the edited artwork,
normals and clip metadata. Restart a running game to load updated clips.

Editable projects with the matched normals are in `export/pixelstudio/cop-{idle,walk,attack}-improved/`
at the repository root. The Godot importer opens these current edited sources. Preserve the
layered projects when replacing the textures so the puppet remains available for further edits.

All enemies are painted procedurally, the same way as the scientist in `character/`. They use one pixel per world pixel, so they match his size and density. The painter reuses the character's `pixel_canvas.gd`, `pixel_pen.gd` and `height_profiles.gd` without changing them. That gives the enemies the same hue-shifted shading (cool shadows, warm highlights), 1 px selective outlines, height maps and OpenGL normal maps, so they react to the game's 2D lights.

Moving cars and tanks use `vehicle_view.gd` during combat and in the gallery. It projects a rotating ground
footprint and fixed upward height separately, matching the map props' 3/4 perspective; it never rotates a
flattened side view upside down. Cars measure 132 × 60 px; tank tracks are 248 × 146 px, with the cannon
extending the total length to about 310 px. The gameplay tank radius is 104 px and its muzzle sits at the
projected cannon tip. Their wrecks use the same renderer, heading and size. `machine_painter.gd` supplies
the robot dog's normal-mapped animation and compact fallback vehicle atlases used by sheet tooling.

| File | Role |
|---|---|
| `enemy_painter.gd` | Specs, poses and painting for every sprite key: humanoids (police and civilians), K9, drone, and the five bosses. It also records anchors per frame: hands, head, eyes, chest and gun muzzle. |
| `enemy_sheets.gd` | Bakes one atlas per sprite key: a `CanvasTexture` (albedo plus normal map), a white silhouette for tints, frame rects and anchors. Finished atlases are cached in `user://enemy_sheets/`. The first launch bakes for about 3 s; after that, loading takes under 0.1 s. The cache key is a hash of the painter source plus `ART_VERSION`, so bump `ART_VERSION` if scripts are exported as binary tokens. |
| `enemy_view.gd` | Reads the enemy's gameplay fields without changing them, and picks the animation state and frame, the tint and the boss power pose. It also draws the lit sprite and ground shadow, and leaves a corpse when an enemy dies. |
| `enemy_fx.gd` | Unlit, additive overlays: stun stars, the mind-control swirl, drone beacons, Static Surge's crackle and cast arcs, Glacia's frost glow, Ironclad's fist glow, and Omega Paragon's eye glow. |
| `muzzle_flash.gd/.gdshader` | A pixel-snapped shader muzzle flash with a short point light, fired when a detective shoots. |
| `enemy_corpse.gd` | Plays the death animation where the enemy fell, holds it, then fades. Frozen kills shatter into ice, vaporized kills burn away, and sick kills stay green. Corpses are capped at 40. |
| `gallery.tscn` | Every sprite in every state, animated, under a movable light. |
| `tests/enemy_art_test.gd` | Sheet, normal-map, outline, scale and cache checks, plus a live combat run. `check.ps1` runs it. |
| `tests/bake_preview.gd` | Dev helper. It writes raw atlases to `test-results/enemies/`. |

## States

The material-detail pass adds uniform seams, hanging plainclothes badges, carrier straps and magazine
catches, armour rivets, individual boss costume accents, K9 harness hardware, drone vents, robot-dog
panels and gadget status lamps. Vehicle atlases and the live rotating vehicle renderer both carry the
pass: door seams, handles, hood vents and push bumpers on interceptors; welds, optics and barrel rings
on tanks. Details follow the existing animated body parts and retain height-map lighting and tints.

- **Police and civilians:** `idle 2`, `walk 6`, `hurt 1`, `death 4`, `frozen 1`, `stunned 1`.
  - Police also have `attack 3`: baton swing, rifle jab, shield bash, or the detective's aim and recoil.
  - Civilians have `panic 6` (an arms-up run) instead of an attack.
- **K9 and drone:** the same set, with a gallop, a bite and a rotor hover.
- **Bosses:**
  - Captain Ironclad: `windup` (slam and charge windup), `charge`, `air`, `slam`.
  - Static Surge: `blink` (after-image streak, out and back in), `cast`.
  - Glacia: `throw` (shard fan), `nova` (arms sweep up).
  - Velvet Viper: patterned stockings, plum bodysuit, seeker pods; `windup`, `charge` and `cast`.
  - Omega Paragon: hovers, plus `dive` and `laser` (eye beams through the visor).

The view infers states from existing fields. For example, a detective has just shot when `shoot_cd` jumps back up, a slam has landed when `slam` clears, and Surge has blinked when `blink_cd` resets. No gameplay hooks are needed.

## Tints (same colours and strengths as before)

The sprite is drawn first, then its silhouette is drawn over it in the tint colour:

| Status | Colour | Strength | Pose |
|---|---|---|---|
| Hit flash | White | 0.85 | Hurt |
| Mind-controlled | `#c46bff` | 0.5 | Normal |
| Frozen | `#9ef0ff` | 0.3 | Iced-over frozen frame |
| Time-locked | `#9ef0ff` | 0.6 | Stunned |
| Sick | `#8fdc3a` | 0.4 | Normal |

## Integration

- **`game/enemy_art.gd`:** a thin wrapper. `EnemyArt.build()` loads every sheet at arena start, and `EnemyArt.sheet(key)` returns one sheet. `CIVPALS` keeps the civilian kinds that `Enemy.setup()` picks from.
- **`game/enemy.gd`:** only the DRAW section changed. It adds the `gfx` render state, `_ready()` (which attaches the FX and flash nodes), `sync()` (which calls `EnemyView.update`), `_draw()`, and `_exit_tree()` (which leaves a corpse when the enemy died with `hp <= 0`). Escaped civilians and enemies removed when a wave is cleared leave no corpse.
- **Feet:** they sit `foot` px below the node origin. That is 15 for humanoids, 24 for bosses and 9 for the dog and drone, matching the scientist's feet for y-sorting.
- **Omega Paragon's eyes:** they line up with the arena's eye-laser origin (`y - 34`), and a test checks this.

## Running

- Gallery: open `enemies/gallery.tscn` and press F6.
  - The mouse moves the light and the wheel sets its height.
  - Tab switches pages, 1–5 preview the tints, F flips facing, O orbits the light and N changes the ambient light.
  - To save every page: `godot --path . res://enemies/gallery.tscn -- --shot test-results/gallery.png`
- Tests: `./check.ps1` (with `-Screenshots`, it also saves `test-results/enemies-*.png` combat captures).

## Notes for gameplay owners

- Enemy bullets (`ebul`) are still drawn by `arena.gd` as squares. Only the shot's origin gets the new shader flash.
- HP and mind-control bars are drawn by the arena at `e.y - e.r - 14`. That is now inside the taller sprites. A head anchor, `EnemyArt.sheet(key)` with `EnemySheets.anchor(sheet, state, frame, "head")`, or a fixed offset of about −50 px for humanoids and −80 px for bosses, would place them above the head.
- The README command `--autoplay 20 --wave 10 --shot ...` now stops on the city scouting screen. For combat captures, use `enemies/tests/enemy_art_test.gd -- --screenshots`.
