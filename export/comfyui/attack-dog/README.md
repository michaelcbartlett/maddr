# Police attack dog — H3 animation pack

Prepared from the supplied `attack dog.png`; untouched original preserved at `references/source.png`.
Fixed three-quarter screen-right framing. **22 clips × five seconds, 24fps, 768×768, 16 steps** using the existing cop/detective REF2VA workflow. No generated animation has been queued or installed by the builder.

## Run

1. Double-click **Queue Attack Dog.bat** in the repository root with ComfyUI running. Jobs append to its existing queue. All reference images and matching organic quadruped videos are assigned automatically.
2. Review the finished clips under ComfyUI's `output/video/mad-villain-sprite/batch/201-k9-idle` through `222-k9-death-ash`. Check leg order, harness stability, clean feet, mouth, looping and framing. Motion guides do not guarantee correct generation.
3. After reviewing/retaking bad clips, double-click **Build Attack Dog MoGe.bat**. It queues MoGe-2 OpenGL normals from the actual finished frames, deduplicates identical frames, collects results and resumes from the existing `.local/moge-cache`. Keep the window open to collect. Full per-frame processing can require roughly 2,700 normal jobs before deduplication. It does not install the art in the game; source, final crop and sprite alpha must later be applied equally to art and normals.

**Preview Attack Dog Queue.bat** is a local dry run. Adding `--check` performs a read-only server/model check. No launcher clears the queue or raises its priority. Animation reruns skip already submitted jobs; use a deliberate `--force` retake with selected IDs and a new seed when needed.

PowerShell examples from repository root:

```powershell
& '.\Preview Attack Dog Queue.bat' --check
& '.\Queue Attack Dog.bat' --shots '202,204,207,208'
& '.\Queue Attack Dog.bat' --shots 208 --force --seed 294712
& '.\Build Attack Dog MoGe.bat' --shots '202,204,207,208'
```

The MoGe launcher waits until results finish, rejects clipped or incomplete videos, and caches by exact decoded RGB frame, matching the enemy importer. Missing clips stop the default full-pack run; choose `--shots` or `--allow-partial` to process a subset. `--stride 2` deliberately processes fewer normal poses; default 1 processes every actual frame, including H3's occasional padded tail frames.

## Motion and references

Guides originate in `../quadruped-guides/organic/`: four distinct leg chains, canine elbows/stifles/hocks, hinged jaw, neck and tail. Walk is four-beat, trot uses diagonal pairs, gallop has separate fore/hind timing and flight. Pounce shows crouch → push-off → reach → landing → recovery. Normal reference height is 400px with soles at y=680. Death reference height is 288px with soles at y=625, matching the smaller guide layout; importing must scale the two groups back to the same character height.

The full original head, fur, harness and existing POLICE/MTA patches belong to Picture 1. H3 is explicitly told to copy only motion from Video 1. Picture 2 is a calibration swatch, never a held item. Ash transformation has no guide so the still-standing rig does not fight the changing silhouette. These are full-body enemy clips, not pre-cut modular limb art.

## Shot list — all five seconds / 24fps

| ID | Clip |
|---|---|
| 201 | Alert idle loop |
| 202 | Four-beat walk loop |
| 203 | Diagonal trot loop |
| 204 | Gallop loop |
| 205 | Walk start / stop |
| 206 | Warning barks, silent footage |
| 207 | Two snapping bites |
| 208 | Two crouch / pounce / bite / landing attacks |
| 209 | Two short hurt flinches |
| 210 | Two heavy staggers |
| 211 | Dazed stun loop |
| 212 | Shiver → frozen hold |
| 213 | Queasy sick loop |
| 214 | Hypnotized walk loop |
| 215 | Cartoon canine X-ray electrical tremble |
| 216 | Burning panic gallop, small attached flames |
| 217 | Search / sniff / return to alert |
| 218 | Cautious backward walk loop |
| 219 | Front collapse onto belly |
| 220 | Near-side collapse |
| 221 | Poison collapse |
| 222 | Charred silhouette → ash pile |

Prompts and assignments live in `animation-queue-manifest.json` and the matching `*-prompt.txt` files. Rebuild guides and this pack using **Build Quadruped Guides.bat**. The separate `mechanical/` guides are ready for a future robot-dog reference; this K9 batch does not substitute the organic dog for robot art.
