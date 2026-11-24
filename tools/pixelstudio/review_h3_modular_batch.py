"""Build a diagnostic modular composite from completed H3 footage.

This is a rough cutout proof, not a production sprite importer. Uses the walk
lower body, a static torso/head/resting near arm, and an independent far arm.
Requires the ComfyUI Python environment (av, cv2, numpy, Pillow).
"""
from pathlib import Path
import argparse
import json
import av
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BATCH = Path('C:/Users/micha/AppData/Local/Comfy-Desktop/ComfyUI-Shared/output/video/mad-villain-sprite/batch')


def load(path):
    with av.open(str(path)) as video:
        return [frame.to_image().convert('RGB') for frame in video.decode(video=0)]


def matte(frame):
    rgb = np.asarray(frame).astype(np.int16)
    # These clips have a dark blue background and nearly black sprite outlines.
    # Keep the outlines; this deliberately does not chroma-key the green prop.
    bg = np.array([14, 24, 35])
    blue_background = (rgb[:,:,1] > rgb[:,:,0]+3) & (rgb[:,:,2] > rgb[:,:,1]+3)
    candidate = ((np.linalg.norm(rgb-bg, axis=2) <= 24) & blue_background).astype(np.uint8)
    _, regions = cv2.connectedComponents(candidate, 8)
    border_ids = np.unique(np.concatenate((regions[0],regions[-1],regions[:,0],regions[:,-1])))
    border_ids = border_ids[border_ids != 0]
    foreground = (~np.isin(regions,border_ids)).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(foreground, 8)
    keep = np.zeros_like(foreground)
    for i in range(1, count):
        if stats[i, cv2.CC_STAT_AREA] >= 90:
            keep[labels == i] = 255
    return Image.fromarray(keep)


def cut(frame, alpha):
    out = frame.convert('RGBA')
    out.putalpha(alpha)
    return out


def native(frame):
    return frame.resize((128, 128), Image.Resampling.NEAREST)


