"""Guided retry of the backward dash; the prompt-only take leaned forward. Never queues."""
import math
import shutil
import av
import numpy as np
from PIL import Image,ImageDraw
import build_h3_layer_test as T
from build_h3_layers import BODY,NO_ARMS
from build_h3_sprite_pack import PACK,PALETTE
import queue_h3_animations as queue

OUT=PACK/'back-dash'


def guide(t):
    amount=0.
    for start in [.4,1.95,3.5]:
        age=t-start
        if 0<=age<.95:
            k=min(age/.12,1)*(1-max(0,min(1,(age-.6)/.35)));amount=max(amount,k*k*(3-2*k))
    image=Image.new('RGB',(768,768),T.BG);d=ImageDraw.Draw(image)
    hip=np.array([390-34*amount,500+26*amount]);lean=math.radians(-18*amount)
    for side,foot in [('far',(345-62*amount,690)),('near',(430+70*amount,690))]:
        a=hip+[0,0];b=np.array(foot,float);delta=b-a;dist=min(np.linalg.norm(delta),214);k=math.sqrt(max(0,108**2-(dist/2)**2))
        knee=(a+b)/2+np.array([delta[1],-delta[0]])/np.linalg.norm(delta)*k
        for name,p,q,w in [('_thigh',a,knee,50),('_shin',knee,b,40)]:d.line([tuple(p),tuple(q)],fill=PALETTE[side+name],width=w)
        d.rounded_rectangle((b[0]-22,b[1]-4,b[0]+50,b[1]+26),radius=9,fill=PALETTE[side+'_foot'])
    rot=lambda x,y:tuple(hip+np.array([x*math.cos(lean)-y*math.sin(lean),x*math.sin(lean)+y*math.cos(lean)]))
    d.polygon([rot(-62,-200),rot(58,-200),rot(58,8),rot(-58,8)],fill=PALETTE['torso'])
    cx,cy=rot(5,-322);d.ellipse((cx-85,cy-110,cx+85,cy+110),fill=PALETTE['head'])
    return image


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    for name in ['proxy-grip.png','armless-body.png']:shutil.copy2(PACK/'layers/references'/name,refs/name)
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    with av.open(str(refs/'guide.mp4'),'w') as output:
        stream=output.add_stream('libx264',rate=24);stream.width=stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
        for i in range(120):
            for packet in stream.encode(av.VideoFrame.from_image(guide(i/24))):output.mux(packet)
        for packet in stream.encode():output.mux(packet)
    guide(.75).save(OUT/'preview.png')
    text=T.prompt(BODY,'Hopping BACKWARD away from what he is looking at, three times, matching the guide. He keeps facing screen-right. The hips drop and drive toward SCREEN-LEFT, the chest and head tilt BACK toward screen-left behind the hips, the front leg stretches out to SCREEN-RIGHT with the heel down, the rear knee bends. The coat tails and hair swing FORWARD toward SCREEN-RIGHT. Never lean or lunge toward screen-right. Recover to the starting stance between repetitions. Stay in place.',NO_ARMS,False)
    row={'id':'70-armless-dash-back','seconds':5,'fps':24,'subject_reference':'armless-body.png','item_reference':'proxy-grip.png','motion_reference':'guide.mp4','prompt':text}
    queue.atomic_json(OUT/'animation-queue-manifest.json',[row])
    print([j['id'] for j in queue.prepare_jobs(OUT,[row],queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
