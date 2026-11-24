"""Queue the scientist animation shot list through ComfyUI's HTTP API.

Python standard library only. Defaults to a local dry run. --check checks the
running server without uploading or queueing; --submit uploads refs and queues.
"""
from pathlib import Path, PurePosixPath
import argparse
import contextlib
import copy
import hashlib
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT=Path(__file__).resolve().parents[2]
DEFAULT_PACK=ROOT/'export/comfyui/scientist-modular'
DEFAULT_STATE=ROOT/'.local/h3-animation-queue'
HEADINGS=('subject_definitions','summary','retention_analysis','detailed_description','overall_soundscape','non_diegetic_music')


class BatchError(Exception):pass


class HTTPBatchError(BatchError):
    def __init__(self,status,message):super().__init__(message);self.status=status


@contextlib.contextmanager
def submission_lock(state_dir):
    state_dir.mkdir(parents=True,exist_ok=True)
    with (state_dir/'submit.lock').open('a+b') as lock:
        lock.seek(0,2)
        if lock.tell()==0:lock.write(b'0');lock.flush()
        lock.seek(0)
        try:
            if os.name=='nt':
                import msvcrt
                msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
            else:
                import fcntl
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except OSError as exc:raise BatchError('Another batch launcher is submitting jobs. Let it finish first.') from exc
        try:yield
        finally:
            lock.seek(0)
            if os.name=='nt':msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
            else:fcntl.flock(lock,fcntl.LOCK_UN)


def read_json(path):
    try:return json.loads(Path(path).read_text(encoding='utf-8-sig'))
    except (OSError,ValueError) as exc:raise BatchError(f'Cannot read {path}: {exc}') from exc


def atomic_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.tmp')
    temp.write_text(json.dumps(value,indent=2,ensure_ascii=False),encoding='utf-8');temp.replace(path)


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()


def one_node(graph,class_type):
    nodes=[(k,n) for k,n in graph.items() if n.get('class_type')==class_type]
    if len(nodes)!=1:raise BatchError(f'Expected one {class_type}, found {len(nodes)}')
    return nodes[0]


def prompt_fields(prompt):
    matches=list(re.finditer(r'(?m)^('+'|'.join(HEADINGS)+r'):\s*\n',prompt))
    if [m[1] for m in matches]!=list(HEADINGS):raise BatchError('Prompt must have the six REF2VA sections exactly once, in order')
    return {m[1]:prompt[m.end():matches[i+1].start() if i+1<len(matches) else len(prompt)].strip() for i,m in enumerate(matches)}


def select_rows(rows,selectors=None,limit=None):
    ids=[r.get('id') for r in rows]
    if len(ids)!=len(set(ids)):raise BatchError('Manifest has duplicate shot IDs')
    if selectors:
        tokens=[s.strip() for s in selectors.split(',') if s.strip()];selected=[]
        for token in tokens:
            found=[r for r in rows if r['id']==token or r['id'].split('-')[0]==token.zfill(2)]
            if not found:raise BatchError(f'Unknown shot: {token}')
            selected.extend(found)
        chosen={r['id'] for r in selected};rows=[r for r in rows if r['id'] in chosen]
    return rows[:limit] if limit else rows


def asset_path(pack,name,override=None):
    if override:source=Path(override).expanduser().resolve()
    else:
        if not isinstance(name,str) or Path(name).name!=name or '\\' in name:raise BatchError(f'Invalid reference filename: {name!r}')
        source=(pack/'references'/name).resolve()
    if not source.is_file():raise BatchError(f'Missing reference: {source}')
    sha=hashlib.sha256(source.read_bytes()).hexdigest()
    return {'source':str(source),'sha256':sha,'server_path':f'MadVillain_Modular_Queue/{sha[:16]}_{source.name}'}


def validate_graph(graph):
    for key,node in graph.items():
        if 'class_type' not in node or not isinstance(node.get('inputs'),dict):raise BatchError(f'Invalid API node {key}')
        for name,value in node['inputs'].items():
            if isinstance(value,list) and len(value)==2 and isinstance(value[0],str) and isinstance(value[1],int):
                if value[0] not in graph:raise BatchError(f'{key}.{name} refers to missing node {value[0]}')


def patch_ui(ui,api,row):
    ui=copy.deepcopy(ui);ui['id']=str(uuid.uuid4());ui['revision']=0
    for cls in ('MiniMaxH3Director','DaSiWa_SeedControl','DaSiWa_EnhancedVideoCombine'):
        _,api_node=one_node(api,cls)
        n=next((n for n in ui['nodes'] if n['type']==cls),None)
        if n is None:raise BatchError(f'UI template is missing {cls}')
        named=n['widgets_values_named']
        for key,value in api_node['inputs'].items():
            if key in named and not isinstance(value,list):named[key]=value
        n['widgets_values']=[named[k] for k in named]
        if cls=='MiniMaxH3Director':n['title']=row['id']+' / queued REF2VA'
    settings=next(n for n in ui['nodes'] if n.get('title')=='Settings')
    steps=one_node(api,'BasicScheduler')[1]['inputs']['steps']
    settings['widgets_values'][list(settings['widgets_values_named']).index('steps')]=steps
    settings['widgets_values_named']['steps']=steps
    return ui


