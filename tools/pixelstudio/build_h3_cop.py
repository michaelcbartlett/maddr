"""Full-body animation set for the basic cop. Enemies do not free-aim, so no layers. Never queues."""
import shutil
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK.parent/'cop'
SOURCE=Path.home()/'Downloads/exec-9ea54b80-8e13-43f7-9623-49041bb9335c.png'
CLEAN='No sparks, stars, smoke, dust, speed lines, glow, flashes, impact marks or particles of any kind; the game adds effects.'
SOLID='He stays exactly in place horizontally; the game moves him. '


def reference(path,height,ground,left=None):
    """The cop on his own backdrop, sized so a raised baton or a fall stays in frame."""
    source=Image.open(SOURCE).convert('RGB');backdrop=source.getpixel((20,20))
    figure=source.crop((290,10,1185,1070));scale=height/figure.height
    # One exact backdrop colour, so no faint box surrounds the pasted figure.
    pixels=np.asarray(figure).copy();near=np.abs(pixels.astype(int)-backdrop).max(axis=2)<26
    count,labels=cv2.connectedComponents(near.astype(np.uint8),connectivity=4)
    edge=set(np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1]))))-{0}
    pixels[np.isin(labels,list(edge))]=backdrop;figure=Image.fromarray(pixels)
    figure=figure.resize((round(figure.width*scale),height),Image.Resampling.NEAREST)
    canvas=Image.new('RGB',(768,768),backdrop)
    canvas.paste(figure,((768-figure.width)//2 if left is None else left,ground-height));canvas.save(path)


def prompt(summary,action,extra=CLEAN):
    return f'''subject_definitions:
<Subject 1> is the cartoon police officer in <Picture 1>, exactly as drawn there.
<Picture 2> is a color swatch only. Its object must NOT appear.

summary:
[reference generation] {summary}

retention_analysis:
<Picture 1> (character appearance): fully_preserved - stocky proportions, oversized head, navy peaked cap with gold badge, thick brown mustache and eyebrows, navy uniform with gold buttons, shoulder bars and star badge, black belt with pouches and silver buckle, black boots, wooden baton, palette, thick black outlines, chunky pixel-art style and scale.
<Picture 2> (swatch): not_preserved - never show it.

detailed_description:
One police officer, full body, three-quarter SCREEN-RIGHT-facing view in every frame. He holds the one wooden baton in the same hand for the whole shot: his far hand, on the right side of the screen. The near hand stays an empty fist.

{action}

{extra}

Keep the same face, expression style, costume details, baton length, limb lengths, head size and body scale in every frame. One baton only. No gun, radio or extra objects. No extra limbs or fingers. No turning to face the camera.

Locked orthographic-style camera, identical position, zoom and framing. Full body, cap and baton always inside the frame with margin. No pan, orbit, cuts, crossfades or reframing. Flat uniform dark blue-gray background. Sharp individual frames with crisp chunky pixel edges and stable colors. No motion blur, ghost trails, frame blending, added texture, text or logos.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''


SHOTS=[
 ('101-cop-idle','stand','A seamless looping idle.',SOLID+'He stands guard, breathing slowly. Shoulders rise and fall, the baton bobs slightly, one eyebrow twitches. Feet planted. First and last frames match.'),
 ('102-cop-walk','stand','A seamless looping walk cycle in place.',SOLID+'A heavy, confident patrol walk at an even pace, about one full stride per second. Clear alternating planted feet, knees bending, free arm swinging opposite the legs, baton held up and bobbing gently. Head stays level.'),
 ('103-cop-run','stand','A seamless looping run cycle in place.',SOLID+'An angry chase run leaning forward, about two full strides per second. Knees high, boots kicking up behind, free arm pumping, baton raised by his shoulder ready to swing. Cap stays on.'),
 ('104-cop-start-stop','stand','Starting and stopping a run in place.',SOLID+'Hold neutral until 0.5. Lean forward and push off into a run by 0.8, run in place until 2.5, then plant the front boot, lean back and skid to a halt by 3.0, settle to neutral by 3.5 and hold.'),
 ('105-cop-alert','stand','Spotting the villain.',SOLID+'Neutral until 0.5. He notices something to screen-right: a small startled hop with eyebrows up, then he scowls, points the baton straight ahead toward screen-right at 1.0, holds it 0.6 seconds, and returns to neutral by 2.2. Hold.'),
 ('106-cop-strike','stand','A single powerful baton strike, repeated three times.',SOLID+'At 0.40, 2.00 and 3.60 seconds: raise the baton high behind his head in 0.20 seconds and hold the wind-up for 0.15; swing it down hard to screen-right in 0.10, stepping forward on the front foot; hold the follow-through with the baton low and forward for 0.15; recover to neutral in 0.45. The baton stays rigid and full length through the swing.'),
 ('107-cop-combo','stand','A two-hit baton combo, performed twice.',SOLID+'At 0.40 and 2.70 seconds: first a downward overhead swing toward screen-right, hitting 0.40 after the start; then without pausing a rising backhand swing back up, hitting 0.95 after the start; hold briefly and recover to neutral by 1.80 after the start. The baton stays rigid and full length.'),
 ('108-cop-hurt','stand','A quick hit reaction, repeated three times.',SOLID+'At 0.40, 1.95 and 3.50 seconds he is struck from screen-right: within 0.10 his head snaps back, eyes squeeze shut, mustache flares, chest caves, the near fist flies up and the front boot lifts. Hold 0.20, recover to neutral in 0.45. He keeps hold of the baton and cap.'),
 ('109-cop-knockback','stand','A heavy knockback, performed twice.',SOLID+'At 0.40 and 2.80 seconds a big blow from screen-right: he bends in half, both boots leave the ground briefly, lands crouched on one knee with the near hand on the floor, shakes his head, and stands back to neutral within 1.8 seconds.'),
 ('110-cop-death-back','small','A single cartoon defeat falling backward.','He is drawn small with wide empty space around him and stays that size. Neutral until 0.4. Struck from screen-right: arms fly up, he tips stiffly backward toward screen-left and lands flat on his back by 1.2, one small bounce, boots up then down. The baton drops beside him. From 1.8 he lies completely still, cap beside his head, fully inside the frame.'),
 ('111-cop-death-front','small','A single cartoon defeat collapsing forward.','He is drawn small with wide empty space around him and stays that size. Neutral until 0.4. His knees buckle, he drops to kneeling by 0.9, sways, then falls face down toward screen-right by 1.6 with a small bounce. The baton rolls out of his hand. From 2.1 he lies completely still, fully inside the frame.'),
 ('112-cop-stunned','stand','A seamless looping dazed stun.',SOLID+'He is dizzy on his feet: head rolling in slow circles, eyes crossed and half closed, knees loose, body swaying left and right, baton hanging limp by his leg. Feet planted. First and last frames match.'),
 ('113-cop-frozen','stand','Being frozen stiff.',SOLID+'Neutral until 0.4. He shivers violently, hugging himself with the near arm, teeth clenched, until 1.2, then snaps rigid: eyes wide, baton stuck half raised, one boot lifted slightly. From 1.4 to 5.0 he does not move at all, not one pixel.'),
 ('114-cop-sick','stand','A seamless looping sickness.',SOLID+'Poisoned: hunched over holding his belly with the near hand, cheeks puffed, skin slightly green, swaying and gagging in slow waves, baton drooping. Feet planted. First and last frames match.'),
 ('115-cop-hypnotized','stand','A seamless looping mind-controlled walk in place.',SOLID+'A stiff zombie-like walk in place: wide blank staring eyes, mouth slack, near arm stretched straight out toward screen-right, baton lowered, slow even steps. Head level.'),
 ('116-cop-tazed','tazed','A seamless looping electrocution seen as an X-ray.',SOLID+'In every frame he stays in this exact splayed X-ray pose, trembling in short stiff jerks: fingers twitching, jaw chattering, knees and boots shaking, cap rattling. Bones, cap, mustache, belt, boots and baton stay drawn exactly as in <Picture 1>. First and last frames match.','Only a thin even cyan glow hugging his outline. NO lightning bolts, arcs or sparks separate from his body.'),
 ('117-cop-burning','stand','A seamless looping panic while on fire.',SOLID+'In every frame after 0.3 small flames burn on his cap, shoulders, elbows and boots. He flails both arms, mouth open shouting, hopping from foot to foot on the spot. Flames flicker but stay the same size and attached to the same places; his face stays visible.','Flames stay small and attached to him. NO smoke clouds, loose embers or separate floating flames.'),
 ('118-cop-disguised-fooled','stand','Looking around confused after losing sight of the villain.',SOLID+'He lowers the baton, scratches the back of his cap with the near hand, looks to screen-left with just his head, looks back to screen-right, shrugs, and returns to neutral by 4.0. Hold.'),
]


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    reference(refs/'cop.png',500,690);reference(refs/'cop-small.png',340,650,300)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    shock=Image.open(SOURCE.parent/'shocked cop.png').convert('RGB').resize((690,690),Image.Resampling.LANCZOS)
    canvas=Image.new('RGB',(768,768),shock.getpixel((4,4)));canvas.paste(shock,(39,39));canvas.save(refs/'cop-tazed.png')
    rows=[]
    for shot in SHOTS:
        ident,size,summary,action=shot[:4];text=prompt(summary,action,*shot[4:])
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':{'stand':'cop.png','small':'cop-small.png','tazed':'cop-tazed.png'}[size],
            'item_reference':'proxy-grip.png','motion_reference':None,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
