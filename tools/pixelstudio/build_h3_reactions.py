"""Full-body reactions: no aiming happens, so no layers are needed. Never queues."""
import shutil
from pathlib import Path
import av
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK/'reactions'
TAZED=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Shared/output/video/2026-11-23/191153_00001_audio.mp4'


def prompt(summary,action,extra):
    return f'''subject_definitions:
<Subject 1> is the mad scientist in <Picture 1>, exactly as drawn there.
<Picture 2> is a color swatch only. Its object must NOT appear.

summary:
[reference generation] {summary}

retention_analysis:
<Picture 1> (character appearance): fully_preserved - identity, proportions, costume, palette, outlines and pixel-art style.
<Picture 2> (swatch): not_preserved - never show it.

detailed_description:
{action}

Empty hands, no gun, weapon or held object. Feet stay near the same canvas position. Constant body scale and limb lengths, five fingers per hand, no extra limbs. {extra}

Locked orthographic-style camera, identical position, zoom and framing. Full body visible with generous margin on all sides. No pan, orbit, cuts, crossfades or reframing. Flat uniform dark blue-gray background. Sharp individual frames, crisp pixel edges, stable colors. No motion blur, ghosting, added texture, text or logos.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['scientist.png','proxy-grip.png']:shutil.copy2(PACK/'references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    with av.open(str(TAZED)) as video:
        for i,frame in enumerate(video.decode(video=0)):
            if i==36:frame.to_image().save(refs/'tazed.png');break
    clean='No lightning, sparks, glow, smoke, flashes or particles of any kind; the game adds effects.'
    shots=[
     ('75-tazed-loop','tazed.png','A seamless looping electrocution. He is already in the X-ray pose in every frame.',
      'He stays in this exact splayed X-ray skeleton pose for the whole shot: bones showing inside the dark body, head, hair, glasses, coat edges and shoes drawn normally. He trembles violently in short stiff jerks: fingers twitching and curling, shoulders and knees shaking, head rattling, jaw chattering, coat edges quivering. Legs stay apart and feet planted. The bone drawing stays the same from frame to frame. The first and last frames match.',
      'Keep one thin even cyan glow hugging the outline. NO lightning bolts, arcs or sparks separate from the body; the game draws those.'),
     ('76-hurt','scientist.png','A quick, clear hit reaction repeated three times.',
      'Facing three-quarter screen-right. Hold neutral for 0.4 seconds. Then, at 0.40, 1.95 and 3.50 seconds, he is struck from the right: head snaps back toward screen-left, teeth clenched, eyebrows up, chest caves, shoulders jump, both arms fly up bent in front of him with open hands, weight rocks onto the back foot and the front toes lift. Reach the full flinch within 0.10 seconds, hold 0.25 seconds, recover to neutral in 0.5 seconds.',
      clean),
     ('77-defeat','scientist.png','A single dramatic cartoon defeat, ending lying down.',
      'Facing three-quarter screen-right. Hold neutral 0.4 seconds. He staggers backward one step clutching his chest, knees wobbling, until 1.40. His legs give way and he topples backward toward screen-left, landing flat on his back by 2.20 with coat spread, arms out and shoes pointing up. One small bounce. From 2.60 to 5.00 he lies completely still, glasses crooked. The whole body stays in frame when lying down.',
      clean),
     ('78-cackle','scientist.png','An evil-genius laugh for wave victories, looping.',
      'Facing three-quarter screen-right. He throws his head back and cackles, mouth wide open, shoulders bouncing, both arms bent and raised at his sides with clawed fingers, coat shaking with each laugh. A steady rhythm of about three laughs per second. The first and last frames match.',
      clean)]
    rows=[]
    for ident,subject,summary,action,extra in shots:
        text=prompt(summary,action,extra)
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':None,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
