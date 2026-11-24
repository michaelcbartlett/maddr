"""Prepare reference-conditioned K9 clips using the quadruped guides. Never queues."""
from pathlib import Path
import argparse
import shutil
import cv2
import numpy as np
from PIL import Image
import quadruped_motion as quad
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK.parent/'attack-dog'
SOURCE=Path.home()/'Downloads/attack dog.png'
CLEAN='No other character, handler, leash, target, blood, wound, gore, floating symbols, lightning bolts, particles, dust or smoke. The game supplies external effects.'
STILL='Perform in place; the game supplies horizontal travel. '

# ID, guide, size, short description, appearance/action beyond the calibration motion.
SHOTS=[
 ('201-k9-idle','idle','stand','A seamless alert idle.','Subtle breathing, eyes scanning, mouth gently panting, ears twitch once. No walking. First and last poses match.'),
 ('202-k9-walk','walk','stand','A seamless four-beat walk in place.','Follow the four separate leg contact tracks: a relaxed four-beat walk, five complete strides in five seconds. Paws lift cleanly and plant in order, head steady, harness attached to torso. End at the starting gait phase.'),
 ('203-k9-trot','trot','stand','A seamless diagonal-pair trot in place.','Near foreleg and far hind leg move together, opposite pair half a cycle later. Eight complete strides in five seconds. Springy but controlled torso, clear foot plants. End at starting gait phase.'),
 ('204-k9-run','run','stand','A seamless fast gallop in place.','Follow the offset fore/hind leg timing and airborne phases in the guide: ten strides in five seconds. Hind legs drive, front legs reach then gather, paws tuck when airborne. Harness stays rigidly fitted; do not stretch its lettering. Match the loop phase.'),
 ('205-k9-start-stop','start-stop','stand','Starting and stopping a walk.','Neutral to 0.45, weight shift and step into a walk by 0.85, walk to 2.6, plant and brake by 3.2, stand alert through 5.0. No skate, camera movement or screen travel.'),
 ('206-k9-alert-bark','bark','stand','Four short warning barks.','At 0.5, 1.6, 2.7 and 3.8 seconds, ears prick, jaw opens wide then closes, throat and chest tense. All four paws stay planted. Do not draw sound-wave symbols; silent footage.'),
 ('207-k9-bite','bite','stand','Two forward snapping bites.','At 0.4 and 2.7, head pulls back for anticipation, jaw opens, then neck and muzzle snap forward and jaw closes sharply at the bite; recover alert. Bite empty air with no victim or object. Keep canine jaw hinge and teeth consistent.'),
 ('208-k9-pounce','pounce','stand','Two pounce-and-bite attacks with landing.','At 0.4 and 2.8 crouch on all four legs, hindquarters load, push into a short upward hop. Front paws reach toward screen-right, hind paws tuck; jaw opens and snaps, land front paws then hind paws, absorb with elbows and hocks, recover. No horizontal root travel; game adds attack displacement. Entire head, tail and paws stay in frame.'),
 ('209-k9-hurt','flinch','stand','Two short startled flinches.','Act alone: head recoils, ears flatten briefly, knees flex, recover within 1.55 seconds after each start at 0.4 and 2.8. No incoming blow, projectile or attacker.'),
 ('210-k9-stagger','stagger','stand','Two heavy four-legged staggers.','At 0.4 and 2.8 shoulders dip, front elbows buckle, head jerks back, hind legs brace, recover to all four paws. Do not kneel like a human or grow hands.'),
 ('211-k9-stunned','stunned','stand','A seamless dazed four-paw stance.','Head droops and sways, ears relax, legs wobble with all paws grounded. Dazed eyes. Keep the canine spine horizontal, no standing upright or floating stars. Match start and end.'),
 ('212-k9-frozen','frozen','stand','Shivering then a perfectly still freeze.','Alert until 0.4, shiver to 1.2 and stop by 1.35. From 1.35 to 5.0 hold perfectly still including ears, tail and pixels. No ice cube or separate crystals; the game adds frost.'),
 ('213-k9-sick','stunned','stand','A seamless queasy loop.','Hunch, head low, ears drooping, visible muzzle skin slightly green, gag with small jaw movements; four paws remain grounded. No vomit or gas. Match start and end.'),
 ('214-k9-hypnotized','walk','stand','A seamless mind-controlled walk.','Vacant wide eyes, stiff neck, level ears and tail, slow deliberate walking following the four-leg guide. Never extend a human arm. Five strides in five seconds; loop cleanly.'),
 ('215-k9-tazed','stunned','stand','A seamless cartoon electrical tremble.','Four-legged stance, legs and jaw trembling, ears rigid, eyes wide. A stylized cyan-white canine X-ray skeleton only within the body; dog-shaped ribcage, four legs, canine skull and tail, no human skeleton. The harness remains opaque. No separate lightning effects. Match start and end.'),
 ('216-k9-burning','run','stand','A seamless on-fire panic run in place.','Run frantically on four legs following the gallop guide, eyes alarmed. Small flames attached to harness edges and tail tip only, no embers or smoke; keep face and paws readable. No human arm flailing. Match body pose at the loop boundary.'),
 ('217-k9-search','search','stand','Searching and sniffing after losing the target.','Follow the head dips in the guide, sniff the empty air, glance with eyes, ears swivel separately, return to the initial alert stance by 4.2 and hold. Keep body facing screen-right.'),
 ('218-k9-retreat','retreat','stand','A seamless cautious backward walk.','Backpedal on four paws while still facing screen-right. Head toward the threat, ears back, measured reverse paw placement. Root stays fixed and game supplies backward travel. Five strides in five seconds; loop.'),
 ('219-k9-death-front','collapse-front','small','One forward cartoon collapse.','Keep small reference scale and wide margins. Neutral to 0.4, front elbows buckle, chest sinks, chin lowers, hind legs fold. Settle on belly with head low by 1.9 and lie entirely still through 5.0. Harness stays attached. No wounds or gore.'),
 ('220-k9-death-side','collapse-side','small','One sideways cartoon defeat.','Keep small reference scale and wide margins. Neutral to 0.4, legs buckle, roll slightly onto the near side and settle with all four legs folded by 1.9. Head and tail droop, no getting up, completely still through 5.0. Follow guide compression/timing; allow the slight side roll without rotating camera. No wounds or gore.'),
 ('221-k9-death-poison','collapse-side','small','One poison collapse.','Keep small reference scale. Neutral to 0.4, muzzle skin turns green, queasy shudder; legs give way and fold as guided, settle on the near side by 1.9. Completely still after 2.3. No vomit, wound or gore.'),
 ('222-k9-death-ash',None,'small','One cartoon charred collapse into ash.','Keep small reference scale and generous margins. Neutral to 0.3. Fur and harness darken to sooty black by 1.2; two white eyes blink. Hold, then at 2.4 the silhouette crumbles straight down into a compact gray ash pile by 3.2, blackened harness settles on top. Completely still after 3.4. No flames, airborne ash, skeleton, wound or gore.'),
]


