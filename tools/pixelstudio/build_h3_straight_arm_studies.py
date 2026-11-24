"""Prepare two H3 straight-arm aiming studies. No uploads or model submissions."""
from pathlib import Path
import copy
import json
import math
import shutil
import av
from PIL import Image,ImageDraw
from build_h3_sprite_pack import ROOT,PACK,mannequin
import queue_h3_animations as queue

OUT=PACK/'straight-arm-studies'


def prompt(side):
    description=(
        'Only the FOREGROUND NEAR arm moves: the arm attached to the shoulder on the '
        'SCREEN-LEFT side of the scientist torso in this fixed right-facing view. '
        'This is the arm that crosses in front of the chest when aiming right. '
        'Keep the background far arm relaxed and completely still.' if side=='near' else
        'Only the BACKGROUND FAR arm moves: the arm attached to the shoulder on the '
        'SCREEN-RIGHT side of the scientist torso in this fixed right-facing view. '
        'Keep it behind the torso and behind the head and hair wherever they overlap. '
        'Keep the foreground near arm relaxed and completely still.')
    return f'''subject_definitions:
<Subject 1> is the mad scientist in <Picture 1>.
<Picture 1> defines the scientist appearance and pixel-art style.
<Picture 2> defines only the rigid matte green calibration pistol.
<Video 1> is a colored mannequin motion guide; transfer its motion only.

summary:
[reference generation] Fixed-camera, straight-elbow {side}-arm aim sweep from straight down to straight up. This is a modular arm pose study, not a firing animation.

retention_analysis:
<Picture 1> (appearance): fully_preserved - identical scientist identity, face, hair, glasses, coat, burgundy shirt, trousers, shoes, colors and pixel style.
<Picture 2> (item): fully_preserved - identical rigid matte green proxy, scale and grip.
<Video 1> (motion): partially_preserved - copy shoulder rotation, fully extended elbow, aligned wrist, timing and fixed camera. Ignore mannequin appearance and colors.

detailed_description:
Use the same three-quarter SCREEN-RIGHT-facing scientist throughout. {description}

The moving arm is fully extended for the ENTIRE clip. The upper arm, elbow center and wrist stay on ONE STRAIGHT LINE: elbow internal angle 180 degrees. The motion comes ONLY from the shoulder socket. Maintain exactly the same upper-arm and forearm lengths. Do not fold the forearm back toward the face, tuck the elbow, salute, scratch the head or make a biceps curl. Keep the wrist aligned with the forearm. The proxy barrel points along the extended arm direction, not at the face. Fingers keep the same grip and correctly cover the handle.

0.00-0.50 seconds: arm fully extended straight DOWN toward the ground, proxy pointing south. Hold.
0.50-4.25 seconds: rotate that STRAIGHT arm in one continuous smooth arc through the SCREEN-RIGHT half-circle: down-right, horizontally right, up-right, then vertically up. The elbow remains extended at EVERY intermediate angle. Hand and proxy travel together along the same circular arc. Follow <Video 1>.
4.25-5.00 seconds: hold the arm fully extended STRAIGHT UP above the shoulder, proxy pointing north. The shoulder stays fixed. No bent-elbow overhead pose. Do not sweep back down in this take.

Keep head, torso, pelvis, both legs, feet, expression and the non-moving arm completely still. Respect head/hair occlusion where the rising arm passes behind them. No duplicated limbs, detached hands or extra props. No firing, recoil, flashes, smoke, projectiles, light effects, speech or text.

Camera locked: no cuts, orbit, tracking, zoom, pan, roll, perspective changes or automatic reframing. Same body size and same right-facing view in every frame. Full body around 70 percent of the square canvas height; feet anchored at 90 percent from the top. Leave clear space above the fully raised hand AND the proxy muzzle, and below the downward-pointing proxy. Nothing may touch or clip any frame edge. Flat dark blue-gray background. Crisp individual pixel-art frames: no motion blur, interpolation ghosts, crosshatching or texture overlays.

overall_soundscape:
Silent. No dialogue, music or sound effects.

non_diegetic_music:
N/A'''


