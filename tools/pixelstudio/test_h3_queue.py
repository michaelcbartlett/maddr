"""Batch contracts and interrupted-submission recovery; never contacts a real ComfyUI server."""
from pathlib import Path
import copy
import contextlib
import io
import json
import tempfile
import unittest
from unittest.mock import patch
import queue_h3_animations as q


class FakeServer:
    url='http://test-comfy'
    def __init__(self):self.uploads=[];self.posts=[];self.accepted={};self.fail_after_accept=False;self.schema={};self.loras=[]
    def upload(self,asset):self.uploads.append(asset['server_path']);return asset['server_path']
    def get(self,path):
        if path=='/queue':return {'queue_running':[],'queue_pending':[[i,k] for i,k in enumerate(self.accepted)]}
        if path.startswith('/history/'):return {}
        if path=='/object_info':return self.schema
        if path=='/models/loras':return self.loras
        raise AssertionError(path)
    def post(self,path,payload):
        assert path=='/prompt';self.posts.append(copy.deepcopy(payload));self.accepted[payload['prompt_id']]=payload
        if self.fail_after_accept:raise q.BatchError('connection lost after acceptance')
        return {'prompt_id':payload['prompt_id'],'number':len(self.posts),'node_errors':{}}


class QueueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack=q.DEFAULT_PACK
        cls.rows=q.read_json(cls.pack/'animation-queue-manifest.json')
        cls.template=q.read_json(cls.pack/'queue-api-template.json')
        cls.ui=q.read_json(cls.pack/'queue-workflow-template.json')
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.state=Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
    def jobs(self,rows=None,**kw):return q.prepare_jobs(self.pack,self.rows[:2] if rows is None else rows,self.template,self.ui,**kw)
    def test_all_shots_and_corrected_motion_refs(self):
        jobs=self.jobs(self.rows);self.assertEqual(len(jobs),36)
        self.assertEqual(sum(j['seconds'] for j in jobs),182)
        expected={'01-near-shoulder':'puppet-shoulder-behind-head-v2.mp4','02-near-elbow':'puppet-elbow-behind-head-v2.mp4',
            '06-far-shoulder':'puppet-far-shoulder-behind-head-v2.mp4','07-far-elbow':'puppet-far-elbow-behind-head-v2.mp4','11-walk':'puppet-walk.mp4'}
        for job in jobs:
            refs=job['assets'];self.assertEqual('motion' in refs,job['id'] in expected)
            if 'motion' in refs:self.assertEqual(Path(refs['motion']['source']).name,expected[job['id']])
            d=q.one_node(job['api'],'MiniMaxH3Director')[1]['inputs'];timeline=json.loads(d['timeline_data'])
            builder=json.loads(d['builder_state'])
            self.assertEqual(d['prompt'],timeline['resolved_prompt']);self.assertEqual(d['prompt'],builder['simple_prompt'])
            self.assertEqual(d['duration'],job['seconds']);self.assertEqual(d['frame_rate'],24)
            self.assertEqual(len(timeline['items']),3 if 'motion' in refs else 2)
            n=next(n for n in job['workflow']['nodes'] if n['type']=='MiniMaxH3Director')
            self.assertEqual(n['widgets_values_named']['prompt'],d['prompt'])
            self.assertEqual(json.loads(n['widgets_values_named']['timeline_data']),timeline)
            self.assertEqual(job['steps'],16)
    def test_repeat_plan_is_stable_but_changes_get_new_keys(self):
        a=self.jobs();b=self.jobs();self.assertEqual([j['key'] for j in a],[j['key'] for j in b])
        self.assertNotEqual(a[0]['key'],self.jobs(seed=55)[0]['key'])
        self.assertNotEqual(a[0]['key'],self.jobs(steps=8)[0]['key'])
    def test_selection_and_missing_reference_fail_clearly(self):
        self.assertEqual([r['id'][:2] for r in q.select_rows(self.rows,'07,01')],['01','07'])
        with self.assertRaises(q.BatchError):q.select_rows(self.rows,'99')
        rows=copy.deepcopy(self.rows[:1]);rows[0]['motion_reference']='missing.mp4'
        with self.assertRaisesRegex(q.BatchError,'Missing reference'):self.jobs(rows)
    def test_unrelated_video_never_leaks_from_template(self):
        job=self.jobs(self.rows[17:18])[0]
        timeline=json.loads(q.one_node(job['api'],'MiniMaxH3Director')[1]['inputs']['timeline_data'])
        self.assertFalse(any(i['type']=='video' for i in timeline['items']))
    def test_prompt_video_mismatch_and_path_escape_rejected(self):
        rows=copy.deepcopy(self.rows[:1]);rows[0]['motion_reference']=None
        with self.assertRaisesRegex(q.BatchError,'mismatch'):self.jobs(rows)
        with self.assertRaises(q.BatchError):q.asset_path(self.pack,'../secret.png')
    def test_submit_and_rerun_deduplicates(self):
        client=FakeServer();jobs=self.jobs()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(q.submit_jobs(client,jobs,self.state),2)
            self.assertEqual(q.submit_jobs(client,jobs,self.state),0)
        self.assertEqual(len(client.posts),2)
        ledger=q.read_json(self.state/'queue-log.json');self.assertTrue(all(j['status']=='submitted' for j in ledger['jobs'].values()))
        for payload in client.posts:
            self.assertEqual(payload['prompt_id'],str(__import__('uuid').UUID(payload['prompt_id'])))
    def test_lost_reply_recovers_without_duplicate(self):
        client=FakeServer();client.fail_after_accept=True;jobs=self.jobs(self.rows[:1])
        with self.assertRaises(q.BatchError):q.submit_jobs(client,jobs,self.state)
        client.fail_after_accept=False
        with contextlib.redirect_stdout(io.StringIO()):self.assertEqual(q.submit_jobs(client,jobs,self.state),0)
        self.assertEqual(len(client.posts),1)
    def test_unknown_submission_never_retries_automatically(self):
        client=FakeServer();client.fail_after_accept=True;jobs=self.jobs(self.rows[:1])
        with self.assertRaises(q.BatchError):q.submit_jobs(client,jobs,self.state)
        client.accepted.clear()
        with self.assertRaisesRegex(q.BatchError,'uncertain'):q.submit_jobs(client,jobs,self.state)
        self.assertEqual(len(client.posts),1)
    def test_force_deliberately_submits_again(self):
        client=FakeServer();jobs=self.jobs(self.rows[:1])
        with contextlib.redirect_stdout(io.StringIO()):q.submit_jobs(client,jobs,self.state);q.submit_jobs(client,jobs,self.state,force=True)
        self.assertEqual(len(client.posts),2)
    def test_http_rejection_is_logged_as_rejected(self):
        client=FakeServer();client.post=lambda *a:(_ for _ in ()).throw(q.HTTPBatchError(400,'node rejected'))
        with self.assertRaises(q.HTTPBatchError):q.submit_jobs(client,self.jobs(self.rows[:1]),self.state)
        self.assertEqual(next(iter(q.read_json(self.state/'queue-log.json')['jobs'].values()))['status'],'rejected')
    def test_server_schema_missing_nodes_stops_before_upload(self):
        client=FakeServer()
        with self.assertRaisesRegex(q.BatchError,'Missing server node'):q.check_server(client,self.jobs())
        self.assertEqual(client.uploads,[]);self.assertEqual(client.posts,[])
    def test_dry_run_does_not_connect(self):
        with patch.object(q,'connect',side_effect=AssertionError('must stay offline')),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(q.main(['--limit','1','--state-dir',str(self.state)]),0)
    def test_check_does_not_upload_or_queue(self):
        client=FakeServer()
        with patch.object(q,'connect',return_value=client),patch.object(q,'check_server',return_value={'queue_pending':[]}),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(q.main(['--check','--limit','1','--state-dir',str(self.state)]),0)
        self.assertEqual(client.uploads,[]);self.assertEqual(client.posts,[])
    def test_shot_can_select_its_matched_subject_pose(self):
        row=copy.deepcopy(self.rows[0]);row['subject_reference']='proxy-grip.png'
        job=self.jobs([row])[0]
        self.assertEqual(Path(job['assets']['subject']['source']).name,'proxy-grip.png')
        timeline=json.loads(q.one_node(job['api'],'MiniMaxH3Director')[1]['inputs']['timeline_data'])
        self.assertEqual(timeline['items'][0]['value'],job['assets']['subject']['server_path'])
    def test_submission_lock_rejects_second_launcher(self):
        with q.submission_lock(self.state):
            with self.assertRaises(q.BatchError):
                with q.submission_lock(self.state):pass


if __name__=='__main__':unittest.main()
