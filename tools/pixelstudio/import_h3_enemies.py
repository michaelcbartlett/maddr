"""Install H3 full-body enemy clips with MoGe normals in the edited-clip format.

Usage: python import_h3_enemies.py [cop] [det]
"""
from pathlib import Path
import json
import math
import shutil
import sys
import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from review_h3_modular_batch import ROOT,DEFAULT_BATCH,load,matte
import moge_normals

ART=ROOT/'godot/art/enemies'
CELL=(176,116);ORIGIN=(98,108)
WIDE=((256,152),(146,134))   # lying bodies, puddles and tall flames
R=lambda a,n,step=1:list(range(a,a+n,step))
# state: (clip id, frames, fps, loop, figure height in the source clip)
KINDS={
 'cop':{'height':80,'clips':{
  'idle':('101',R(23,33),24,True,500),'walk':('102',R(28,29),24,True,500),'run':('103',R(71,12),24,True,500),
  'attack':('120',R(12,36),30,False,430),'hurt':('145',[18,19,21,23,26],20,False,430),
  'stagger':('146',R(10,42,2),12,False,430),'frozen':('113',[70],1,False,500),'stunned':('112',R(44,20,2),12,True,500),
  'sick':('114',R(57,46,3),8,True,500),'hypnotized':('115',R(55,19),24,True,500),'burning':('117',R(75,9),18,True,500),
  'death':('110',R(34,30),24,False,340),'death_poison':('151',R(22,60,3),10,False,340),
  'death_melt':('152',R(40,78,3),14,False,340),'death_burnt':('153',R(20,98,4),13,False,340)},
  'hits':{'attack':[11,19]}},
 'det':{'height':88,'clips':{
  'idle':('121',R(35,34),24,True,500),'walk':('124',R(61,18),24,True,500),'backpedal':('142',R(57,18),24,True,500),
  'flee':('143',R(80,13),24,True,500),'attack':('126',R(24,92,3),24,False,500),'shoot':('127',[19,20,21,22,24,26,28],24,False,500),
  'cornered':('144',R(42,26,2),24,False,500),'hurt':('131',[24,25,27,30,33],20,False,500),'frozen':('136',[90],1,False,500),
  'stunned':('135',R(39,30,3),9,True,500),'sick':('137',R(45,30,3),8,True,500),'hypnotized':('138',R(59,32,2),12,True,500),
  'burning':('140',R(71,24,2),14,True,500),'death':('133',R(37,28),24,False,330),'death_poison':('154',R(20,62,3),10,False,330),
  'death_melt':('155',R(36,82,3),14,False,330),'death_burnt':('156',R(16,102,4),13,False,330)},
  'hits':{}}}


def clip(number):
    folder=next(d for d in DEFAULT_BATCH.iterdir() if d.name.startswith(number+'-'))
    return folder.name,load(max(folder.glob('*_audio.mp4'),key=lambda p:p.stat().st_mtime))


def cutout(frame,solo):
    """Figure alpha. `solo` keeps only the biggest piece (drops loose smoke, sparks and tracers)."""
    alpha=(np.asarray(matte(frame))>0)
    count,labels,stats,_=cv2.connectedComponentsWithStats(alpha.astype(np.uint8),8)
    if count<2:return alpha
    main=max(range(1,count),key=lambda i:stats[i,cv2.CC_STAT_AREA])
    if solo:return labels==main
    keep=np.isin(labels,[i for i in range(1,count) if stats[i,cv2.CC_STAT_AREA]>260])
    return keep


def feet(alpha):
    ys,xs=np.where(alpha);ground=ys.max();row=xs[ys>ground-30];return (row.min()+row.max())/2,ground


def place(rgb,alpha,scale,foot):
    """Area-filtered, hard-edged 1:1 game pixels with the foot point on ORIGIN."""
    m=np.array([[scale,0,ORIGIN[0]-foot[0]*scale],[0,scale,ORIGIN[1]-foot[1]*scale]])
    over=4;mo=m*over;size=(CELL[0]*over,CELL[1]*over)
    a=cv2.warpAffine(alpha.astype(np.float32),mo,size,flags=cv2.INTER_LINEAR)
    c=cv2.warpAffine(rgb.astype(np.float32)*alpha[...,None],mo,size,flags=cv2.INTER_LINEAR)
    a=cv2.resize(a,CELL,interpolation=cv2.INTER_AREA);c=cv2.resize(c,CELL,interpolation=cv2.INTER_AREA)
    solid=a>=.5;out=np.zeros((CELL[1],CELL[0],4),np.uint8)
    out[solid,:3]=np.clip(c[solid]/a[solid,None],0,255);out[solid,3]=255
    return out,m


