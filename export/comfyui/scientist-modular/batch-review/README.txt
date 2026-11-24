SCIENTIST BATCH REVIEW - 2026-11-23

All 36 completed clips are present. Reviewed representative early, middle,
and late frames at source resolution and at the intended 128px cell size.
This is visual triage, not a frame-by-frame production acceptance check.

RESULT
There is enough consistent character art and motion to build a first modular
set. The videos are source material: each needs selected poses, clean alpha,
stable anchors, loop timing, prop removal, and pixel cleanup. File labels do
not reliably identify the moving arm. Label extracted assets by actual depth.

FIRST MODULAR PROOF
Open modular-proof.mp4 (24fps) or modular-proof.gif.
Columns show walk source, far-arm source, arm cutout, combined result.
Uses the lower body from 11-walk, static upper body/head/resting near arm
from frame 50 of 06-far-shoulder, and a separate far-arm shoulder sweep.
The walk repeats independently while the arm changes pose. Far arm is drawn
behind torso and head. Green proxy is deliberately retained for diagnostics.

PNG sheets use 128x128 cells, 16 columns, 124 used cells. Unused cells are
transparent. These are diagnostic cutouts, not production-ready game assets.
proof-metadata.json records sources, frame selection, belt tracking, and limits.
Current rough masks can leave seams; hidden arm pixels are not reconstructed.
The original shoulder clip also cuts the prop at the top in overhead poses.
The repeated walk span has not been cleaned into a seamless loop.
No game runtime or existing sprite assets were changed for this proof.

CLIP TRIAGE
01 near shoulder: usable far-arm source; relabel, overhead proxy clipped.
02 near elbow: useful bends; upper arm also moves, not isolated elbow motion.
03 near elbow up: little movement; needs replacement for bend coverage.
04 near elbow down: useful lowered arm/grip poses; shoulder also moves.
05 near wrist: useful grip angles; replace the varying proxy with a rigid item.
06 far shoulder: strong first arm source; source used in modular proof.
07 far elbow: useful arm poses; not a perfectly isolated elbow sweep.
08 far wrist: appears to animate the near arm; relabel by actual depth.
09 idle: strong body source; select stable loop frames.
10 blink: usable facial poses; extract only wanted facial changes.
11 walk: strong locomotion source; lower body used in modular proof.
12 run: strong locomotion source; clean loop and anchors.
13 backpedal: useful source; check foot direction/timing when choosing loop.
14 start stop: useful transitions; split start and stop before importing.
15 hurt: weak reaction; replacement recommended for a readable hit response.
16 fall: useful fall and settle; full final frame remains inside canvas.
17 stunned: adds stars; remove baked effects before reusing body poses.
18 near recoil: adds muzzle flash; use clean arm frames, separate game effects.
19 far recoil: moving arm appears foreground; relabel and remove flash.
20 dual recoil: useful separate grips; props vary from one to two.
21 charge release: adds bright shot effect; salvage clean arm frames.
22 grapple cast: invents hook/extra gun; salvage arm poses, discard generated gear.
23 grapple brace: rope crosses body; useful lean/crouch with cleanup.
24 near thrust: readable thrust; proxy turns into sword/crossguard.
25 near slash: useful overhead/downward slash poses.
26 near reverse slash: little movement; replacement recommended.
27 near whip cast: invents whip and changes props; selected arm poses usable.
28 far thrust: foreground arm appears to move; relabel; prop appears late.
29 far slash: useful raised and lowered arm poses; verify actual arm labels.
30 far whip cast: little movement; replacement recommended.
31 kick: good readable kick poses.
32 stomp: good knee raise and down motion.
33 leap land: useful takeoff/landing; head clips at apex, replace apex frames.
34 airborne: useful tucked legs; remove generated boot flames.
35 dash: reads as running; does not add much distinct dash coverage.
36 device activate: useful near hand toward chest; replace generated item.

NEXT PRODUCTION PASS
Prioritize idle, walk, run, far-arm aim, recoil, kick, stomp, hurt, and fall.
Build one complete character using those before commissioning more poses.
Use dedicated transparent arm/hand sheets with shoulder, elbow, and grip anchors.
Keep weapons and visual effects separate. Author missing occluded pixels rather
than expecting a single flattened video to contain a complete hidden limb.
