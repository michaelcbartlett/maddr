"""Full-body animation set for the detective. The aim sweep supplies every firing elevation. Never queues."""
import shutil
import sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK.parent/'detective'
CLEAN='No muzzle flash, bullets, smoke, sparks, stars, dust, speed lines, glow, impact marks, blood or particles of any kind; the game adds effects. The revolver is an inert toy prop that never emits anything.'
SOLID='He stays exactly in place horizontally; the game moves him. '
READY='Both hands hold the revolver forward in a two-handed grip, as in <Picture 1>. '


def reference(source,path,height,ground,left=None):
    image=Image.open(source).convert('RGB').resize((1254,1254),Image.Resampling.NEAREST);backdrop=image.getpixel((1200,1200))
    pixels=np.asarray(image).copy()
    pixels[130:374,1070:1200]=backdrop                       # painted smoke above the barrel
    near=(np.abs(pixels.astype(int)-backdrop).max(axis=2)<24).astype(np.uint8)
    _,labels=cv2.connectedComponents(near,connectivity=4)
    edge=set(np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1]))))-{0}
    pixels[np.isin(labels,list(edge))]=backdrop
    ys,xs=np.where(np.abs(pixels.astype(int)-backdrop).max(axis=2)>0)
    figure=Image.fromarray(pixels[ys.min():ys.max()+1,xs.min():xs.max()+1]);scale=height/figure.height
    figure=figure.resize((round(figure.width*scale),height),Image.Resampling.NEAREST)
    canvas=Image.new('RGB',(768,768),backdrop);canvas.paste(figure,((768-figure.width)//2 if left is None else left,ground-height));canvas.save(path)


def prompt(summary,action,extra=CLEAN):
    return f'''subject_definitions:
<Subject 1> is the cartoon detective in <Picture 1>, exactly as drawn there.
<Picture 2> is a color swatch only. Its object must NOT appear.

summary:
[reference generation] {summary}

retention_analysis:
<Picture 1> (character appearance): fully_preserved - oversized head, brown fedora with dark purple band, messy brown hair, X-shaped cheek scar, thick scowling eyebrows, stubble, tan trench coat with turned-up collar, buttons and loose belt, white shirt, dark red tie, badge on a neck chain, dark trousers, brown shoes, blue-steel revolver, palette, thick black outlines, pixel-art style and scale.
<Picture 2> (swatch): not_preserved - never show it.

detailed_description:
One detective, full body, three-quarter SCREEN-RIGHT-facing view in every frame. Exactly one revolver, always the same size and shape.

{action}

{extra}

Keep the same face, costume details, limb lengths, head size and body scale in every frame. The fedora stays on unless stated. No extra weapons, badges, limbs or fingers. No turning to face the camera.

Locked orthographic-style camera, identical position, zoom and framing. Full body, hat, coat and revolver always inside the frame with margin. No pan, orbit, cuts, crossfades or reframing. Flat uniform dark blue-gray background. Sharp individual frames with crisp pixel edges and stable colors. No motion blur, ghost trails, frame blending, added texture, text or logos.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''


SHOTS=[
 ('121-det-idle','stand','A seamless looping relaxed idle.',SOLID+'He stands with the revolver lowered in his far hand beside his leg, near hand in his coat pocket, breathing slowly, coat tails swaying slightly. Feet planted. First and last frames match.'),
 ('122-det-walk','stand','A seamless looping walk cycle in place.',SOLID+'A slow suspicious walk, about one full stride per second, revolver held low and ready in the far hand, near arm swinging gently, coat tails swaying. Clear alternating planted feet. Head level.'),
 ('123-det-run','stand','A seamless looping run cycle in place.',SOLID+'A determined run leaning forward, about two full strides per second, revolver held up by his shoulder, near hand holding his fedora on, coat tails streaming toward screen-left.'),
 ('124-det-aim-walk','stand','A seamless looping walk in place while aiming.',SOLID+READY+'He advances with careful short steps, about one stride per second, knees bent, arms and revolver perfectly level and steady, coat swaying. Head and gun stay at the same height.'),
 ('125-det-draw','stand','Drawing and lowering the revolver.',SOLID+'Start with the revolver lowered beside his leg until 0.6. He snaps it up into the two-handed aim toward screen-right by 1.0, holds perfectly still until 3.0, lowers it again by 3.8 and holds.'),
 ('126-det-aim-sweep','stand','A slow full aiming sweep.',SOLID+READY+'Feet and hips stay planted while both straight arms, shoulders and head tilt together so the revolver points along the aim. 0.0-0.5 hold pointing steeply DOWN toward screen-right and the floor. 0.5-4.3 sweep slowly and evenly up through level to pointing steeply UP toward the upper right. 4.3-5.0 hold. His eyes always look along the barrel.'),
 ('127-det-shoot','stand','A level revolver recoil, repeated three times.',SOLID+READY+'Aim level. At 0.75, 2.25 and 3.75 seconds a quick kick: the barrel jumps up about twenty degrees, elbows bend, shoulders rock back, hat brim and coat tails jolt; everything settles to exactly the same level aim within 0.45 seconds.'),
 ('128-det-reload','stand','Reloading the revolver, once.',SOLID+'From the two-handed aim he swings the cylinder open, tips the gun up, taps it empty, thumbs in fresh rounds with the near hand, flicks the cylinder shut with a wrist snap at 3.2, and returns to the level aim by 3.8. Hold.'),
 ('129-det-alert','stand','Spotting the villain.',SOLID+'Relaxed with the revolver low until 0.5. He narrows his eyes, leans forward, tips up the brim of his fedora with the near thumb at 1.1, then raises the revolver into the two-handed aim by 1.8 and holds.'),
 ('130-det-dodge','stand','A short evasive sidestep in place, performed twice.',SOLID+'At 0.5 and 2.8 seconds: he ducks low and leans sharply back toward screen-left, coat flaring, revolver tucked to his chest, holds 0.25, then rises back into the level aim within 0.7 seconds.'),
 ('131-det-hurt','stand','A quick hit reaction, repeated three times.',SOLID+'From the level aim, at 0.40, 1.95 and 3.50 seconds he is struck from screen-right: within 0.10 his head snaps back, eyes shut, teeth clenched, hat jolts, arms drop, front foot lifts. Hold 0.20, recover to the level aim in 0.50.'),
 ('132-det-knockback','stand','A heavy knockback, performed twice.',SOLID+'At 0.40 and 2.80 seconds a big blow from screen-right: he folds at the waist, both feet leave the ground briefly, lands on one knee with the near hand on the floor, shakes his head, and rises to the level aim within 1.8 seconds.'),
 ('133-det-death-back','small','A single cartoon defeat falling backward.','He is drawn small with wide empty space around him and stays that size. Neutral until 0.4. Struck from screen-right, he clutches his chest, staggers one step, and falls flat on his back toward screen-left by 1.6 with one small bounce. The revolver drops beside him and the fedora lands on his chest. From 2.2 he lies completely still, fully inside the frame.'),
 ('134-det-death-front','small','A single cartoon defeat collapsing forward.','He is drawn small with wide empty space around him and stays that size. Neutral until 0.4. His knees buckle, he drops to kneeling by 1.0, the revolver slips from his hand, his hat falls off, and he falls face down toward screen-right by 1.8 with coat spread over him. From 2.3 he lies completely still, fully inside the frame.'),
 ('135-det-stunned','stand','A seamless looping dazed stun.',SOLID+'Dizzy on his feet: head rolling in slow circles, eyes crossed and half closed, hat tilted, knees loose, body swaying, revolver hanging limp by his leg. Feet planted. First and last frames match.'),
 ('136-det-frozen','stand','Being frozen stiff.',SOLID+'Neutral until 0.4. He shivers violently, collar up, hugging himself, teeth clenched, until 1.2, then snaps rigid mid-aim with eyes wide. From 1.4 to 5.0 he does not move at all, not one pixel.'),
 ('137-det-sick','stand','A seamless looping sickness.',SOLID+'Poisoned: hunched over holding his belly with the near hand, cheeks puffed, skin slightly green, swaying and gagging in slow waves, revolver drooping. Feet planted. First and last frames match.'),
 ('138-det-hypnotized','stand','A seamless looping mind-controlled walk in place.',SOLID+'A stiff zombie-like walk in place: wide blank staring eyes, mouth slack, near arm stretched toward screen-right, revolver lowered, slow even steps.'),
 ('139-det-tazed','stand','A seamless looping electrocution seen as an X-ray.',SOLID+'In every frame after 0.3 he is rigid with arms and legs splayed, trembling in short stiff jerks. His body shows as a cartoon X-ray: white skeleton bones inside a black silhouette, while fedora, face, coat edges, badge, shoes and revolver stay drawn normally. The skeleton drawing stays consistent.','Only a thin even cyan glow hugging his outline. NO lightning bolts, arcs or sparks separate from his body.'),
 ('140-det-burning','stand','A seamless looping panic while on fire.',SOLID+'In every frame after 0.3 small flames burn on his hat, shoulders, coat hem and shoes. He flails, mouth open shouting, hopping from foot to foot on the spot, revolver still in one hand. Flames flicker but stay the same size and attached to the same places; his face stays visible.','Flames stay small and attached to him. NO smoke clouds, loose embers or separate floating flames.'),
 ('142-det-backpedal','stand','A seamless looping backward walk in place while aiming.',SOLID+READY+'He backs away from what he aims at: careful reversed steps, about one stride per second, knees bent, weight leaning back toward screen-left, revolver level and steady toward screen-right, worried scowl.'),
 ('143-det-flee','stand','A seamless looping panicked run in place.',SOLID+'A frightened all-out run toward screen-right, about two and a half strides per second, leaning far forward, near hand clamping the fedora on his head, revolver waving in the far hand, mouth open, coat streaming toward screen-left. Twice he glances back toward screen-left by turning only his head for a moment.'),
 ('144-det-cornered','stand','A cornered last-ditch shot, performed twice.',SOLID+'At 0.4 and 2.8 seconds: he skids to a stop, spins his shoulders toward screen-right, throws up the near arm to shield his face, squeezes his eyes shut and thrusts the revolver out one-handed; a small recoil kick at 1.0 after the start; he flinches, then settles into the two-handed level aim within 1.9 after the start.'),
 ('141-det-fooled','stand','Losing sight of the villain.',SOLID+'He lowers the revolver, rubs his stubble with the near hand, pulls a small notepad from his coat and frowns at it, puts it away, shrugs, and returns to the level aim by 4.4. Hold.'),
]


def main():
    source=Path(sys.argv[1]) if len(sys.argv)>1 else OUT/'references/source.png'
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    if source!=refs/'source.png':Image.open(source).convert('RGB').save(refs/'source.png')
    reference(refs/'source.png',refs/'det.png',500,690);reference(refs/'source.png',refs/'det-small.png',330,650,260)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    rows=[]
    for shot in SHOTS:
        ident,size,summary,action=shot[:4];text=prompt(summary,action,*shot[4:])
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':'det.png' if size=='stand' else 'det-small.png',
            'item_reference':'proxy-grip.png','motion_reference':None,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print(len(queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))),'jobs')


if __name__=='__main__':main()
