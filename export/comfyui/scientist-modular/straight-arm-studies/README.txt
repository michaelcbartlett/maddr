STRAIGHT-ARM AIM STUDIES - 2026-11-23

Start ComfyUI, then run "Queue Straight Arm Studies.bat" in the repository root.
It uses the existing clean H3 REF2VA workflow, installed model and two LoRAs,
16 steps, 768x768 and 24fps. It uploads the correct scientist, green proxy and
motion references, then submits ONLY these two new shots:

37-near-straight-sweep: 5 seconds, foreground near arm.
38-far-straight-sweep:  5 seconds, background far arm.

Both clips: hold arm pointing straight down for 0.5s, sweep the fully extended
arm through screen-right to horizontal and then overhead, hold straight up for
the final 0.75s. Shoulder rotates. Elbow stays at 180 degrees. Wrist and proxy
remain aligned with the forearm. Body and camera remain fixed throughout.
These are clean aim-pose studies with no firing or effects.

References use the actual scientist shoulder arrangement: the foreground near
shoulder is on screen-left, while the background far shoulder is screen-right.
The moving arm is identified by color in each motion guide and by anatomy in
each prompt. Head/hair occlude the raised arm where appropriate. Reference
framing leaves room for the fully raised hand and proxy above the head.

An earlier guide-renderer bug reused the elbow angle variable when calculating
the knees. It has been fixed in build_h3_sprite_pack.py. The new guides validate
all 240 frames: elbow angle 180 degrees, constant upper/forearm lengths, fixed
shoulder and full subject framing. Existing batch videos were not overwritten.
H3 may still deviate from the requested motion; review the generated elbow and
actual moving arm before treating the output as a production pose bank.

FILES
37-near-straight-sweep-prompt.txt / 38-far-straight-sweep-prompt.txt: full prompts.
*-workflow.json: editable ComfyUI workflows with synchronized prompts and refs.
*-api.json: exact API graphs prepared for the two new shots.
references/: scientist, proxy, two motion videos, and per-frame joint records.
near-sweep-contact.png / far-sweep-contact.png: motion-guide contact sheets.
validation.json: numerical guide validation and generation settings.

The launcher uploads the hash-named references before queueing. Loading the
editable workflows manually requires those same references to be installed.

OUTPUTS
ComfyUI-Shared/output/video/mad-villain-sprite/batch/37-near-straight-sweep/
ComfyUI-Shared/output/video/mad-villain-sprite/batch/38-far-straight-sweep/
Submission log: .local/h3-straight-arm-queue/queue-log.json

"Preview Straight Arm Studies.bat" lists the plan without queueing anything.
To run only one shot, use the queue launcher with --shots 37 or --shots 38.
Rerunning skips an identical job already submitted; --force requests a new take.
No generation was submitted while preparing this pack.

Rebuild locally with ComfyUI Python:
python tools/pixelstudio/build_h3_straight_arm_studies.py

The generated clips will supply the straight overhead arm poses for the game;
the current upper-angle pose bank has not been replaced with invented art.