def prepare_jobs(pack,rows,template,ui,steps=None,seed=None,subject=None,item=None,motion_dir=None):
    seed_default=int(one_node(template,'DaSiWa_SeedControl')[1]['inputs']['seed_value'])
    jobs=[]
    for row in rows:
        if not re.fullmatch(r'\d{2,3}-[a-z0-9-]+',row['id']):raise BatchError(f'Invalid shot ID: {row["id"]}')
        seconds=float(row['seconds']);fps=float(row.get('fps',24))
        if not 0<seconds<=15 or fps!=24:raise BatchError(f'{row["id"]}: expected 24 fps and duration 0-15 seconds')
        fields=prompt_fields(row['prompt']);motion=row.get('motion_reference')
        if bool(motion)!=bool(re.search(r'<Video\s+1>',row['prompt'])):raise BatchError(f'{row["id"]}: prompt/video reference mismatch')
        assets={'subject':asset_path(pack,row.get('subject_reference','scientist.png'),subject),'item':asset_path(pack,row['item_reference'],item)}
        if motion:assets['motion']=asset_path(pack,motion,Path(motion_dir)/motion if motion_dir else None)
        api=copy.deepcopy(template)
        _,director=one_node(api,'MiniMaxH3Director');values=director['inputs']
        timeline=json.loads(values['timeline_data'])
        items=[]
        for slot,role in enumerate(('subject','item')):
            items.append({'id':'batch-'+role,'type':'image','value':assets[role]['server_path'],'enabled':True,
                'slot':slot,'start':slot,'order':slot,'duration':1,'forge_label':'character-1' if slot==0 else 'custom',
                'forge_role':'subject' if slot==0 else 'custom','prompt':fields['subject_definitions']})
        if motion:items.append({'id':'batch-motion','type':'video','value':assets['motion']['server_path'],'enabled':True,
            'slot':0,'start':0,'order':2,'duration':min(seconds,5),'trim_start':0,'trim_end':min(seconds,5),'media_mode':'video',
            'forge_role':'pose','prompt':'Motion and camera only; do not copy mannequin appearance.'})
        builder={'version':2,'mode':'REF2VA','duration':seconds,'prompt_mode':'simple','simple_prompt':row['prompt'],
            'ref':{**fields,'soundscape':fields['overall_soundscape'],'music':fields['non_diegetic_music']}}
        # Rebuild the complete timeline and builder together: no old prompt or video can survive.
        timeline={'version':1,'items':items,'prompt_blocks':[],'builder_state':builder,'resolved_prompt':row['prompt'],
            'resolution':{'aspect':'1:1','resolution':'custom','custom_mode':'fixed','custom_width':768,'custom_height':768,'input_scaling':'Auto'},'refmods':[]}
        values.update(mode='REF2VA',prompt=row['prompt'],width=768,height=768,duration=seconds,frame_rate=24,
            timeline_data=json.dumps(timeline,separators=(',',':')),builder_state=json.dumps(builder,separators=(',',':')))
        values.pop('external_prompt_overwrite',None)
        _,seed_node=one_node(api,'DaSiWa_SeedControl');effective_seed=seed_default if seed is None else seed
        seed_node['inputs'].update(seed_value=effective_seed,seed_control_state=json.dumps({'mode':'fixed','last_seed':str(effective_seed),'recent':[str(effective_seed)]}))
        if steps is not None:one_node(api,'BasicScheduler')[1]['inputs']['steps']=steps
        _,combine=one_node(api,'DaSiWa_EnhancedVideoCombine')
        combine['inputs'].update(frame_rate=24,filename_prefix='video/mad-villain-sprite/batch/'+row['id']+'/%date:hhmmss%',save_output=True,save_metadata=True)
        validate_graph(api)
        key=digest({'api':api,'assets':{k:a['sha256'] for k,a in assets.items()}})
        workflow=patch_ui(ui,api,row)
        jobs.append({'id':row['id'],'seconds':seconds,'seed':effective_seed,'steps':one_node(api,'BasicScheduler')[1]['inputs']['steps'],
            'assets':assets,'api':api,'workflow':workflow,'key':key})
    return jobs


