"""Canine anatomy, gait contacts and exact H3 guide assignment. No live generation."""
import json
import math
import unittest
from pathlib import Path
import av
import numpy as np
import quadruped_motion as q
import build_h3_attack_dog as dog
import queue_h3_animations as queue
from check_h3_framing import cut_edges


class QuadrupedTests(unittest.TestCase):
    def test_constant_bones_attached_sockets_and_reachable_ground_contacts(self):
        half=math.hypot(180.,22.)/2
        for mode in q.MODES:
            for study in q.STUDIES:
                for i in range(120):
                    p=q.pose(i/24,study,mode);j=p['joints']
                    self.assertAlmostEqual(math.dist(j['pelvis'],j['spine']),half,places=6)
                    self.assertAlmostEqual(math.dist(j['spine'],j['chest']),half,places=6)
                    self.assertAlmostEqual(math.dist(j['neck_base'],j['skull']),91,places=6)
                    for leg,contact in p['contacts'].items():
                        front='front' in leg;far=leg.startswith('far');lengths=(95,99) if front else (90,91)
                        self.assertAlmostEqual(math.dist(j[leg+'_root'],j[leg+'_mid']),lengths[0],places=5)
                        self.assertAlmostEqual(math.dist(j[leg+'_mid'],j[leg+'_distal']),lengths[1],places=5)
                        self.assertLess(p['ik_error'][leg],1e-4)
                        socket=np.array(j['chest'] if front else j['pelvis'])
                        self.assertAlmostEqual(np.linalg.norm(np.array(j[leg+'_root'])-socket),math.hypot(19,8) if far else 0,places=5)
                        self.assertLessEqual(j[leg+'_paw'][1],q.GROUND-(9 if far else 0)+1e-6)
                        if contact:self.assertAlmostEqual(j[leg+'_paw'][1],q.GROUND-(9 if far else 0),places=5)

    def test_fore_elbows_and_hind_stifles_have_opposite_bends(self):
        j=q.pose(0,'idle')['joints']
        for leg in ('near_front','far_front','near_hind','far_hind'):
            root=np.array(j[leg+'_root']);a=np.array(j[leg+'_distal'])-root;b=np.array(j[leg+'_mid'])-root
            cross=a[0]*b[1]-a[1]*b[0]
            self.assertGreater(cross*(1 if 'front' in leg else -1),0)

    def test_trot_uses_diagonal_pairs_and_gallop_has_flight(self):
        flight=False;single_foot_walk=False
        for i in range(120):
            c=q.pose(i/24,'trot')['contacts']
            self.assertEqual(c['near_front'],c['far_hind'])
            self.assertEqual(c['far_front'],c['near_hind'])
            if not any(q.pose(i/24,'run')['contacts'].values()):flight=True
            if sum(q.pose(i/24,'walk')['contacts'].values())==3:single_foot_walk=True
        self.assertTrue(flight);self.assertTrue(single_foot_walk)

    def test_loops_freeze_death_holds_and_pounce_anticipation(self):
        for mode in q.MODES:
            for study in ('idle','walk','trot','run','retreat','stunned'):
                a=q.pose(0,study,mode)['joints'];b=q.pose(5,study,mode)['joints']
                for name in a:self.assertLess(math.dist(a[name],b[name]),1e-6,(mode,study,name))
            for study,start in [('frozen',1.4),('collapse-front',2.),('collapse-side',2.)]:
                self.assertEqual(q.pose(start,study,mode)['joints'],q.pose(4.9,study,mode)['joints'])
            rest=q.pose(.4,'pounce',mode);crouch=q.pose(.75,'pounce',mode);air=q.pose(1.15,'pounce',mode)
            self.assertGreater(crouch['joints']['pelvis'][1],rest['joints']['pelvis'][1])
            self.assertLess(air['joints']['pelvis'][1],rest['joints']['pelvis'][1])
            self.assertFalse(any(air['contacts'].values()))
            landing=q.pose(1.7,'pounce',mode)['contacts']
            self.assertTrue(landing['near_front']);self.assertFalse(landing['near_hind'])

    def test_robot_spine_is_rigid_and_organic_gallop_flexes(self):
        bends=[]
        for mode in q.MODES:
            for i in range(120):
                j=q.pose(i/24,'run',mode)['joints']
                span=math.dist(j['pelvis'],j['chest'])
                if mode=='mechanical':self.assertAlmostEqual(span,math.hypot(180.,22.),places=5)
                else:bends.append(span)
        self.assertGreater(max(bends)-min(bends),1)

    def test_representative_frames_have_margin_and_contact_soles(self):
        for mode in q.MODES:
            for study in q.STUDIES:
                for t in (0,.75,1.15,1.7,3.4,4.9):
                    frame=q.render(q.pose(t,study,mode))
                    self.assertFalse(cut_edges(frame),(mode,study,t))
                    self.assertTrue(np.all(np.asarray(frame)[681:]==np.array(q.BG)),(mode,study,t,'below ground'))
        frame=np.asarray(q.render(q.pose(0,'idle')))
        self.assertTrue(np.all(frame[681:]==np.array(q.BG)))

    def test_all_guides_are_24fps_with_120_matching_pose_records(self):
        rows=json.loads((q.OUT/'motion-catalog.json').read_text())
        self.assertEqual(len(rows),36)
        for row in rows:
            data=json.loads((q.OUT/row['joints']).read_text());self.assertEqual(len(data['frames']),120)
            with av.open(str(q.OUT/row['video'])) as video:
                stream=video.streams.video[0]
                self.assertEqual(float(stream.average_rate),24)
                self.assertEqual(sum(1 for _ in video.decode(video=0)),120)
            self.assertEqual(data['small'],row['small'])
            self.assertEqual(data['frames'][24]['joints']['chest'],list(q.pose(1.,row['study'],row['mode'])['joints']['chest']))

    def test_dog_batch_uses_organic_guides_and_smaller_death_layout(self):
        rows=queue.read_json(dog.OUT/'animation-queue-manifest.json')
        jobs=queue.prepare_jobs(dog.OUT,rows,queue.read_json(dog.OUT/'queue-api-template.json'),queue.read_json(dog.OUT/'queue-workflow-template.json'),steps=16)
        self.assertEqual(len(jobs),22)
        for row in rows:
            self.assertEqual(row['fps'],24);self.assertEqual(row['seconds'],5)
            if '-death-' in row['id']:self.assertEqual(row['subject_reference'],'dog-small.png')
            if row['motion_reference']:
                self.assertEqual((dog.OUT/'references'/row['motion_reference']).read_bytes(),(q.OUT/'organic'/row['motion_reference']).read_bytes())
            self.assertIn('Four legs only',row['prompt'])
        self.assertIsNone(next(r for r in rows if 'death-ash' in r['id'])['motion_reference'])


if __name__=='__main__':unittest.main()
