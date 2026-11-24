"""Import the approved H3 scientist as a native 128px layered game skin.

Keeps the body, arms, hands, weapons and effects separate. Rebuild with ComfyUI's
Python environment; runtime needs only the generated PNGs and JSON, not videos.
"""
from pathlib import Path
import json
import math
import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
from review_h3_modular_batch import ROOT, DEFAULT_BATCH, load, matte, cut, native as raw_native
from preview_h3_walk_shoot import locate_belt
import moge_normals

OUT=ROOT/'godot/character/art/scientist_h3'

def native(image):
    image=raw_native(image);rgba=np.asarray(image).copy()
    n,labels,stats,_=cv2.connectedComponentsWithStats((rgba[:,:,3]>0).astype(np.uint8),8)
    for i in range(1,n):
        if stats[i,cv2.CC_STAT_AREA]<4:rgba[labels==i]=0
    return Image.fromarray(rgba)


def polygon(points):
    image=Image.new('L',(768,768));ImageDraw.Draw(image).polygon(points,fill=255)
    return np.asarray(image)>0


def extract(frame,region):
    alpha=np.asarray(matte(frame)).copy();alpha[~region]=0
    rgb=np.asarray(frame).astype(np.int16)
    green=(rgb[:,:,1]>85)&(rgb[:,:,1]>rgb[:,:,0]*1.5)&(rgb[:,:,1]>rgb[:,:,2]*1.4)
    alpha[cv2.dilate(green.astype(np.uint8),np.ones((3,3),np.uint8))>0]=0
    return cut(frame,Image.fromarray(alpha))


def normal(image):
    rgba=np.asarray(image);mask=rgba[:,:,3]>0
    height=np.minimum(distance_transform_edt(mask),3)*1.5
    gy,gx=np.gradient(height)
    vector=np.stack((-gx,gy,np.ones_like(gx)*3),axis=2)
    vector/=np.linalg.norm(vector,axis=2,keepdims=True)
    result=np.zeros_like(rgba);result[:,:,:3]=np.rint((vector*.5+.5)*255).astype(np.uint8)
    result[:,:,3]=rgba[:,:,3]
    return Image.fromarray(result)


def save_part(name,image):
    small=native(image);small.save(OUT/(name+'.png'));normal(small).save(OUT/(name+'_n.png'))


def grip_geometry(frame,shoulder=None):
    rgb=np.asarray(frame).astype(np.int16)
    mask=(rgb[:,:,1]>130)&(rgb[:,:,1]>rgb[:,:,0]*1.6)&(rgb[:,:,1]>rgb[:,:,2]*1.5)
    count,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
    component=max(range(1,count),key=lambda i:stats[i,cv2.CC_STAT_AREA])
    ys,xs=np.where(labels==component);points=np.column_stack((xs,ys)).astype(float)
    _,axes=np.linalg.eigh(np.cov(points.T));u=axes[:,-1]
    if (u[0]<0 if shoulder is None else np.dot(u,points.mean(axis=0)-shoulder)<0):u=-u
    v=np.array([-u[1],u[0]]);us,vs=points@u,points@v
    values,counts=np.unique(np.rint(vs).astype(int),return_counts=True)
    dense=values[counts>counts.max()*.7]
    center=float(dense.mean());bar_height=float(dense.max()-dense.min()+1)
    grip=u*(us.min()+.22*(us.max()-us.min()))+v*(center+bar_height*1.05)
    return grip,float(math.atan2(u[1],u[0]))


# Straightened arm space: shoulder at ARM_O, hand along +x. Source pixels.
ARM_O=np.array([110.,100.]);ARM_SIZE=(420,220)
# Sleeve edges at the shoulder, cap length, and the first column not hidden by
# the torso, as drawn in the two straight-sweep studies.
ARM_SHAPE={'near':{'top':-32,'bottom':52,'cap':46,'clear':0,'search':(-52,-18,34,66)},
           'far':{'top':-13,'bottom':58,'cap':30,'clear':48,'search':(-30,4,44,72)}}


