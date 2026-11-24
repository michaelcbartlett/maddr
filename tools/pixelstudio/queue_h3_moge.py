"""MoGe-2 normal maps from completed H3 clips, with frame hashes and resumable jobs.

Default is a local plan, never a submission. --submit appends jobs; --collect
downloads completed results into the cache used by the enemy sprite importer.
No queue clearing, priority changes, game imports or silhouette fallbacks.
"""
from pathlib import Path
import argparse
import hashlib
import io
import time
import urllib.parse
import av
import numpy as np
from PIL import Image
import queue_h3_animations as queue
from moge_normals import CACHE, MODEL
from review_h3_modular_batch import DEFAULT_BATCH
from check_h3_framing import cut_edges

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PACK = ROOT/'export/comfyui/swat-shield'


def graph(key, server_path):
    return {
        '1': {'class_type': 'LoadImage', 'inputs': {'image': server_path}},
        '2': {'class_type': 'LoadMoGeModel', 'inputs': {'model_name': MODEL}},
        '3': {'class_type': 'MoGeInference', 'inputs': {
            'moge_model': ['2', 0], 'image': ['1', 0], 'resolution_level': 9,
            'fov_x_degrees': 10.0, 'batch_size': 1, 'force_projection': True,
            'apply_mask': False, 'refine_steps': 0}},
        '4': {'class_type': 'MoGeRender', 'inputs': {'moge_geometry': ['3', 0], 'output': 'normal_opengl'}},
        '5': {'class_type': 'SaveImage', 'inputs': {
            'images': ['4', 0], 'filename_prefix': 'mad-villain-normals/'+key}},
    }


def cached(key, size=None):
    try:
        with Image.open(CACHE/(key+'.png')) as image:
            image.load()
            return image.mode == 'RGB' and (size is None or image.size == tuple(size))
    except OSError:
        return False


