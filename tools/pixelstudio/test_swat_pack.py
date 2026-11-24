"""Shield phase/handedness contracts and frame-to-MoGe alignment; no real submissions."""
from pathlib import Path
import contextlib
import hashlib
import io
import tempfile
import unittest
from unittest.mock import patch
import av
import numpy as np
from PIL import Image, ImageDraw
import build_h3_swat_shield as swat
import queue_h3_animations as q
import queue_h3_moge as moge


class ShieldPackTests(unittest.TestCase):
    def test_pack_uses_matching_item_and_motion_references(self):
        rows=q.read_json(swat.OUT/'animation-queue-manifest.json')
        jobs=q.prepare_jobs(swat.OUT,rows,q.read_json(swat.OUT/'queue-api-template.json'),q.read_json(swat.OUT/'queue-workflow-template.json'),steps=16)
        self.assertEqual(len(jobs),28)
        self.assertEqual(len({j['id'] for j in jobs}),28)
        grenade=next(j for j in jobs if 'grenade' in j['id'])
        self.assertEqual(Path(grenade['assets']['item']['source']).name,'grenade-proxy.png')
        self.assertEqual(Path(grenade['assets']['motion']['source']).name,'guide-grenade.mp4')
        for row in rows:
            self.assertIn('near arm, originating on screen-left',row['prompt'])
            self.assertIn('far arm, originating on screen-right',row['prompt'])
            if '-death-' in row['id']: self.assertEqual(row['subject_reference'],'swat-small.png')

    def test_shield_is_down_during_both_baton_swings_and_back_up_afterward(self):
        for kind,wind,hit,end in [('strike',1.03,1.22,1.9),('combo',.94,1.07,2.1)]:
            with self.subTest(kind=kind):
                self.assertEqual(swat.guide_pose(kind,wind)['shield'],swat.LOW['shield'])
                self.assertEqual(swat.guide_pose(kind,hit)['shield'],swat.LOW['shield'])
                self.assertEqual(swat.guide_pose(kind,end)['shield'],swat.REST['shield'])
        for i in range(120): self.assertEqual(swat.guide_pose('walk',i/24)['shield'],swat.REST['shield'])

    def test_guides_have_no_clipped_props_and_grenade_releases(self):
        for kind in ['walk','strike','combo','raise','lower','grenade']:
            for i in range(120):
                image=swat.draw_guide(swat.guide_pose(kind,i/24))
                self.assertFalse(moge.cut_edges(image),(kind,i))
        self.assertEqual(swat.guide_pose('grenade',1.45)['grenade'],1)
        self.assertEqual(swat.guide_pose('grenade',1.6)['grenade'],2)


class NormalPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        self.pack=self.root/'pack'; self.pack.mkdir(); self.batch=self.root/'batch'; self.state=self.root/'state'
        self.cache=self.root/'cache'
        self.cache_patch=patch.object(moge,'CACHE',self.cache); self.cache_patch.start()
        q.atomic_json(self.pack/'animation-queue-manifest.json',[{'id':'171-swat-guard-idle','seconds':5,'fps':24}])
        folder=self.batch/'171-swat-guard-idle'; folder.mkdir(parents=True)
        frame=Image.new('RGB',(32,32),swat.BG); ImageDraw.Draw(frame).rectangle((9,8,23,26),fill='#b7b6c8')
        with av.open(str(folder/'test_audio.mp4'),'w') as output:
            stream=output.add_stream('libx264',rate=24); stream.width=stream.height=32; stream.pix_fmt='yuv420p'
            for i in range(124):
                for packet in stream.encode(av.VideoFrame.from_image(frame)): output.mux(packet)
            for packet in stream.encode(): output.mux(packet)

    def tearDown(self): self.cache_patch.stop(); self.temp.cleanup()

    def prepare(self,**kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return moge.prepare(self.pack,self.batch,self.state,**kwargs)

    def test_actual_frame_indices_hashes_and_exact_reuse(self):
        index,jobs=self.prepare(stride=3)
        clip=index['clips'][0]
        self.assertEqual(clip['decoded_frames'],124)
        self.assertEqual([f['frame'] for f in clip['frames']],list(range(0,124,3)))
        self.assertLess(len(jobs),len(clip['frames']))  # identical frames deduplicate
        for job in jobs:
            image=Image.open(job['assets']['frame']['source']).convert('RGB')
            key=hashlib.sha256(np.asarray(image).tobytes()).hexdigest()[:24]
            self.assertEqual(job['id'],'moge-'+key)
            self.assertEqual(job['api']['4']['inputs']['output'],'normal_opengl')
            self.assertNotIn('front',job)
            self.cache.mkdir(exist_ok=True); Image.new('RGB',image.size,(128,128,255)).save(self.cache/(key+'.png'))
        self.assertFalse(self.prepare(stride=3)[1])

    def test_missing_clip_stops_before_index_or_submission(self):
        q.atomic_json(self.pack/'animation-queue-manifest.json',[{'id':'172-swat-guard-walk','seconds':5,'fps':24}])
        with self.assertRaisesRegex(q.BatchError,'Finish the animation batch first'): self.prepare()
        self.assertFalse((self.state/'normal-frame-index.json').exists())

    def test_reviewed_effect_edges_are_bound_to_video_and_exact_frames(self):
        source=next((self.batch/'171-swat-guard-idle').glob('*.mp4'))
        review={'version':1,'clips':{'171-swat-guard-idle':{
            'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'allowed_frames':[0],'reason':'Reviewed projectile at the edge; character is inside.'}}}
        with patch.object(moge,'cut_edges',return_value={'right':18}):
            with self.assertRaisesRegex(q.BatchError,'unreviewed sampled frames'): self.prepare(stride=124)
            q.atomic_json(self.pack/'moge-framing-review.json',review)
            index,jobs=self.prepare(stride=124)
            self.assertEqual(index['clips'][0]['clipped_frames'],[0])
            self.assertTrue(jobs)
            with self.assertRaisesRegex(q.BatchError,'unreviewed sampled frames'): self.prepare(stride=62)
            review['clips']['171-swat-guard-idle']['source_sha256']='wrong-video'
            q.atomic_json(self.pack/'moge-framing-review.json',review)
            with self.assertRaisesRegex(q.BatchError,'different video'): self.prepare(stride=124)

    def test_dry_run_never_connects_and_cancelled_job_does_not_wait_forever(self):
        with patch.object(q,'connect',side_effect=AssertionError('dry run contacted server')),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(moge.main(['--pack',str(self.pack),'--batch',str(self.batch),'--state-dir',str(self.state),'--stride','124']),0)
        index=q.read_json(self.state/'normal-frame-index.json'); key=index['clips'][0]['frames'][0]['key']
        q.atomic_json(self.state/'queue-log.json',{'jobs':{'one':{'id':'moge-'+key,'prompt_id':'cancelled','server':'http://fake'}}})
        class Client:
            url='http://fake'
            def get(self,path): return {'queue_running':[],'queue_pending':[]} if path=='/queue' else {}
        with self.assertRaisesRegex(q.BatchError,'absent from both queue and history'): moge.collect(Client(),self.state,index)

    def test_collect_rejects_misaligned_normals_without_poisoning_cache(self):
        index,jobs=self.prepare(stride=124)
        key=index['clips'][0]['frames'][0]['key']
        q.atomic_json(self.state/'queue-log.json',{'jobs':{'one':{'id':'moge-'+key,'prompt_id':'pid','server':'http://fake'}}})
        class Client:
            url='http://fake'
            def __init__(self,size): self.size=size
            def get(self,path): return {'pid':{'status':{'status_str':'success'},'outputs':{'5':{'images':[{'filename':'n.png'}]}}}}
            def request(self,path):
                buf=io.BytesIO(); Image.new('RGB',self.size,(128,128,255)).save(buf,format='PNG'); return buf.getvalue()
        with self.assertRaisesRegex(q.BatchError,'do not match source'): moge.collect(Client((16,16)),self.state,index)
        self.assertFalse((self.cache/(key+'.png')).exists())
        self.assertEqual(moge.collect(Client((32,32)),self.state,index),(1,0))
        self.assertTrue(moge.cached(key,(32,32)))


if __name__=='__main__': unittest.main()