class Client:
    def __init__(self,url,timeout=30):self.url=url.rstrip('/');self.timeout=timeout
    def request(self,path,method='GET',body=None,headers=None):
        req=urllib.request.Request(self.url+path,data=body,method=method,headers=headers or {})
        try:
            with urllib.request.urlopen(req,timeout=self.timeout) as response:return response.read()
        except urllib.error.HTTPError as exc:
            detail=exc.read().decode(errors='replace')[:5000]
            raise HTTPBatchError(exc.code,f'{method} {path}: HTTP {exc.code}: {detail}') from exc
        except (urllib.error.URLError,TimeoutError,OSError) as exc:raise BatchError(f'{method} {self.url+path}: {exc}') from exc
    def get(self,path):return json.loads(self.request(path))
    def post(self,path,value):return json.loads(self.request(path,'POST',json.dumps(value).encode(),{'Content-Type':'application/json'}))
    def exists(self,path):
        p=PurePosixPath(path);query=urllib.parse.urlencode({'filename':p.name,'subfolder':str(p.parent),'type':'input'})
        try:self.request('/view?'+query,'HEAD');return True
        except BatchError as exc:
            if 'HTTP 404:' in str(exc):return False
            raise
    def upload(self,asset):
        target=PurePosixPath(asset['server_path'])
        if self.exists(str(target)):return str(target)
        boundary='sprite_'+uuid.uuid4().hex;parts=[]
        for key,value in [('type','input'),('subfolder',str(target.parent)),('overwrite','false')]:
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
        mime=mimetypes.guess_type(asset['source'])[0] or 'application/octet-stream'
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{target.name}"\r\nContent-Type: {mime}\r\n\r\n'.encode())
        parts.extend([Path(asset['source']).read_bytes(),f'\r\n--{boundary}--\r\n'.encode()])
        result=json.loads(self.request('/upload/image','POST',b''.join(parts),{'Content-Type':'multipart/form-data; boundary='+boundary}))
        actual=str(PurePosixPath(result.get('subfolder',''))/result['name'])
        if actual!=str(target):raise BatchError(f'Upload renamed {target} to {actual}; stop to avoid wrong reference assignments')
        return actual


def connect(url=None):
    candidates=[url] if url else [os.getenv('COMFYUI_URL'),'http://127.0.0.1:8188','http://127.0.0.1:8000']
    failures=[]
    for address in dict.fromkeys(u for u in candidates if u):
        client=Client(address)
        try:client.get('/system_stats');return client
        except BatchError as exc:failures.append(str(exc))
    raise BatchError('Cannot connect to ComfyUI. Start it or pass --url http://host:port.\n'+'\n'.join(failures))


def check_server(client,jobs):
    info=client.get('/object_info');errors=[]
    loras=client.get('/models/loras') if any(n['class_type']=='DaSiWa_LTX2LoraLoader' for n in jobs[0]['api'].values()) else []
    for job in jobs:
        for node_id,node in job['api'].items():
            cls=node['class_type'];schema=info.get(cls)
            if schema is None:errors.append(f'Missing server node: {cls}');continue
            inputs=node['inputs'];input_schema=schema.get('input',{})
            for name,spec in input_schema.get('required',{}).items():
                if name not in inputs:errors.append(f'{job["id"]}: {cls}.{name} is required')
            for name,value in inputs.items():
                if isinstance(value,list):continue
                spec=input_schema.get('required',{}).get(name,input_schema.get('optional',{}).get(name))
                if spec and isinstance(spec[0],list) and value not in spec[0]:errors.append(f'{cls}.{name}: {value!r} is unavailable on this server')
            if cls=='DaSiWa_LTX2LoraLoader':
                # Hidden JSON stacks need an explicit inventory check too.
                for row in json.loads(inputs['stack_data']):
                    if row.get('on') and row.get('lora') not in ('None','',None) and row['lora'] not in loras:errors.append('Missing LoRA: '+row['lora'])
    if errors:raise BatchError('Server preflight failed:\n'+'\n'.join(dict.fromkeys(errors)))
    return client.get('/queue')