def prepare(pack, batch, state, shots=None, stride=1, allow_partial=False, allow_clipped=False, framing_review=None):
    rows = queue.select_rows(queue.read_json(pack/'animation-queue-manifest.json'), shots, None)
    review_path=framing_review or pack/'moge-framing-review.json'
    review=queue.read_json(review_path) if review_path.exists() else {'version':1,'clips':{}}
    if not isinstance(review,dict) or review.get('version')!=1 or not isinstance(review.get('clips'),dict):
        raise queue.BatchError('Invalid MoGe framing review: '+str(review_path))
    sources={}; missing=[]
    for row in rows:
        folder=batch/row['id']; files=list(folder.glob('*_audio.mp4')) or list(folder.glob('*.mp4'))
        if not files: missing.append(row['id'])
        else: sources[row['id']]=max(files,key=lambda p:p.stat().st_mtime_ns)
    if missing and not allow_partial:
        raise queue.BatchError('Finish the animation batch first. Missing: '+', '.join(missing)+'. Use --shots or --allow-partial for a deliberate subset.')
    if not sources: raise queue.BatchError('No completed clips found. Run Queue SWAT Shield.bat first.')
    for ident in missing: print('NOT READY:',ident)
    index={'version':1,'pack':str(pack.resolve()),'stride':stride,'clips':[]}; jobs={}
    frames_dir=state/'frames'; frames_dir.mkdir(parents=True,exist_ok=True)
    for row in rows:
        if row['id'] not in sources: continue
        source=sources[row['id']]; before=source.stat(); frames=[]; clipped=[]
        with av.open(str(source)) as video:
            stream=video.streams.video[0]
            if abs(float(stream.average_rate or 0)-row['fps']) > .01:
                raise queue.BatchError(f'{source}: expected {row["fps"]}fps')
            count=0
            for i,decoded in enumerate(video.decode(video=0)):
                count=i+1
                if i % stride: continue
                frame=decoded.to_image().convert('RGB')
                if cut_edges(frame): clipped.append(i)
                # Same key contract as moge_normals.estimate; never key by filename or pose number.
                key=hashlib.sha256(np.asarray(frame).tobytes()).hexdigest()[:24]
                path=frames_dir/(key+'.png')
                if not path.exists(): frame.save(path)
                frames.append({'frame':i,'seconds':i/row['fps'],'key':key,'size':list(frame.size),
                               'normal':str(CACHE/(key+'.png'))})
                if key not in jobs and not cached(key,frame.size):
                    server='MadVillain_Normals/'+key+'.png'; api=graph(key,server)
                    # Contract-compatible with the crash-safe H3 submission ledger.
                    jobs[key]={'id':'moge-'+key,'key':queue.digest({'api':api,'rgb':key}),
                               'api':api,'workflow':{},'assets':{'frame':{
                                   'source':str(path),'server_path':server}}}
        after=source.stat()
        if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):
            raise queue.BatchError(f'{source}: still being written; retry after generation finishes')
        expected=round(row['seconds']*row['fps'])
        # H3 often pads 5s/24fps clips to 124 frames; retain the actual decoded frame indices.
        if count < expected or count > expected+row['fps']:
            raise queue.BatchError(f'{source}: {count} frames; expected about {expected}. Possibly incomplete or wrong clip.')
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()
        reviewed=review['clips'].get(row['id'])
        approved=set()
        if reviewed:
            if not isinstance(reviewed,dict) or not reviewed.get('reason') or not isinstance(reviewed.get('allowed_frames'),list):
                raise queue.BatchError('Invalid framing review for '+row['id'])
            if reviewed.get('source_sha256')!=source_sha256:
                raise queue.BatchError(f'{row["id"]}: framing review belongs to a different video. Review the replacement clip before MoGe.')
            approved=set(reviewed['allowed_frames'])
        unreviewed=set(clipped)-approved
        if unreviewed and not allow_clipped:
            raise queue.BatchError(f'{row["id"]}: subject/effect touches the canvas edge at {len(unreviewed)} unreviewed sampled frames. Review/retake before MoGe; --allow-clipped explicitly bypasses this check.')
        if clipped and approved: print(f'{row["id"]}: reviewed edge effects ({len(clipped)} frames): {reviewed["reason"]}',flush=True)
        index['clips'].append({'id':row['id'],'source':str(source),'source_sha256':source_sha256,
                               'fps':row['fps'],'decoded_frames':count,'frames':frames,'clipped_frames':clipped})
        print(f'{row["id"]}: {len(frames)} sampled / {count} decoded frames',flush=True)
    queue.atomic_json(state/'normal-frame-index.json',index)
    return index,list(jobs.values())


def preflight(client, jobs):
    info=client.get('/object_info')
    if 'LoadImage' not in info: raise queue.BatchError('Missing server node: LoadImage')
    # LoadImage's combo contains only already-uploaded images. Don't demand new frames
    # exist there during a read-only check; all other nodes/enums use the standard check.
    filtered={'api':{k:v for k,v in jobs[0]['api'].items() if v['class_type']!='LoadImage'}}
    return queue.check_server(client,[filtered])


