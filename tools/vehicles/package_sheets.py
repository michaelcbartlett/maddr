"""Copy generated masters and describe their sprite regions without editing pixels."""
from pathlib import Path
import json,shutil
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'godot/art/vehicles'
GENERATED=Path.home()/'.codex/generated_images/01a208d6-6657-7f83-9635-7533a4e6cb71'
SOURCES=[
 ('delorean','DeLorean DMC-12','397fbce5-72e7-4666-9c15-0eff538995d6',220,92),
 ('grand-wagoneer','1980s Jeep Grand Wagoneer','a613da6d-46b9-4fc9-ad4d-d2f22664b3e8',245,105),
 ('boxy-sedan','1980s Sedan','896726e8-c8c8-4287-885a-47cc88a8161d',235,96),
 ('compact-hatchback','1980s Compact','f700bbbf-2829-4a12-b53c-0d75d6d3f055',195,82),
 ('cargo-van','1980s Cargo Van','4ad1c1c2-465e-4673-a1ef-4e4f36c527f1',255,112),
 ('pickup','1980s Pickup','5e7fd398-e083-4632-8f8a-087e7dc291f2',250,108),
 ('police-sedan','1980s Police Cruiser','c2ded101-f818-4f2e-8350-ead7a26dfa1d',245,100),
]
VIEWS=['front_left','front','front_right','left','rear_left','rear','rear_right','right']
POLICE_BULBS=[[(227,113),(272,139)],[(630,138),(698,138)],[(1058,138),(1106,112)],
 [(1554,141),(1554,178)],[(194,558),(241,582)],[(631,583),(696,584)],
 [(1126,557),(1087,584)],[(1531,576),(1531,619)]]

def main():
    catalog=[]
    for ident,name,token,length,width in SOURCES:
        source=GENERATED/f'exec-{token}.png';target=OUT/ident/f'{ident}-8way-v1.png'
        target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():shutil.copy2(source,target)
        image=Image.open(target);assert image.mode=='RGBA'
        alpha=np.asarray(image.getchannel('A'));assert alpha.min()==0 and alpha.max()==255
        height,pixels=alpha.shape;frames={}
        for i,view in enumerate(VIEWS):
            row,col=divmod(i,4);x0,x1=col*pixels//4,(col+1)*pixels//4;y0,y1=row*height//2,(row+1)*height//2
            count,labels,stats,centers=cv2.connectedComponentsWithStats((alpha[y0:y1,x0:x1]>127).astype(np.uint8),8)
            major=max(stats[1:],key=lambda s:s[4]);x,y,w,h,area=map(int,major)
            assert area>10000,(ident,view,area)
            x=max(x0,x+x0-2);y=max(y0,y+y0-2);w=min(w+4,x1-x);h=min(h+4,y1-y)
            frame={'region':[x,y,w,h],'opaque_pixels':area}
            if ident=='police-sedan':
                frame['bulbs']=[[px-x,py-y] for px,py in POLICE_BULBS[i]]
                red,blue=[image.getpixel(point) for point in POLICE_BULBS[i]]
                assert red[0]>red[2]*1.3 and blue[2]>blue[0]*1.3,(view,red,blue)
            frames[view]=frame
        entry={'id':ident,'name':name,'sheet':f'res://art/vehicles/{ident}/{target.name}',
               'world_length':length,'world_width':width,'police':ident=='police-sedan','frames':frames}
        catalog.append(entry)
        (target.parent/'views.json').write_text(json.dumps(entry,indent=2),encoding='utf-8')
    (OUT/'catalog.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
    print(json.dumps({'models':len(catalog),'views':sum(len(e['frames']) for e in catalog),'pixel_edits':False}))

if __name__=='__main__':main()
