"""Prepare the riot officer's full-body H3 pack. Builds references/guides, never queues."""
from pathlib import Path
import argparse
import math
import shutil
import av
import cv2
import numpy as np
from PIL import Image, ImageDraw
from build_h3_sprite_pack import PACK, PALETTE
import queue_h3_animations as queue

OUT = PACK.parent / 'swat-shield'
SOURCE = Path.home() / 'Downloads/riot police.png'
BG = (22, 29, 40)
CLEAN = 'No sparks, stars, smoke, dust, speed lines, flashes, impact marks or loose particles; the game adds effects. No other character or target.'
STILL = 'His root stays in place; the game supplies horizontal movement. '
GUARD = 'Shield held upright in the far/screen-right hand, covering chest and abdomen, top just below his eyes; visor and eyes remain visible. Baton stays in the near/screen-left hand. '
ROOM = 'Keep the small reference scale, ground line and generous empty margins throughout the fall. '


def reference(source, path, height, ground):
    # Conditioning only: preserve the supplied design and save the untouched original too.
    image = Image.open(source).convert('RGB')
    image = image.resize((1445, 1089), Image.Resampling.NEAREST).crop((220, 8, 1152, 1065))
    pixels = np.asarray(image).copy()
    # Flatten only edge-connected blue background. Keep black outlines and armor grays.
    r, g, b = pixels.astype(np.int16).transpose(2, 0, 1)
    candidate = ((g > r + 2) & (b > g + 2) & (r < 42) & (b < 70)).astype(np.uint8)
    _, labels = cv2.connectedComponents(candidate, connectivity=4)
    edge = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    pixels[np.isin(labels, edge[edge != 0])] = BG
    figure = Image.fromarray(pixels).resize((round(image.width * height / image.height), height), Image.Resampling.NEAREST)
    canvas = Image.new('RGB', (768, 768), BG)
    canvas.paste(figure, ((768 - figure.width) // 2, ground - height))
    canvas.save(path)


def prompt(summary, action, size='stand', guide=None, grenade=False, transformed=False, extra=CLEAN):
    item = ('<Picture 2> defines only the small olive grenade with a metal safety lever. It appears only while held in the throwing action; never copy its background.' if grenade else
            '<Picture 2> is a calibration color swatch only; its object must NOT appear.')
    motion = ('\n<Video 1> defines joint movement, shield height, timing and framing only. Never render the colored mannequin or copy its colors.' if guide else '')
    retention = ('\n<Video 1>: partially_preserved - pose and rigid prop motion only.' if guide else '')
    clamp = ('Preserve his identity and equipment until the explicitly described transformation begins.' if transformed else
             'Keep face, armor panels, helmet, visor, shield size, baton length, limb lengths and body scale consistent throughout.')
    return f'''subject_definitions:
<Subject 1> is the one armored riot officer in <Picture 1>, exactly as drawn.
{item}{motion}

summary:
[reference generation] {summary}

retention_analysis:
<Picture 1>: fully_preserved - stocky proportions, oversized navy helmet, clear rigid visor, eyebrows and eyes, black face mask, navy armor and pouches, NYPD chest and shoulder patches, black gloves and boots, short straight black baton, tall rigid slate-gray riot shield with its existing NYPD panel, chunky pixel clusters, thick black outlines and palette.
<Picture 2>: {'partially_preserved - held grenade shape and colors only.' if grenade else 'not_preserved - never show the calibration object.'}{retention}

detailed_description:
One full-body riot officer in the original three-quarter SCREEN-RIGHT-facing view. Fixed equipment handedness: the near arm, originating on screen-left of the torso, holds the baton; the far arm, originating on screen-right, holds the shield. These are the same physical hands in every frame. Do not mirror him, exchange hands, turn his body or hide the head inside the shield. Shoulder joints stay attached to the same places on the torso. The rigid shield moves as one solid object and does not bend, shrink, dissolve into his body or grow another hand.

{action}

{extra}

{clamp} Do not add a rifle, pistol, second shield, second baton or extra limbs. Preserve existing NYPD markings without adding new lettering. Both props stay held unless the action explicitly releases or stows them. The shield can occlude his far forearm but cannot cut through his face or near baton arm.
Locked orthographic-style camera: identical position, zoom and size, no orbit, pan, cuts, crossfades or reframing. Whole helmet, feet and all held or dropped props remain inside the frame with margin. Uniform flat dark blue-gray background, no ground shadow, scenery or floor texture. Crisp separate pixel-art frames; no motion blur, ghosting, frame blending, texture crawling or smoothing.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''


# All clips are five seconds at 24fps. Deaths use a smaller reference, not a camera zoom.
SHOTS = [
 ('171-swat-guard-idle', 'stand', 'A seamless shield-up guard idle.', STILL + GUARD + 'Feet planted, subtle breathing and one blink; no pumping of the shield. First and last poses match.'),
 ('172-swat-guard-walk', 'stand', 'A seamless shield-up walking cycle.', STILL + GUARD + 'Walk in place for five complete strides in five seconds. Clear alternating foot plants and bent knees, compact cautious steps. Shield remains raised throughout; baton tucked beside the near hip. Start and end at the same gait phase.', 'walk'),
 ('173-swat-guard-run', 'stand', 'A seamless armored advance in place.', STILL + GUARD + 'A compact heavy jog, eight complete strides in five seconds; both boots briefly airborne, knees alternating, forward lean. Shield braced high throughout, baton tucked safely by the near shoulder. End at the starting gait phase.'),
 ('174-swat-start-stop', 'stand', 'Starting and stopping a shield-up walk.', STILL + GUARD + 'Hold until 0.5. Shift weight, push off and take cautious alternating steps by 0.85. Walk until 2.6, plant the lead boot and brake by 3.1; recover the starting guard by 3.6 and hold.'),
 ('175-swat-alert', 'stand', 'Spotting a threat and bracing.', STILL + 'Begin with shield at the hip. At 0.4 eyes widen, knees bend and shield rises in front of the chest by 0.85. Scowl and brace until 2.5; lower to the starting stance by 3.4 and hold. No pointing or extra person.'),
 ('176-swat-shield-raise', 'stand', 'Raising the shield into guard, twice.', STILL + 'At 0.4 and 2.7 raise the far-hand shield from its low hip carry to upright chest-height guard in 0.4 seconds; top below the eyes. Hold 0.5, lower smoothly in 0.4, settle. The near-hand baton stays low. No strike.', 'raise'),
 ('177-swat-shield-lower', 'stand', 'Lowering the shield to expose a baton attack opening, twice.', STILL + GUARD + 'At 0.4 and 2.7 lower the shield to the far hip in 0.35, rotate it slightly outward so the near arm has a clear striking path; hold 0.55, return to high guard in 0.4. Baton stays in the near hand without swinging.', 'lower'),
 ('178-swat-baton-strike', 'stand', 'Shield down, one powerful baton strike, shield back up; twice.', STILL + GUARD + 'At 0.4 and 2.7: lower shield to far hip in 0.3; lift near-hand baton above the near shoulder in 0.25, hold anticipation 0.15; snap it down and forward toward screen-right in 0.12, then low follow-through 0.18. Recover baton beside the near hip and raise shield to guard in 0.5. Baton remains straight and fully visible; shield never blocks its path. Return to starting guard before the next repetition.', 'strike'),
 ('179-swat-baton-combo', 'stand', 'Shield down, downward swing and rising backhand, shield up; twice.', STILL + GUARD + 'At 0.3 and 2.7: lower shield to far hip in 0.25; lift baton above the near shoulder in 0.25, hold 0.15; downward swing 0.12 with low follow-through 0.15, rising backhand sweep 0.2, brief high hold 0.15, recover and raise shield in 0.5. Keep shield away from the near arm for both swings.', 'combo'),
 ('180-swat-shield-bash', 'stand', 'A short shield shove and recovery, twice.', STILL + GUARD + 'At 0.5 and 2.8 brace both boots, pull the shield close to the chest for 0.25, thrust the whole shield straight toward screen-right in 0.15 with a small torso lean, hold 0.2, return to guard in 0.5. Shield stays rigid and upright; the baton stays in its near hand. He acts alone.'),
 ('181-swat-grenade-throw', 'stand', 'One readable grenade throw, then return to shield guard.', STILL + GUARD + 'Hold guard until 0.3. Tuck the far-hand shield close at the far hip; stow the baton visibly in the near-side belt loop by 0.7. The now-empty near hand retrieves ONE small olive grenade matching Picture 2 by 1.0. Pin removal is implied; do not use the shield hand. Draw the throwing elbow back, grenade beside the helmet at 1.25, hold anticipation to 1.45. Throw overarm toward screen-right; the near hand opens at 1.6. The held grenade is absent from the first open-hand frame onward; the game supplies the flying projectile. Do not draw a flying grenade or explosion. Follow through until 1.95, retrieve the baton from the same belt loop by 2.6, raise shield to guard by 3.2 and hold to 5.0. No duplicate or morphing props.', 'grenade'),
 ('182-swat-shield-block', 'stand', 'Three self-contained shield block reactions.', STILL + GUARD + 'At 0.4, 1.95 and 3.5 mime resistance against the shield: rigid shield jerks inward a little, bracing elbow compresses, torso and knees absorb the force, one short backward weight shift, recover within 0.8. No incoming projectile, attacker, hit flash or shield damage.'),
 ('183-swat-guard-break', 'stand', 'The shield guard opens and recovers, twice.', STILL + GUARD + 'At 0.4 and 2.7 mime losing balance: shield arm flung outward and low, chest exposed, head jerks back, front boot lifts. Hold the exposed pose 0.35, wobble, then pull shield back to guard by 1.8 after each start. Do not drop shield or baton.'),
 ('184-swat-hurt', 'stand', 'Three unshielded startled flinches.', STILL + 'Shield low at far hip. At 0.4, 1.95 and 3.5 mime a sudden flinch: head snaps back, eyes squeeze shut, chest caves, shoulders jump, near elbow rises while retaining baton, front boot lifts. Hold 0.2 and recover in 0.45. Nothing touches him; no attacker appears.'),
 ('185-swat-knockback', 'stand', 'A heavy stagger to one knee and recovery, twice.', STILL + 'At 0.4 and 2.8 double over, both boots briefly hop backward, land on one knee, shield edge resting on the ground. Shake helmet slowly, push back to standing guard within 1.8 seconds. Both props stay held, no sliding root or unseen attacker.'),
 ('186-swat-stunned', 'stand', 'A seamless dazed idle.', STILL + 'Shield droops to far hip, baton hangs at near side; knees loose, eyes unfocused, head rolling gently, body swaying. Feet planted, equipment retained. First and last poses match.'),
 ('187-swat-frozen', 'stand', 'Shivering and freezing into a held pose.', STILL + GUARD + 'Neutral until 0.4; shiver until 1.2, then freeze rigid with eyes wide and one heel raised. Hold perfectly still from 1.4 to 5.0. Do not add an ice cube or crystals; game supplies frost.'),
 ('188-swat-sick', 'stand', 'A seamless queasy loop.', STILL + 'Shield low; head and chest hunch, exposed skin slightly green, eyes squint; knees wobble in slow waves. He retains both props and does not use a third hand to hold his belly. No vomit or gas. Match start and end.'),
 ('189-swat-hypnotized', 'stand', 'A seamless mind-controlled walk.', STILL + 'Blank wide eyes behind visor, head level, slow stiff walk in place with three complete strides in five seconds. Shield held low and baton dangling, both in their original hands. No spirals drawn over the eyes. End at the starting gait phase.'),
 ('190-swat-tazed', 'stand', 'A seamless cartoon electrocution loop.', STILL + 'Limbs splayed but still holding both props, jaw chattering under mask, helmet and fingers trembling in short stiff jerks, knees shaking. A stylized cyan-white X-ray skeleton is visible only through his body beneath the armor; shield and baton stay opaque and rigid. No duplicate external skeleton. Match start and end.'),
 ('191-swat-burning', 'stand', 'A seamless on-fire panic.', STILL + 'Panic on the spot, wide eyes, hopping from boot to boot and shaking shield and baton without letting go. Small flames attached to helmet rim, shoulders and boots; keep face and shield visible. Match the first and last body poses.'),
 ('192-swat-fooled', 'stand', 'Searching after losing sight of the villain.', STILL + 'Lower shield, glance left with just the eyes and head, glance right, lift near shoulder in a confused shrug while retaining baton, return to high guard by 4.0 and hold. Body keeps its original view.'),
 ('193-swat-death-back', 'small', 'One backward cartoon defeat.', ROOM + 'Neutral until 0.4. Knees stiffen, arms fly up, topple toward screen-left onto his back by 1.5, bounce once. Release baton and shield as he falls; they land beside him fully within the frame, shield flat on the floor without covering his head. Helmet remains on. From 2.3 lie completely still. No wound or gore.'),
 ('194-swat-death-front', 'small', 'One forward cartoon collapse.', ROOM + 'Neutral until 0.4. Knees buckle, shield slips out of far hand and settles flat toward screen-right. Drop to knees, then tip face-down toward screen-right beside the shield by 1.8. Baton falls beside the near hand, helmet remains on. A small settling bounce, then completely still from 2.5. No wound or gore.'),
 ('195-swat-death-side', 'small', 'One sideways exhausted collapse.', ROOM + 'Neutral until 0.4. Whole body sways, knees give way and he folds onto his near side toward screen-left by 1.7, curled with knees bent. Shield and baton drop beside him, not through him. One small boot twitch at 2.2; completely still from 2.7. Keep the same camera and helmet. No wound or gore.'),
 ('196-swat-death-poison', 'small', 'One queasy poison defeat.', ROOM + 'Neutral until 0.3. Visible skin turns pea-green, eyes bulge, gag behind mask and wobble twice; both props slip from his hands and settle nearby. Knees give way, fall backward by 2.6, one foot twitch at 3.2, completely still from 3.6. Helmet and armor stay on. No vomit, wounds or gore.'),
 ('197-swat-death-melt', 'small', 'One cartoon wax-like melt.', ROOM + 'Neutral until 0.3. Look down at hands, turn sickly yellow-green. From 0.6 soften like wax: armor and body sag together, limbs elongate then collapse straight down into a small flat puddle of navy and green by 2.8. Rigid helmet, baton and shield remain solid and settle beside/on the puddle without melting. Completely still from 3.2. No skeleton, exposed tissue or gore.'),
 ('198-swat-death-ash', 'small', 'One cartoon charred collapse into ash.', ROOM + 'Neutral until 0.3. Body and armor darken to sooty black by 1.2; two white eyes blink behind visor. Hold, blink twice, cough once. At 2.4 crumble straight down into a compact dark-gray ash pile by 3.2. Helmet settles on top; blackened rigid shield and baton lie beside the pile. Completely still from 3.4. No fire, airborne ash, smoke, skeleton or gore.'),
]


def lerp_pose(a, b, k):
    k = k * k * (3 - 2 * k)
    return {name: tuple(x + (y - x) * k for x, y in zip(a[name], b[name])) if isinstance(a[name], tuple) else a[name] + (b[name] - a[name]) * k for name in a}


REST = dict(hand=(302, 533), elbow=(278, 486), shield=(472, 476), angle=22., lean=0., step=0., grenade=0.)
LOW = {**REST, 'shield': (485, 566)}
WIND = {**LOW, 'hand': (287, 327), 'elbow': (240, 394), 'angle': -115., 'lean': -6.}
HIT = {**LOW, 'hand': (440, 496), 'elbow': (365, 436), 'angle': 28., 'lean': 10.}
HIGH = {**LOW, 'hand': (412, 332), 'elbow': (333, 388), 'angle': -65., 'lean': 2.}


def guide_pose(kind, t):
    if kind == 'walk':
        return {**REST, 'step': math.sin(t * 2 * math.pi)}
    if kind == 'grenade':
        keys = [(0, REST), (.3, REST), (.7, {**LOW, 'angle': 90.}), (1., {**LOW, 'grenade': 1.}),
                (1.25, {**WIND, 'grenade': 1.}), (1.45, {**WIND, 'grenade': 1.}),
                (1.6, {**HIT, 'grenade': 2.}), (1.95, {**HIT, 'grenade': 2.}),
                (2.6, LOW), (3.2, REST), (5., REST)]
    else:
        start = (.3 if kind == 'combo' else .4) if t < 2.7 else 2.7
        local = t - start
        if kind == 'raise':
            keys = [(0, LOW), (.4, REST), (.9, REST), (1.3, LOW), (2.3, LOW)]
        elif kind == 'lower':
            keys = [(0, REST), (.35, LOW), (.9, LOW), (1.3, REST), (2.3, REST)]
        elif kind == 'strike':
            keys = [(0, REST), (.3, LOW), (.55, WIND), (.7, WIND), (.82, HIT), (1., HIT), (1.5, REST), (2.3, REST)]
        else:
            keys = [(0, REST), (.25, LOW), (.5, WIND), (.65, WIND), (.77, HIT), (.92, HIT), (1.12, HIGH), (1.27, HIGH), (1.77, REST), (2.4, REST)]
        t = local
    if t <= keys[0][0]: return keys[0][1]
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if ta <= t <= tb: return lerp_pose(a, b, (t - ta) / (tb - ta))
    return keys[-1][1]


def draw_guide(p):
    image = Image.new('RGB', (768, 768), BG); d = ImageDraw.Draw(image)
    lean = p['lean']; shoulder = (333 + lean, 439)
    def limb(a, b, color, width=27):
        d.line([a, b], fill=color, width=width)
        for x, y in (a, b): d.ellipse((x-width/2, y-width/2, x+width/2, y+width/2), fill=color)
    for side, x, sign in [('far', 415, -1), ('near', 355, 1)]:
        step = p['step'] * sign
        foot = (x + step * 29, 684 - max(0, step) * 20)
        knee = ((x + foot[0])/2, 605)
        limb((x, 555), knee, PALETTE[side+'_thigh'], 39); limb(knee, foot, PALETTE[side+'_shin'], 33)
        d.rectangle((foot[0]-23, foot[1]-10, foot[0]+28, foot[1]+8), fill=PALETTE[side+'_foot'])
    sx, sy = p['shield']
    limb((425+lean, 444), (sx-25, sy), PALETTE['far_upper_arm'])
    d.polygon([(326+lean, 421), (440+lean, 421), (434, 562), (337, 562)], fill=PALETTE['torso'])
    d.ellipse((324+lean, 267, 447+lean, 418), fill=PALETTE['head'])
    d.rectangle((346+lean, 339, 455+lean, 385), outline='#eeeeff', width=7)
    d.rounded_rectangle((sx-41, sy-101, sx+41, sy+101), radius=14, fill='#8c9aa4', outline='#d0d6e0', width=5)
    limb(shoulder, p['elbow'], PALETTE['near_upper_arm']); limb(p['elbow'], p['hand'], PALETTE['near_forearm'])
    hx, hy = p['hand']
    if p['grenade'] < .5:
        a = math.radians(p['angle']); end = (hx+85*math.cos(a), hy+85*math.sin(a))
        limb((hx-12*math.cos(a), hy-12*math.sin(a)), end, '#8a4a1c', 13)
    elif p['grenade'] < 1.5:
        d.ellipse((hx-14, hy-34, hx+14, hy-4), fill='#648440', outline='#d4d0b0', width=3)
    d.ellipse((hx-14, hy-14, hx+14, hy+14), fill=PALETTE['near_hand'])
    return image


def make_guide(kind, path):
    with av.open(str(path), 'w') as video:
        stream = video.add_stream('libx264', rate=24); stream.width = stream.height = 768
        stream.pix_fmt = 'yuv420p'; stream.options = {'crf': '12'}
        for i in range(120):
            for packet in stream.encode(av.VideoFrame.from_image(draw_guide(guide_pose(kind, i/24)))): video.mux(packet)
        for packet in stream.encode(): video.mux(packet)


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--source', type=Path, default=SOURCE)
    args = parser.parse_args(); refs = OUT/'references'; refs.mkdir(parents=True, exist_ok=True)
    if not args.source.exists(): parser.error('Missing source image: '+str(args.source))
    shutil.copy2(args.source, refs/'source.png')
    reference(args.source, refs/'swat.png', 430, 690); reference(args.source, refs/'swat-small.png', 305, 625)
    shutil.copy2(PACK/'references/proxy-grip.png', refs/'proxy-grip.png')
    # Geometric prop calibration plate, not final game art.
    prop = Image.new('RGB', (768,768), BG); d=ImageDraw.Draw(prop)
    d.rounded_rectangle((322,315,446,479), radius=47, fill='#556735', outline='#161c18', width=12)
    for y in (352,391,430): d.line((331,y,437,y), fill='#313e24', width=9)
    for x in (361,402): d.line((x,323,x,469), fill='#313e24', width=7)
    d.rectangle((363,283,406,321), fill='#505746'); d.line([(367,278),(432,278),(457,372)], fill='#b1b6b1', width=14)
    d.ellipse((326,268,369,310), outline='#b1b6b1', width=7); prop.save(refs/'grenade-proxy.png')
    for name in ('queue-api-template.json','queue-workflow-template.json'): shutil.copy2(PACK/name, OUT/name)
    rows=[]; guide_kinds=sorted({s[4] for s in SHOTS if len(s)>4})
    for kind in guide_kinds: make_guide(kind, refs/('guide-'+kind+'.mp4'))
    for shot in SHOTS:
        ident,size,summary,action=shot[:4]; kind=shot[4] if len(shot)>4 else None
        extra=CLEAN
        if 'tazed' in ident: extra=CLEAN+' Only thin cyan light attached to his body; no separate lightning bolts or arcs.'
        if 'burning' in ident: extra='Only small attached flames; no smoke, embers, floating flames or other characters.'
        text=prompt(summary,action,size,kind,'grenade' in ident,'death-melt' in ident or 'death-ash' in ident,extra)
        rows.append(dict(id=ident,seconds=5,fps=24,subject_reference='swat-small.png' if size=='small' else 'swat.png',
                         item_reference='grenade-proxy.png' if 'grenade' in ident else 'proxy-grip.png',
                         motion_reference='guide-'+kind+'.mp4' if kind else None,prompt=text))
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'),steps=16)
    preview=Image.new('RGB',(6*256,4*256),BG)
    preview.paste(Image.open(refs/'swat.png').resize((256,256)),(0,0))
    preview.paste(Image.open(refs/'swat-small.png').resize((256,256)),(256,0))
    for j,kind in enumerate(('walk','strike','combo'),1):
        for k,t in enumerate((0,.4,.85,1.1,1.5,2.1)):
            preview.paste(draw_guide(guide_pose(kind,t)).resize((256,256)),(k*256,j*256))
    preview.save(OUT/'reference-and-guide-preview.png')
    print(f'Prepared {len(jobs)} clips, {sum(j["seconds"] for j in jobs)} seconds at 24fps, 16 steps. Never submitted.')


if __name__=='__main__': main()
