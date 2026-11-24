"""Prepare queue templates from a proven take; never submit a generation."""
from pathlib import Path
import av
import json
from build_h3_sprite_pack import PACK, COMMON, render_guides


def main():
    source=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Shared/output/video/mad-villain-sprite/01-near-shoulder/115037_00001_audio.mp4'
    with av.open(str(source)) as c:
        api=json.loads(c.metadata['prompt']);workflow=json.loads(c.metadata['workflow'])
    api={key:{k:n[k] for k in ('class_type','inputs','_meta') if k in n} for key,n in api.items()}
    (PACK/'queue-api-template.json').write_text(json.dumps(api,indent=2),encoding='utf-8')
    (PACK/'queue-workflow-template.json').write_text(json.dumps(workflow,indent=2),encoding='utf-8')
    render_guides(PACK/'references',behind_head=True,studies=('elbow',))
    render_guides(PACK/'references',behind_head=True,studies=('shoulder',),moving_arm='far')
    shots=json.loads((PACK/'animation-commissions.json').read_text(encoding='utf-8'))
    guide_map={
        '01-near-shoulder':'puppet-shoulder-behind-head-v2.mp4',
        '02-near-elbow':'puppet-elbow-behind-head-v2.mp4',
        '06-far-shoulder':'puppet-far-shoulder-behind-head-v2.mp4',
        '07-far-elbow':'puppet-far-elbow-behind-head-v2.mp4',
        '11-walk':'puppet-walk.mp4',
    }
    sharp=' Sharp individual frames and crisp sleeve, hand and prop edges. No motion blur, frame blending, ghost trails, crosshatching or texture overlays.'
    for row in shots:
        prompt=row['prompt']
        motion=guide_map.get(row['id'])
        if motion and not row['motion_reference']:
            prompt=prompt.replace('defines only the held green calibration prop.',
                'defines only the held green calibration prop.\n<Video 1> is a mannequin motion guide; transfer movement only.')
            prompt=prompt.replace('detailed_description:',
                '<Video 1> (motion): partially_preserved - transfer timing and joint positions, ignore mannequin appearance.\n\ndetailed_description:')
        body,tail=prompt.split('\n\noverall_soundscape:',1)
        body+=sharp
        if row['id'].startswith(('01-','02-','06-','07-')):
            role='near' if '-near-' in row['id'] else 'far'
            body+=f' Move only the {role} arm named in this shot; keep the other arm still. Follow <Video 1>.'
            body+=' Where the guide puts the hand or prop behind the head silhouette, the head hides it completely. No translucent overlap or duplicate prop.'
            if role=='far':body+=' Keep the far arm behind the torso at the shoulder; the foreground near arm stays relaxed.'
        row.update(motion_reference=motion,prompt=body+'\n\noverall_soundscape:'+tail)
    (PACK/'animation-queue-manifest.json').write_text(json.dumps(shots,indent=2),encoding='utf-8')
    print(f'Prepared {len(shots)} jobs with five corrected/appropriate motion references and 16-step API template.')


if __name__=='__main__':main()
