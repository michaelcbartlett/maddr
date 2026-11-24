"""Remaining isolated scientist layers after the successful layer test; never queues."""
import math
import shutil
import av
import cv2
import numpy as np
from PIL import Image,ImageDraw
import json
import build_h3_layer_test as T
from build_h3_sprite_pack import PACK,PALETTE
from import_h3_scientist import ARM_O,OUT as ART,cut_straight_arm
from review_h3_modular_batch import DEFAULT_BATCH,load
import queue_h3_animations as queue

OUT=PACK/'layers'


def far_reference(path,degrees):
    """Far sleeve rebuilt without the torso, its gripping hand and the proxy."""
    video=load(max((DEFAULT_BATCH/'38-far-straight-sweep').glob('*_audio.mp4'),key=lambda p:p.stat().st_mtime))
    pose=next(p for p in json.loads((ART/'body.json').read_text())['poses']['far'] if p['kind']=='aim' and p['aim_degrees']==0)
    frame=video[pose['source_frame']];shoulder=np.array(pose['shoulder'])*6;grip=shoulder+(np.array(pose['grip'])*6-shoulder)/1.14
    sleeve,hand,angle=cut_straight_arm(frame,shoulder,grip,'far')
    c,s=math.cos(angle),math.sin(angle);m=np.array([[c,s,0.],[-s,c,0.]]);m[:,2]=ARM_O-m[:,:2]@shoulder
    rgb=cv2.warpAffine(np.asarray(frame),m,(520,220),flags=cv2.INTER_NEAREST);q=rgb.astype(int)
    green=((q[:,:,1]>85)&(q[:,:,1]>q[:,:,0]*1.5)&(q[:,:,1]>q[:,:,2]*1.4)).astype(np.uint8)
    n,labels,stats,_=cv2.connectedComponentsWithStats(green,8)
    prop=cv2.dilate(np.isin(labels,[i for i in range(1,n) if stats[i,cv2.CC_STAT_AREA]>60]).astype(np.uint8),np.ones((5,5),np.uint8))>0
    outline=(cv2.dilate(prop.astype(np.uint8),np.ones((9,9),np.uint8))>0)&(q.sum(axis=2)<150)
    strip=np.zeros((220,520,4),np.uint8);on=prop|outline;strip[on,:3]=rgb[on];strip[on,3]=255
    for layer in [sleeve,hand]:
        part=strip[:,:420];mask=layer[:,:,3]>0;part[mask]=layer[mask]
    factor=(T.UPPER+T.FORE)/float(np.linalg.norm(grip-shoulder));a=math.radians(degrees);c,s=math.cos(a)*factor,math.sin(a)*factor
    m=np.array([[c,-s,0.],[s,c,0.]]);m[:,2]=T.SHOULDER-m[:,:2]@ARM_O
    image=Image.new('RGBA',(768,768),T.BG)
    image.alpha_composite(Image.fromarray(cv2.warpAffine(strip,m,(768,768),flags=cv2.INTER_NEAREST)));image.convert('RGB').save(path)


def recolor(draw):
    def far(t,study):
        image,joints=draw(t,study);a=np.asarray(image).copy()
        for part in ['upper_arm','forearm','hand']:
            src=[int(PALETTE['near_'+part][i:i+2],16) for i in (1,3,5)];dst=[int(PALETTE['far_'+part][i:i+2],16) for i in (1,3,5)]
            a[(a==src).all(axis=2)]=dst
        return Image.fromarray(a),joints
    return far


def jolt_guide(t,study):
    """A spring-back of the whole limb: wrist lifts, elbow gives, then settles."""
    kick=0.
    for start in [.75,2.,3.25]:
        age=t-start
        if 0<=age<.5:kick=max(kick,min(age/.06,1)*math.exp(-max(0,age-.06)*9))
    old=T.arm_pose;T.arm_pose=lambda *_:(9*kick,-27*kick)
    try:return T.arm_guide(t,study)
    finally:T.arm_pose=old


def run_guide(t,study):
    image=Image.new('RGB',(768,768),T.BG);d=ImageDraw.Draw(image);phase=t*math.tau*1.6;bob=8*abs(math.sin(phase))
    for side,x,offset in [('far',372,math.pi),('near',400,0)]:
        hip=(x,490-bob);ankle=(x+78*math.sin(phase+offset),672-max(0,math.cos(phase+offset))*80)
        dx,dy=ankle[0]-hip[0],ankle[1]-hip[1];dist=min(math.hypot(dx,dy),216);k=math.sqrt(max(0,108**2-(dist/2)**2))
        knee=(hip[0]+dx/2+dy/dist*k,hip[1]+dy/2-dx/dist*k)
        for name,p,q,w in [('_thigh',hip,knee,50),('_shin',knee,ankle,40)]:d.line([p,q],fill=PALETTE[side+name],width=w)
        d.ellipse((knee[0]-22,knee[1]-22,knee[0]+22,knee[1]+22),fill=PALETTE[side+'_shin'])
        d.rounded_rectangle((ankle[0]-22,ankle[1]-4,ankle[0]+50,ankle[1]+26),radius=9,fill=PALETTE[side+'_foot'])
    d.polygon([(330,300-bob),(460,300-bob),(445,505-bob),(330,505-bob)],fill=PALETTE['torso'])
    d.ellipse((320,62-bob,490,282-bob),fill=PALETTE['head']);return image,None