def encode(n,m,solid):
    moved=cv2.warpAffine(n,m,CELL,flags=cv2.INTER_AREA if False else cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
    moved=moge_normals.unit(moved);moved[:,:,2]=np.maximum(moved[:,:,2],.15);moved=moge_normals.unit(moved)
    out=np.zeros((CELL[1],CELL[0],4),np.uint8);out[solid,:3]=np.rint((moved[solid]*.5+.5)*255);out[solid,3]=255;return out


def extend(n,alpha):
    inside=cv2.erode(alpha.astype(np.uint8),np.ones((5,5),np.uint8))>0
    if not inside.any():inside=alpha
    if not inside.any():return n
    _,(iy,ix)=distance_transform_edt(~inside,return_indices=True);return n[iy,ix]


def build(kind):
    spec=KINDS[kind];out=ART/kind
    backup=ROOT/'export/pixelstudio'/('previous-'+kind)
    if out.exists() and not backup.exists():shutil.copytree(out,backup)
    out.mkdir(parents=True,exist_ok=True)
    for old in out.glob(kind+'_*'):old.unlink()
    cache={};base={}
    global CELL,ORIGIN
    normal_cell=(CELL,ORIGIN)
    for state,(number,frames,fps,loop,height) in spec['clips'].items():
        CELL,ORIGIN=WIDE if state.startswith('death') or state=='burning' else normal_cell
        name,video=cache.setdefault(number,clip(number));scale=spec['height']/height
        foot=feet(cutout(video[0],True))
        frames=[f for f in frames if f<len(video)]
        chosen=[video[f] for f in frames];solo=not state.startswith('death')
        alphas=[cutout(f,solo) for f in chosen];estimated=moge_normals.estimate(chosen)
        if estimated is None:raise SystemExit('ComfyUI is not reachable')
        normals=[extend(n,a) for n,a in zip(estimated,alphas)]
        if loop and len(normals)>2:normals=moge_normals.smooth_loop(normals)
        art=Image.new('RGBA',(CELL[0]*len(chosen),CELL[1]));nrm=Image.new('RGBA',art.size);anchors=[];aims=[];clipped=0
        for i,(frame,alpha,n) in enumerate(zip(chosen,alphas,normals)):
            tile,m=place(np.asarray(frame),alpha,scale,foot);solid=tile[:,:,3]>0
            clipped+=int(solid[0].any() or solid[-1].any() or solid[:,0].any() or solid[:,-1].any())
            art.paste(Image.fromarray(tile),(i*CELL[0],0));nrm.paste(Image.fromarray(encode(n,m,solid)),(i*CELL[0],0))
            h=spec['height'];ys,xs=np.where(solid)
            muzzle=[h*.42,-h*.55]
            if kind=='det' and len(xs) and state in ('attack','shoot','walk','backpedal','cornered'):
                k=int(np.argmax(xs-.15*ys*0));top=ys[xs>=xs.max()-1];muzzle=[float(xs.max()-ORIGIN[0]),float(top.min()-ORIGIN[1]+1)]
            anchors.append({'head':[0,-round(h*.8)],'eye':[round(h*.13),-round(h*.72)],'eye_far':[round(h*.04),-round(h*.72)],
                'chest':[0,-round(h*.42)],'hand_n':[round(h*.25),-round(h*.4)],'hand_f':[-round(h*.2),-round(h*.35)],'muzzle':muzzle})
            if state=='attack' and kind=='det':aims.append(math.degrees(math.atan2(muzzle[1]+h*.68,muzzle[0]+h*.08)))
        art.save(out/f'{kind}_{state}.png');nrm.save(out/f'{kind}_{state}_n.png')
        meta={'format':'enemy-edited-clip-v1','native':True,'kind':kind,'animation':state,'frame_width':CELL[0],'frame_height':CELL[1],
            'frame_count':len(chosen),'fps':fps,'holds':[1]*len(chosen),'origin':list(ORIGIN),'anchors':anchors,'loop':loop,
            'normal_mode':'moge-2','source_clip':name,'source_frames':frames}
        if state in spec['hits']:meta['hit_frames']=spec['hits'][state]
        if aims:meta['aim_degrees']=[round(a,1) for a in aims]
        (out/f'{kind}_{state}.json').write_text(json.dumps(meta),encoding='utf-8')
        print(kind,state,len(chosen),'frames','CLIPPED %d'%clipped if clipped else '',('aims %.0f..%.0f'%(aims[0],aims[-1])) if aims else '')
    CELL,ORIGIN=normal_cell
    manifest=json.loads((ART/'edited.json').read_text());manifest[kind]=list(spec['clips'])
    (ART/'edited.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')


if __name__=='__main__':
    for kind in (sys.argv[1:] or list(KINDS)):build(kind)
