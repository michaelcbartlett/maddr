"""Regression: posing the legs must not overwrite the near-arm elbow angle."""
import math
import unittest
from build_h3_sprite_pack import mannequin,arm_pose


def bend(joints):
    a=joints['shoulder'];b=joints['elbow'];c=joints['wrist']
    upper=math.atan2(b[1]-a[1],b[0]-a[0])
    fore=math.atan2(c[1]-b[1],c[0]-b[0])
    return math.degrees(math.atan2(math.sin(fore-upper),math.cos(fore-upper)))


class MotionGuideTests(unittest.TestCase):
    def test_raise_bends_first_and_extends_before_apex(self):
        self.assertEqual(arm_pose(.75,'natural-raise'),(0,0))
        self.assertEqual(arm_pose(1.,'natural-raise'),(0,-90))
        for time in [1.05,1.2,1.35]:
            upper,elbow=arm_pose(time,'natural-raise')
            self.assertAlmostEqual(upper+elbow,-90)
        for time in [1.4,1.8,2.2,4.35,4.9]:
            self.assertEqual(arm_pose(time,'natural-raise'),(-90,0))
        for side in ['near','far']:
            for frame in range(120):
                _,joints=mannequin(frame/24,'natural-raise',side=='far',side,True)
                arm=joints[side]
                self.assertEqual(arm['shoulder'],(350 if side=='near' else 418,287))
                self.assertAlmostEqual(math.dist(arm['shoulder'],arm['elbow']),84)
                self.assertAlmostEqual(math.dist(arm['elbow'],arm['wrist']),96)
                self.assertAlmostEqual(bend(arm),arm_pose(frame/24,'natural-raise')[1])

    def test_elbow_study_transfers_requested_bend_after_leg_ik(self):
        for side in ['near','far']:
            for time in [0.,.5,1.25,2.0]:
                _,joints=mannequin(time,'elbow',True,side,True)
                self.assertAlmostEqual(bend(joints[side]),arm_pose(time,'elbow',True)[1])

    def test_straight_sweep_is_collinear_in_every_frame(self):
        for side in ['near','far']:
            for frame in range(120):
                _,joints=mannequin(frame/24,'straight-sweep',True,side,True)
                self.assertAlmostEqual(bend(joints[side]),0.)
                self.assertEqual(joints[side]['shoulder'],(350 if side=='near' else 418,287))

    def test_sweep_goes_down_right_then_up(self):
        for time,expected in [(0,90),(.5,90),(2.375,0),(4.25,-90),(4.99,-90)]:
            angle,elbow=arm_pose(time,'straight-sweep')
            self.assertAlmostEqual(angle,expected);self.assertEqual(elbow,0)


if __name__=='__main__':unittest.main()
