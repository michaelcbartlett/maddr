"""Colored canine motion calibration, not generated character art. Never submits jobs.

Four independent three-link legs, fixed-length two-bone IK, separate canine
stifle/hock and elbow/wrist chains, neck/skull/jaw/tail sockets and contact tracks.
Organic and mechanical guides share the rig and color IDs, not movement timing.
"""
from pathlib import Path
import argparse
import json
import math
import av
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'export/comfyui/quadruped-guides'
BG=(22,29,40)
FPS=24
GROUND=680.
MODES=('organic','mechanical')
STUDIES=('idle','walk','trot','run','start-stop','bark','bite','pounce',
         'flinch','stagger','stunned','frozen','search','retreat','collapse-front','collapse-side')
PALETTE={
    'pelvis':'#df43ac','spine':'#9c51d6','chest':'#6448d0','neck':'#a7d543',
    'skull':'#ffd43c','muzzle':'#ff9c37','jaw':'#e86762',
    'tail_base':'#eeeeec','tail_mid':'#acb8c4','tail_tip':'#667782',
    'near_front_upper':'#fa3939','near_front_lower':'#ff882b','near_front_distal':'#ffc45b','near_front_paw':'#ffef9a',
    'far_front_upper':'#178fc9','far_front_lower':'#15c9c4','far_front_distal':'#74dfed','far_front_paw':'#b9f9ff',
    'near_hind_upper':'#8db82a','near_hind_lower':'#438e47','near_hind_distal':'#4dda85','near_hind_paw':'#b3ef9a',
    'far_hind_upper':'#4c68cb','far_hind_lower':'#8859b9','far_hind_distal':'#b493e3','far_hind_paw':'#e5c5ff',
}


def endpoint(origin, degrees, length):
    a=math.radians(degrees)
    return np.array(origin,float)+np.array((math.cos(a),math.sin(a)))*length


def rotate(point,degrees):
    a=math.radians(degrees);x,y=point
    return np.array((x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a)))


def smooth(k):
    k=max(0.,min(1.,k));return k*k*(3-2*k)


def keys(t,points):
    if t<=points[0][0]:return points[0][1]
    for (ta,a),(tb,b) in zip(points,points[1:]):
        if ta<=t<=tb:return a+(b-a)*smooth((t-ta)/(tb-ta))
    return points[-1][1]


def pulse(t,starts,points):
    return max([keys(t-s,points) if t>=s else 0. for s in starts]+[0.],key=abs)


def two_bone(root,end,a,b,bend):
    root=np.array(root,float);end=np.array(end,float);delta=end-root
    actual=float(np.linalg.norm(delta));distance=max(abs(a-b)+1e-5,min(actual,a+b-1e-5))
    direction=delta/max(actual,1e-9)
    projected=(a*a-b*b+distance*distance)/(2*distance)
    height=math.sqrt(max(0.,a*a-projected*projected))
    mid=root+direction*projected+np.array((-direction[1],direction[0]))*height*bend
    reached=root+direction*distance
    return mid,reached,float(np.linalg.norm(reached-end))


def stride(phase,duty,width,lift):
    phase%=1.
    if phase<duty:
        return width*(.5-phase/duty),0.,True
    u=(phase-duty)/(1-duty)
    return width*(-.5+smooth(u)), -lift*math.sin(math.pi*u),False


