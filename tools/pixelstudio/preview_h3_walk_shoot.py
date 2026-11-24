"""Preview independently timed walk and recoil layers using existing game guns."""
from pathlib import Path
import json
import math
import av
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from review_h3_modular_batch import ROOT, DEFAULT_BATCH, load, matte, cut, native, sheet

OUT = ROOT/'export/comfyui/scientist-modular/walk-shoot-preview'
SHOTS = [('18-near-recoil','Walk + single fire'),('20-dual-recoil','Walk + dual fire')]


def locate_belt(frame, template):
    gray = cv2.cvtColor(np.asarray(frame),cv2.COLOR_RGB2GRAY)
    scores = cv2.matchTemplate(gray[445:521,340:440],template,cv2.TM_CCOEFF_NORMED)
    _,confidence,_,location = cv2.minMaxLoc(scores)
    return location[0]+340-371, location[1]+445-469, confidence


def game_gun():
    # Crop the existing game's base gun, leaving its old arm and hand behind.
    art = Image.open(ROOT/'godot/character/art/weapon_albedo.png').convert('RGBA')
    gun = np.asarray(art.crop((54,51,84,65))).copy()
    rgb = gun[:,:,:3].astype(np.int16)
    skin = (rgb[:,:,0] > rgb[:,:,1]*1.15) & (rgb[:,:,1] > rgb[:,:,2]*1.15)
    gun[:,:,3][skin] = 0
    return gun


def replace_proxies(frame, gun, body_patch):
    rgb = np.asarray(frame).astype(np.int16)
    green = (rgb[:,:,1]>100) & (rgb[:,:,1]>rgb[:,:,0]*1.55) & (rgb[:,:,1]>rgb[:,:,2]*1.4)
    green_mask = cv2.dilate(green.astype(np.uint8),np.ones((3,3),np.uint8))>0
    foreground = np.asarray(matte(frame)).copy()
    foreground[green_mask] = 0
    top = cut(frame,Image.fromarray(foreground))
    result = Image.new('RGBA',frame.size)
    # Reuse visible torso pixels from the stationary reference only where the
    # proxy crossed the body. This remains a diagnostic patch of occluded art.
    patch = np.asarray(body_patch).copy()
    patch[:,:,3][~green_mask] = 0
    result.alpha_composite(Image.fromarray(patch))
    count,labels,stats,_ = cv2.connectedComponentsWithStats(green.astype(np.uint8),8)
    transforms = []
    for component in range(1,count):
        if stats[component,cv2.CC_STAT_AREA] < 1000: continue
        ys,xs = np.where(labels==component)
        points = np.column_stack((xs,ys)).astype(float)
        _,axes = np.linalg.eigh(np.cov(points.T))
        u = axes[:,-1]
        if u[0]<0: u=-u
        v = np.array([-u[1],u[0]])
        us,vs = points@u,points@v
        # Detached green grip fragments are not additional weapons.
        if us.max()-us.min()<140 or abs(math.degrees(math.atan2(u[1],u[0])))>35:
            continue
        # Dense rows describe the horizontal bar, excluding its grip extension.
        bins = np.rint(vs).astype(int)
        values,counts = np.unique(bins,return_counts=True)
        dense = values[counts > counts.max()*.7]
        center_v = float(dense.mean())
        lo,hi = float(us.min()),float(us.max())
        scale = (hi-lo)/(gun.shape[1]-1)
        # Barrel center is row 8 in the existing gun crop.
        origin = u*lo+v*(center_v-8*scale)
        matrix = np.array([[u[0]*scale,v[0]*scale,origin[0]],
                           [u[1]*scale,v[1]*scale,origin[1]]],np.float32)
        placed = cv2.warpAffine(gun,matrix,frame.size,flags=cv2.INTER_NEAREST)
        result.alpha_composite(Image.fromarray(placed))
        transforms.append({'origin':origin.tolist(),'scale':scale,'angle':math.degrees(math.atan2(u[1],u[0]))})
    result.alpha_composite(top)
    return result,transforms


