"""Test whether H3 can animate one isolated body part per clip; never queues."""
import json
import math
import shutil
import av
import cv2
import numpy as np
from PIL import Image,ImageDraw
from build_h3_sprite_pack import PACK,PALETTE,arm_pose,endpoint
from review_h3_modular_batch import DEFAULT_BATCH,load
from import_h3_scientist import ARM_O,OUT as ART,cut_straight_arm,grip_geometry
import queue_h3_animations as queue

OUT=PACK/'layer-test'
BG=(14,24,35)
SHOULDER=np.array([330.,384.])
UPPER,FORE=102,110


def arm_reference(path,degrees):
    """Near sleeve, hand and proxy only, from the clean straight-sweep frame."""
    video=load(max((DEFAULT_BATCH/'37-near-straight-sweep').glob('*_audio.mp4'),key=lambda p:p.stat().st_mtime))
    frame=video[62];pose={'shoulder': [46.933, 55.211], 'grip': [91.927, 55.848]}  # frame 62 socket and grip
    shoulder=np.array(pose['shoulder'])*6;grip=shoulder+(np.array(pose['grip'])*6-shoulder)/1.14
    sleeve,hand,angle=cut_straight_arm(frame,shoulder,grip,'near')
    c,s=math.cos(angle),math.sin(angle)
    m=np.array([[c,s,0.],[-s,c,0.]]);m[:,2]=ARM_O-m[:,:2]@shoulder
    # Wider view than the importer's strip so the whole proxy stays in frame.
    size=(520,220);rgb=cv2.warpAffine(np.asarray(frame),m,size,flags=cv2.INTER_NEAREST)
    q=rgb.astype(int);green=((q[:,:,1]>85)&(q[:,:,1]>q[:,:,0]*1.5)&(q[:,:,1]>q[:,:,2]*1.4)).astype(np.uint8)
    n,labels,stats,_=cv2.connectedComponentsWithStats(green,8)
    prop=cv2.dilate(np.isin(labels,[i for i in range(1,n) if stats[i,cv2.CC_STAT_AREA]>60]).astype(np.uint8),np.ones((5,5),np.uint8))>0
    dark=q.sum(axis=2)<150;outline=(cv2.dilate(prop.astype(np.uint8),np.ones((9,9),np.uint8))>0)&dark
    strip=np.zeros((220,520,4),np.uint8)
    for mask,color in [(prop|outline,rgb)]:strip[mask,:3]=color[mask];strip[mask,3]=255
    for layer in [sleeve,hand]:
        part=strip[:,:420];on=layer[:,:,3]>0;part[on]=layer[on]
    factor=(UPPER+FORE)/float(np.linalg.norm(grip-shoulder));a=math.radians(degrees)
    c,s=math.cos(a)*factor,math.sin(a)*factor
    m=np.array([[c,-s,0.],[s,c,0.]]);m[:,2]=SHOULDER-m[:,:2]@ARM_O
    placed=Image.fromarray(cv2.warpAffine(strip,m,(768,768),flags=cv2.INTER_NEAREST))
    image=Image.new('RGBA',(768,768),BG);image.alpha_composite(placed);image.convert('RGB').save(path)


def body_reference(path,clip='walk'):
    meta=json.loads((ART/'body.json').read_text());index=meta['clips'][clip]['start'];row=meta['rows_per_variant']+index//8
    atlas=Image.open(ART/'body.png').convert('RGBA');x=index%8*128
    tile=atlas.crop((x,row*128,x+128,row*128+128)).resize((768,768),Image.Resampling.NEAREST)
    image=Image.new('RGBA',(768,768),BG);image.alpha_composite(tile);image.convert('RGB').save(path)


def arm_guide(t,study):
    image=Image.new('RGB',(768,768),BG);d=ImageDraw.Draw(image);upper,bend=arm_pose(t,study)
    a=tuple(SHOULDER);b=endpoint(a,upper,UPPER);c=endpoint(b,upper+bend,FORE)
    for name,p,q,w in [("near_upper_arm",a,b,66),("near_forearm",b,c,60)]:
        d.line([p,q],fill=PALETTE[name],width=w)
        for x,y in (p,q):d.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill=PALETTE[name])
    angle=math.radians(upper+bend)
    d.polygon([(c[0]+x*math.cos(angle)-y*math.sin(angle),c[1]+x*math.sin(angle)+y*math.cos(angle))
        for x,y in [(-9,-46),(110,-46),(110,-14),(12,-14),(12,28),(-9,28)]],fill='#00ff00')
    d.ellipse((c[0]-26,c[1]-26,c[0]+26,c[1]+26),fill=PALETTE['near_hand'])
    return image,(a,b,c)