def cut_straight_arm(frame,shoulder,grip,side):
    """Return a sleeve and a hand in straightened space, without chest or face.

    The sleeve edge follows the drawn outline. Hidden shoulder columns reuse the
    visible sleeve, and the shoulder end is a soft round cap, not a flat cut.
    """
    shape=ARM_SHAPE[side];angle=math.atan2(*(grip-shoulder)[::-1]);c,sn=math.cos(angle),math.sin(angle)
    matrix=np.array([[c,sn,0.],[-sn,c,0.]]);matrix[:,2]=ARM_O-matrix[:,:2]@shoulder
    def straighten(image):return cv2.warpAffine(image,matrix,ARM_SIZE,flags=cv2.INTER_NEAREST)
    rgb=straighten(np.asarray(frame)).astype(np.int16);opaque=straighten(np.asarray(matte(frame)))>0
    r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2];yy,xx=np.indices(r.shape)
    ox,oy=ARM_O.astype(int);length=float(np.linalg.norm(grip-shoulder))
    green=cv2.dilate(((g>85)&(g>r*1.5)&(g>b*1.4)).astype(np.uint8),np.ones((3,3),np.uint8))>0
    skin=(r>g*1.18)&(r>b*1.12)&(g>85)&~green
    # Hand: the skin component at the grip, plus its own outline.
    near_grip=(xx-ox-length)**2+(yy-oy)**2<56**2
    count,labels,stats,centers=cv2.connectedComponentsWithStats((skin&near_grip).astype(np.uint8),8)
    choices=[i for i in range(1,count) if stats[i,cv2.CC_STAT_AREA]>150]
    main=max(choices,key=lambda i:stats[i,cv2.CC_STAT_AREA]-25*np.linalg.norm(centers[i]-[ox+length,oy]))
    hand=labels==main
    for i in choices:
        if i!=main and np.linalg.norm(centers[i]-centers[main])<38:hand|=labels==i
    columns=np.where(hand.sum(axis=0)>12)[0];end=int(columns.min())
    dark=(r+g+b)<150
    hand=hand|(cv2.dilate(hand.astype(np.uint8),np.ones((15,15),np.uint8))>0)&dark&opaque&(xx>=end)
    hand&=~green
    # Sleeve edges: outer side of the dark outline, regularised along the arm.
    tops,bottoms=[],[];start=ox+shape['clear'];t0,t1,b0,b1=shape['search']
    for x in range(start,end):
        column=dark[:,x]
        ys=[y for y in range(oy+t0,oy+t1) if column[y]];tops.append(ys[-1]-5 if ys else np.nan)
        ys=[y for y in range(oy+b0,oy+b1) if column[y]];bottoms.append(ys[0]+5 if ys else np.nan)
    def regular(values,fallback):
        # Straight edge: a curved fit makes a rigid sleeve bow like a bent elbow.
        v=np.array(values,float);ok=~np.isnan(v);xs=np.arange(len(v));fit=None
        ok&=np.abs(np.nan_to_num(v,nan=1e6)-fallback)<15
        for _ in range(4):
            if ok.sum()<30:return np.full(len(v),float(fallback))
            fit=np.polyval(np.polyfit(xs[ok],v[ok],1),xs);ok&=np.abs(np.nan_to_num(v,nan=1e6)-fit)<7
        if abs(fit[0]-fallback)>9:return np.full(len(v),float(fallback))
        return fit
    tops=regular(tops,oy+shape['top']);bottoms=regular(bottoms,oy+shape['bottom'])
    top=np.zeros(ARM_SIZE[0])+tops[0];bottom=np.zeros(ARM_SIZE[0])+bottoms[0]
    top[start:end]=tops;bottom[start:end]=bottoms
    mask=(xx>=ox)&(xx<end)&(yy>=top[xx])&(yy<=bottom[xx])
    cy,ry=(top[ox]+bottom[ox])/2,(bottom[ox]-top[ox])/2
    mask|=(xx<ox)&(((xx-ox)/shape['cap'])**2+((yy-cy)/ry)**2<=1)
    color=rgb.copy()
    if shape['clear']:
        # Stretch the visible cloth over the torso-hidden upper arm. Mirroring
        # it would leave a symmetric chevron in the folds.
        first=ox-shape['cap'];last=end-34
        for x in range(first,last):
            color[:,x]=rgb[:,int(start+(x-first)*(last-start)/(last-first))]
    if side=='near' and .6<angle<1.35:
        # His hair hangs over the shoulder in these frames; it is cloth-grey, so
        # colour alone cannot reject it. Reuse the sleeve just past the joint.
        for x in range(ox-shape['cap'],ox+8):color[:,x]=rgb[:,2*(ox+8)-x]
    cr,cg,cb=color[:,:,0],color[:,:,1],color[:,:,2]
    cloth=(cr+cg+cb>240)&(np.abs(cr-cg)<30)&(np.abs(cb-cg)<42)
    cuff=xx>=end-24
    inner=cv2.erode(mask.astype(np.uint8),np.ones((13,13),np.uint8))>0
    # Stray shirt/face/background inside the sleeve edge or shoulder cap.
    bad=mask&~cuff&~cloth&(~inner|(xx<ox+55))
    good=mask&cloth
    _,(iy,ix)=distance_transform_edt(~good,return_indices=True)
    color[bad]=color[iy[bad],ix[bad]]
    # Redraw one consistent outline; keep the shoulder cap's inner edge soft.
    padded=np.pad(mask,8).astype(np.uint8)
    eroded=cv2.erode(padded,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(13,13)))[8:-8,8:-8]>0
    rim=mask&~eroded&(xx<end-6)
    rim|=mask&(xx>=end-6)&((yy<top[xx]+7)|(yy>bottom[xx]-7))
    color[rim]=np.where((xx>ox+4)[...,None],[12,9,18],[96,90,118])[rim]
    def layer(colors,alpha):
        return np.dstack((np.clip(colors,0,255).astype(np.uint8),alpha.astype(np.uint8)*255))
    return layer(color,mask&~hand&~green),layer(rgb,hand),angle


def place_straight_arm(layer,shoulder,angle,factor):
    c,sn=math.cos(angle)*factor,math.sin(angle)*factor
    matrix=np.array([[c,-sn,0.],[sn,c,0.]]);matrix[:,2]=shoulder-matrix[:,:2]@ARM_O
    return Image.fromarray(cv2.warpAffine(layer,matrix,(768,768),flags=cv2.INTER_NEAREST))


RAISE={'near':('57-arm-only-raise',[28,30,32,34,36,38]),'far':('61-far-arm-raise',[26,28,30,32,34,36])}
SWEEP={'near':'71-near-natural-sweep','far':'72-far-natural-sweep'}
JOLT={'near':('73-near-natural-jolt',None),'far':('74-far-natural-jolt',None)}


def jolt_frames(video):
    """Peak kick, mid and settling frames of the second jolt (the first starts straight)."""
    angles=[grip_geometry(f,ISOLATED_SHOULDER)[1] for f in video]
    peak=min(range(46,64),key=lambda i:angles[i])
    return [peak,peak+2,peak+5]


def clip(name):
    files=list((DEFAULT_BATCH/name).glob('*_audio.mp4'))
    return load(max(files,key=lambda p:p.stat().st_mtime)) if files else None


REST_POLYGON=[(224, 324), (234, 310), (254, 304), (272, 310), (284, 324), (286, 348), (284, 370), (280, 385), (278, 400), (283, 422), (283, 452), (287, 481), (294, 488), (296, 516), (302, 528), (315, 539), (318, 560), (312, 568), (312, 580), (304, 596), (273, 600), (250, 582), (240, 562), (237, 536), (228, 534), (206, 517), (206, 490), (210, 476), (204, 452), (201, 426), (201, 385), (207, 354), (216, 332)]
BACK_DASH=[14,16,20,26,30]
REST_SHOULDER=np.array([249.,346.])


