MATCHED STRAIGHT-ARM RECOIL STUDIES

Run "Queue Straight Arm Recoil.bat" from the repository root with ComfyUI open.
This queues six new 5-second, 24fps, 768x768 H3 REF2VA shots at 16 steps:

40 near arm, horizontal right
41 near arm, straight up
42 near arm, straight down
43 far arm, horizontal right
44 far arm, straight up
45 far arm, straight down

Each shot uses its OWN starting-pose image captured from the approved completed
37/38 straight-arm sweep, the green proxy image, and a matched recoil guide.
The guides keep the elbow at 180 degrees in all 720 frames. They show three
small shoulder-driven kicks at 1.00, 2.25 and 3.50 seconds, returning completely
to the same extended pose. Body, legs and camera stay fixed. No generated muzzle
effects are requested; the game supplies the actual weapon and effects.

The launcher installs the needed hash-named references before submitting.
No jobs were submitted while this pack was prepared. Read-only live ComfyUI
preflight passed. "Preview Straight Arm Recoil.bat" previews without queueing.
The queue launcher accepts --shots 40,41 to request a subset, --seed NUMBER for
another seed, and --force for a deliberate repeat of an accepted request.

Outputs:
ComfyUI-Shared/output/video/mad-villain-sprite/batch/<40..45-shot-id>/
Log:
repository .local/h3-straight-recoil-queue/queue-log.json

The full per-shot prompts and editable workflows are in this folder.
Regenerate the pack with ComfyUI Python:
python tools/pixelstudio/build_h3_straight_recoil.py

These are generation requests. Review the returned arm identity, elbow shape,
framing and unwanted effects before replacing the game's temporary recoil warp.