def body_guide(t,study=None):
    image=Image.new('RGB',(768,768),BG);d=ImageDraw.Draw(image);phase=t*math.tau*1.2
    for side,x,offset in [('far',372,math.pi),('near',405,0)]:
        hip=(x,500);ankle=(x+42*math.sin(phase+offset),690-max(0,math.cos(phase+offset))*22)
        dx,dy=ankle[0]-hip[0],ankle[1]-hip[1];dist=math.hypot(dx,dy);k=math.sqrt(max(0,104**2-(dist/2)**2))
        knee=(hip[0]+dx/2+dy/dist*k,hip[1]+dy/2-dx/dist*k)
        for name,p,q,w in [('_thigh',hip,knee,50),('_shin',knee,ankle,40)]:d.line([p,q],fill=PALETTE[side+name],width=w,joint='curve')
        d.ellipse((knee[0]-22,knee[1]-22,knee[0]+22,knee[1]+22),fill=PALETTE[side+'_shin'])
        d.rounded_rectangle((ankle[0]-22,ankle[1]-4,ankle[0]+50,ankle[1]+26),radius=9,fill=PALETTE[side+'_foot'])
    d.polygon([(310,300),(440,300),(450,510),(330,510)],fill=PALETTE['torso'])
    d.ellipse((300,60,470,280),fill=PALETTE['head'])
    return image,None


def prompt(subject,motion,absent,prop):
    item='the rigid matte green calibration pistol held in the hand' if prop else 'a color swatch only; its object must NOT appear'
    return f'''subject_definitions:
<Subject 1> is {subject}, exactly as shown in <Picture 1>. <Picture 1> is a complete, finished isolated sprite layer, not a cropped person. <Picture 2> is {item}. <Video 1> defines motion and timing only; never render the colored guide.

summary:
[reference generation] Isolated game-sprite layer animation of {subject}. Nothing else exists in the frame.

retention_analysis:
<Picture 1>: fully_preserved - exact parts present, shapes, colors, outlines, pixel-art style and scale. Add no body parts.
<Picture 2>: {'fully_preserved - rigid green proxy and grip' if prop else 'not_preserved - never show it'}.
<Video 1>: partially_preserved - joint motion, timing, position and scale. Ignore its appearance.

detailed_description:
{motion}

{absent} This is a detached puppet part, a clean cartoon costume layer with a smooth rounded cloth end. It never becomes a full person. Empty flat background everywhere else, in every frame from first to last.

Fixed camera, position, scale and framing. Flat uniform dark blue-gray background. Crisp pixel edges, stable colors, fully opaque. No motion blur, ghosting, shadows, effects, flashes, particles, added texture, text or logos.

overall_soundscape:
Silent. No speech, sound effects or music.

non_diegetic_music:
N/A'''

ARM='one isolated white laboratory-coat sleeve with its cuff and hand gripping a green pistol'
NO_BODY='There is NO head, hair, face, neck, torso, coat body, legs or second arm. Do not draw a person attached to the sleeve.'


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    arm_reference(refs/'arm-only-down.png',90);arm_reference(refs/'arm-only-level.png',0);body_reference(refs/'armless-body.png')
    shots=[
     ('56-arm-only-sweep','arm-only-down.png',arm_guide,'straight-sweep',prompt(ARM,
      'The rounded shoulder end stays pinned at one fixed point. The straight sleeve rotates slowly around it: 0.00-0.50 hold pointing straight down; 0.50-4.25 sweep through screen-right to straight up; 4.25-5.00 hold straight up. The elbow stays extended, the wrist aligned, the length constant.',NO_BODY,True)),
     ('57-arm-only-raise','arm-only-level.png',arm_guide,'natural-raise',prompt(ARM,
      'The rounded shoulder end stays pinned at one fixed point. Hold level pointing screen-right until 0.75; bend ONLY the elbow so the forearm and gun point straight up by 1.00, upper sleeve still level; then raise the upper sleeve while the elbow opens, finishing fully straight overhead at 1.40. Hold to 2.20, lower slowly as one straight unit to level at 3.20, hold, then repeat the raise from 3.70 to 4.35 and hold. Cloth folds naturally at the elbow. Never bend at the top.',NO_BODY,True)),
     ('58-armless-walk','armless-body.png',body_guide,'walk',prompt('the mad scientist costume puppet body with no arm layers',
      'Walk in place at a steady pace, facing three-quarter screen-right, with planted alternating feet, gentle coat sway and small hair movement. Head, torso and scale stay steady.',
      'There are NO arms, sleeves, hands or held objects. The coat sides are smooth closed cloth at the shoulders.',False))]
    rows=[];sheet=Image.new('RGB',(1152,576),BG)
    for j,(ident,subject,draw,study,text) in enumerate(shots):
        motion='guide-'+ident+'.mp4'
        with av.open(str(refs/motion),'w') as output:
            stream=output.add_stream('libx264',rate=24);stream.width=stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
            for i in range(120):
                image,joints=draw(i/24,study)
                if joints:
                    for p,q,n in [(joints[0],joints[1],UPPER),(joints[1],joints[2],FORE)]:assert abs(math.dist(p,q)-n)<1e-6
                if i==26:sheet.paste(image.resize((288,288)),(288*j+288,288))
                for packet in stream.encode(av.VideoFrame.from_image(image)):output.mux(packet)
            for packet in stream.encode():output.mux(packet)
        sheet.paste(Image.open(refs/subject).resize((288,288)),(288*j+288,0))
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':motion,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    sheet.save(OUT/'preview.png');queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    jobs=queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))
    print([j['id'] for j in jobs])


if __name__=='__main__':main()
