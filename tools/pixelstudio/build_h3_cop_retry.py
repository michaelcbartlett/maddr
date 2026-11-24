"""Guided retakes of the cop's combat clips. Wording describes only his body: naming a blow
makes H3 draw the thing that hits him. Never queues."""
import math
import shutil
import av
import numpy as np
from PIL import Image,ImageDraw
from build_h3_cop import CLEAN,OUT as COP,SOLID,prompt,reference
from build_h3_sprite_pack import PACK,PALETTE
import queue_h3_animations as queue

OUT=COP.parent/'cop-retry'
BG=(22,29,40)
SCALE=.86;PIVOT=np.array([384.,690.])
# Joint positions traced from references/cop.png (500px figure, ground 690).
REST={'hip':(335,590),'lean':0,'head':(0,0),'head_tilt':0,'near':(225,545),'far':(512,455),'baton':-68,
      'foot_n':(260,672),'foot_f':(420,672)}


def mix(a,b,k):
    return {key:(a[key]+(b[key]-a[key])*k if not isinstance(a[key],tuple) else tuple(x+(y-x)*k for x,y in zip(a[key],b[key]))) for key in a}


def pose(**changes):return {**REST,**changes}


def track(keys,starts):
    def at(t):
        current=REST
        for s in starts:
            local=t-s
            if local<0:break
            for (ta,a),(tb,b) in zip(keys,keys[1:]):
                if ta<=local<=tb:
                    k=(local-ta)/max(tb-ta,1e-6);k=k*k*(3-2*k);return mix(a,b,k)
            current=keys[-1][1]
        return current
    return at


def draw(p):
    image=Image.new('RGB',(768,768),BG);d=ImageDraw.Draw(image)
    S=lambda q:tuple(PIVOT+(np.array(q,float)-PIVOT)*SCALE)
    def limb(name,a,b,w):
        a,b=S(a),S(b);w=w*SCALE;d.line([a,b],fill=PALETTE[name],width=round(w))
        for x,y in (a,b):d.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill=PALETTE[name])
    hip=np.array(p['hip'],float);lean=math.radians(p['lean'])
    body=lambda x,y:hip+np.array([x*math.cos(lean)-y*math.sin(lean),x*math.sin(lean)+y*math.cos(lean)])
    def arm(side,shoulder,hand,bulge):
        a=np.array(shoulder);b=np.array(hand,float);mid=(a+b)/2;v=b-a;n=np.array([-v[1],v[0]])/max(np.linalg.norm(v),1)
        elbow=mid+n*bulge;limb(side+'_upper_arm',a,elbow,56);limb(side+'_forearm',elbow,b,50)
        x,y=S(b);r=27*SCALE;d.ellipse((x-r,y-r,x+r,y+r),fill=PALETTE[side+'_hand'])
    def baton():
        h=np.array(p['far'],float);a=math.radians(p['baton']);u=np.array([math.cos(a),math.sin(a)])
        s,e=S(h-u*42),S(h+u*172);d.line([s,e],fill='#8a4a1c',width=round(30*SCALE))
        for x,y in (s,e):d.ellipse((x-13,y-13,x+13,y+13),fill='#8a4a1c')
    for side,key,x in [('far','foot_f',45),('near','foot_n',-45)]:
        a=body(x,0);f=np.array(p[key],float);limb(side+'_thigh',a,(a+f)/2,66);limb(side+'_shin',(a+f)/2,f,56)
        x0,y0=S(f);d.rounded_rectangle((x0-42*SCALE,y0-16,x0+52*SCALE,y0+18),radius=8,fill=PALETTE[side+'_foot'])
    arm('far',body(100,-130),p['far'],18);baton()
    d.polygon([S(body(-105,-160)),S(body(110,-160)),S(body(95,15)),S(body(-95,15))],fill=PALETTE['torso'])
    d.line([S(body(-95,-5)),S(body(95,-5))],fill=PALETTE['pelvis'],width=22)
    head=body(5,-235)+np.array(p['head'],float);tilt=math.radians(p['head_tilt'])+lean
    turn=lambda x,y:head+np.array([x*math.cos(tilt)-y*math.sin(tilt),x*math.sin(tilt)+y*math.cos(tilt)])
    d.polygon([S(turn(x,y)) for x,y in [(-100,-40),(105,-40),(105,78),(60,90),(-60,90),(-100,50)]],fill=PALETTE['head'])
    d.polygon([S(turn(x,y)) for x,y in [(-130,-60),(-70,-120),(20,-155),(110,-140),(110,-70),(140,-45),(20,-40),(-110,-30)]],fill='#334a9a')
    arm('near',body(-95,-125),p['near'],-16)
    return image