def pose(t,study='walk',mode='organic'):
    if study not in STUDIES or mode not in MODES:raise ValueError((study,mode))
    machine=mode=='mechanical'
    phase_t=t
    root=np.array((288.,503.));pitch=0.;neck_angle=-51.;head_angle=0.;jaw=9.;tail=0.
    gait=None;blend=1.;attack=0.;fall=0.;fold=0.;stun=0.
    if study in ('walk','trot','run','retreat'):gait=study
    elif study=='start-stop':
        gait='walk';blend=keys(t,[(0,0),(.45,0),(.85,1),(2.6,1),(3.2,0),(5,0)])
    elif study=='bite':
        attack=pulse(t,(.4,2.7),[(0,0),(.3,-.35),(.45,-.35),(.58,1),(.8,.85),(1.35,0)])
        neck_angle+=attack*24;head_angle=attack*7;jaw=keys(attack,[(-.35,30),(0,9),(.5,30),(1,0)])
        pitch=attack*3
    elif study=='pounce':
        attack=pulse(t,(.4,2.8),[(0,0),(.3,-.35),(.45,-.35),(.7,1),(.95,1),(1.2,.1),(1.5,0)])
        root[1]-=max(attack,0)*52;root[1]-=min(attack,0)*45
        pitch=attack*-7;neck_angle+=max(attack,0)*9;jaw=9+max(attack,0)*20
    elif study in ('flinch','stagger'):
        fold=pulse(t,(.4,2.8),[(0,0),(.12,1),(.4,.8),(1.,.5),(1.55,0)])
        root[1]+=fold*(49 if study=='stagger' else 14);pitch=fold*-7
        neck_angle-=fold*16;head_angle-=fold*8;jaw=9+fold*10
    elif study=='bark':
        jaw=7+pulse(t,(.5,1.6,2.7,3.8),[(0,0),(.12,1),(.28,1),(.45,0)])*28
        neck_angle-=max(jaw-7,0)*.18
    elif study=='stunned':
        stun=math.sin(t*2*math.pi/2.5);root[1]+=8+5*stun;pitch=stun*3
        neck_angle+=13+stun*5;head_angle=stun*6;jaw=15
    elif study=='frozen':
        freeze=min(t,1.35);shake=(1-smooth((freeze-1.1)/.25))*math.sin(freeze*48)*2 if freeze>.4 else 0
        root[0]+=shake;neck_angle-=keys(freeze,[(0,0),(.4,0),(1.2,8),(1.35,8)])
        jaw=9
    elif study=='search':
        head_angle=keys(t,[(0,0),(.5,0),(1.2,12),(2.2,-12),(3.2,8),(4.2,0),(5,0)])
        neck_angle+=keys(t,[(0,0),(1.,20),(2.,20),(3.,-8),(4.2,0),(5,0)])
    elif study.startswith('collapse'):
        fall=keys(t,[(0,0),(.4,0),(1.35,1),(1.55,.94),(1.9,1),(5,1)])
        root[1]+=fall*(99 if study=='collapse-side' else 63)
        pitch=fall*(0 if study=='collapse-side' else 12)
        neck_angle+=fall*(66 if study=='collapse-side' else 60)
        head_angle=fall*(18 if study=='collapse-side' else 12);jaw=9+fall*8
    if study not in ('frozen','collapse-front','collapse-side'):
        root[1]+=math.sin(t*2*math.pi/2.5)*(0.8 if machine else 2.)
        tail=math.sin(t*2*math.pi/2.5)*(2 if machine else 8)
    cycles={'walk':5,'trot':8,'run':10,'retreat':5}
    phases={
        'walk':{'near_hind':0.,'near_front':.25,'far_hind':.5,'far_front':.75},
        'trot':{'near_front':0.,'far_hind':0.,'far_front':.5,'near_hind':.5},
        'run':{'near_front':.08,'far_front':0.,'near_hind':.51,'far_hind':.43},
        'retreat':{'near_hind':0.,'near_front':.25,'far_hind':.5,'far_front':.75},
    }
    if gait:
        if machine and gait=='run':
            # A controlled diagonal bounding trot, not an organic flexible-spine gallop.
            phases['run']=phases['trot']
        cycle=phase_t*cycles[gait]/5
        amp=({'walk':2,'retreat':2,'trot':6,'run':11}[gait])*(.3 if machine else 1.)
        root[1]-=amp*(.5-.5*math.cos(cycle*4*math.pi))*blend
    pelvis=root
    half=math.hypot(180.,22.)/2;back_angle=math.degrees(math.atan2(-22.,180.))+pitch
    arch=0.
    if gait and not machine:
        arch=math.sin(cycle*2*math.pi)*({'walk':1.,'retreat':1.,'trot':2.5,'run':7.}[gait])*blend
    spine=endpoint(pelvis,back_angle+arch,half);chest=endpoint(spine,back_angle-arch,half)
    neck_base=chest+rotate((8.,-24.),pitch-arch)
    skull=endpoint(neck_base,neck_angle+pitch,91.)
    joints={'pelvis':pelvis,'spine':spine,'chest':chest,'neck_base':neck_base,
            'skull':skull,'muzzle':skull+rotate((72.,19.),head_angle),
            'jaw_hinge':skull+rotate((18.,35.),head_angle)}
    joints['jaw_tip']=endpoint(joints['jaw_hinge'],head_angle+jaw,70.)
    tail_root=pelvis+rotate((-35.,-20.),pitch);joints['tail_root']=tail_root
    prev=tail_root
    for name,angle,length in [('tail_base',-172,65),('tail_mid',-130,62),('tail_tip',-70,55)]:
        prev=endpoint(prev,angle+pitch+tail,length);joints[name]=prev
    contacts={};errors={}
    for leg in ('far_hind','far_front','near_hind','near_front'):
        front='front' in leg;far=leg.startswith('far')
        anchor=(chest if front else pelvis)+rotate((19 if far else 0,-8 if far else 0),pitch-arch if front else pitch)
        paw=np.array((484. if front else 283.,GROUND-(9 if far else 0)))
        if far:paw[0]+=22
        contact=True
        if gait:
            width={'walk':69,'trot':83,'run':110,'retreat':60}[gait]*(.8 if machine else 1)
            duty={'walk':.7,'trot':.54,'run':.34,'retreat':.7}[gait]
            lift={'walk':24,'trot':38,'run':65,'retreat':22}[gait]*(.7 if machine else 1)
            dx,dy,contact=stride(cycle+phases[gait][leg],duty,width,lift)
            paw+=np.array((dx*(-1 if gait=='retreat' else 1),dy))*blend
            if blend<1e-4:contact=True
        if study=='pounce':
            flight=pulse(t,(.4,2.8),[(0,0),(.45 if front else .5,0),(.7 if front else .72,1),
                                    (.95 if front else .97,1),(1.25 if front else 1.42,0),(1.5,0)])
            paw[0]+=flight*(45 if front else -8)
            paw[1]-=flight*(100 if front else 88)
            contact=flight<=1e-6
        if fold:
            paw[0]-=fold*(18 if front else 8)
        if study=='collapse-side':paw[0]+=fall*(12 if front else 14)
        offset=np.array((-9.,-25.) if front else (-18.,-44.))
        distal=paw+offset
        a,b=(95.,99.) if front else (90.,91.)
        mid,reached,error=two_bone(anchor,distal,a,b,1 if front else -1)
        if error>1e-3:
            # A guide must never silently stretch bones or detach a planted paw.
            raise ValueError(f'Unreachable {study}/{mode}/{leg} at {t:.3f}: {error:.2f}px')
        joints.update({leg+'_root':anchor,leg+'_mid':mid,leg+'_distal':reached,leg+'_paw':paw})
        contacts[leg]=contact;errors[leg]=error
    return {'joints':{k:tuple(float(x) for x in v) for k,v in joints.items()},
            'contacts':contacts,'ik_error':errors,'head_angle':head_angle,'jaw_angle':jaw,
            'mode':mode,'study':study,'time':t}


