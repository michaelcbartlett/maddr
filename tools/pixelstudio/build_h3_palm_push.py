"""Isolated open-palm shove arm, near and far views. Never queues."""
import shutil
import av
import cv2
import numpy as np
from PIL import Image,ImageDraw
import build_h3_layer_test as T
from build_h3_layers import recolor
from build_h3_sprite_pack import PACK
from import_h3_scientist import REST_POLYGON,REST_SHOULDER,polygon,clip
from review_h3_modular_batch import matte
import queue_h3_animations as queue

OUT=PACK/'palm-push'
# seconds, upper-arm angle, elbow bend (screen angles, down = 90)
KEYS=[(0,86,-22),(.16,118,-112),(.24,118,-112),(.34,2,-4),(.50,2,-4),(.95,86,-22)]


def pose(t,*_):
    for start in [.5,2.,3.5]:
        local=t-start
        if 0<=local<=KEYS[-1][0]:
            for (ta,a,b),(tb,c,d) in zip(KEYS,KEYS[1:]):
                if ta<=local<=tb:
                    k=(local-ta)/(tb-ta);k=k*k*(3-2*k);return a+(c-a)*k,b+(d-b)*k
    return KEYS[0][1],KEYS[0][2]


def draw(t,study):
    old=T.arm_pose;T.arm_pose=pose
    try:image,joints=T.arm_guide(t,study)
    finally:T.arm_pose=old
    pixels=np.asarray(image).copy();pixels[(pixels==(0,255,0)).all(axis=2)]=T.BG
    image=Image.fromarray(pixels);d=ImageDraw.Draw(image)
    wrist=np.array(joints[2],float);u=wrist-np.array(joints[1],float);u/=np.linalg.norm(u)
    upper,bend=pose(t);flat=abs(upper+bend)<30      # upright flat palm at the thrust
    v=np.array([-u[1],u[0]]) if flat else u
    a,b=(wrist-v*34+u*16,wrist+v*34+u*16) if flat else (wrist-v*4,wrist+v*46)
    d.line([tuple(a),tuple(b)],fill='#f2b49b',width=26);return image,joints


def reference(path,dim):
    frame=clip('38-far-straight-sweep')[50]
    region=(cv2.GaussianBlur(polygon(REST_POLYGON).astype(np.float32),(0,0),3)>.5)&(np.asarray(matte(frame))>0)
    ys,xs=np.where(region);hand=np.array([xs[ys>ys.max()-30].mean(),ys.max()-30.])
    scale=(T.UPPER+T.FORE+30)/np.linalg.norm(hand-REST_SHOULDER)
    m=np.array([[scale,0,0],[0,scale,0]],float);m[:,2]=T.SHOULDER-scale*REST_SHOULDER
    rgb=(np.asarray(frame).astype(np.float32)*(.86 if dim else 1.)).astype(np.uint8)
    rgba=np.dstack((rgb,region.astype(np.uint8)*255));image=Image.new('RGBA',(768,768),T.BG)
    image.alpha_composite(Image.fromarray(cv2.warpAffine(rgba,m,(768,768),flags=cv2.INTER_NEAREST)));image.convert('RGB').save(path)


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True);shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    reference(refs/'near-open-arm.png',False);reference(refs/'far-open-arm.png',True)
    who='one isolated white laboratory-coat sleeve with its cuff and one EMPTY open bare hand'
    base=('The rounded shoulder end stays pinned at one fixed point. The arm hangs relaxed with a soft elbow. Three times, at 0.50, 2.00 and 3.50 seconds, '
        'it performs a sharp cartoon palm push toward screen-right: the elbow folds and draws back, then the whole arm snaps straight and level to screen-right '
        'with the wrist cocked up and the open hand flat and upright, {view}, fingers together pointing up, held for a moment before swinging back down to the exact '
        'relaxed start. Cloth folds bunch at the elbow on the draw and stretch on the push. The hand is empty at all times. It pushes empty air; nothing is there.')
    rows=[];sheet=Image.new('RGB',(6*220,2*220),T.BG);marks=[0,16,18,20,28]
    for j,(ident,subject,fn,view) in enumerate([
        ('157-near-palm-push','near-open-arm.png',draw,'showing the BACK of the hand, palm facing screen-right'),
        ('158-far-palm-push','far-open-arm.png',recolor(draw),'showing the thumb-side edge of the hand, palm facing screen-right')]):
        motion='guide-'+ident+'.mp4';sheet.paste(Image.open(refs/subject).resize((220,220)),(0,j*220))
        with av.open(str(refs/motion),'w') as output:
            stream=output.add_stream('libx264',rate=24);stream.width=stream.height=768;stream.pix_fmt='yuv420p';stream.options={'crf':'12'}
            for i in range(120):
                image,_=fn(i/24,'')
                if i in marks:sheet.paste(image.resize((220,220)),((1+marks.index(i))*220,j*220))
                for packet in stream.encode(av.VideoFrame.from_image(image)):output.mux(packet)
            for packet in stream.encode():output.mux(packet)
        text=T.prompt(who,base.format(view=view),T.NO_BODY+' No gun, block, tool or object of any kind.',False)
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':motion,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    sheet.save(OUT/'preview.png');queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([x['id'] for x in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
