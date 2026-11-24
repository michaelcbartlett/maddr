"""Natural aiming arms: the elbow bends when level and opens toward the extremes.

Replaces the stiff straight sweeps. Forearm and gun always point along the aim,
so every frame can be selected by its measured gun angle. Never queues.
"""
import math
import shutil
import av
import cv2
import numpy as np
from PIL import Image,ImageDraw
import build_h3_layer_test as T
from build_h3_layers import FAR,NEAR,recolor
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK/'natural-arms'
THICK=1.18
# aim degrees (down positive) -> how far the upper arm hangs below the forearm
BEND=[(-90,0),(-70,10),(-45,28),(-15,42),(15,44),(45,34),(70,16),(90,6)]


def bend(aim):
    return float(np.interp(aim,[a for a,_ in BEND],[b for _,b in BEND]))


def sweep(t,*_):
    k=max(0,min(1,(t-.4)/4.2));aim=90-180*k
    b=bend(aim);return aim+b,-b


def jolt(t,*_):
    kick=0.
    for start in [.75,2.,3.25]:
        age=t-start
        if 0<=age<.5:kick=max(kick,min(age/.06,1)*math.exp(-max(0,age-.06)*9))
    b=bend(0);return b+10*kick,-b-30*kick


def guided(pose):
    def draw(t,study):
        old=T.arm_pose;T.arm_pose=pose
        try:return T.arm_guide(t,study)
        finally:T.arm_pose=old
    return draw


def thicken(source,target,degrees):
    """Match the fuller sleeve of his relaxed arm without changing its length."""
    a=math.radians(degrees);r=np.array([[math.cos(a),-math.sin(a)],[math.sin(a),math.cos(a)]])
    m2=r@np.diag([1.,THICK])@r.T;m=np.zeros((2,3));m[:,:2]=m2;m[:,2]=T.SHOULDER-m2@T.SHOULDER
    image=cv2.warpAffine(np.asarray(Image.open(source).convert('RGB')),m,(768,768),flags=cv2.INTER_NEAREST,borderValue=T.BG)
    Image.fromarray(image).save(target)


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    for source,name,degrees in [('layer-test/references/arm-only-down.png','near-down.png',90),('layer-test/references/arm-only-level.png','near-level.png',0),
        ('layers/references/far-down.png','far-down.png',90),('layers/references/far-level.png','far-level.png',0)]:
        thicken(PACK/source,refs/name,degrees)
    motion='The rounded shoulder end stays pinned at one fixed point. A relaxed, natural aiming arm, NOT a stiff straight stick. Starting hanging down with the elbow almost straight, the hand and block sweep slowly and evenly in an arc through screen-right to straight up, from 0.40 to 4.60 seconds. The forearm, hand and block always point along the same line. While the hand is near level, the elbow hangs clearly BELOW the line from shoulder to hand, with the upper arm sloping down and the forearm level, a comfortable bent elbow. Near straight down and straight up the elbow opens until the arm is extended. Follow the guide exactly. Soft cloth folds gather inside the elbow. The elbow never points upward and never bends backward.'
    recoil='The rounded shoulder end stays pinned. The arm holds a comfortable level aim: upper arm sloping down, elbow bent and hanging low, forearm, hand and block level. Three times, at 0.75, 2.00 and 3.25 seconds, a short springy jolt folds the elbow a little more and pops the hand up and back, then everything settles to exactly the starting pose within half a second. The green block is an inert solid lump of plastic; it does nothing. No light of any kind.'
    far_jolt=recolor(guided(jolt));far_sweep=recolor(guided(sweep))
    shots=[('71-near-natural-sweep','near-down.png',guided(sweep),NEAR,motion),('72-far-natural-sweep','far-down.png',far_sweep,FAR,motion),
        ('73-near-natural-jolt','near-level.png',guided(jolt),NEAR,recoil),('74-far-natural-jolt','far-level.png',far_jolt,FAR,recoil)]
    rows=[];sheet=Image.new('RGB',(5*230,4*230),T.BG)
    for j,(ident,subject,draw,who,text_) in enumerate(shots):
        name='guide-'+ident+'.mp4'
        sheet.paste(Image.open(refs/subject).resize((230,230)),(0,j*230))
        with av.open(str(refs/name),'w') as output:
            stream=output.add_stream('libx264',rate=24);stream.width=stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
            for i in range(120):
                image,joints=draw(i/24,'')
                assert abs(math.dist(joints[0],joints[1])-T.UPPER)<1e-6 and abs(math.dist(joints[1],joints[2])-T.FORE)<1e-6
                if i in (20,46,60,86):sheet.paste(image.resize((230,230)),((1+[20,46,60,86].index(i))*230,j*230))
                for packet in stream.encode(av.VideoFrame.from_image(image)):output.mux(packet)
            for packet in stream.encode():output.mux(packet)
        text=T.prompt(who,text_,T.NO_BODY,True).replace('the rigid matte green calibration pistol held in the hand','the rigid matte green block held in the hand')
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':name,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    sheet.save(OUT/'preview.png');queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