def render(p,small=False):
    image=Image.new('RGB',(768,768),BG);d=ImageDraw.Draw(image)
    scale=.72 if small else 1.;ground=625 if small else GROUND
    def at(pt):return (384+(pt[0]-384)*scale,ground+(pt[1]-GROUND)*scale)
    j=p['joints'];machine=p['mode']=='mechanical'
    def limb(a,b,color,width):
        a=at(a);b=at(b);w=max(2,round(width*scale))
        d.line([a,b],fill=color,width=w)
        for x,y in (a,b):d.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill=color)
    def polygon(points,color):d.polygon([at(q) for q in points],fill=color)
    def leg(name):
        width=18 if name.startswith('far') else 23
        limb(j[name+'_root'],j[name+'_mid'],PALETTE[name+'_upper'],width)
        limb(j[name+'_mid'],j[name+'_distal'],PALETTE[name+'_lower'],width-3)
        x,y=j[name+'_paw']
        # Paw is the sole/contact control, so don't draw a round bone cap below it.
        limb(j[name+'_distal'],(x,y-10),PALETTE[name+'_distal'],width-5)
        polygon([(x-15,y-13),(x+20,y-13),(x+25,y),(x-15,y)],PALETTE[name+'_paw'])
        for joint in ('root','mid','distal'):
            x,y=at(j[name+'_'+joint]);r=4*scale
            d.ellipse((x-r,y-r,x+r,y+r),fill='#17202b')
    leg('far_hind');leg('far_front')
    last='tail_root'
    for key in ('tail_base','tail_mid','tail_tip'):
        limb(j[last],j[key],PALETTE[key],14 if machine else 20);last=key
    limb(j['pelvis'],j['spine'],PALETTE['spine'],65 if machine else 84)
    limb(j['spine'],j['chest'],PALETTE['chest'],65 if machine else 90)
    for name,radius in [('pelvis',37),('chest',40)]:
        x,y=at(j[name]);r=radius*scale
        if machine:d.rectangle((x-r,y-r*.8,x+r,y+r*.8),fill=PALETTE[name])
        else:d.ellipse((x-r,y-r,x+r,y+r),fill=PALETTE[name])
    limb(j['neck_base'],j['skull'],PALETTE['neck'],45)
    leg('near_hind');leg('near_front')
    center=np.array(j['skull']);angle=p['head_angle']
    head=lambda v: center+rotate(v,angle)
    polygon([head(q) for q in [(-49,-39),(25,-45),(50,-8),(27,36),(-39,40)]],PALETTE['skull'])
    # Separate ears and lower jaw make head identity/hinge movement explicit.
    for x in (-29,13):polygon([head((x-15,-32)),head((x-5,-110)),head((x+21,-33))],PALETTE['skull'])
    polygon([head((20,4)),head((89,7)),head((95,28)),head((25,32))],PALETTE['muzzle'])
    hinge=np.array(j['jaw_hinge']);a=p['jaw_angle']+angle
    polygon([hinge+rotate(q,a) for q in [(0,0),(68,0),(65,14),(-2,13)]],PALETTE['jaw'])
    eye=at(head((25,-12)));r=4*scale;d.ellipse((eye[0]-r,eye[1]-r,eye[0]+r,eye[1]+r),fill='#10151d')
    return image


