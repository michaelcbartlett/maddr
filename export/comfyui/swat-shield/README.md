# Shield officer animation pack

Source: `references/source.png`, copied unchanged from the supplied `riot police.png`.
This is a separate shield/baton pack; it does not replace the rifle SWAT sprites or install/enable an enemy.

## Run

1. From the repository root, double-click **Queue SWAT Shield.bat** with ComfyUI running. It appends all 28 H3 jobs using the same REF2VA workflow as the cop/detective batches, at **16 steps, 768×768, 24fps, five seconds each** (140 seconds total). Existing queue entries remain in order. Closing the launcher after submission does not stop generation.
2. Review the completed clips in ComfyUI's `output/video/mad-villain-sprite/batch/171-swat-guard-idle` through `198-swat-death-ash`. Fix bad clips before running normals. Higher steps and motion guides help, but do not guarantee correct hands, lettering, occlusion or clean loops.
3. Run **Build SWAT Shield MoGe.bat** after the animations finish. Keep its window open to collect results. It computes **MoGe-2 OpenGL normals for every actual video frame**, deduplicating identical frames, and writes the existing `.local/moge-cache` format. Allow for roughly 3,400 frame maps before deduplication; this is a separate GPU pass. The frame index is `.local/h3-swat-moge/normal-frame-index.json`. Art and normals still need the same crop, scaling and alpha during the eventual sprite import.

**Preview SWAT Shield Queue.bat** prints the plan without uploading/submitting. Add `--check` to validate the running server without modifying its queue.
Rerunning either generation launcher skips already submitted jobs; the MoGe launcher also skips cached maps. MoGe never falls back to silhouette normals. Failed or interrupted downloads can be collected by rerunning. A timeout during submission stops instead of risking duplicate GPU work.

Examples from PowerShell in the repository root:

```powershell
& '.\Preview SWAT Shield Queue.bat' --check
& '.\Queue SWAT Shield.bat' --shots '172,178,181'
& '.\Queue SWAT Shield.bat' --shots 178 --force --seed 872341
& '.\Build SWAT Shield MoGe.bat' --shots '172,178,181'
& '.\Build SWAT Shield MoGe.bat' --allow-partial
```

`--force` deliberately resubmits selected animation jobs; use it for retakes. The normal tool always picks the newest matching finished video, checks 24fps/frame count and rejects cut-off subjects before submission. `--allow-clipped` bypasses the framing check deliberately. `--stride 2` or `--stride 3` samples fewer normal frames; the default is every frame, preserving exact pose correspondence. Missing clips stop the default full-pack MoGe run; `--shots` or `--allow-partial` limits it to available work. No queue clearing or priority insertion.

## Direction, props and framing

Fixed original three-quarter screen-right view. Baton stays in the **near/screen-left** hand; shield stays in the **far/screen-right** hand. No mirrored hands or rifle. Shield raised while walking/jogging, lowered at the far hip before baton swings and returned to guard afterward. Six motion guides cover walking, raising/lowering, strike, combo and grenade throw. The colored figures and geometric grenade plate are calibration references only, not final art.

The grenade throw visibly stows the baton, retrieves one grenade in that same hand, winds up, opens the hand at release, then retrieves the baton and raises the shield. The game will supply the flying grenade at the release frame; no projectile/explosion is baked into this clip. Shield remains in its own hand.

Standing reference is 430px high on a 768px canvas, feet at y=690. Death reference is 305px high, feet at y=625, leaving room for the fallen body and dropped gear. The same final game height will require scaling the two reference groups differently. No camera zoom inside any clip. Future sprite export can target the game's 128px art scale with matched normal maps.

## Shots — each five seconds, 24fps

| ID | Animation | Notes |
|---|---|---|
| 171 | Guard idle | Shield up, loop |
| 172 | Guard walk | Shield up, guided, loop |
| 173 | Guard run | Compact armored jog, loop |
| 174 | Start/stop | Guarded walking transitions |
| 175 | Alert | Notice and brace |
| 176 | Shield raise | Two guided repetitions |
| 177 | Shield lower | Two guided repetitions |
| 178 | Baton strike | Lower shield → wind up → swing → recover → guard; twice |
| 179 | Baton combo | Downward swing and rising backhand; twice |
| 180 | Shield bash | Two short shoves |
| 181 | Grenade throw | One throw, fixed hands, release at about 1.6s |
| 182 | Shield block | Three braced reactions, no incoming projectile |
| 183 | Guard break | Shield flung low/out, then recover; twice |
| 184 | Hurt | Three exposed flinches |
| 185 | Knockback | Stagger onto a knee, recover; twice |
| 186 | Stunned | Dazed loop |
| 187 | Frozen | Shiver, then perfectly still |
| 188 | Sick | Queasy loop |
| 189 | Hypnotized | Stiff walking loop |
| 190 | Tazed | Body-only X-ray loop, opaque equipment |
| 191 | Burning | Panic loop, small attached flames |
| 192 | Fooled | Search, shrug, return to guard |
| 193 | Death backward | Dropped gear, held corpse |
| 194 | Death forward | Shield settles beside body |
| 195 | Death sideways | Fold onto near side |
| 196 | Death poison | Green, wobble, collapse |
| 197 | Death melt | Cartoon colored puddle, solid gear |
| 198 | Death ash | Charred silhouette → ash pile |

Individual six-section prompts are beside this README; the queue reads `animation-queue-manifest.json`. `reference-and-guide-preview.png` is a framing/motion review, not generated animation footage.

Rebuild the pack with the ComfyUI Python environment:

```bat
python tools/pixelstudio/build_h3_swat_shield.py --source "C:/Users/micha/Downloads/riot police.png"
```

The builder only prepares files. No scripts in this pack install the unreviewed animations into the game.
