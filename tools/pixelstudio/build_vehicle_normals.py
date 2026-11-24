"""MoGe normal maps for the 8-view vehicle sheets: writes <sheet>_n.png beside each sheet.

Each view is estimated alone on a neutral backdrop at MoGe's working size, then returned to
its exact place, so the normal sheet shares the albedo sheet's regions.
"""
from pathlib import Path
import json
import sys
import cv2
import numpy as np
from PIL import Image,ImageDraw
from scipy.ndimage import distance_transform_edt
import moge_normals
moge_normals.FRONT=True

ROOT=Path(__file__).resolve().parents[2]/'godot/art/vehicles'


DIAGONAL=['front_left','rear_right','front_right','rear_left']


def ground(size):
    g=Image.new('RGBA',(size,size),(112,116,122,255));d=ImageDraw.Draw(g)
    for j,y in enumerate(range(0,size,46)):
        for i,x in enumerate(range(0,size,64)):
            if (i+j)%2:d.rectangle((x,y,x+63,y+45),fill=(132,136,142,255))
    return g


def compose(image,regions,name):
    """Canvas for one view. A straight view alone reads as a flat relief, so it is shown
    among the same car's diagonal views, which tell MoGe the roof, hood and sides apart."""
    crop=lambda n:image.crop((regions[n][0],regions[n][1],regions[n][0]+regions[n][2],regions[n][1]+regions[n][3]))
    car=crop(name)
    if name in DIAGONAL:
        size,fill=768,640;canvas=Image.new('RGBA',(size,size),(118,122,128,255))
    else:
        size,fill=1024,500;canvas=ground(size)
        for other,(x,y) in zip(DIAGONAL,[(16,16),(1008,16),(16,1008),(1008,1008)]):
            q=crop(other);q.thumbnail((330,270))
            canvas.alpha_composite(q,(x if x<500 else x-q.width,y if y<500 else y-q.height))
    scale=fill/max(car.size);new=(max(1,round(car.width*scale)),max(1,round(car.height*scale)));at=((size-new[0])//2,(size-new[1])//2)
    canvas.alpha_composite(car.resize(new,Image.Resampling.LANCZOS),at);return canvas.convert('RGB'),at,new


def main():
    names=sys.argv[1:]
    for sheet in sorted(ROOT.glob('*/*8way-v1.png')):
        if names and sheet.parent.name not in names:continue
        image=Image.open(sheet).convert('RGBA');rgba=np.asarray(image);alpha=rgba[:,:,3]
        regions={k:v['region'] for k,v in json.loads((sheet.parent/'views.json').read_text())['frames'].items()}
        normal=np.zeros_like(rgba);boxes=[tuple(r) for r in regions.values()];frames=[];placed=[]
        for name in regions:
            canvas,at,size=compose(image,regions,name);frames.append(canvas);placed.append((at,size))
        estimated=moge_normals.estimate(frames)
        if estimated is None:raise SystemExit('ComfyUI is not reachable')
        for (x,y,w,h),(at,size),n in zip(boxes,placed,estimated):
            part=n[at[1]:at[1]+size[1],at[0]:at[0]+size[0]]
            part=cv2.resize(part,(int(w),int(h)),interpolation=cv2.INTER_AREA)
            own=alpha[y:y+h,x:x+w]>0
            # The thick drawn outline is not geometry: light it like the body edge beside it.
            luma=rgba[y:y+h,x:x+w,:3].max(axis=2);inside=cv2.erode((alpha[y:y+h,x:x+w]>200).astype(np.uint8),np.ones((7,7),np.uint8))>0
            good=inside&~((luma<30)&(distance_transform_edt(own)<9))
            _,(iy,ix)=distance_transform_edt(~good,return_indices=True);part=part[iy,ix]
            part=moge_normals.unit(cv2.GaussianBlur(part,(0,0),.8));part[:,:,2]=np.maximum(part[:,:,2],.12);part=moge_normals.unit(part)
            patch=normal[y:y+h,x:x+w];patch[own,:3]=np.rint((part[own]*.5+.5)*255).astype(np.uint8);patch[own,3]=alpha[y:y+h,x:x+w][own]
        out=sheet.with_name(sheet.stem+'_n.png');Image.fromarray(normal).save(out)
        mask=alpha>200;missing=int((mask&(normal[:,:,3]==0)).sum())
        print(sheet.parent.name,len(boxes),'views; unlit opaque pixels',missing)


if __name__=='__main__':main()
