"""Validate exported graphs and invoke the installed Director without loading model weights."""
from pathlib import Path
from zipfile import ZipFile
import importlib.util
import json
import math
import shutil
import sys
import types

ROOT=Path(__file__).resolve().parents[2]
PACK=ROOT/'export/comfyui/scientist-modular'
COMFY=Path.home()/'AppData/Local/Comfy-Desktop/ComfyUI-Installs/ComfyUI/ComfyUI'
NODES=COMFY/'custom_nodes/ComfyUI-DaSiWa-Nodes/nodes'
sys.path.insert(0,str(COMFY))
pkg=types.ModuleType('sprite_h3_validation');pkg.__path__=[str(NODES)];sys.modules[pkg.__name__]=pkg
# Prevent the Director's optional Prompt Forge backstop from importing/starting any LLM.
forge=types.ModuleType(pkg.__name__+'.h3_forge');forge.unload_forge_models=lambda:None;sys.modules[forge.__name__]=forge
spec=importlib.util.spec_from_file_location(pkg.__name__+'.nodes_minimax_h3_director',NODES/'nodes_minimax_h3_director.py')
director_module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=director_module;spec.loader.exec_module(director_module)
prompt_helper=sys.modules[pkg.__name__+'.helper_minimax_h3_prompt_builder']


def validate_graph(graph,top=False):
    nodes={n['id']:n for n in graph['nodes']}
    edges=graph['links']
    links={link[0]:link for link in edges} if top else {l['id']:[l['id'],l['origin_id'],l['origin_slot'],l['target_id'],l['target_slot'],l['type']] for l in edges}
    assert len(nodes)==len(graph['nodes']) and len(links)==len(edges)
    for link_id,origin,output,target,input_slot,kind in links.values():
        if origin in nodes:
            assert link_id in nodes[origin]['outputs'][output].get('links',[]),(origin,output,link_id)
        if target in nodes:
            assert nodes[target]['inputs'][input_slot]['link']==link_id,(target,input_slot,link_id)
    for n in nodes.values():
        for inp in n.get('inputs',[]):
            if inp.get('link') is not None: assert inp['link'] in links
        for out in n.get('outputs',[]):
            for link in out.get('links') or []: assert link in links


def main():
    import folder_paths
    stage=ROOT/'.local/h3-sprite-validation/input'
    stage_refs=stage/'MadVillain_Modular_20261123';stage_refs.mkdir(parents=True,exist_ok=True)
    for p in (PACK/'references').iterdir():
        if p.suffix in ('.png','.mp4'): shutil.copyfile(p,stage_refs/p.name)
    folder_paths.set_input_directory(str(stage))
    count=0;native_count=0
    for row in json.loads((PACK/'animation-commissions.json').read_text(encoding='utf-8')):
        with ZipFile(PACK/'shot-workflows.zip') as z: workflow=json.loads(z.read(row['id']+'.json'))
        validate_graph(workflow,True)
        for sub in workflow['definitions']['subgraphs']: validate_graph(sub)
        n=next(n for n in workflow['nodes'] if n['type']=='MiniMaxH3Director')
        values=n['widgets_values_named'];assert n['widgets_values']==list(values.values())
        timeline=json.loads(values['timeline_data'])
        assert values['mode']=='REF2VA' and values['frame_rate']==24 and values['duration']==row['seconds']
        parsed=prompt_helper.parse_ref_prompt(values['prompt']);assert parsed is not None
        for item in timeline['items']:
            assert (stage/item['value']).is_file(),item['value']
        if row['id'] in ['01-near-shoulder','02-near-elbow','11-walk','18-near-recoil']:
            call={k:v for k,v in values.items() if k!='minimax_h3_director_ui'}
            call['ref2va_model']=object()
            result=director_module.MiniMaxH3Director().build_guide(**call)
            guide=result[0]
            assert guide['mode']=='REF2VA' and len(guide['ref_images'])==2
            assert len(guide['ref_videos'])==int(row['motion_reference'] is not None)
            assert guide['first_frame'] is None and guide['last_frame'] is None
            assert guide['resolved_prompt']==row['prompt']
            assert (guide['width'],guide['height'],guide['frame_rate'])==(768,768,24)
            native_count+=1
        count+=1
    # Verify the calibration guides keep their fixed roots and exact bone lengths.
    for study in ['shoulder','elbow','walk']:
        frames=json.loads((PACK/f'references/puppet-{study}-joints.json').read_text())
        assert len(frames)==120
        for frame in frames:
            j=frame['joints'];assert j['head']==[384,182] and j['pelvis']==[384,464]
            for side in ['near','far']:
                assert math.isclose(math.dist(j[side]['shoulder'],j[side]['elbow']),84,abs_tol=.001)
                assert math.isclose(math.dist(j[side]['elbow'],j[side]['wrist']),96,abs_tol=.001)
                assert math.isclose(math.dist(j[side+'_leg']['hip'],j[side+'_leg']['knee']),112,abs_tol=.001)
                assert math.isclose(math.dist(j[side+'_leg']['knee'],j[side+'_leg']['ankle']),112,abs_tol=.001)
    report={'workflow_graphs_validated':count,'installed_director_reference_load_tests':native_count,
        'motion_guides':3,'frames_per_guide':120,'fps':24,'model_inference_run':False,
        'note':'Graph/reference preparation verified; generation quality and GPU model execution remain untested.'}
    (PACK/'validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))


if __name__=='__main__':main()