def guide(side,refs):
    frames=[];records=[];checks=[]
    output_path=refs/f'puppet-{side}-straight-sweep.mp4'
    with av.open(str(output_path),'w') as output:
        stream=output.add_stream('libx264',rate=24)
        stream.width=768;stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
        for index in range(120):
            image,joints=mannequin(index/24,'straight-sweep',True,side,True)
            # Match the actual subject's near shoulder on screen-left. Scale the
            # complete scene once, leaving room for the overhead prop muzzle.
            scaled=image.resize((691,691),Image.Resampling.NEAREST)
            canvas=Image.new('RGB',(768,768),'#14202b');canvas.paste(scaled,(38,61))
            scale=691/768
            transformed={}
            for name,value in joints.items():
                if isinstance(value,dict):transformed[name]={k:[p[0]*scale+38,p[1]*scale+61] for k,p in value.items()}
                else:transformed[name]=[value[0]*scale+38,value[1]*scale+61]
            arm=transformed[side];s,e,w=[arm[k] for k in ['shoulder','elbow','wrist']]
            a=[s[0]-e[0],s[1]-e[1]];b=[w[0]-e[0],w[1]-e[1]]
            upper=math.hypot(*a);fore=math.hypot(*b)
            dot=sum(x*y for x,y in zip(a,b))/(upper*fore)
            angle=math.degrees(math.acos(max(-1,min(1,dot))))
            assert angle>179.999,(side,index,angle)
            assert abs(upper-84*scale)<1e-6 and abs(fore-96*scale)<1e-6
            assert all(0<v<768 for point in [s,e,w] for v in point)
            records.append({'frame':index,'time':index/24,'elbow_degrees':angle,'joints':transformed})
            checks.append(angle);frames.append(canvas)
            for packet in stream.encode(av.VideoFrame.from_image(canvas)):output.mux(packet)
        for packet in stream.encode():output.mux(packet)
    (refs/f'puppet-{side}-straight-sweep-joints.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
    frames[0].save(refs/f'puppet-{side}-straight-sweep.png')
    contact=Image.new('RGB',(256*7,280),'#14202b');draw=ImageDraw.Draw(contact)
    for j,index in enumerate([0,27,42,57,72,87,119]):
        contact.paste(frames[index].resize((256,256),Image.Resampling.NEAREST),(j*256,0))
        draw.text((j*256+6,260),f'{index/24:.2f}s / straight elbow',fill='white')
    contact.save(OUT/f'{side}-sweep-contact.png')
    return {'side':side,'frames':len(frames),'fps':24,'minimum_elbow_degrees':min(checks),
        'maximum_elbow_degrees':max(checks),'upper_length':84*691/768,'forearm_length':96*691/768}


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['scientist.png','proxy-grip.png']:shutil.copy2(PACK/'references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    rows=[];validation=[]
    for number,side in [(37,'near'),(38,'far')]:
        validation.append(guide(side,refs))
        row={'id':f'{number}-{side}-straight-sweep','seconds':5,'fps':24,'item_reference':'proxy-grip.png',
            'motion_reference':f'puppet-{side}-straight-sweep.mp4','prompt':prompt(side)}
        rows.append(row)
        (OUT/f'{row["id"]}-prompt.txt').write_text(row['prompt'],encoding='utf-8')
    (OUT/'animation-queue-manifest.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))
    for job in jobs:
        queue.atomic_json(OUT/(job['id']+'-workflow.json'),job['workflow'])
        queue.atomic_json(OUT/(job['id']+'-api.json'),job['api'])
    (OUT/'validation.json').write_text(json.dumps({'guides':validation,'queue_jobs':2,'requested_seconds':10,'steps':jobs[0]['steps']},indent=2),encoding='utf-8')
    print(json.dumps({'pack':str(OUT),'jobs':len(jobs),'validation':validation}))


if __name__=='__main__':main()