def write_video(path,frames):
    with av.open(str(path),'w') as output:
        stream=output.add_stream('libx264',rate=24)
        stream.width,stream.height=frames[0].size
        stream.pix_fmt='yuv420p';stream.options={'crf':'17'}
        for frame in frames:
            for packet in stream.encode(av.VideoFrame.from_image(frame.convert('RGB'))):output.mux(packet)
        for packet in stream.encode():output.mux(packet)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    walk=load(next((DEFAULT_BATCH/'11-walk').glob('*_audio.mp4')))
    still=load(next((DEFAULT_BATCH/'06-far-shoulder').glob('*_audio.mp4')))[50]
    buckle=cv2.cvtColor(np.asarray(walk[30]),cv2.COLOR_RGB2GRAY)[469:496,371:405]
    yy,xx=np.indices((768,768))
    # The patch is restricted to the torso and upper sleeve, never the resting hand.
    patch_alpha=np.asarray(matte(still)).copy()
    patch_alpha[(yy<285)|(yy>=495)|(xx>459)]=0
    patch=cut(still,Image.fromarray(patch_alpha))
    gun=game_gun();Image.fromarray(gun).save(OUT/'existing-game-gun.png')
    walk_positions=[locate_belt(frame,buckle) for frame in walk]
    # Pick a loop with matching lower-body pose and motion direction at the seam.
    signatures=[]
    for frame,(dx,dy,_) in zip(walk,walk_positions):
        gray=cv2.cvtColor(np.asarray(frame),cv2.COLOR_RGB2GRAY)
        aligned=cv2.warpAffine(gray,np.float32([[1,0,-dx],[0,1,-dy]]),(768,768))
        signatures.append(cv2.resize(aligned[495:747,130:540],(68,42)).astype(float))
    choices=[]
    for start in range(15,50):
        for length in range(20,53):
            end=start+length
            pose=np.mean(np.abs(signatures[start]-signatures[end]))
            velocity=np.mean(np.abs((signatures[start+1]-signatures[start])-(signatures[end+1]-signatures[end])))
            choices.append((pose+.35*velocity,start,length))
    score,start,length=min(choices)
    lower=[]
    for frame,(dx,dy,_) in zip(walk,walk_positions):
        alpha=np.asarray(matte(frame)).copy();alpha[yy<495+dy]=0
        lower.append(cut(frame,Image.fromarray(alpha)))
    all_layers=[];all_proxy=[];records=[]
    for shot,label in SHOTS:
        recoil=load(next((DEFAULT_BATCH/shot).glob('*_audio.mp4')))[12:104]
        combined=[];proxy_combined=[];tracking=[]
        for i,frame in enumerate(recoil):
            wi=start+i%length
            wx,wy,wconf=walk_positions[wi]
            sx,sy,sconf=locate_belt(frame,buckle)
            translated_patch=Image.new('RGBA',(768,768));translated_patch.alpha_composite(patch,(sx,sy))
            upper,transforms=replace_proxies(frame,gun,translated_patch)
            upper_alpha=np.asarray(upper.getchannel('A')).copy();upper_alpha[yy>=495+sy]=0
            upper.putalpha(Image.fromarray(upper_alpha))
            original_alpha=np.asarray(matte(frame)).copy();original_alpha[yy>=495+sy]=0
            original=cut(frame,Image.fromarray(original_alpha))
            result=Image.new('RGBA',(768,768));result.alpha_composite(lower[wi]);result.alpha_composite(upper,(wx-sx,wy-sy))
            proxy=Image.new('RGBA',(768,768));proxy.alpha_composite(lower[wi]);proxy.alpha_composite(original,(wx-sx,wy-sy))
            combined.append(native(result));proxy_combined.append(native(proxy))
            tracking.append({'frame':i,'recoil_source_frame':i+12,'walk_frame':wi,'upper_offset':[wx-sx,wy-sy],'belt_confidence':round(sconf,3),'guns':transforms})
        sheet(combined,OUT/(shot+'-walk-shoot.png'))
        all_layers.append(combined);all_proxy.append(proxy_combined)
        records.append({'shot':shot,'label':label,'frames':tracking})
    font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',18)
    small=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',14)
    rendered=[];proxy_rendered=[]
    for i in range(min(map(len,all_layers))):
        for layers,destination in [(all_layers,rendered),(all_proxy,proxy_rendered)]:
            canvas=Image.new('RGB',(768,468),'#14202e');draw=ImageDraw.Draw(canvas)
            draw.text((18,12),'WALK + SHOOT / 128px sprites / 24 fps',font=font,fill='#edf2f7')
            for j,(_,label) in enumerate(SHOTS):
                x=j*384
                draw.rectangle((x+8,44,x+375,430),fill='#24354a')
                # Moving floor markers make the in-place walk easier to read.
                for q in range(-1,8):
                    marker=x+q*64-(i*3)%64
                    if x+10<marker<x+362:draw.line((marker,416,marker+16,416),fill='#50617a',width=2)
                tile=layers[j][i].resize((384,384),Image.Resampling.NEAREST)
                canvas.paste(tile,(x,43),tile)
                draw.text((x+22,438),label,font=font,fill='#edf2f7')
            draw.text((18,30),'Rough layer composite; source recoil and flashes retained',font=small,fill='#b4c3d4')
            destination.append(canvas)
    write_video(OUT/'walk-shoot.mp4',rendered)
    write_video(OUT/'walk-shoot-green-proxy.mp4',proxy_rendered)
    rendered[38].save(OUT/'walk-shoot-still.png')
    contact=Image.new('RGB',(768,468*3))
    for row,index in enumerate([12,38,81]):contact.paste(rendered[index],(0,row*468))
    contact.save(OUT/'walk-shoot-contact.png')
    gif=[frame.resize((512,312),Image.Resampling.NEAREST) for frame in rendered]
    gif[0].save(OUT/'walk-shoot.gif',save_all=True,append_images=gif[1:],duration=[round((i+1)*1000/24)-round(i*1000/24) for i in range(len(gif))],loop=0)
    (OUT/'metadata.json').write_text(json.dumps({'fps':24,'native_cell':[128,128],
        'walk_loop':{'start':start,'length':length,'seam_score':score},
        'gun_source':'godot/character/art/weapon_albedo.png',
        'limitations':['Diagnostic composite, not imported into game','Upper body is flattened source recoil footage','Original flashes retained','Rough matte and torso patch beneath proxy','Existing game gun has lower detail than the new scientist'],
        'variants':records},indent=2),encoding='utf-8')
    print(json.dumps({'video':str(OUT/'walk-shoot.mp4'),'frames':len(rendered),'walk_loop':[start,length]}))


if __name__=='__main__':main()