def reference(source,path,small=False):
    image=Image.open(source).convert('RGB').resize((1445,1089),Image.Resampling.NEAREST).crop((105,90,1342,981))
    rgb=np.asarray(image).copy();r,g,b=rgb.astype(np.int16).transpose(2,0,1)
    # Only edge-connected dark-blue backdrop, preserving black outlines and navy harness.
    candidate=((g>r+2)&(b>g+2)&(r<44)&(b<75)).astype(np.uint8)
    _,labels=cv2.connectedComponents(candidate,connectivity=4)
    edge=np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])))
    rgb[np.isin(labels,edge[edge!=0])]=quad.BG
    height=288 if small else 400;ground=625 if small else 680
    figure=Image.fromarray(rgb).resize((round(image.width*height/image.height),height),Image.Resampling.NEAREST)
    canvas=Image.new('RGB',(768,768),quad.BG);canvas.paste(figure,((768-figure.width)//2,ground-height));canvas.save(path)


def prompt(summary,action,guide,ident):
    motion=('\n<Video 1> defines only four-legged pose, joint movement, timing, contact and framing. Never copy the colored mannequin, ear shapes, limb thicknesses or its appearance.' if guide else '')
    retain=('\n<Video 1>: partially_preserved - canine leg order, elbow/stifle/hock movement, paw contacts, jaw timing and grounded body motion only.' if guide else '')
    change=('Preserve identity until the explicitly described ash transformation begins.' if 'death-ash' in ident else 'Preserve head size, body proportions, fur pattern, paw size and fitted harness throughout.')
    clean=CLEAN
    if 'burning' in ident:clean=CLEAN.replace('particles, dust or smoke','loose flames, embers, particles, dust or smoke')
    return f'''subject_definitions:
<Subject 1> is the ONE police German shepherd in <Picture 1>, exactly as drawn.
<Picture 2> is a calibration swatch only. Its object must NOT appear.{motion}

summary:
[reference generation] {summary}

retention_analysis:
<Picture 1>: fully_preserved - black-and-tan fur layout, oversized alert head, long muzzle, upright ears, bushy curved tail, four canine legs and paws, navy police harness, back handle, straps, pouches, yellow tabs and existing POLICE/MTA patches, chunky pixel clusters, thick black outlines, palette and original three-quarter screen-right view.
<Picture 2>: not_preserved - never show the calibration object.{retain}

detailed_description:
One full-body German shepherd, facing SCREEN-RIGHT throughout. Four legs only: two front legs with backward-bending elbows and wrists, two hind legs with forward stifles then rear hocks and paws. Near and far legs remain attached to their original shoulder/hip sockets. The neck supports the head; lower jaw hinges below the skull. Tail has a continuous chain from the rump. No human knees, hands, upright biped stance, duplicated paws, swapped legs or rubber limbs. Preserve the original character's proportions; the guide is motion only.

{STILL if 'death-' not in ident else ''}{action}

{clean}
{change} Keep existing harness markings stable; add no labels, collar, weapon or accessories. Do not detach the harness, slide the shoulder sockets or change the number of legs. Harness follows torso, not the swinging leg. During ordinary locomotion the spine stays horizontal and the jaw/head do not turn into a human face.
Fixed orthographic-style camera and original three-quarter view, identical position, size and zoom. Whole ears, muzzle, tail, all four paws and flames if specified stay inside the canvas with margin. No pan, orbit, cuts, crossfades or scale drift. Uniform flat dark blue-gray background, no ground shadow, floor texture or scenery. Crisp separate pixel-art frames, no motion blur, ghost trails, frame blending, smoothing, added texture or crawling colors.

overall_soundscape:
Silent. No barking audio, speech, sound effects or music.

non_diegetic_music:
N/A'''


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',type=Path,default=SOURCE)
    args=parser.parse_args()
    if not args.source.is_file():parser.error('Missing supplied dog reference: '+str(args.source))
    if not (quad.OUT/'motion-catalog.json').exists():quad.build()
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True);shutil.copy2(args.source,refs/'source.png')
    reference(args.source,refs/'dog.png');reference(args.source,refs/'dog-small.png',True)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ('queue-api-template.json','queue-workflow-template.json'):shutil.copy2(PACK/name,OUT/name)
    rows=[]
    for ident,guide,size,summary,action in SHOTS:
        motion='guide-'+guide+('-small' if size=='small' else '')+'.mp4' if guide else None
        if motion:shutil.copy2(quad.OUT/'organic'/motion,refs/motion)
        text=prompt(summary,action,guide,ident)
        rows.append(dict(id=ident,seconds=5,fps=24,subject_reference='dog-small.png' if size=='small' else 'dog.png',
                         item_reference='proxy-grip.png',motion_reference=motion,prompt=text))
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'),steps=16)
    print(f'Prepared {len(jobs)} K9 clips, 110 seconds at 24fps. No generation jobs submitted.')


if __name__=='__main__':main()
