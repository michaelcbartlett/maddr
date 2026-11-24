"""Prepare matched straight-arm recoil commissions from completed sweep poses."""
from pathlib import Path
import json
import shutil
import av
from PIL import Image
from build_h3_sprite_pack import PACK,SHARED,mannequin
import queue_h3_animations as queue

OUT=PACK/'straight-arm-recoil'

def prompt(side,direction):
    role='foreground near (screen-left shoulder in the right-facing body)' if side=='near' else 'background far (screen-right shoulder, behind torso and head)'
    angle={'level':'horizontally SCREEN-RIGHT','up':'vertically STRAIGHT UP','down':'vertically STRAIGHT DOWN'}[direction]
    return f'''subject_definitions:
<Subject 1> is the scientist in <Picture 1>, which is a frame from the approved straight-arm sweep.
<Picture 2> defines the green calibration pistol only.
<Video 1> defines the small recoil motion only; ignore mannequin appearance.

summary:
[reference generation] Three small straight-arm recoil pulses, {side} arm aimed {angle}. Preserve the approved pose and return to it fully after each pulse.

retention_analysis:
<Picture 1> (appearance and starting pose): fully_preserved - identical scientist, face, glasses, hair, coat, burgundy shirt, trousers, shoes, pixel style, fixed shoulder, extended arm and baseline aim.
<Picture 2> (item): fully_preserved - rigid matte green proxy, same size and continuous grip.
<Video 1> (motion): partially_preserved - transfer timing, tiny shoulder kick and recovery, straight elbow and fixed camera. Never render the mannequin.

detailed_description:
Maintain the fixed three-quarter SCREEN-RIGHT-facing body shown in <Picture 1>. Only the {role} arm performs the motion. Keep that arm aimed {angle}. The other arm, head, torso, pelvis, legs, feet and expression remain still.

The moving elbow stays fully extended at 180 degrees throughout. Upper arm, elbow center and wrist remain collinear. Keep the wrist aligned and fingers wrapped around the same proxy handle. No elbow curls, folded-arm recoil, saluting, head touching, altered limb lengths, detached parts or extra hands.

Hold the exact ready pose for the first second. At 1.00, 2.25 and 3.50 seconds perform three separate restrained recoil pulses: a tiny quick shoulder-driven kick of only a few degrees, then a smooth complete recovery to the original extended pose within about 0.25 seconds. Pause clearly between pulses. Hold the original pose for the last second. The proxy stays rigid and returns to precisely the same position and angle each time. Follow <Video 1>. Do not turn this into a large arm swing, a new aim sweep, torso rocking or a camera shake.

Keep the camera position, size, zoom, perspective and framing fixed. Full body and full hand/proxy visible with clear margin overhead and below. No clipping, cuts, pans, zooms, orbit or reframing. Stable pixel edges and colors, no motion blur, ghost frames, crosshatching or texture overlays. Flat dark blue-gray background. Do NOT render firing effects: no muzzle flash, beam, projectile, smoke, sparks, added weapons, sounds, dialogue, text or logos. These are clean modular limb poses; the game supplies its own weapon and shot effects.

overall_soundscape:
Silent. No speech, music or sound effects.

non_diegetic_music:
N/A'''

def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['scientist.png','proxy-grip.png']:shutil.copy2(PACK/'references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    rows=[];number=40
    for side,shot,indices in [('near','37-near-straight-sweep',{'level':60,'up':115,'down':0}),
                              ('far','38-far-straight-sweep',{'level':45,'up':115,'down':0})]:
        root=SHARED/'output/video/mad-villain-sprite/batch'/shot
        source=max(root.glob('*_audio.mp4'),key=lambda p:p.stat().st_mtime)
        pictures={}
        with av.open(str(source)) as video:
            for i,frame in enumerate(video.decode(video=0)):
                if i in indices.values():pictures[i]=frame.to_image()
        for direction,index in indices.items():
            subject=f'scientist-{side}-{direction}.png';pictures[index].save(refs/subject)
            motion=f'puppet-{side}-straight-recoil-{direction}.mp4'
            with av.open(str(refs/motion),'w') as output:
                stream=output.add_stream('libx264',rate=24);stream.width=768;stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
                for frame in range(120):
                    image,joints=mannequin(frame/24,'straight-recoil-'+direction,True,side,True)
                    arm=joints[side];s,e,w=[arm[k] for k in ['shoulder','elbow','wrist']]
                    cross=(e[0]-s[0])*(w[1]-e[1])-(e[1]-s[1])*(w[0]-e[0])
                    assert abs(cross)<1e-6
                    canvas=Image.new('RGB',(768,768),'#14202b');canvas.paste(image.resize((691,691),Image.Resampling.NEAREST),(38,61))
                    for packet in stream.encode(av.VideoFrame.from_image(canvas)):output.mux(packet)
                for packet in stream.encode():output.mux(packet)
            row={'id':f'{number}-{side}-straight-recoil-{direction}','seconds':5,'fps':24,
                'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':motion,'prompt':prompt(side,direction)}
            rows.append(row);number+=1
            (OUT/(row['id']+'-prompt.txt')).write_text(row['prompt'],encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))
    for job in jobs:queue.atomic_json(OUT/(job['id']+'-workflow.json'),job['workflow'])
    queue.atomic_json(OUT/'validation.json',{'jobs':len(jobs),'seconds_each':5,'requested_seconds':30,
        'fps':24,'steps':16,'guide_frames_checked':720,'subject_references':[row['subject_reference'] for row in rows]})
    print(json.dumps({'pack':str(OUT),'jobs':len(jobs),'requested_seconds':30}))

if __name__=='__main__':main()