BODY='the mad scientist costume puppet body with no arm layers'
NO_ARMS='There are NO arms, sleeves, hands or held objects. The coat sides are smooth closed cloth at the shoulders.'
FAR='one isolated white laboratory-coat sleeve with its cuff and a hand wrapped around a green block'
NEAR=T.ARM.replace('a green pistol','a green block')
JOLT='The rounded shoulder end stays pinned at one fixed point. The arm is extended level to screen-right. Three times, at 0.75, 2.00 and 3.25 seconds, it makes a short springy jolt: the hand pops slightly up and back, the elbow gives a little, then everything settles to exactly the starting pose within half a second. The green block is an inert solid lump of plastic; it does nothing. No light of any kind.'
DASH='Three times, at 0.40, 1.95 and 3.50 seconds: snap into the pose, hold it clearly for half a second, recover to the starting stance. Stay IN PLACE with the hips at the same canvas position; the game moves the body. Same screen-right view throughout, no turning. No speed lines. Pose: '


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    shutil.copy2(PACK/'layer-test/references/arm-only-level.png',refs/'near-level.png');far_reference(refs/'far-level.png',0);far_reference(refs/'far-down.png',90);T.body_reference(refs/'armless-body.png','idle')
    sweep='The rounded shoulder end stays pinned at one fixed point. The straight sleeve rotates slowly around it: 0.00-0.50 hold pointing straight down; 0.50-4.25 sweep through screen-right to straight up; 4.25-5.00 hold straight up. Elbow extended, wrist aligned, constant length.'
    lift='The rounded shoulder end stays pinned. Hold level until 0.75; bend ONLY the elbow so the forearm points straight up by 1.00, upper sleeve still level; then raise the upper sleeve while the elbow opens, fully straight overhead at 1.40. Hold to 2.20, lower slowly as one straight unit to level at 3.20, hold, repeat the raise from 3.70 to 4.35 and hold. Cloth folds naturally at the elbow. Never bend at the top.'
    far_draw=recolor(T.arm_guide)
    shots=[('60-far-arm-sweep','far-down.png',far_draw,'straight-sweep',FAR,sweep,T.NO_BODY,True),
     ('61-far-arm-raise','far-level.png',far_draw,'natural-raise',FAR,lift,T.NO_BODY,True),
     ('62-near-arm-jolt','near-level.png',jolt_guide,'',NEAR,JOLT,T.NO_BODY,True),
     ('63-far-arm-jolt','far-level.png',recolor(jolt_guide),'',FAR,JOLT,T.NO_BODY,True),
     ('64-armless-idle','armless-body.png',None,'',BODY,'Stand still in the starting stance with both feet planted. Very gentle slow breathing and slight hair sway only, returning exactly to the first frame.',NO_ARMS,False),
     ('65-armless-run','armless-body.png',run_guide,'',BODY,'Run in place at a brisk even pace facing three-quarter screen-right, leaning slightly forward, knees high, coat tails streaming toward screen-left. Head and scale steady.',NO_ARMS,False)]
    for ident,pose in [('66-armless-dash-forward','deep forward lunge toward screen-right, front knee bent, rear leg long behind, coat and hair trailing toward screen-left.'),
        ('67-armless-dash-back','hips drive toward screen-left while the face still looks screen-right, torso leaning back, front leg extended right, coat and hair sweeping toward screen-right.'),
        ('68-armless-dash-up','body stretched tall and narrow toward the top of the screen, legs together, toes down, coat and hair trailing downward.'),
        ('69-armless-dash-down','low compressed crouch driving toward the bottom of the screen, knees bent, coat and hair billowing upward.')]:
        shots.append((ident,'armless-body.png',None,'',BODY,DASH+pose,NO_ARMS,False))
    rows=[];sheet=Image.new('RGB',(5*230,4*230),T.BG)
    for j,(ident,subject,draw,study,who,motion_text,absent,prop) in enumerate(shots):
        text=T.prompt(who,motion_text,absent,prop);motion=None
        if prop:text=text.replace('the rigid matte green calibration pistol held in the hand','the rigid matte green block held in the hand')
        if draw:
            motion='guide-'+ident+'.mp4'
            with av.open(str(refs/motion),'w') as output:
                stream=output.add_stream('libx264',rate=24);stream.width=stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
                for i in range(120):
                    image,_=draw(i/24,study)
                    if i==26:sheet.paste(image.resize((230,230)),(j%5*230,(j//5*2+1)*230))
                    for packet in stream.encode(av.VideoFrame.from_image(image)):output.mux(packet)
                for packet in stream.encode():output.mux(packet)
        else:
            lines=[l for l in text.split('\n') if not l.startswith('<Video 1>:')]
            text='\n'.join(lines).replace(' <Video 1> defines motion and timing only; never render the colored guide.','')
        sheet.paste(Image.open(refs/subject).resize((230,230)),(j%5*230,j//5*2*230))
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':motion,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    sheet.save(OUT/'preview.png');queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
