"""Report H3 frames whose subject is cut off by the canvas edge.

Usage: python check_h3_framing.py [id-prefix ...]   (default: every clip)
"""
import sys
import numpy as np
from review_h3_modular_batch import DEFAULT_BATCH,load


def cut_edges(frame,need=10):
    """Edges the subject runs into, with how many pixels touch. Glow and grain are ignored."""
    rgb=np.asarray(frame).astype(int);h,w=rgb.shape[:2]
    corners=np.concatenate([rgb[:14,:14].reshape(-1,3),rgb[:14,-14:].reshape(-1,3),rgb[-14:,:14].reshape(-1,3),rgb[-14:,-14:].reshape(-1,3)])
    backdrop=np.median(corners,axis=0)
    far=np.abs(rgb-backdrop).max(axis=2)>52
    strips={'left':far[:,1:4],'right':far[:,-4:-1],'top':far[1:4].T,'bottom':far[-4:-1].T}
    return {k:int(v.all(axis=1).sum()) for k,v in strips.items() if v.all(axis=1).sum()>=need}


def main():
    wanted=sys.argv[1:];bad=0
    for folder in sorted(p for p in DEFAULT_BATCH.iterdir() if p.is_dir()):
        if wanted and not any(folder.name.startswith(w) for w in wanted):continue
        files=list(folder.glob('*_audio.mp4'))
        if not files:continue
        hits={}
        for i,frame in enumerate(load(max(files,key=lambda p:p.stat().st_mtime))):
            for edge in cut_edges(frame):hits.setdefault(edge,[]).append(i)
        if hits:
            bad+=1
            print(folder.name,{k:f'{len(v)} frames ({v[0]}-{v[-1]})' for k,v in hits.items()})
    print('clips with cut-off frames:',bad)


if __name__=='__main__':main()