def write_guide(path,study,mode='organic',small=False):
    records=[];path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with av.open(str(path),'w') as video:
        stream=video.add_stream('libx264',rate=FPS);stream.width=stream.height=768
        stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
        for i in range(120):
            p=pose(i/FPS,study,mode);records.append(p)
            for packet in stream.encode(av.VideoFrame.from_image(render(p,small))):video.mux(packet)
        for packet in stream.encode():video.mux(packet)
    path.with_suffix('.json').write_text(json.dumps({'fps':FPS,'seconds':5,'small':small,
        'layout':{'scale':.72 if small else 1.,'pivot':[384,GROUND],'ground':625 if small else GROUND},
        'joint_coordinates':'unscaled rig pixels; apply layout to match the video','frames':records},indent=2),encoding='utf-8')


def build():
    OUT.mkdir(parents=True,exist_ok=True);catalog=[]
    for mode in MODES:
        for study in STUDIES:
            path=OUT/mode/('guide-'+study+'.mp4');write_guide(path,study,mode)
            catalog.append({'mode':mode,'study':study,'small':False,'seconds':5,'fps':FPS,'video':str(path.relative_to(OUT)),
                            'joints':str(path.with_suffix('.json').relative_to(OUT))})
        for study in ('collapse-front','collapse-side'):
            path=OUT/mode/('guide-'+study+'-small.mp4');write_guide(path,study,mode,True)
            catalog.append({'mode':mode,'study':study,'small':True,'seconds':5,'fps':FPS,'video':str(path.relative_to(OUT)),
                            'joints':str(path.with_suffix('.json').relative_to(OUT))})
        render(pose(0,'idle',mode)).save(OUT/mode/'rig.png')
    (OUT/'motion-catalog.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
    (OUT/'palette.json').write_text(json.dumps(PALETTE,indent=2),encoding='utf-8')
    font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',18)
    chart=Image.new('RGB',(1280,960),BG);d=ImageDraw.Draw(chart)
    for row,study in enumerate(('walk','trot','run','pounce')):
        for col,t in enumerate((.4,.65,.9,1.15,1.4)):
            chart.paste(render(pose(t,study)).resize((256,240)),(col*256,row*240))
        d.text((12,row*240+8),study,font=font,fill='white')
    chart.save(OUT/'motion-preview.png')
    legend=Image.new('RGB',(1280,850),BG);legend.paste(render(pose(0,'idle')).resize((768,768)),(0,30));d=ImageDraw.Draw(legend)
    d.text((20,15),'Quadruped joint/part calibration — faces screen-right',font=font,fill='white')
    for i,(name,color) in enumerate(PALETTE.items()):
        y=45+i*28;d.rectangle((790,y,813,y+19),fill=color);d.text((827,y),name,font=font,fill='white')
    legend.save(OUT/'rig-and-palette.png')
    print(f'Built {len(catalog)} canine guides at 24fps. No generation jobs submitted.')


if __name__=='__main__':
    argparse.ArgumentParser(description=__doc__).parse_args();build()