def save_rest_arm():
    """Relaxed, empty near arm: bent elbow and open hand, for an unarmed off side."""
    video=clip('38-far-straight-sweep')
    if not video:return False
    frame=video[50];shape=cv2.GaussianBlur(polygon(REST_POLYGON).astype(np.float32),(0,0),3)>.5
    region=shape&(np.asarray(matte(frame))>0);factor=1.14
    matrix=np.array([[factor,0,0],[0,factor,0]],float);matrix[:,2]=np.array([39.,53.])*6-factor*REST_SHOULDER
    rgba=np.dstack((np.asarray(frame),region.astype(np.uint8)*255))
    image=native(Image.fromarray(cv2.warpAffine(rgba,matrix,(768,768),flags=cv2.INTER_NEAREST)))
    image.save(OUT/'rest_near.png');estimated=moge_normals.estimate([frame])
    if estimated is None:tile=normal(image)
    else:
        n=cv2.warpAffine(solid_normals(estimated[0],frame),matrix,(768,768),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
        tile=moge_normals.encode(n,np.asarray(image.getchannel('A')))
    tile.save(OUT/'rest_near_n.png');return True


BURN_CLIP=DEFAULT_BATCH.parents[1]/'2026-11-23/202951_00001_audio.mp4'


def glowing(frame,threshold,factor):
    """Cut a self-lit pose: keep the main shape and everything its glow encloses."""
    rgb=np.asarray(frame).copy();ellipse=lambda n:cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(n,n))
    if threshold is None:
        # Not outlined by a glow: separate by distance from the flat backdrop.
        backdrop=np.median(np.concatenate((rgb[:40,:40].reshape(-1,3),rgb[:40,-40:].reshape(-1,3))),axis=0)
        bright=(np.abs(rgb.astype(int)-backdrop).max(axis=2)>13).astype(np.uint8)
    else:bright=(rgb.max(axis=2)>threshold).astype(np.uint8)
    bright=cv2.morphologyEx(cv2.morphologyEx(bright,cv2.MORPH_OPEN,ellipse(7)),cv2.MORPH_CLOSE,ellipse(15))
    count,labels,stats,_=cv2.connectedComponentsWithStats(bright,8)
    main=(labels==max(range(1,count),key=lambda k:stats[k,cv2.CC_STAT_AREA])).astype(np.uint8)
    # Clothes are nearly as dark as the backdrop; everything the glow encloses is body.
    flood=np.pad(main,1);cv2.floodFill(flood,None,(0,0),2);mask=(flood[1:-1,1:-1]!=2)
    ys,xs=np.where(mask)
    matrix=np.array([[factor,0,384-factor*(xs.min()+xs.max())/2],[0,factor,740-factor*ys.max()]])
    rgba=np.dstack((rgb,mask.astype(np.uint8)*255))
    return native(Image.fromarray(cv2.warpAffine(rgba,matrix,(768,768),flags=cv2.INTER_NEAREST)))


