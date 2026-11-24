SCIENTIST / PROP / MOTION REFERENCE TEST PACK

AUTOMATIC BATCH QUEUE
Use Queue Scientist Animations.bat in the repository root to queue the 36-shot set.
Preview Scientist Queue.bat shows its plan without generation. The queue script uses
animation-queue-manifest.json and the clean take's 16-step API template, including the
corrected near/far guides. See QUEUE-INSTRUCTIONS.txt for selection, reruns and outputs.

CORRECTED ARM STUDIES
For the far-arm elbow study, use Scientist-Far-Elbow-Behind-Head-v2.json.
It replaces the original batch #02 guide with puppet-far-elbow-behind-head-v2.mp4:
the upper arm stays fixed, only the far forearm/hand bend, and the head/torso
occlude them. It retains the 115037 take's 16-step settings and LoRAs, with a
fixed seed. The guide is 5 seconds at 24fps. Draw-order and reference loading
checks pass; the resulting H3 generation still needs visual review.
The original puppet-elbow.mp4 and batch ZIP are older, uncorrected references.

Start by importing Scientist-Subject-Item-Motion-REF2VA.json in ComfyUI.
It is a copy of your supplied DaSiWa C-MMH3-33 workflow; the original is untouched.

References, in order:
  Picture 1: scientist.png       character identity and pixel-art appearance
  Picture 2: proxy-grip.png      a plain green calibration prop
  Video 1:   puppet-shoulder.mp4 fixed-camera near-arm articulation guide

The Director uses REF2VA, 768 x 768, 24fps, requested duration 5 seconds.
H3 rounds duration to its native frame grid; it may output slightly over 5 seconds.
Interpolation and upscaling remain disabled. Original sampling settings are retained.
Installed reference-model, encoder and VAE filenames replace the unavailable example paths.
No animation generation has been submitted. This pack is a motion-transfer experiment,
not a validated final sprite export or a guarantee of pixel-exact pose transfer.

SETUP
Reference files must be in ComfyUI input/MadVillain_Modular_20261123/.
If they are missing, copy the files from references/ there, or use the Director's
upload/replace controls for each tile. The same three reference slots remain reusable.
The prop may be replaced by your actual blaster; keep it in Picture 2's slot.
The calibration prop and mannequin are deterministic geometric diagrams, not generated
game artwork. They are deliberately plain so shape, joints and grip are easy to assess.

FIRST TESTS
Run 01-near-shoulder, 02-near-elbow, 11-walk and 18-near-recoil first.
Full prompts and seconds are in animation-prompts.txt and animation-commissions.json.
Every shot also has a ready-configured workflow in shot-workflows.zip.
Each workflow uses the appropriate prop and duration. Motion videos are enabled only
for shots 01, 02 and 11; other shots are prompt-driven with their video tile disabled.
Do not generate the entire batch before inspecting the first results at 128px size.

MIXAMO PATH
1. Apply an animation to a rigged character in Mixamo and download FBX.
2. Use a character/mannequin close to the scientist's proportions; retarget if needed.
3. Import into Blender. Use a fixed orthographic camera in the same right-facing
   three-quarter view. Lock its transform and orthographic scale for every clip.
4. Use 24fps. Keep the root stationary for walk/run references. Keep the ground line
   and the character's size consistent. Leave space for fully extended arms/props.
5. Parent a simple grip proxy to the hand bone if the action needs a held item.
6. Render an MP4. Replace Video 1 in the Director with that MP4, enable its tile,
   set the crop to the intended action, and match the requested output duration.
7. Keep Picture 1 as the scientist and Picture 2 as the prop. Describe Video 1 as
   motion/camera guidance only; retain the scientist's appearance and proportions.
   Do not pass FBX directly into the video-reference lane.

QUALITY GATE
Check the generated result at 128px character scale as well as full resolution:
  - same head, hair, glasses, face, coat, palette and limb lengths throughout
  - consistent feet/ground line and no camera drift or scale changes
  - a stable grip, correct occlusion and no fingers merged into the prop
  - recognizable anticipation, action/contact, follow-through and recovery
  - a stable palette/pixel grid and usable first/last poses
  - no copied mannequin colors, body parts or background
The colors label the source mannequin; H3 does not treat them as rigid joint constraints.
If video reference follows timing but loses articulation/identity, compare against a
dedicated pose-driven animation pipeline before spending on the full batch.

MODULAR GAME ART
After approval, extract frames and clean them at the intended sprite scale. Remove the
green proxy, preserve fingers/sleeves, fill hidden surfaces where needed, and record the
shoulder, elbow, wrist/grip and muzzle attachment points. Keep weapons and visual effects
separate. Green-screen removal alone cannot recreate anatomy hidden behind the prop.
The existing game uses separate aiming arms/weapons; these videos need a new import and
attachment pass before they can replace the scientist rig. This pack does not change it.

SOURCES
Director: https://github.com/darksidewalker/ComfyUI-DaSiWa-Nodes/blob/main/docs/minimax_h3_director.md
H3: https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/docs/VIDEO_PROMPT_WRITING_GUIDE_ref_en.md
Mixamo: https://helpx.adobe.com/creative-cloud/help/animate-characters-mixamo.html
Camera: https://docs.blender.org/manual/en/latest/render/cameras.html
