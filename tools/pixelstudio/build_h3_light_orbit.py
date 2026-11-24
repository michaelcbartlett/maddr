"""Prepare a frozen-pose lighting study for photometric normals; never queues."""
import json
import shutil
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK/'light-orbit'


def prompt(pose,arms):
    return f'''subject_definitions:
<Subject 1> is the mad scientist in <Picture 1>, as a rigid painted statue that never moves.
<Picture 2> is a color swatch only. Its object must NOT appear.

summary:
[reference generation] Photometric lighting study of a completely frozen character. Only the direction of one soft light changes.

retention_analysis:
<Picture 1> (character appearance): fully_preserved - identity, proportions, costume, pixel-art style and material colors.
<Picture 2> (swatch): not_preserved - never show it.

detailed_description:
A rigid motionless statue of the scientist, {pose}. {arms} Every pixel of the silhouette stays at the same position from first to last frame. No breathing, blinking, hair movement, coat movement or expression change.

The ONLY change is the direction of one large, soft, neutral WHITE directional light, outside the frame and never visible. Constant brightness and color, no dark shadows cast on the background, dim even fill light so no area becomes pure black. Shading moves clearly and smoothly across the rounded forms of head, nose, glasses, shirt, sleeves and coat folds. Remove the painted default shading; show only shading caused by the current light.
0.00-0.80 seconds: light from the viewer, straight in front, flat even shading.
0.80-1.60: light from SCREEN-LEFT; left-facing surfaces bright, right-facing surfaces dim.
1.60-2.40: light from directly ABOVE; upward-facing surfaces bright.
2.40-3.20: light from SCREEN-RIGHT; right-facing surfaces bright, left-facing surfaces dim.
3.20-4.00: light from directly BELOW; downward-facing surfaces bright.
4.00-5.00: light from the viewer again, identical to the opening frames.
Each direction is reached quickly, then held steady.

No visible lamp, ball, orb, glow, rays, lens flare, bloom, colored light, rim outline, flicker, shiny wet or metallic materials.

Locked orthographic-style camera, identical position, zoom and framing. No pan, orbit, cuts or reframing. Full body centered at 75 percent of canvas height with margin. Flat uniform unchanging dark blue-gray background. Sharp pixel edges. No blur, ghosting, added texture, text, logos, weapons, extra limbs or fingers.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['scientist.png','proxy-grip.png']:shutil.copy2(PACK/'references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    shots=[('59-light-orbit','standing in the three-quarter screen-right view of <Picture 1>','Both arms hang relaxed at the sides with empty hands.')]
    rows=[{'id':i,'seconds':5,'fps':24,'item_reference':'proxy-grip.png','motion_reference':None,'prompt':prompt(p,a)} for i,p,a in shots]
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))
    for r in rows:(OUT/(r['id']+'-prompt.txt')).write_text(r['prompt'],encoding='utf-8')
    print(json.dumps([j['id'] for j in jobs]))


if __name__=='__main__':main()
