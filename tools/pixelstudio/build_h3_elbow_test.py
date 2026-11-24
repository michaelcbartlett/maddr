"""Correct the far-arm elbow guide and reuse the clean 16-step take's settings."""
from pathlib import Path
import av
import json
import math
import uuid
from PIL import Image, ImageDraw
from build_h3_sprite_pack import PACK, INPUT_SUBDIR, PALETTE, mannequin, render_guides

SOURCE=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Shared/output/video/mad-villain-sprite/01-near-shoulder/115037_00001_audio.mp4'
REFERENCE='puppet-far-elbow-behind-head-v2.mp4'


def main():
    refs=PACK/'references'
    render_guides(refs,behind_head=True,studies=('elbow',),moving_arm='far')
    with av.open(str(SOURCE)) as container:
        workflow=json.loads(container.metadata['workflow'])
        submitted=json.loads(container.metadata['prompt'])
    workflow['id']=str(uuid.uuid4());workflow['revision']=0
    node=next(n for n in workflow['nodes'] if n['type']=='MiniMaxH3Director')
    node['title']='02 Far-arm elbow: corrected depth / 16 steps'
    values=node['widgets_values_named']
    timeline=json.loads(values['timeline_data']);builder=json.loads(values['builder_state'])
    motion=next(item for item in timeline['items'] if item['type']=='video')
    motion.update(value=f'{INPUT_SUBDIR}/{REFERENCE}',enabled=True,trim_start=0,trim_end=5,
                  duration=5,source_duration=5,source_width=768,source_height=768,media_mode='video',
                  prompt='Far-arm elbow motion only. The torso and head occlude the moving arm wherever they overlap.')
    builder['ref']['detailed_description']=(
        "One continuous fixed-camera sprite articulation study of <Subject 1>. Preserve <Picture 1>'s scientist: "
        "same face, grin, wild white hair, black glasses, white coat, burgundy shirt, trousers, shoes, proportions, "
        "palette and pixel-art shading. Keep the entire body, head, expression, feet and foreground near arm still. "
        "Only the BACKGROUND FAR FOREARM AND HAND move, holding the matte green calibration grip from <Picture 2>. "
        "The far arm is the arm already moving in the previous shoulder study: the screen-right arm in this "
        "right-facing three-quarter view. The screen-left foreground arm stays relaxed and motionless. "
        "Keep the moving upper arm horizontal toward screen-right, shoulder and elbow in fixed positions. "
        "Follow <Video 1>: slowly fold the far elbow, briefly show the folded pose, then straighten, twice. "
        "Keep upper arm and forearm lengths constant, fingers wrapped around the same grip, prop rigid and "
        "consistent in size. No shoulder sweep or torso turn. "
        "DEPTH: the far arm is behind the torso and head. When the hand, forearm or green prop overlaps the "
        "head or torso silhouette, hide that overlapping section completely. Follow the opaque occlusion "
        "demonstrated by <Video 1>. Reappear only after clearing that silhouette. No transparent head, ghost "
        "hand, duplicate grip or hand painted over the face. Ignore the mannequin's colors and identity. "
        "Locked camera angle, framing, zoom and body scale; feet planted at the same ground line. Full body "
        "visible with generous arm clearance on a flat dark blue-gray background. Sharp individual frames, "
        "crisp sleeve, hand and prop edges. No motion blur, frame blending, ghost trails, crosshatching, "
        "texture overlays, new limbs, added facial hair, dialogue, text or logos.")
    prompt='\n\n'.join(f'{key}:\n{builder["ref"][key]}' for key in (
        'subject_definitions','summary','retention_analysis','detailed_description','overall_soundscape','non_diegetic_music'))
    builder.update(duration=5,mode='REF2VA',simple_prompt=prompt)
    timeline.update(builder_state=builder,resolved_prompt=prompt)
    values.update(prompt=prompt,duration=5,mode='REF2VA',frame_rate=24,
                  builder_state=json.dumps(builder,separators=(',',':')),timeline_data=json.dumps(timeline,separators=(',',':')))
    node['widgets_values']=[values[k] for k in values]
    seed=next(n for n in workflow['nodes'] if n['type']=='DaSiWa_SeedControl')
    seed_values=seed['widgets_values_named'];used_seed=submitted[str(seed['id'])]['inputs']['seed_value']
    state=json.loads(seed_values['seed_control_state']);state.update(mode='fixed',last_seed=str(used_seed))
    seed_values.update(seed_value=used_seed,seed_control_state=json.dumps(state,separators=(',',':')))
    seed['widgets_values']=[seed_values[k] for k in seed_values]
    settings=next(n for n in workflow['nodes'] if n.get('title')=='Settings')
    assert settings['widgets_values_named']['steps']==16
    combine=next(n for n in workflow['nodes'] if n['type']=='DaSiWa_EnhancedVideoCombine')
    prefix='video/mad-villain-sprite/02-far-elbow-behind-head-v2/%date:hhmmss%'
    combine['widgets_values'][8]=prefix;combine['widgets_values_named']['filename_prefix']=prefix
    stack=next(n for n in workflow['nodes'] if n['type']=='DaSiWa_LTX2LoraLoader')
    assert stack['widgets_values'][0]==submitted[str(stack['id'])]['inputs']['stack_data']
    (PACK/'Scientist-Far-Elbow-Behind-Head-v2.json').write_text(json.dumps(workflow,indent=2,ensure_ascii=False),encoding='utf-8')
    # Check actual draw order, fixed upper arm, and exact limb lengths for every frame.
    mask=Image.new('1',(768,768));ImageDraw.Draw(mask).ellipse((310,118,458,246),fill=1)
    inside=[(x,y) for y in range(118,247) for x in range(310,459) if mask.getpixel((x,y))]
    head_color=tuple(bytes.fromhex(PALETTE['head'][1:]))
    frames_with_hidden_pixels=0
    for i in range(120):
        im,j=mannequin(i/24,'elbow',head_in_front=True,moving_arm='far')
        assert j['far']['shoulder']==(350,287) and j['far']['elbow']==(434.0,287.0)
        assert math.isclose(math.dist(j['far']['elbow'],j['far']['wrist']),96,abs_tol=.0001)
        assert all(im.getpixel(point)==head_color for point in inside),'head overwritten by hand/prop'
        wrist=tuple(round(v) for v in j['far']['wrist'])
        if mask.getpixel(wrist): frames_with_hidden_pixels+=1
    assert frames_with_hidden_pixels>0,'test must exercise a real head overlap'
    board=Image.new('RGB',(768,400),'#222832');d=ImageDraw.Draw(board)
    for i,t in enumerate([0,.5,1,1.25,1.5,2]):
        im,_=mannequin(t,'elbow',head_in_front=True,moving_arm='far');im=im.resize((192,192))
        x=i%3*256;y=i//3*200;board.paste(im,(x+32,y+8));d.text((x+2,y+2),f'{t}s',fill='white')
    board.save(PACK/'far-elbow-v2-preview.jpg')
    report={'base_take':SOURCE.name,'study':'far elbow','frames':120,'fps':24,'seconds':5,
            'head_occlusion_test':'passed for all 120 frames','overlap_frames_tested':frames_with_hidden_pixels,
            'fixed_shoulder_and_elbow_test':'passed','constant_forearm_length_test':'passed',
            'steps':16,'fixed_seed':used_seed,'lora_stack_preserved':True,'model_inference_run':False}
    (PACK/'far-elbow-v2-validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))


if __name__=='__main__':main()
