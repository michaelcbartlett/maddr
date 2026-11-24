"""Make a non-destructive behind-head test from the user's cleaner second take."""
from pathlib import Path
import av
import copy
import json
import shutil
import uuid
from PIL import Image, ImageDraw
from build_h3_sprite_pack import PACK, INPUT_SUBDIR, PALETTE, ROOT, mannequin, render_guides

SOURCE=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Shared/output/video/mad-villain-sprite/01-near-shoulder/113525_00001_audio.mp4'


def main():
    with av.open(str(SOURCE)) as video:
        workflow=json.loads(video.metadata['workflow'])
        submitted=json.loads(video.metadata['prompt'])
    refs=PACK/'references'
    render_guides(refs,behind_head=True)
    workflow['id']=str(uuid.uuid4());workflow['revision']=0
    n=next(n for n in workflow['nodes'] if n['type']=='MiniMaxH3Director')
    n['title']='Near arm behind head: v2 depth test'
    values=n['widgets_values_named'];timeline=json.loads(values['timeline_data']);builder=json.loads(values['builder_state'])
    video_item=next(item for item in timeline['items'] if item['type']=='video')
    video_item['value']=f'{INPUT_SUBDIR}/puppet-shoulder-behind-head-v2.mp4'
    video_item['enabled']=True
    depth=('Depth order for this study: far arm behind torso; moving arm in front of torso; '
           'head in front of moving forearm, hand and prop whenever their silhouettes overlap. '
           'During the folded-elbow pose, the hand and prop pass behind the head and are hidden '
           'inside its silhouette, reappearing as they clear it. Follow the visible occlusion in '
           '<Video 1>. Keep a solid head silhouette. No transparent skin, ghost limbs or duplicate props.')
    builder['ref']['detailed_description']+='\n'+depth
    prompt='\n\n'.join(f'{key}:\n{builder["ref"][key]}' for key in (
        'subject_definitions','summary','retention_analysis','detailed_description','overall_soundscape','non_diegetic_music'))
    builder['simple_prompt']=prompt
    timeline['builder_state']=builder;timeline['resolved_prompt']=prompt
    values['prompt']=prompt;values['builder_state']=json.dumps(builder,separators=(',',':'))
    values['timeline_data']=json.dumps(timeline,separators=(',',':'))
    n['widgets_values']=[values[k] for k in values]
    seed_node=next(n for n in workflow['nodes'] if n['type']=='DaSiWa_SeedControl')
    # Preserve the numeric seed actually submitted, not the different UI-history
    # string (64-bit seeds can be rounded by JavaScript's Number representation).
    used_seed=submitted[str(seed_node['id'])]['inputs']['seed_value']
    seed_values=seed_node['widgets_values_named']
    state=json.loads(seed_values['seed_control_state']);state.update(mode='fixed',last_seed=str(used_seed))
    seed_values.update(seed_value=used_seed,seed_control_state=json.dumps(state,separators=(',',':')))
    seed_node['widgets_values']=[seed_values[k] for k in seed_values]
    combine=next(n for n in workflow['nodes'] if n['type']=='DaSiWa_EnhancedVideoCombine')
    prefix='video/mad-villain-sprite/01-near-shoulder-behind-head-v2/%date:hhmmss%'
    combine['widgets_values'][8]=prefix;combine['widgets_values_named']['filename_prefix']=prefix
    # Preserve the second take's LoRA stack and every sampling/model setting.
    stack=next(n for n in workflow['nodes'] if n['type']=='DaSiWa_LTX2LoraLoader')
    assert stack['widgets_values'][0]==submitted[str(stack['id'])]['inputs']['stack_data']
    filename=PACK/'Scientist-Near-Arm-Behind-Head-v2.json'
    filename.write_text(json.dumps(workflow,ensure_ascii=False,indent=2),encoding='utf-8')
    im,joints=mannequin(4.2,'shoulder',head_in_front=True)
    wrist=joints['near']['wrist'];assert im.getpixel((round(wrist[0]),round(wrist[1])))==tuple(bytes.fromhex(PALETTE['head'][1:]))
    original,_=mannequin(0,'shoulder');fixed,_=mannequin(0,'shoulder',head_in_front=True)
    assert original.tobytes()==fixed.tobytes(),'starting pose must stay identical'
    board=Image.new('RGB',(768,400),'#222832');draw=ImageDraw.Draw(board)
    for i,t in enumerate([0,1,2.3,3.6,4.2,4.6]):
        tile,_=mannequin(t,'shoulder',head_in_front=True);tile=tile.resize((192,192))
        x=i%3*256;y=i//3*200;board.paste(tile,(x+32,y+8));draw.text((x+2,y+2),str(t)+'s',fill='white')
    board.save(PACK/'occlusion-v2-preview.jpg')
    report={'base_take':SOURCE.name,'effective_submitted_seed':used_seed,'fixed_seed':True,
        'preserved_loras':json.loads(stack['widgets_values'][0]),'head_occludes_hand_test':'passed',
        'initial_pose_pixel_identity':'passed','generation_quality_verified':False}
    (PACK/'occlusion-v2-validation.json').write_text(json.dumps(report,indent=2))
    print(filename)
    print('Head hides overlapping hand/prop; first pose identical; clean take settings and LoRAs retained; seed fixed.')


if __name__=='__main__':main()