def submit_jobs(client,jobs,state_dir,force=False):
    ledger_path=state_dir/'queue-log.json'
    ledger=read_json(ledger_path) if ledger_path.exists() else {'version':1,'jobs':{}}
    pending=[]
    for job in jobs:
        ledger_key=digest({'server':client.url,'job':job['key']})
        old=ledger['jobs'].get(ledger_key)
        if old and not force:
            if old['status']=='submitted':print('SKIP already submitted:',job['id']);continue
            prompt_id=old['prompt_id'];queue=client.get('/queue');history=client.get('/history/'+prompt_id)
            if history or any(item[1]==prompt_id for group in ['queue_running','queue_pending'] for item in queue.get(group,[])):
                old['status']='submitted';atomic_json(ledger_path,ledger);print('SKIP recovered accepted job:',job['id']);continue
            if old['status']=='submitting':raise BatchError(f'{job["id"]}: previous submission has an uncertain result. Check ComfyUI; use --force --shots {job["id"]} to deliberately resubmit.')
        pending.append((ledger_key,job))
    # Upload every needed reference before submitting the first generation.
    assets={a['server_path']:a for _,job in pending for a in job['assets'].values()}
    for asset in assets.values():client.upload(asset)
    accepted=0
    for ledger_key,job in pending:
        prompt_id=str(uuid.uuid4())
        record={'id':job['id'],'server':client.url,'prompt_id':prompt_id,'status':'submitting','job_key':job['key']}
        ledger['jobs'][ledger_key]=record;atomic_json(ledger_path,ledger)
        payload={'prompt_id':prompt_id,'client_id':'mad-villain-sprite-batch','prompt':job['api'],
            'extra_data':{'sprite_batch':{'shot':job['id'],'job_key':job['key']},'extra_pnginfo':{'workflow':job['workflow']}}}
        atomic_json(state_dir/'requests'/(job['id']+'-'+prompt_id+'.json'),payload)
        try:
            response=client.post('/prompt',payload)
            if not response.get('prompt_id'):raise BatchError('ComfyUI returned no prompt ID: '+json.dumps(response))
        except HTTPBatchError as exc:
            record.update(status='rejected',error=str(exc));atomic_json(ledger_path,ledger);raise
        except BatchError:
            # Never retry a POST automatically: a timeout may happen after acceptance.
            atomic_json(ledger_path,ledger);raise
        record.update(status='submitted',prompt_id=response['prompt_id'],queue_number=response.get('number'))
        atomic_json(ledger_path,ledger);accepted+=1
        print(f'QUEUED {job["id"]}: {response["prompt_id"]}',flush=True)
        if response.get('node_errors'):raise BatchError('ComfyUI accepted this job with node errors; remaining submissions stopped: '+json.dumps(response['node_errors']))
    return accepted


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pack',type=Path,default=DEFAULT_PACK)
    mode=p.add_mutually_exclusive_group();mode.add_argument('--submit',action='store_true');mode.add_argument('--check',action='store_true')
    p.add_argument('--url',help='ComfyUI URL; otherwise COMFYUI_URL, port 8188, then 8000')
    p.add_argument('--shots',help='Comma-separated numbers or complete IDs, e.g. 01,02,07,11')
    p.add_argument('--limit',type=int);p.add_argument('--steps',type=int);p.add_argument('--seed',type=int)
    p.add_argument('--subject',type=Path);p.add_argument('--item',type=Path);p.add_argument('--motion-dir',type=Path)
    p.add_argument('--state-dir',type=Path,default=DEFAULT_STATE);p.add_argument('--force',action='store_true',help='Deliberately requeue jobs already in the log')
    args=p.parse_args(argv)
    if args.limit is not None and args.limit<1:p.error('--limit must be positive')
    if args.steps is not None and args.steps<1:p.error('--steps must be positive')
    if args.seed is not None and not 0<=args.seed<2**64:p.error('--seed must be an unsigned 64-bit integer')
    try:
        rows=select_rows(read_json(args.pack/'animation-queue-manifest.json'),args.shots,args.limit)
        jobs=prepare_jobs(args.pack,rows,read_json(args.pack/'queue-api-template.json'),read_json(args.pack/'queue-workflow-template.json'),
            args.steps,args.seed,args.subject,args.item,args.motion_dir)
        if not jobs:raise BatchError('No jobs selected')
        for job in jobs:
            motion=Path(job['assets']['motion']['source']).name if 'motion' in job['assets'] else 'none (prompt-driven)'
            print(f'{job["id"]}: {job["seconds"]}s, 24fps, {job["steps"]} steps; item={Path(job["assets"]["item"]["source"]).name}; motion={motion}')
        atomic_json(args.state_dir/'last-plan.json',[{k:v for k,v in j.items() if k not in ('api','workflow')} for j in jobs])
        if not args.submit and not args.check:
            print(f'DRY RUN: {len(jobs)} jobs, {sum(j["seconds"] for j in jobs):g} requested seconds. No uploads or queue changes. Use --submit to queue.');return 0
        client=connect(args.url);queue=check_server(client,jobs)
        print(f'Connected to {client.url}; server schema preflight passed. Existing pending jobs: {len(queue.get("queue_pending",[]))}')
        if args.check:print('CHECK ONLY: no uploads or generation submissions.');return 0
        with submission_lock(args.state_dir):count=submit_jobs(client,jobs,args.state_dir,args.force)
        print(f'Submitted {count} jobs. ComfyUI will process its queue; the launcher does not need to remain open.\nLog: {args.state_dir/"queue-log.json"}')
        return 0
    except BatchError as exc:print('ERROR:',exc,file=sys.stderr);return 1


if __name__=='__main__':raise SystemExit(main())
