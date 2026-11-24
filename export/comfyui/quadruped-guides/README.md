# Quadruped motion calibration

These are geometric motion guides for **dogs and robot dogs**, not final character art or a trained motion model. Use the supplied character image as Picture 1 and the appropriate guide as Video 1 in the existing H3 REF2VA workflow. The guide defines movement; the character image defines appearance. Motion reference improves control but H3 can still swap legs, alter patches or hallucinate occluded parts; review before import.

## Rig

All four legs have separate root, middle joint, distal joint and paw/contact control. Forelegs use shoulder → backward elbow → wrist → paw. Hind legs use hip → forward stifle → rear hock → paw. Separate colors identify every leg segment and paw. Pelvis, two spine links, chest, neck, skull, muzzle, hinged lower jaw and three tail segments have their own colors/sockets. The far legs draw behind the torso and near legs in front. A fixed projected three-quarter view keeps both pairs identifiable without rotating the camera.

`rig-and-palette.png` shows the part colors; `palette.json` contains their stable IDs. Each MP4 has an adjacent JSON containing all 120 frames of joint coordinates, contact flags and layout, so guides can be inspected or reused without tracking the video. Coordinates are **unscaled rig pixels**; apply the file's scale/pivot/ground layout to match its video. The coordinates describe the calibration rig, not automatic sockets extracted from AI-generated character art.

All guides are **768×768, 24fps, five seconds**, fixed camera, screen-right facing, root fixed horizontally. Organic motion includes tail sway, small body bob and linked spine flex. Mechanical motion holds the two spine links straight, reduces bob/swing and uses diagonal bounding instead of a flexible organic gallop. Both versions preserve bone lengths using separate front/hind IK. The generated skeleton is intentionally simple; it is a controllable reference, not an assertion of polished final animation.

Paw tracks distinguish stance and swing. In an in-place walk, a grounded paw travels backward relative to the fixed body; the game supplies matching body travel. Pounce guides include vertical lift and landing, while gameplay supplies horizontal attack displacement. No root translation should be inferred from these videos.

## Files

`organic/` and `mechanical/` each contain:

- `guide-idle.mp4`, `guide-walk.mp4`, `guide-trot.mp4`, `guide-run.mp4`
- `guide-start-stop.mp4`, `guide-retreat.mp4`
- `guide-bark.mp4`, `guide-bite.mp4`, `guide-pounce.mp4`
- `guide-flinch.mp4`, `guide-stagger.mp4`, `guide-stunned.mp4`, `guide-frozen.mp4`
- `guide-search.mp4`, `guide-collapse-front.mp4`, `guide-collapse-side.mp4`
- Two smaller collapse guides with `-small` suffix for wider death framing
- `rig.png` and a matching JSON pose track beside each video

**36 guides total**. `motion-catalog.json` inventories both modes and sizes. `motion-preview.png` shows walk, trot, run and pounce sequences.

Standard sole baseline: y=680. Small death layout: scale 0.72 around x=384, baseline y=625. Do not combine a small guide and a full-size reference without matching the layout. The source still may have a different body outline: tell H3 to preserve the reference's proportions and ignore the calibration figure's appearance.

## Use / rebuild

The attached police dog is prepared in the separate `../attack-dog/` pack with matching references and organic guide assignments. Root launchers are **Queue Attack Dog.bat**, **Preview Attack Dog Queue.bat**, and **Build Attack Dog MoGe.bat**. The robot guides are ready, but no robot-dog art reference was supplied and no robot animation queue is fabricated from the organic dog image.

Double-click **Build Quadruped Guides.bat** to rebuild all guides and refresh the attack-dog pack from the supplied Downloads image. It prepares files only, never queues generation. The ComfyUI Python environment supplies Pillow, NumPy, OpenCV and PyAV. Source: `tools/pixelstudio/quadruped_motion.py`; K9 pack builder: `tools/pixelstudio/build_h3_attack_dog.py`.

For a robot reference later, retain its chassis, sensors and actual hardware; ignore the guide's ears, tail, jaw or any part that the robot does not have. Do not add fur, flesh, panting or an organic skeleton. Use the mechanical gait guide that matches its intended action. `robot-prompt-template.txt` supplies the six-section starting prompt; insert the desired action and use the matching Video 1. The reference and motion still need a reviewed first pass before bulk generation.
