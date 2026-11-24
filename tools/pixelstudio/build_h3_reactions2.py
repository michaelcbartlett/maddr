"""Burning loop from the user's burn clip, and a defeat retry with room to lie down. Never queues."""
import shutil
from pathlib import Path
import av
from PIL import Image
from build_h3_reactions import prompt
from build_h3_sprite_pack import PACK
import queue_h3_animations as queue

OUT=PACK/'reactions-2'
BURN=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Shared/output/video/2026-11-23/202951_00001_audio.mp4'


def main():
    refs=OUT/'references';refs.mkdir(parents=True,exist_ok=True)
    shutil.copy2(PACK/'references/proxy-grip.png',refs/'proxy-grip.png')
    for name in ['queue-api-template.json','queue-workflow-template.json']:shutil.copy2(PACK/name,OUT/name)
    with av.open(str(BURN)) as video:
        for i,frame in enumerate(video.decode(video=0)):
            if i==31:frame.to_image().save(refs/'burning.png');break
    # Half-size figure on its own backdrop: lying down needs about twice the width.
    source=Image.open(PACK/'references/scientist.png').convert('RGB').resize((768,768),Image.Resampling.NEAREST)
    small=source.resize((422,422),Image.Resampling.NEAREST);canvas=Image.new('RGB',(768,768),source.getpixel((4,4)))
    canvas.paste(small,(250,300));canvas.save(refs/'scientist-small.png')
    shots=[('79-burning-loop','burning.png','A seamless looping panic while on fire. He is already burning in every frame.',
      'He stays in this wide flailing stance for the whole shot, shouting. Hands shake and claw the air, head rattles, knees jitter, coat edges flap. Feet stay planted. Small flames on his hair, shoulders, cuffs, coat hem and shoes flicker and change shape rapidly but stay attached to the same places and the same size. The first and last frames match.',
      'Keep flames small and attached to him. NO smoke clouds, NO loose embers or separate floating flames; the game draws those. He stays fully visible and his face is never covered.'),
     ('80-defeat','scientist-small.png','A single cartoon defeat. He is drawn small with a lot of empty space around him and stays that small size.',
      'Facing three-quarter screen-right. Hold neutral 0.4 seconds. He clutches his chest and staggers, knees wobbling, until 1.20. His knees buckle and he drops to kneeling at 1.60, sways, then falls over sideways to lie on the ground by 2.40, curled slightly, coat spread. One tiny bounce. From 2.80 to 5.00 he lies completely still. He remains in the same area of the frame; his entire body, head to shoes, is always well inside the frame with wide empty margins.',
      'No zooming in. No lightning, sparks, smoke, flashes or particles.')]
    rows=[]
    for ident,subject,summary,action,extra in shots:
        text=prompt(summary,action,extra)
        rows.append({'id':ident,'seconds':5,'fps':24,'subject_reference':subject,'item_reference':'proxy-grip.png','motion_reference':None,'prompt':text})
        (OUT/(ident+'-prompt.txt')).write_text(text,encoding='utf-8')
    queue.atomic_json(OUT/'animation-queue-manifest.json',rows)
    print([j['id'] for j in queue.prepare_jobs(OUT,rows,queue.read_json(OUT/'queue-api-template.json'),queue.read_json(OUT/'queue-workflow-template.json'))])


if __name__=='__main__':main()