WIND=pose(far=(505,318),baton=-112,lean=-5,near=(215,520),head=(-4,2))
HIT=pose(hip=(350,600),lean=13,far=(548,520),baton=14,near=(240,560),head=(10,4),foot_f=(448,672))
LOW=pose(hip=(350,606),lean=17,far=(520,585),baton=38,near=(225,555),head=(12,6),foot_f=(448,672))
RISE=pose(hip=(345,590),lean=-2,far=(540,395),baton=-38,near=(250,540),head=(0,-4),foot_f=(448,672))
HIGH=pose(hip=(340,588),lean=-8,far=(500,325),baton=-98,near=(235,530),head=(-8,-2),foot_f=(440,672))
FLINCH=pose(hip=(318,592),lean=-17,head=(-16,4),head_tilt=-14,near=(175,470),far=(470,400),baton=-96,foot_f=(405,640))
FOLD=pose(hip=(300,580),lean=34,head=(16,22),head_tilt=12,near=(330,600),far=(440,560),baton=-30,foot_n=(240,668),foot_f=(385,668))
HOP=pose(hip=(285,560),lean=26,head=(10,14),near=(300,580),far=(430,520),baton=-40,foot_n=(225,640),foot_f=(370,636))
KNEEL=pose(hip=(290,634),lean=30,head=(14,18),near=(345,668),far=(455,570),baton=-55,foot_n=(205,674),foot_f=(400,674))
KNEEL2=pose(hip=(290,630),lean=24,head=(-6,8),head_tilt=-10,near=(345,668),far=(455,565),baton=-58,foot_n=(205,674),foot_f=(400,674))

SHOTS=[
 ('119-cop-strike','One strong downward baton swing, performed three times. The baton is always fully visible.',
  SOLID+'Follow the guide. The baton is lifted high ABOVE and slightly behind the cap, clearly visible over his head for the whole wind-up, then swept down and forward to screen-right with a step onto the front foot, held low a moment, and returned to neutral. The baton keeps its full length and stays straight; the hand never lets go.',
  track([(0,REST),(.22,WIND),(.42,WIND),(.52,HIT),(.60,LOW),(.78,LOW),(1.2,REST)],[.4,1.9,3.4])),
 ('120-cop-combo','Two linked baton swings, performed twice. The baton is always fully visible.',
  SOLID+'Follow the guide. First a downward swing from high above the cap to low in front; then, without a pause, a rising backhand sweep from low in front back up to high above the cap; a brief hold; return to neutral. The baton stays straight, full length and in the same hand. He swings at empty air; nothing is there.',
  track([(0,REST),(.22,WIND),(.38,WIND),(.48,HIT),(.58,LOW),(.74,LOW),(.88,RISE),(.98,HIGH),(1.2,HIGH),(1.65,REST)],[.4,2.75])),
 ('145-cop-flinch','A cartoon startled flinch acted alone on an empty stage, three times.',
  SOLID+'Follow the guide. An actor miming a sudden flinch: his head jerks back and up, eyes squeeze shut, teeth clench under the mustache, chest caves in, shoulders jump, near fist flies up, front boot lifts; he holds it briefly and settles back to his neutral stance. He is completely alone; nothing touches him and nothing else is in the picture.',
  track([(0,REST),(.09,FLINCH),(.30,FLINCH),(.75,REST)],[.4,1.95,3.5])),
 ('146-cop-stagger','A cartoon stagger to one knee and recovery, acted alone on an empty stage, twice.',
  SOLID+'Follow the guide. An actor miming losing his breath: he doubles over at the waist, makes a tiny backward hop with both boots, drops onto one knee with the near hand on the floor, shakes his head slowly, then stands back up to neutral. Cap and baton stay with him. He is completely alone; nothing touches him and nothing else is in the picture.',
  track([(0,REST),(.10,FOLD),(.22,HOP),(.40,KNEEL),(.75,KNEEL2),(1.05,KNEEL),(1.8,REST)],[.4,2.75])),
]


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    reference(refs/'cop.png',430,690);shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    rows=[];sheet=Image.new('RGB',(6*230,4*230),BG);sheet.paste(Image.open(refs/'cop.png').resize((230,230)),(0,0))
    for j,(ident,summary,action,at) in enumerate(SHOTS):
        guide='guide-'+ident+'.mp4'
        with av.open(str(refs/guide),'w') as output:
            stream=output.add_stream('libx264',rate=24);stream.width=stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
            for i in range(120):
                image=draw(at(i/24))
                if i in (0,18,21,24,30):sheet.paste(image.resize((230,230)),((1+[0,18,21,24,30].index(i))*230,j*230))
                for packet in stream.encode(av.VideoFrame.from_image(image)):output.mux(packet)
            for packet in stream.encode():output.mux(packet)
        text=prompt(summary,action,CLEAN+' The frame contains only this one officer and empty background from first to last frame.')
        text=text.replace('<Picture 2> is a color swatch only. Its object must NOT appear.','<Picture 2> is a color swatch only. Its object must NOT appear. <Video 1> defines body motion, timing, position and scale only; never render the colored mannequin.')
        text=text.replace('<Picture 2> (swatch): not_preserved - never show it.','<Picture 2> (swatch): not_preserved - never show it.\n<Video 1>: partially_preserved - joint motion, baton angle and timing. Ignore its appearance.')
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':'cop.png','item_reference':'proxy-grip.png','motion_reference':guide,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    sheet.save(OUT/'preview.png');queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
