"""Per-frame MoGe-2 normals through the local ComfyUI server, cached on disk.

Returns None when the server is unavailable and the cache is incomplete, so the
importer can fall back to its silhouette normals.
"""
import hashlib
import json
import time
import urllib.request
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
CACHE=ROOT/'.local/moge-cache'
SHARED=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Shared'
URL='http://127.0.0.1:8188'
MODEL='moge_2_vitl_normal_fp16.safetensors'


def call(path,body=None):
    data=json.dumps(body).encode() if body else None
    request=urllib.request.Request(URL+path,data,{'Content-Type':'application/json'})
    return json.load(urllib.request.urlopen(request,timeout=20))


FRONT=False   # set True to run ahead of long renders already queued


def submit(key,frame):
    folder=SHARED/'input/MadVillain_Normals';folder.mkdir(parents=True,exist_ok=True)
    frame.save(folder/(key+'.png'))
    return call('/prompt',{'front':FRONT,'prompt':{
        '1':{'class_type':'LoadImage','inputs':{'image':'MadVillain_Normals/'+key+'.png'}},
        '2':{'class_type':'LoadMoGeModel','inputs':{'model_name':MODEL}},
        '3':{'class_type':'MoGeInference','inputs':{'moge_model':['2',0],'image':['1',0],'resolution_level':9,
            'fov_x_degrees':10.0,'batch_size':1,'force_projection':True,'apply_mask':False,'refine_steps':0}},
        '4':{'class_type':'MoGeRender','inputs':{'moge_geometry':['3',0],'output':'normal_opengl'}},
        '5':{'class_type':'SaveImage','inputs':{'images':['4',0],'filename_prefix':'mad-villain-normals/'+key}}}})['prompt_id']


def estimate(frames):
    """RGB frames -> list of HxWx3 float unit normals (x right, y up, z out)."""
    CACHE.mkdir(parents=True,exist_ok=True)
    keys=[hashlib.sha256(np.asarray(f.convert('RGB')).tobytes()).hexdigest()[:24] for f in frames]
    try:
        waiting={}
        for key,frame in zip(keys,frames):
            if not (CACHE/(key+'.png')).exists() and key not in waiting:waiting[key]=submit(key,frame.convert('RGB'))
        deadline=time.time()+900
        while waiting:
            if time.time()>deadline:raise TimeoutError('MoGe queue')
            for key,job in list(waiting.items()):
                done=call('/history/'+job)
                if job not in done:continue
                if done[job]['status']['status_str']!='success':raise RuntimeError(str(done[job]['status'])[:300])
                item=done[job]['outputs']['5']['images'][0]
                Image.open(SHARED/'output'/item['subfolder']/item['filename']).convert('RGB').save(CACHE/(key+'.png'))
                del waiting[key]
            time.sleep(.5)
    except (OSError,RuntimeError,TimeoutError,KeyError) as error:
        print('MoGe unavailable, using silhouette normals:',error);return None
    out=[]
    for key in keys:
        n=np.asarray(Image.open(CACHE/(key+'.png'))).astype(np.float32)/127.5-1
        out.append(unit(n))
    return out


def unit(n):
    return n/(np.linalg.norm(n,axis=2,keepdims=True)+1e-6)


def smooth_loop(normals,weight=.5):
    """Average each frame with its loop neighbours to stop lighting shimmer."""
    count=len(normals)
    return [unit(normals[i]+weight*(normals[i-1]+normals[(i+1)%count])) for i in range(count)]


def encode(n,alpha):
    """Unit normals at source size -> 128px RGBA normal tile under `alpha`."""
    small=unit(cv2.resize(n,(128,128),interpolation=cv2.INTER_AREA))
    small[:,:,2]=np.maximum(small[:,:,2],.15);small=unit(small)
    rgba=np.zeros((128,128,4),np.uint8);rgba[:,:,:3]=np.rint((small*.5+.5)*255);rgba[:,:,3]=alpha
    rgba[alpha==0]=0
    return Image.fromarray(rgba)