def sheet(frames, path):
    out = Image.new('RGBA', (128*16, 128*((len(frames)+15)//16)))
    for i, frame in enumerate(frames):
        out.paste(frame, ((i%16)*128, (i//16)*128))
    out.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batch', type=Path, default=DEFAULT_BATCH)
    parser.add_argument('--output', type=Path, default=ROOT/'export/comfyui/scientist-modular/batch-review')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = {p.name: next(p.glob('*_audio.mp4')) for p in sorted(args.batch.iterdir()) if p.is_dir() and list(p.glob('*_audio.mp4'))}
    if len(sources) != 36:
        raise RuntimeError(f'Expected 36 completed clips, found {len(sources)}')
    walk = load(sources['11-walk'])
    arm = load(sources['06-far-shoulder'])
    base = arm[50]
    # Cut along the far shoulder and waist, keeping the resting near hand intact.
    region = Image.new('L', (768,768))
    ImageDraw.Draw(region).polygon([(0,0),(550,0),(550,275),(452,275),
        (434,296),(449,350),(456,410),(465,495),(311,495),
        (311,579),(119,579),(119,495),(0,495)], fill=255)
    body_alpha = Image.fromarray(np.minimum(np.asarray(matte(base)), np.asarray(region)))
    body = cut(base, body_alpha)
    # A modest expansion keeps changing source hair edges out of the arm cutout.
    exclusion = np.asarray(body_alpha.filter(ImageFilter.MaxFilter(9))) > 0
    yy, xx = np.indices((768,768))
    # The arm source still contains its original pelvis and coat below the waist.
    full_silhouette = np.asarray(matte(base).filter(ImageFilter.MaxFilter(9))) > 0
    exclusion |= full_silhouette & (yy >= 495)
    arm_roi = (xx > 330) & (yy < 590)
    lower = []
    arms = []
    composites = []
    panels = []
    fontpath = Path('C:/Windows/Fonts/consola.ttf')
    font = ImageFont.truetype(str(fontpath), 17) if fontpath.exists() else ImageFont.load_default()
    refgray = cv2.cvtColor(np.asarray(walk[30]), cv2.COLOR_RGB2GRAY)
    buckle = refgray[469:496, 371:405]
    offsets = []
    for i in range(len(arm)):
        # The clocks are intentionally independent: repeat a selected walk span
        # while the far arm makes its slower shoulder sweep.
        wi = 20 + i % 70
        w = walk[wi]
        gray = cv2.cvtColor(np.asarray(w), cv2.COLOR_RGB2GRAY)
        result = cv2.matchTemplate(gray[445:521,340:440], buckle, cv2.TM_CCOEFF_NORMED)
        _, confidence, _, loc = cv2.minMaxLoc(result)
        dx,dy = loc[0]+340-371, loc[1]+445-469
        offsets.append({'frame':i,'walk_source_frame':wi,'root_offset':[dx,dy], 'belt_match':round(confidence,3)})
        wa = np.asarray(matte(w)).copy()
        wa[yy < 495+dy] = 0
        l = cut(w, Image.fromarray(wa))
        aa = np.asarray(matte(arm[i])).copy()
        aa[exclusion | ~arm_roi] = 0
        # Drop small disconnected remnants of the source coat/body silhouette.
        component_count, components, stats, _ = cv2.connectedComponentsWithStats((aa>0).astype(np.uint8),8)
        for component in range(1,component_count):
            if stats[component,cv2.CC_STAT_AREA] < 1200:
                aa[components==component] = 0
        a = cut(arm[i], Image.fromarray(aa))
        # Far arm behind torso and head; lower body supplies coat tails and legs.
        composite = Image.new('RGBA', (768,768))
        composite.alpha_composite(a, (dx,dy))
        composite.alpha_composite(l)
        composite.alpha_composite(body, (dx,dy))
        lower.append(native(l)); arms.append(native(a)); composites.append(native(composite))
        panel = Image.new('RGB', (1024,316), '#182535')
        draw = ImageDraw.Draw(panel)
        draw.text((12,8), '128px / 24fps - rough cutout proof; green proxy retained', font=font, fill='#edf2f7')
        for j,(label,frame) in enumerate([('Walk source', native(w)),('Far-arm source',native(arm[i])),('Extracted far arm',native(a)),('Combined layers',native(composite))]):
            tile = Image.new('RGBA',(128,128),'#24354a')
            tile.alpha_composite(frame.convert('RGBA'))
            panel.paste(tile.convert('RGB').resize((256,256),Image.Resampling.NEAREST), (j*256,36))
            draw.text((j*256+10,294),label,font=font,fill='#edf2f7')
        panels.append(panel)
    native(body).save(args.output/'static-upper-body.png')
    sheet(lower,args.output/'walk-lower-body.png')
    sheet(arms,args.output/'far-arm.png')
    sheet(composites,args.output/'combined-proof.png')
    with av.open(str(args.output/'modular-proof.mp4'),'w') as output:
        stream = output.add_stream('libx264',rate=24)
        stream.width,stream.height,stream.pix_fmt = 1024,316,'yuv420p'
        stream.options = {'crf':'18'}
        for panel in panels:
            for packet in stream.encode(av.VideoFrame.from_image(panel)):
                output.mux(packet)
        for packet in stream.encode():
            output.mux(packet)
    # GIF uses a global palette and an exact integer-millisecond approximation.
    gifframes = [p.resize((768,237),Image.Resampling.NEAREST) for p in panels]
    durations = [round((i+1)*1000/24)-round(i*1000/24) for i in range(len(gifframes))]
    gifframes[0].save(args.output/'modular-proof.gif',save_all=True,append_images=gifframes[1:],duration=durations,loop=0)
    panels[50].save(args.output/'modular-proof-still.png')
    overview = Image.new('RGB',(1024,316*4),'#182535')
    for row,index in enumerate([15,50,75,100]): overview.paste(panels[index],(0,row*316))
    overview.save(args.output/'modular-proof-contact.png')
    (args.output/'proof-metadata.json').write_text(json.dumps({
        'completed_clips':len(sources),'fps':24,'cell':[128,128],'frames':len(arm),
        'sources':{k:str(v) for k,v in sources.items()},'layer_order':['far arm','walk lower body','static upper body and resting near arm'],
        'limitations':['Rough polygon masks; not production segmentation','Green proxy retained','Static head/torso/near arm','Selected walk span repeats without loop cleanup','No invented hidden pixels or replacement weapon','Overhead source prop is clipped by the original video'],
        'frames_metadata':offsets},indent=2),encoding='utf-8')
    print(json.dumps({'completed_clips':len(sources),'preview':str(args.output/'modular-proof.mp4'),'frames':len(composites)}))


if __name__ == '__main__': main()
