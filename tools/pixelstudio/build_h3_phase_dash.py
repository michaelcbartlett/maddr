"""Prepare phase-dash body studies for the scientist; does not queue a render.

Directions are relative to his facing (screen-right). The game mirrors every clip
for left-facing play. Streaks, glow and dissolve are engine effects, not artwork.
"""
import json
import shutil
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

# id, short name, pose description
CORE=[
 ('48-dash-back','backward dash','Hips and torso drive toward SCREEN-LEFT while the face keeps looking SCREEN-RIGHT. Torso leans back, rear foot reaches left, front leg extends to the right with toes pushing off. Coat tails and hair sweep forward toward SCREEN-RIGHT.'),
 ('49-dash-up','upward (north) dash','He drives toward the TOP of the screen. Body stretches tall and narrow, knees drawn together, toes pointed down. Coat tails, sleeves and hair hang and trail DOWNWARD. Keep the same three-quarter screen-right view; do not show his back.'),
 ('50-dash-down','downward (south) dash','He drives toward the BOTTOM of the screen. Body compresses low with bent knees, head and shoulders pushed down and forward. Coat tails, sleeves and hair billow UPWARD. Keep the same three-quarter screen-right view.'),
 ('51-phase-vanish','phase-out and phase-in pose','Anticipation: he hunches and pulls both arms tight across his chest, chin tucked, coat wrapped close, smallest silhouette. Then the release: he snaps open into a wide, braced landing stance with coat flaring outward, and settles. He stays fully solid and opaque throughout; the game adds the disappearing effect.'),
]
DIAGONALS=[
 ('52-dash-up-forward','diagonal up-forward dash','He drives toward the UPPER-RIGHT. Torso leans forward and stretches upward, rear leg trailing to the lower-left. Coat tails and hair trail toward the LOWER-LEFT.'),
 ('53-dash-down-forward','diagonal down-forward dash','He drives toward the LOWER-RIGHT. Deep forward lunge with low head, front knee bent, rear leg long behind. Coat tails and hair trail toward the UPPER-LEFT.'),
 ('54-dash-up-back','diagonal up-backward dash','He drives toward the UPPER-LEFT while still looking SCREEN-RIGHT. Torso leans back and stretches upward, front leg trailing to the lower-right. Coat tails and hair trail toward the LOWER-RIGHT.'),
 ('55-dash-down-back','diagonal down-backward dash','He drives toward the LOWER-LEFT while still looking SCREEN-RIGHT. Low backward crouch, rear knee bent, front leg extended to the right. Coat tails and hair trail toward the UPPER-RIGHT.'),
]


def prompt(name,pose):
    return f'''subject_definitions:
<Subject 1> is the mad scientist in <Picture 1>.
<Picture 1> defines his appearance, proportions, costume and pixel-art style.
<Picture 2> is a color calibration swatch only. The object in it must NOT appear in this shot.

summary:
[reference generation] An in-place {name} body study for a game sprite, repeated three times with clear ready, action and recovery poses. Empty hands.

retention_analysis:
<Picture 1> (character appearance): fully_preserved - bald crown, wild white hair, thick eyebrows, black glasses, grin, burgundy shirt, white laboratory coat, dark trousers, shoes, palette and pixel shading.
<Picture 2> (swatch): not_preserved - never show the object, its color or any weapon.

detailed_description:
One scientist, full body, three-quarter SCREEN-RIGHT-facing view in every frame. Both hands are EMPTY closed fists for the entire shot. No gun, tool or held object.

{pose}

Timing, repeated three times:
0.00-0.40 seconds: neutral ready stance.
0.40-0.55: quick anticipation.
0.55-1.00: snap into the full action pose and hold it clearly.
1.00-1.35: recover, coat and hair settling.
1.35-1.65: neutral ready stance.
Then repeat the same motion at 1.65 and at 3.30 seconds. End in the exact starting stance.

Perform everything IN PLACE: the pelvis stays at the same canvas position, the game moves him. Only small pelvis height changes are allowed. Fists stay tucked near the ribs and clear of the face and belt so the arms can be separated. Constant limb lengths, head size and body scale. No spinning, turning around, jumping high, falling or extra steps.

Fixed orthographic-style camera, identical position, zoom and framing. No pan, orbit, tracking, cuts or reframing. Character centered at about 70 percent of canvas height, ground line at 88 percent from the top, with margin around hair, coat and feet. Flat uniform dark blue-gray background. Sharp individual frames with crisp pixel edges and stable colors. Fully opaque character. No motion blur, speed lines, streaks, afterimages, ghost trails, glow, transparency, particles, portals, smoke, electricity, crosshatching, texture overlays, text or logos. No extra limbs or fingers.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''


def build(folder,shots):
    out=PACK/folder;refs=out/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['scientist.png','proxy-grip.png']:shutil.copy2(PACK/'references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,out/name)
    rows=[{'id':i,'seconds':5,'fps':24,'item_reference':'proxy-grip.png','motion_reference':None,
        'prompt':prompt(name,pose)} for i,name,pose in shots]
    queue.atomic_json(out/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(out,rows,queue.read_json(out/'queue-api-template.json'),queue.read_json(out/'queue-workflow-template.json'))
    for row in rows:(out/(row['id']+'-prompt.txt')).write_text(row['prompt'],encoding='utf-8')
    print(json.dumps({'pack':str(out),'jobs':[j['id'] for j in jobs],'queued':False}))


if __name__=='__main__':
    build('phase-dash',CORE)
    build('phase-dash-diagonals',DIAGONALS)
