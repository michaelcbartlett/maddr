"""Prepare forearm-first raises with a fully extended overhead arrival."""
from pathlib import Path
import json
import shutil
import av
from PIL import Image,ImageDraw
from build_h3_sprite_pack import PACK,SHARED,mannequin
import queue_h3_animations as queue

OUT=PACK/'natural-arm-raise'

def prompt(side):
    role='foreground near arm, attached to the screen-left shoulder' if side=='near' else 'background far arm, attached to the screen-right shoulder and behind the head and torso'
    return f'''subject_definitions:
<Subject 1> is the scientist shown in <Picture 1>. <Picture 2> defines only the green calibration pistol. <Video 1> defines the joint sequence and timing only; never render the mannequin.

summary:
[reference generation] A natural two-stage upward aiming motion using the {role}: forearm lifts first while upper arm remains horizontal, then shoulder raises while elbow straightens. Arrive fully extended overhead.

retention_analysis:
<Picture 1>: fully_preserved - scientist identity, pixel style, clothing, proportions, fixed body pose, shoulder location, starting horizontal aim and grip.
<Picture 2>: fully_preserved - rigid green calibration pistol and grip.
<Video 1>: partially_preserved - exact upper-arm and forearm sequence, timing, constant bone lengths, fixed body and camera. Ignore mannequin appearance.

detailed_description:
Fixed three-quarter screen-right-facing scientist. Only the {role} moves. Keep the shoulder socket fixed to the same point on the coat. All other body parts, feet, expression, clothing and camera remain still.

Follow this exact sequence, twice:
0.00-0.75 seconds: hold the arm fully extended horizontally screen-right, gun level.
0.75-1.00: KEEP THE UPPER ARM HORIZONTAL. Bend only the elbow from straight to a right angle, lifting the forearm until the gun points straight up. Elbow stays level with the shoulder.
1.00-1.40: KEEP THE FOREARM AND GUN POINTING VERTICALLY UP. Raise the upper arm at the shoulder while simultaneously opening the elbow. Finish with shoulder, elbow and wrist in one straight vertical line overhead.
1.40-2.20: hold the fully straight overhead arm. No bending, folding, bounce or curling at the apex.
2.20-3.20: slowly lower the entire arm as a straight unit back to horizontal. Elbow remains extended during this return.
3.20-3.70: hold horizontal.
3.70-3.95: again bend only the elbow with upper arm horizontal until the forearm and gun point vertically up.
3.95-4.35: again raise the shoulder and open the elbow together, keeping the forearm vertical.
4.35-5.00: hold fully extended straight overhead.

The bend happens BEFORE the shoulder rises, never at or after the top. Do not raise a straight arm overhead and then fold it. No wrist curl, hand touching the head, shoulder sliding, torso sway, chest panel attached to the sleeve, coat stretching, extra limbs or detached parts. Constant upper-arm and forearm lengths. Keep the same hand gripping the same rigid proxy throughout. Respect near/far depth shown in the guide.

Fixed camera position, scale, perspective, framing and zoom. Full body and full overhead hand/proxy inside frame with margin. No pan, orbit, cuts or reframing. Clean consistent pixel edges, stable colors, no blur, ghosting, texture overlays, effects, firing, flash, projectiles, smoke, electricity, text or logos. Flat dark blue-gray background.

overall_soundscape:
Silent. No dialogue, sound effects or music.

non_diegetic_music:
N/A'''

def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['scientist.png','proxy-grip.png']:shutil.copy2(PACK/'references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    rows=[]
    for number,side,index in [(46,'near',60),(47,'far',45)]:
        source=max((SHARED/'output/video/mad-villain-sprite/batch'/f'{37 if side=="near" else 38}-{side}-straight-sweep').glob('*_audio.mp4'),key=lambda p:p.stat().st_mtime)
        subject=f'scientist-{side}-level.png'
        with av.open(str(source)) as video:
            for i,frame in enumerate(video.decode(video=0)):
                if i==index:frame.to_image().save(refs/subject);break
        motion=f'puppet-{side}-natural-raise.mp4'
        with av.open(str(refs/motion),'w') as output:
            stream=output.add_stream('libx264',rate=24);stream.width=768;stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
            for frame in range(120):
                image,_=mannequin(frame/24,'natural-raise',side=='far',side,True)
                canvas=Image.new('RGB',(768,768),'#14202b');canvas.paste(image.resize((691,691),Image.Resampling.NEAREST),(38,61))
                for packet in stream.encode(av.VideoFrame.from_image(canvas)):output.mux(packet)
            for packet in stream.encode():output.mux(packet)
        row={'id':f'{number}-{side}-natural-raise','seconds':5,'fps':24,'subject_reference':subject,
             'item_reference':'proxy-grip.png','motion_reference':motion,'prompt':prompt(side)}
        rows.append(row);(OUT/(row['id']+'-prompt.txt')).write_text(row['prompt'],encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))
    for job in jobs:queue.atomic_json(OUT/(job['id']+'-workflow.json'),job['workflow'])
    sheet=Image.new('RGB',(1280,345),'#14202b');draw=ImageDraw.Draw(sheet)
    for i,time in enumerate([.75,1.,1.2,1.4]):
        image,_=mannequin(time,'natural-raise',False,'near',True)
        sheet.paste(image.resize((320,320)),(i*320,25));draw.text((i*320+10,8),['Level','Elbow bends; upper arm level','Shoulder rises; elbow opens','Straight BEFORE overhead hold'][i],fill='white')
    sheet.save(OUT/'motion-sequence.png')
    queue.atomic_json(OUT/'validation.json',{'jobs':2,'seconds_each':5,'fps':24,'steps':16,'guide_frames':240,'queued':False})
    (OUT/'README.txt').write_text('Run Queue Natural Arm Raise.bat from the repository root. Two 5-second H3 REF2VA jobs, 24 fps, 16 steps.\nEach has its matched scientist pose, proxy grip and colored joint guide.\nThe elbow bends while the upper arm stays level, then opens during the shoulder lift. The apex is already straight.\nNo jobs have been submitted by the build script. Outputs: video/mad-villain-sprite/batch/46-near-natural-raise and 47-far-natural-raise.\nThese references must be reviewed and imported before enabling the new quick raise in game.\n',encoding='utf-8')
    print(json.dumps({'pack':str(OUT),'jobs':len(jobs),'requested_seconds':10,'queued':False}))

if __name__=='__main__':main()