def save_reactions():
    """Full-body reactions as 8-column sheets. Returns {name: frame count}."""
    def sheet(name,images,normals=None):
        size=(1024,128*((len(images)+7)//8))
        for suffix,tiles in [('',images),('_n',normals)]:
            if tiles is None:continue
            atlas=Image.new('RGBA',size)
            for j,tile in enumerate(tiles):atlas.paste(tile,(j%8*128,j//8*128))
            atlas.save(OUT/(name+suffix+'.png'))
        counts[name]=len(images)
    counts={}
    video=clip('75-tazed-loop')
    if video:sheet('tazed',[glowing(video[i],105,.95) for i in range(30,46,2)])
    burn=clip('79-burning-loop');picks=range(30,54,2)
    if not burn and BURN_CLIP.exists():burn=load(BURN_CLIP);picks=range(24,38,2)
    if burn:sheet('burn',[glowing(burn[i],None,1.0) for i in picks])
    for name,source,frames in [('hurt','76-hurt',[29,30,32]),('cackle','78-cackle',list(range(15,45)))]:
        video=clip(source)
        if not video:continue
        chosen=[video[i] for i in frames];estimated=moge_normals.estimate(chosen);tiles=[];normals_=[]
        for j,frame in enumerate(chosen):
            alpha=np.asarray(matte(frame))>0;ys,xs=np.where(alpha);dy=740-ys.max();dx=0 if name=='cackle' else 24
            matrix=np.array([[1,0,dx],[0,1,dy]],float)
            rgba=np.dstack((np.asarray(frame),alpha.astype(np.uint8)*255))
            if name=='hurt':
                filled,filled_mask,_=fill_edges(frame,load(next((DEFAULT_BATCH/'09-idle').glob('*_audio.mp4')))[20]);dy=min(dy,0)
                tile=native(filled_tile(filled,filled_mask,dx,dy))
            else:tile=native(Image.fromarray(cv2.warpAffine(rgba,matrix,(768,768),flags=cv2.INTER_NEAREST)))
            tiles.append(tile)
            if estimated is None:normals_.append(normal(tile))
            else:normals_.append(moge_normals.encode(cv2.warpAffine(solid_normals(estimated[j],frame),matrix,(768,768),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE),np.asarray(tile.getchannel('A'))))
        sheet(name,tiles,normals_)
    return counts


def solid_normals(n,frame):
    """Extend normals past the matte so a redrawn outline is lit like its edge."""
    inside=cv2.erode((np.asarray(matte(frame))>0).astype(np.uint8),np.ones((5,5),np.uint8))>0
    _,(iy,ix)=distance_transform_edt(~inside,return_indices=True)
    return n[iy,ix]


ISOLATED_SHOULDER=np.array([330.,384.]);ISOLATED_LENGTH=212.


def isolated_arm(frame,shoulder,side):
    """Cut a frame that contains only one arm; no body mask is needed."""
    rgb=np.asarray(frame).astype(np.int16);r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    alpha=np.asarray(matte(frame))>0
    count,labels,stats,_=cv2.connectedComponentsWithStats(alpha.astype(np.uint8),8)
    alpha=labels==max(range(1,count),key=lambda i:stats[i,cv2.CC_STAT_AREA])
    green=(g>70)&(g>r*1.4)&(g>b*1.3)
    gun=cv2.morphologyEx(green.astype(np.uint8),cv2.MORPH_OPEN,np.ones((5,5),np.uint8))>0
    skin=(r>g*1.18)&(r>b*1.12)&(g>85)&~green&alpha
    count,labels,stats,centers=cv2.connectedComponentsWithStats(skin.astype(np.uint8),8)
    main=max(range(1,count),key=lambda i:stats[i,cv2.CC_STAT_AREA])
    # Fingers can be separate islands around the proxy handle.
    group=[i for i in range(1,count) if stats[i,cv2.CC_STAT_AREA]>24 and np.linalg.norm(centers[i]-centers[main])<52]
    hand=np.isin(labels,group);ys,xs=np.where(hand);grip=np.array([xs.mean(),ys.mean()])
    _,angle=grip_geometry(frame,ISOLATED_SHOULDER)
    dark=(r+g+b)<150
    # The proxy's outline goes with the proxy; the hand keeps its own.
    sleeve=((r+g+b>240)&(np.abs(r-g)<30))|((r>g*1.6)&(r>b)&(g<85)&(r>60))
    near=lambda mask,n:cv2.dilate(mask.astype(np.uint8),np.ones((n,n),np.uint8))>0
    sleeve&=alpha&~hand&~near(green,3)
    count,labels,stats,_=cv2.connectedComponentsWithStats(near(sleeve,5).astype(np.uint8),8)
    sleeve&=labels==max(range(1,count),key=lambda i:stats[i,cv2.CC_STAT_AREA])
    disk=lambda n:cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(n,n))
    cloth=cv2.morphologyEx(sleeve.astype(np.uint8),cv2.MORPH_CLOSE,disk(15))
    cloth=(cv2.morphologyEx(cloth,cv2.MORPH_OPEN,disk(13))>0)&alpha&~hand
    body=(cv2.dilate(cloth.astype(np.uint8),disk(13))>0)&~hand&~near(green,3)
    # H3's thin outline is ragged after the 128px step; draw an even one. The
    # shoulder end stays soft so it melts into the coat.
    yy,xx=np.indices(alpha.shape);soft=(xx-ISOLATED_SHOULDER[0])**2+(yy-ISOLATED_SHOULDER[1])**2<48**2
    rgb=rgb.copy();rgb[body&~cloth&~soft]=(12,9,18);rgb[body&~cloth&soft]=(96,90,118)
    hand=(hand|(near(hand,13)&dark&alpha))&~near(green,3)&~body
    # Match the overhead reach of the straight aim poses it blends into.
    factor={'near':1.14*220,'far':1.14*190}[side]/ISOLATED_LENGTH
    matrix=np.array([[factor,0,0],[0,factor,0]],float);matrix[:,2]=shoulder-factor*ISOLATED_SHOULDER
    def layer(mask):
        rgba=np.dstack((rgb.astype(np.uint8),mask.astype(np.uint8)*255))
        return native(Image.fromarray(cv2.warpAffine(rgba,matrix,(768,768),flags=cv2.INTER_NEAREST)))
    return layer(body),layer(hand),factor*grip+matrix[:,2],angle,(frame,matrix)


def build_straight_arm_banks(near_recoil):
    """Extract sleeve-only pose banks from the completed straight-arm studies."""
    yy,xx=np.indices((768,768));poses={}
    for side,shot,reference,anchor,patch_xy in [
        ('near','37-near-straight-sweep',60,(277.,342.),(385,478)),
        ('far','38-far-straight-sweep',45,(412.,330.),(371,479))]:
        path=max((DEFAULT_BATCH/shot).glob('*_audio.mp4'),key=lambda p:p.stat().st_mtime)
        video=load(path);gray=cv2.cvtColor(np.asarray(video[reference]),cv2.COLOR_RGB2GRAY)
        px,py=patch_xy;template=gray[py:py+27,px:px+29]
        candidates=[]
        for index,frame in enumerate(video):
            gray=cv2.cvtColor(np.asarray(frame),cv2.COLOR_RGB2GRAY)
            scores=cv2.matchTemplate(gray[py-18:py+45,px-18:px+47],template,cv2.TM_CCOEFF_NORMED)
            _,confidence,_,loc=cv2.minMaxLoc(scores)
            shoulder=np.array(anchor)+np.array(loc)-18
            grip,angle=grip_geometry(frame,shoulder)
            # Refine the calibration handle with the nearest isolated skin blob.
            rgb=np.asarray(frame).astype(np.int16)
            skin=(rgb[:,:,0]>rgb[:,:,1]*1.18)&(rgb[:,:,0]>rgb[:,:,2]*1.2)&(rgb[:,:,1]>65)
            skin &= ((xx-grip[0])**2+(yy-grip[1])**2)<85**2
            n,labels,stats,centers=cv2.connectedComponentsWithStats(skin.astype(np.uint8),8)
            hands=[i for i in range(1,n) if 80<stats[i,cv2.CC_STAT_AREA]<6500 and stats[i,cv2.CC_STAT_WIDTH]<100 and stats[i,cv2.CC_STAT_HEIGHT]<110]
            if hands:
                chosen=min(hands,key=lambda i:np.linalg.norm(centers[i]-grip))
                if np.linalg.norm(centers[chosen]-grip)<65:grip=centers[chosen]
            candidates.append((index,frame,shoulder,grip,angle,confidence))
        # Fit one socket to the sweep's hand rays after removing body bob. A
        # guessed per-frame coat/belt point makes the drawn shoulder slide.
        normals=np.array([[-math.sin(c[4]),math.cos(c[4])] for c in candidates])
        registered=np.array([c[3]-(c[2]-np.array(anchor)) for c in candidates])
        fitted=np.linalg.lstsq(normals,np.sum(normals*registered,axis=1),rcond=None)[0]
        candidates=[(i,f,fitted+(s-np.array(anchor)),g,ang,confidence) for i,f,s,g,ang,confidence in candidates]
        arms=[];hands=[];poses[side]=[]
        # An isolated arm clip needs no body mask; prefer it when it exists.
        arm_video=clip(SWEEP[side]);isolated_files=bool(arm_video);origins=[]
        if isolated_files:
            arm_angles=[math.degrees(grip_geometry(f,ISOLATED_SHOULDER)[1]) for f in arm_video]
            socket=np.mean([c[2] for c in candidates],axis=0)
        selected=[]
        for degrees in range(-90,91,5):
            selected.append((degrees,min(candidates,key=lambda c:abs(math.degrees(c[4])-degrees))))
        for degrees,(index,frame,shoulder,grip,angle,confidence) in selected:
            if isolated_files:
                index=min(range(len(arm_video)),key=lambda i:abs(arm_angles[i]-degrees))
                arm,hand,grip,angle,origin=isolated_arm(arm_video[index],socket,side);origins.append(origin)
                arms.append(arm);hands.append(hand)
                poses[side].append({'aim_degrees':degrees,'weapon_angle':angle,'kind':'aim',
                    'shoulder':(socket/6).tolist(),'grip':(grip/6).tolist(),
                    'source':SWEEP[side],'source_frame':index})
                continue
            origins.append(None);turn=0.0
            if side=='far' and not -20<=degrees<=20:
                # Head and torso cover the far sleeve at steep angles. Turn a
                # fully visible straight sleeve instead of importing the hole.
                index,frame,shoulder,grip,angle,confidence=dict(selected)[-20 if degrees<0 else 20]
                turn=math.radians(degrees)-angle
            sleeve_layer,hand_layer,arm_angle=cut_straight_arm(frame,shoulder,grip,side)
            # Match the larger master body's proportions without changing its
            # world size or dropping additional native sprite pixels.
            factor=1.14
            arm=place_straight_arm(sleeve_layer,shoulder,arm_angle+turn,factor)
            hand=place_straight_arm(hand_layer,shoulder,arm_angle+turn,factor)
            reach=np.linalg.norm(grip-shoulder)*factor
            grip=shoulder+reach*np.array([math.cos(arm_angle+turn),math.sin(arm_angle+turn)])
            angle+=turn
            arms.append(native(arm));hands.append(native(hand))
            poses[side].append({'aim_degrees':degrees,'weapon_angle':angle,'kind':'aim',
                'shoulder':(shoulder/6).tolist(),'grip':(grip/6).tolist(),
                'source':shot,'source_frame':index,'belt_confidence':round(confidence,3)})
        # Forearm-first raise, from the isolated arm clip. The game plays it only
        # for a fast upward flick; both views briefly share this drawn sleeve.
        base_shoulder=np.array([sum(p['shoulder'][k] for p in poses[side])/len(poses[side])*6 for k in (0,1)])
        kinds=[(JOLT[side],['recoil_high','recoil_mid','recoil_low'])]
        for (name,indices),labels_ in kinds:
            extra=clip(name)
            if not extra:continue
            if indices is None:indices=jolt_frames(extra)
            for step,(index,kind) in enumerate(zip(indices,labels_)):
                arm,hand,grip,angle,origin=isolated_arm(extra[index],base_shoulder,side)
                arms.append(arm);hands.append(hand);origins.append(origin)
                poses[side].append({'aim_degrees':-90 if kind=='raise' else 0,'weapon_angle':angle,'kind':kind,'step':step,
                    'shoulder':(base_shoulder/6).tolist(),'grip':(grip/6).tolist(),'source':name,'source_frame':index})
        used=[o for o in origins if o];estimated=moge_normals.estimate([o[0] for o in used]) if used else None
        warped=[]
        for o in origins:
            if not o or estimated is None:warped.append(None);continue
            n=solid_normals(estimated[next(k for k,u in enumerate(used) if u is o)],o[0])
            warped.append(cv2.warpAffine(n,o[1],(768,768),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE))
        for suffix,frames in [('arm',arms),('hand',hands)]:
            atlas=Image.new('RGBA',(1024,128*((len(frames)+7)//8)));normals=Image.new('RGBA',atlas.size)
            for i,image in enumerate(frames):
                at=(i%8*128,i//8*128);atlas.paste(image,at)
                n=warped[i] if i<len(warped) else None
                normals.paste(normal(image) if n is None else moge_normals.encode(n,np.asarray(image.getchannel('A'))),at)
            atlas.save(OUT/(side+'_'+suffix+'_poses.png'));normals.save(OUT/(side+'_'+suffix+'_poses_n.png'))
    return poses


def build_arm_banks(shoulder,near_recoil,torso_region):
    if all(list((DEFAULT_BATCH/shot).glob('*_audio.mp4')) for shot in ['37-near-straight-sweep','38-far-straight-sweep']):
        return build_straight_arm_banks(near_recoil)
    elbow=load(next((DEFAULT_BATCH/'02-near-elbow').glob('*_audio.mp4')))
    down=load(next((DEFAULT_BATCH/'04-near-elbow-down').glob('*_audio.mp4')))
    bank_specs={
        'near':[(near_recoil,12,0,'aim','18-near-recoil'),
            (elbow,80,-20,'aim','02-near-elbow'),(elbow,88,-40,'aim','02-near-elbow'),
            (elbow,96,-60,'aim','02-near-elbow'),(elbow,104,-80,'aim','02-near-elbow'),
            (down,40,30,'aim','04-near-elbow-down'),(down,70,55,'aim','04-near-elbow-down'),
            (down,100,80,'aim','04-near-elbow-down'),
            (near_recoil,30,0,'recoil_high','18-near-recoil'),
            (near_recoil,35,0,'recoil_mid','18-near-recoil'),
            (near_recoil,40,0,'recoil_low','18-near-recoil')],
        'far':[(shoulder,25,65,'aim','06-far-shoulder'),(shoulder,35,35,'aim','06-far-shoulder'),
            (shoulder,50,0,'aim','06-far-shoulder'),(shoulder,60,-25,'aim','06-far-shoulder'),
            (shoulder,68,-45,'aim','06-far-shoulder'),(shoulder,75,-65,'aim','06-far-shoulder'),
            (shoulder,82,-85,'aim','06-far-shoulder')]}
    yy,xx=np.indices((768,768));poses={}
    base_fg=np.asarray(matte(shoulder[50]))>0
    body_exclusion=base_fg & (torso_region|((yy>274)&(xx<317))|(yy>=414))
    for side,specs in bank_specs.items():
        shoulder_point=np.array([234.,318.]) if side=='near' else np.array([432.,318.])
        arms=[];hands=[];poses[side]=[]
        for video,index,selection,kind,source in specs:
            frame=video[index];grip,angle=grip_geometry(frame)
            if side=='near':
                weight=min(1,abs(min(selection,0))/70)
                elbow_point=np.array([330*(1-weight)+207*weight,365*(1-weight)+385*weight])
                if selection>0:elbow_point=np.array([285.,395.])
                region=Image.new('L',(768,768));d=ImageDraw.Draw(region)
                for a,b,width in [(shoulder_point,elbow_point,112),(elbow_point,grip,104)]:
                    d.line([tuple(a),tuple(b)],fill=255,width=width)
                    for point in [a,b]:d.ellipse((point[0]-width/2,point[1]-width/2,point[0]+width/2,point[1]+width/2),fill=255)
                region=np.asarray(region)>0
                # The reference head stays still. Avoid carrying its hair along
                # with a raised foreground forearm.
                difference=np.max(np.abs(np.asarray(frame).astype(np.int16)-np.asarray(elbow[0]).astype(np.int16)),axis=2)
                region &= (yy>285)|(difference>28)
                # Source recoil has a reliable hand-painted silhouette at aim 0.
                if source=='18-near-recoil':
                    region=polygon([(188,285),(231,270),(272,277),(315,302),(414,304),
                        (469,280),(590,270),(596,349),(558,378),(477,383),(463,411),
                        (335,416),(259,404),(209,368),(188,326)])
            else:
                elbow_point=(shoulder_point+grip)/2+np.array([0.,30.])
                region_image=Image.new('L',(768,768));d=ImageDraw.Draw(region_image)
                for a,b in [(shoulder_point,elbow_point),(elbow_point,grip)]:
                    d.line([tuple(a),tuple(b)],fill=255,width=92)
                    for point in [a,b]:d.ellipse((point[0]-46,point[1]-46,point[0]+46,point[1]+46),fill=255)
                region=(np.asarray(region_image)>0)&~body_exclusion
                # Source body motion can leave disconnected coat/hair remnants.
                region &= np.asarray(matte(frame))>0
                count,labels,stats,_=cv2.connectedComponentsWithStats(region.astype(np.uint8),8)
                for component in range(1,count):
                    if stats[component,cv2.CC_STAT_AREA]<500:region[labels==component]=False
            hand_region=((xx-grip[0])**2+(yy-grip[1])**2)<65**2
            arm=extract(frame,region & ~hand_region)
            hand=extract(frame,region & hand_region)
            arms.append(native(arm));hands.append(native(hand))
            poses[side].append({'aim_degrees':selection,'weapon_angle':angle,'kind':kind,
                'shoulder':(shoulder_point/6).tolist(),'grip':(grip/6).tolist(),
                'source':source,'source_frame':index})
        for suffix,frames in [('arm',arms),('hand',hands)]:
            atlas=Image.new('RGBA',(128*8,128*((len(frames)+7)//8)))
            normals=Image.new('RGBA',atlas.size)
            for i,image in enumerate(frames):
                pos=(i%8*128,i//8*128);atlas.paste(image,pos);normals.paste(normal(image),pos)
            atlas.save(OUT/(side+'_'+suffix+'_poses.png'))
            normals.save(OUT/(side+'_'+suffix+'_poses_n.png'))
    return poses


def armless_offset(first,frame):
    a,b=[cv2.cvtColor(np.asarray(f),cv2.COLOR_RGB2GRAY) for f in (first,frame)]
    _,_,_,loc=cv2.minMaxLoc(cv2.matchTemplate(b[280:420,330:450],a[300:400,350:430],cv2.TM_CCOEFF_NORMED))
    return loc[0]-20,loc[1]-20


def track(reference,frame,box,search):
    """Offset of a landmark (glasses or buckle) from the idle reference, in native pixels."""
    a,b=[cv2.cvtColor(np.asarray(f),cv2.COLOR_RGB2GRAY) for f in (reference,frame)]
    x0,y0,x1,y1=box;left,top=max(0,x0-search),max(0,y0-search)
    scores=cv2.matchTemplate(b[top:min(768,y1+search),left:min(768,x1+search)],a[y0:y1,x0:x1],cv2.TM_CCOEFF_NORMED)
    _,confidence,_,loc=cv2.minMaxLoc(scores)
    return [round((left+loc[0]-x0)/6),round((top+loc[1]-y0)/6)],round(float(confidence),2)


FILL_PAD=72


def match_head(reference,frame):
    """Best rotation and shift that places the reference's face on this frame."""
    a,b=[cv2.resize(cv2.cvtColor(np.asarray(f),cv2.COLOR_RGB2GRAY),(384,384),interpolation=cv2.INTER_AREA) for f in (reference,frame)]
    box=(150,60,245,140);center=((box[0]+box[2])/2,(box[1]+box[3])/2);best=(-1,)
    for degrees in np.arange(-20,20.5,1.):
        turned=cv2.warpAffine(a,cv2.getRotationMatrix2D(center,degrees,1.),(384,384))
        _,score,_,at=cv2.minMaxLoc(cv2.matchTemplate(b,turned[box[1]:box[3],box[0]:box[2]],cv2.TM_CCOEFF_NORMED))
        if score>best[0]:best=(score,degrees,at[0]-box[0],at[1]-box[1])
    score,degrees,dx,dy=best
    m=cv2.getRotationMatrix2D((center[0]*2,center[1]*2),degrees,1.);m[:,2]+=(dx*2,dy*2);return m,score


def fill_edges(frame,reference):
    """Return RGB and alpha on a canvas padded by FILL_PAD with a cut-off head completed.

    Only pixels outside the original frame are invented, from the reference head."""
    pad=FILL_PAD;size=768+pad*2
    alpha=np.asarray(matte(frame))>0;rgb=np.zeros((size,size,3),np.uint8);mask=np.zeros((size,size),bool)
    rgb[pad:-pad,pad:-pad]=np.asarray(frame);mask[pad:-pad,pad:-pad]=alpha
    m,score=match_head(reference,frame)
    if score>.55:
        head=np.asarray(reference).copy();head_alpha=((np.asarray(matte(reference))>0)).astype(np.uint8);head_alpha[262:]=0
        shift=m.copy();shift[:,2]+=pad
        extra=cv2.warpAffine(head,shift,(size,size),flags=cv2.INTER_NEAREST);extra_alpha=cv2.warpAffine(head_alpha,shift,(size,size),flags=cv2.INTER_NEAREST)>0
        inside=np.zeros((size,size),bool);inside[pad+4:-pad-4,pad+4:-pad-4]=True
        add=extra_alpha&~inside;rgb[add]=extra[add];mask|=add
    return rgb,mask,score


def filled_tile(rgb,mask,dx=0,dy=0):
    """Back to a 128px tile, shifted so the completed part fits inside the cell."""
    rgba=np.dstack((rgb,mask.astype(np.uint8)*255))
    moved=cv2.warpAffine(rgba,np.array([[1.,0,dx-FILL_PAD],[0,1.,dy-FILL_PAD]]),(768,768),flags=cv2.INTER_NEAREST)
    return Image.fromarray(moved)


def armless_layer(frame):
    alpha=np.asarray(matte(frame))>0;rgb=np.asarray(frame).copy()
    # Smooth the armpit notch inherited from the reference cutout.
    yy,xx=np.indices(alpha.shape);zone=(yy>355)&(yy<465)&(xx<250)
    filled=cv2.morphologyEx(alpha.astype(np.uint8),cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(45,45)))>0
    out=np.where(zone,filled,alpha);total=rgb.astype(int).sum(axis=2)
    _,(iy,ix)=distance_transform_edt(~(alpha&(total>420)),return_indices=True)
    inside=cv2.erode(out.astype(np.uint8),cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(15,15)))>0
    # Solid cloth inside the edge, one outline on it.
    fix=zone&out&inside&(total<240)
    rgb[fix]=rgb[iy[fix],ix[fix]]
    rgb[zone&out&~inside]=(12,9,18)
    return cut(Image.fromarray(rgb),Image.fromarray(out.astype(np.uint8)*255))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    save_rest_arm();reactions=save_reactions()
    walk=load(next((DEFAULT_BATCH/'11-walk').glob('*_audio.mp4')))
    idle=load(next((DEFAULT_BATCH/'09-idle').glob('*_audio.mp4')))
    shoulder=load(next((DEFAULT_BATCH/'06-far-shoulder').glob('*_audio.mp4')))
    near_recoil=load(next((DEFAULT_BATCH/'18-near-recoil').glob('*_audio.mp4')))
    near=near_recoil[12]
    base=shoulder[50];yy,xx=np.indices((768,768))
    turn_files=list((DEFAULT_BATCH/'39-right-front-left-turn').glob('*_audio.mp4'))
    if turn_files:
        front=load(max(turn_files,key=lambda p:p.stat().st_mtime))[55]
        front_region=(yy<285)|polygon([(255,280),(510,280),(495,335),(510,425),
            (535,495),(225,495),(240,425),(270,335)])
        left=220-(yy-495)*30/160;right=535+(yy-495)*30/160
        front_region |= (yy>=495)&(yy<655)&(xx>left)&(xx<right)
        front_region |= yy>=655
        save_part('turn_front',extract(front,front_region))
    torso_region=polygon([(0,0),(550,0),(550,275),(434,275),(432,299),
        (448,350),(458,414),(465,495),(291,495),(290,430),
        (268,397),(258,350),(270,291),(267,274),(0,274)])
    torso=extract(base,torso_region)
    underarm=Image.new('RGBA',(768,768))
    sweep_files=list((DEFAULT_BATCH/'37-near-straight-sweep').glob('*_audio.mp4'))
    if sweep_files:
        # Complementary pose: the new overhead study exposes the coat beneath
        # the sleeve. This patch stays on the body, never on the rotating arm.
        exposed=load(max(sweep_files,key=lambda p:p.stat().st_mtime))[115]
        patch=extract(exposed,polygon([(245,390),(350,380),(485,390),
            (490,520),(205,520),(225,445)]))
        factor=1.14
        transform=np.array([[factor,0,389-400*factor],[0,factor,480-490*factor]],np.float32)
        underarm=Image.fromarray(cv2.warpAffine(np.asarray(patch),transform,(768,768),flags=cv2.INTER_NEAREST))
        a=np.asarray(underarm.getchannel('A')).copy()
        coat_edge=258-(yy-350)*.9
        a[(yy<355)|(yy>=450)|(xx>=310)|(xx<coat_edge)]=0
        underarm.putalpha(Image.fromarray(a))
        # The torso cut leaves a hole between collar and shoulder and a ragged
        # armpit. Finish that coat edge on the body, under the moving sleeve.
        edge=polygon([(284,258),(262,268),(240,284),(228,304),(226,326),(238,350),
            (228,374),(214,398),(204,424),(310,424),(310,258)])
        rgba=np.asarray(underarm).copy();total=rgba[:,:,:3].astype(int).sum(axis=2)
        _,(iy,ix)=distance_transform_edt(~((rgba[:,:,3]>0)&(total>400)),return_indices=True)
        bad=edge&((rgba[:,:,3]==0)|((total<240)&(xx<258)))
        rgba[bad]=rgba[iy[bad],ix[bad]]
        # Above the sampled patch use flat coat shadow instead of column smears.
        rgba[edge&(yy<355)]=(188,178,206,255)
        # Outer (left/top) edge only: the bottom continues into the coat.
        rim=edge&~(np.roll(edge,8,axis=1)&np.roll(edge,6,axis=0))&(xx<285)
        rim&=(yy<350)|~np.roll(edge,8,axis=1)
        rgba[rim]=(12,9,18,255)
        rgba[~edge&(yy<424)&(xx<258),3]=0
        underarm=Image.fromarray(rgba)
    poses=build_arm_banks(shoulder,near_recoil,torso_region)
    near_region=polygon([(188,285),(231,270),(272,277),(315,302),
        (414,304),(469,286),(580,275),(588,345),(558,372),
        (477,378),(463,405),(335,413),(259,399),(209,365),(188,326)])
    near_hand_region=polygon([(480,276),(583,273),(590,347),(558,374),(478,371),(469,326)])
    near_arm=extract(near,near_region & ~near_hand_region)
    near_hand=extract(near,near_region & near_hand_region)
    far_region=polygon([(425,288),(469,286),(567,276),(575,263),
        (663,263),(670,342),(640,364),(584,360),(570,393),(498,402),(439,361)])
    far_hand_region=polygon([(575,265),(665,263),(672,341),(641,365),(574,355),(563,309)])
    far_arm=extract(base,far_region & ~far_hand_region)
    far_hand=extract(base,far_region & far_hand_region)
    rest=extract(shoulder[25],polygon([(459,430),(475,446),(510,456),
        (533,484),(529,519),(513,539),(484,519),(467,489)]))
    # Remove the original torso/coat from the resting far-arm cutout.
    rest_alpha=np.asarray(rest.getchannel('A')).copy()
    rest_alpha[(xx<466)|(yy>548)]=0;rest.putalpha(Image.fromarray(rest_alpha))
    for name,image in [('near_arm',near_arm),('near_hand',near_hand),('far_arm',far_arm),('far_hand',far_hand)]:save_part(name,image)
    buckle=cv2.cvtColor(np.asarray(walk[30]),cv2.COLOR_RGB2GRAY)[469:496,371:405]
    anchors={'head':[57,24],'helmet':[57,7],'brow':[62,24],
        'eyeFar':[57,29],'eyeNear':[76,29],'nose':[73,36],'mouth':[65,43],
        'ear':[44,34],'neck':[60,47],'chest':[62,64],'belt':[65,80],
        'hip':[64,86],'back':[45,67],'backpack':[40,64],
        # Legacy rig names: its primary shoulder is the new near/foreground arm.
        'shoulderFar':[39,53],'shoulderNear':[72,50],
        'elbowOff':[78,68],'handOff':[84,82],
        'kneeBack':[49,102],'footBack':[43,120],'kneeFront':[72,104],'footFront':[77,122]}
    clips={};frames=[]
    armless_files=list((DEFAULT_BATCH/'58-armless-walk').glob('*_audio.mp4'))
    armless=load(max(armless_files,key=lambda p:p.stat().st_mtime)) if armless_files else None
    walk_clip=('walk',armless,15,19) if armless else ('walk',walk,45,34)
    armless_idle=clip('64-armless-idle')
    idle_clip=('idle',armless_idle,33,51) if armless_idle else ('idle',idle,20,32)
    run_video=clip('65-armless-run')
    extra=[('run',run_video,list(range(49,74)))]
    # Only a fifth of a second long: hand-picked frames, no loop.
    back=clip('70-armless-dash-back')
    for label,video,picks in [('dash_forward',clip('66-armless-dash-forward'),[11,13,15,19,25]),
        ('dash_up',clip('68-armless-dash-up'),[8,10,12,14,18]),('dash_down',clip('69-armless-dash-down'),[11,15,16,17,17]),
        ('dash_back',back,BACK_DASH)]:
        extra.append((label,video,picks))
    specs=[(n,v,list(range(a,a+b))) for n,v,a,b in [idle_clip,walk_clip]]+[(n,v,p) for n,v,p in extra if v and p]
    armless_sources=[v for v in [armless,armless_idle,run_video]+[v for _,v,_ in extra] if v]
    for name,source,indices in specs:
        start,length=indices[0],len(indices)
        clips[name]={'start':len(frames),'count':length,'fps':24,'source_start':start}
        for index in indices:
            frame=source[index]
            if any(source is v for v in armless_sources):
                # Already one clean armless layer: no torso, coat or sleeve cuts.
                dx,dy=(0,0) if name.startswith('dash') else armless_offset(source[0],frame)
                layer=armless_layer(frame)
                if name=='dash_back':
                    filled,filled_mask,_=fill_edges(frame,armless_idle[33])
                    layer=filled_tile(filled,filled_mask,30,0)
                landmark=armless_idle[33] if armless_idle else source[0]
                head_at,head_fit=track(landmark,frame,(318,135,482,205),170 if name.startswith('dash') else 30)
                belt_at,belt_fit=track(landmark,frame,(345,462,432,500),130 if name.startswith('dash') else 30)
                if head_fit<.4:head_at=[0,0]
                if belt_fit<.4:belt_at=head_at
                if name=='dash_back':head_at=[head_at[0]+5,head_at[1]];belt_at=[belt_at[0]+5,belt_at[1]]
                free=Image.new('RGBA',(768,768));free.alpha_composite(rest,(max(0,dx),max(0,dy)));free.alpha_composite(layer)
                frames.append({'free':native(free),'armed':native(layer),'source_frame':index,'head':head_at,'torso':belt_at,'fit':[head_fit,belt_fit],
                    'anchors':{key:[point[0]+dx/6,point[1]+dy/6] for key,point in anchors.items()},'belt_confidence':1.0,'rgb':frame,'clip':name})
                continue
            dx,dy,confidence=locate_belt(frame,buckle)
            lower_alpha=np.asarray(matte(frame)).copy();lower_alpha[(yy<414+dy)|(xx>530)]=0
            # Keep the lower-body cutout inside the torso's right edge until the
            # waist. The source's aiming sleeve leaves a horizontal black remnant
            # just below the old arm cut; it must not remain on the body layer.
            torso_edge=458+dx+(yy-(414+dy))*7/81
            lower_alpha[(yy<495+dy)&(xx>torso_edge)]=0
            lower=cut(frame,Image.fromarray(lower_alpha))
            current={}
            for armed in [False,True]:
                combined=Image.new('RGBA',(768,768))
                if not armed:combined.alpha_composite(rest,(dx,dy))
                combined.alpha_composite(lower)
                combined.alpha_composite(underarm,(dx,dy))
                combined.alpha_composite(torso,(dx,dy))
                current['armed' if armed else 'free']=native(combined)
            current['anchors']={key:[point[0]+dx/6,point[1]+dy/6] for key,point in anchors.items()}
            current['source_frame']=index;current['belt_confidence']=round(confidence,3)
            frames.append(current)
    for name in clips:
        loop=[f for f in frames if f.get('clip')==name]
        estimated=moge_normals.estimate([f['rgb'] for f in loop]) if loop else None
        if estimated is None:continue
        solid=[solid_normals(n,f['rgb']) for f,n in zip(loop,estimated)]
        if name=='dash_back':solid=[cv2.warpAffine(n,np.array([[1.,0,30],[0,1.,0]]),(768,768),borderMode=cv2.BORDER_REPLICATE) for n in solid]
        for f,n in zip(loop,solid if name.startswith('dash') else moge_normals.smooth_loop(solid)):f['n']=n
    columns=8;rows=(len(frames)+columns-1)//columns
    atlas=Image.new('RGBA',(128*columns,128*rows*2))
    normals=Image.new('RGBA',atlas.size)
    for i,frame in enumerate(frames):
        for row,key in enumerate(['free','armed']):
            pos=((i%columns)*128,(i//columns+row*rows)*128)
            atlas.paste(frame[key],pos)
            tile=normal(frame[key])
            if 'n' in frame:
                # The resting far hand is a separate cutout; keep its own normals.
                body_alpha=np.asarray(frame['armed'].getchannel('A'));tile.paste(moge_normals.encode(frame['n'],body_alpha),(0,0),frame['armed'].getchannel('A'))
            normals.paste(tile,pos)
    atlas.save(OUT/'body.png');normals.save(OUT/'body_n.png')
    data={'version':1,'cell':[128,128],'columns':columns,'rows_per_variant':rows,
        'origin':[64,102],'world_scale':0.75,'clips':clips,
        'arms':{'near':{'shoulder':[39,53],'grip':[88,53]},'far':{'shoulder':[72,50],'grip':[103,52]}},
        'poses':poses,'reactions':reactions,'frames':[{k:v for k,v in frame.items() if k not in ['free','armed','rgb','clip','n']} for frame in frames],
        'sources':{'walk':'58-armless-walk' if armless else '11-walk','idle':'64-armless-idle' if armless_idle else '09-idle','torso_far_arm':'06-far-shoulder','near_arm':'18-near-recoil'},
        'notes':['128px native layers; weapons and shot effects come from gameplay',
            'Near and far arm poses rotate independently around their own shoulders',
            'Layer normals are estimated per frame by MoGe-2 and smoothed over each loop; the rest approximate silhouette depth']}
    (OUT/'body.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    check=Image.new('RGBA',(768,384),'#24354a')
    for j,i in enumerate([0,len(frames)-16,len(frames)-5]):
        image=frames[i]['free'].copy()
        image.alpha_composite(native(near_arm));image.alpha_composite(native(near_hand))
        check.paste(image.resize((256,256),Image.Resampling.NEAREST),(j*256,64))
    check.convert('RGB').save(OUT/'import-preview.png')
    print(json.dumps({'output':str(OUT),'frames':len(frames),'atlas':atlas.size}))


if __name__=='__main__':main()