def collect(client, state, index):
    ledger=queue.read_json(state/'queue-log.json') if (state/'queue-log.json').exists() else {'jobs':{}}
    records={r['id'][5:]:r for r in ledger['jobs'].values() if r['id'].startswith('moge-') and r['server']==client.url}
    wanted={f['key']:f for c in index['clips'] for f in c['frames']}; pending=0
    CACHE.mkdir(parents=True,exist_ok=True)
    active=None
    for key,frame in wanted.items():
        if cached(key,frame['size']): continue
        record=records.get(key)
        if not record: raise queue.BatchError('No submission for '+key+'. Run with --submit to queue missing maps.')
        ident=record['prompt_id']; history=client.get('/history/'+ident)
        if ident not in history:
            if active is None:
                live=client.get('/queue')
                active={item[1] for group in ('queue_running','queue_pending') for item in live.get(group,[])}
            if ident in active: pending+=1; continue
            # It may have finished between reading history and reading the queue.
            history=client.get('/history/'+ident)
            if ident not in history:
                raise queue.BatchError(f'{key}: job is absent from both queue and history (cancelled/cleared/rejected). Inspect ComfyUI, then use --submit --force to deliberately retry missing maps.')
        result=history[ident]
        if result.get('status',{}).get('status_str')!='success':
            raise queue.BatchError(f'MoGe failed for {key}: {result.get("status")}. Check ComfyUI; rerun --submit --force after fixing the cause.')
        try: item=result['outputs']['5']['images'][0]
        except (KeyError,IndexError): raise queue.BatchError('MoGe returned no saved normal map: '+key)
        query=urllib.parse.urlencode({'filename':item['filename'],'subfolder':item.get('subfolder',''),'type':item.get('type','output')})
        with Image.open(io.BytesIO(client.request('/view?'+query))) as output:
            image=output.convert('RGB')
            if image.size!=tuple(frame['size']):
                raise queue.BatchError(f'{key}: normal dimensions {image.size} do not match source {frame["size"]}; refusing a misaligned cache entry')
            temp=CACHE/(key+'.tmp.png'); image.save(temp); temp.replace(CACHE/(key+'.png'))
    return len(wanted)-pending,pending


def run(args):
    # The caller holds the state lock across planning as well as submission, so
    # a second launcher cannot replace the frame index while results are collected.
    if args.collect:
        index=queue.read_json(args.state_dir/'normal-frame-index.json'); jobs=[]
    else:
        index,jobs=prepare(args.pack,args.batch,args.state_dir,args.shots,args.stride,args.allow_partial,args.allow_clipped,args.framing_review)
    count=len({f['key'] for c in index['clips'] for f in c['frames']})
    print(f'{len(index["clips"])} clips, {count} unique source frames; {len(jobs)} uncached normal jobs.')
    if not (args.submit or args.collect or args.check):
        print('DRY RUN. No uploads or queue changes. --submit queues; --collect retrieves finished maps.'); return 0
    client=queue.connect(args.url)
    if not args.collect:
        preflight(client,jobs or [{'api':graph('preflight-only','MadVillain_Normals/preflight-only.png')}])
    if args.check: print('CHECK ONLY. Server preflight passed; no uploads or queue changes.'); return 0
    if args.submit and jobs: queue.submit_jobs(client,jobs,args.state_dir,args.force)
    while True:
        ready,pending=collect(client,args.state_dir,index)
        print(f'MoGe normals cached: {ready}/{count}; pending: {pending}',flush=True)
        if not pending or not args.wait: break
        time.sleep(5)
    print('Frame/normal mapping: '+str(args.state_dir/'normal-frame-index.json'))
    return 0


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pack',type=Path,default=DEFAULT_PACK); p.add_argument('--batch',type=Path,default=DEFAULT_BATCH)
    p.add_argument('--state-dir',type=Path,default=ROOT/'.local/h3-swat-moge'); p.add_argument('--url')
    mode=p.add_mutually_exclusive_group(); mode.add_argument('--submit',action='store_true'); mode.add_argument('--collect',action='store_true'); mode.add_argument('--check',action='store_true')
    p.add_argument('--wait',action='store_true'); p.add_argument('--force',action='store_true')
    p.add_argument('--shots'); p.add_argument('--stride',type=int,default=1,help='Default 1 = every frame. Larger values deliberately sample fewer poses.')
    p.add_argument('--allow-partial',action='store_true'); p.add_argument('--allow-clipped',action='store_true')
    p.add_argument('--framing-review',type=Path,help='Source-hash-bound edge-effect exceptions; defaults to PACK/moge-framing-review.json')
    args=p.parse_args(argv)
    if args.stride<1: p.error('--stride must be positive')
    if args.wait and not (args.submit or args.collect): p.error('--wait requires --submit or --collect')
    try:
        with queue.submission_lock(args.state_dir):
            return run(args)
    except (queue.BatchError,OSError,ValueError,av.error.FFmpegError) as exc:
        print('ERROR:',exc); return 1


if __name__=='__main__': raise SystemExit(main())
