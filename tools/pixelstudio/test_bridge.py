"""Run with: python -m unittest discover -s tools/pixelstudio -p test_bridge.py"""
import hashlib
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from bridge import BridgeServer, REPO, SOURCE, current_edited_character, export_character, find_godot, instrument
from prepare_editor import patch_editor


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = find_godot()
        cls.project = REPO / 'godot'
        cls.editor = REPO / '.local' / 'pixelstudio-editor'
        cls.server = BridgeServer(('127.0.0.1', 0), cls.project, cls.editor, cls.godot)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_all_supported_clips_preserve_source_and_have_complete_rig(self):
        source = self.project / SOURCE
        before = hashlib.sha256(source.read_bytes()).digest()
        with tempfile.TemporaryDirectory(dir=REPO / '.local') as temp:
            for animation, count in [('walk', 8), ('idle', 4), ('attack', 3)]:
                with self.subTest(animation=animation):
                    data = export_character(self.project, self.godot, animation, Path(temp) / f'{animation}.pixelstudio')
                    self.assertEqual(len(data['frames']), count)
                    self.assertEqual(len(data['layers']), 18)
                    layers = {layer['id']: layer for layer in data['layers']}
                    for key, parent in [('baton', 'near-hand'), ('near-hand', 'near-forearm'), ('near-forearm', 'near-upper-arm'), ('near-upper-arm', 'torso')]:
                        self.assertEqual(layers['layer-' + key]['parent'], 'layer-' + parent)
                    for frame in data['frames']:
                        self.assertEqual(len(frame['cels']), 18)
                        self.assertIn('attachmentAngle', frame['poses']['layer-baton'])
                        self.assertEqual(frame['maps'], {})
        # The Godot exporter additionally compares every reassembled RGBA frame with the
        # unmodified painter and fails on any difference, including silhouette outlines.
        self.assertEqual(hashlib.sha256(source.read_bytes()).digest(), before)

    def test_rejects_unadapted_painter(self):
        with self.assertRaises(ValueError):
            instrument('extends RefCounted\n')

    def test_import_opens_the_current_edited_game_clips(self):
        for animation, count in [('idle', 4), ('walk', 8), ('attack', 3)]:
            data, path = current_edited_character(self.project, animation)
            self.assertIn('improved', path.parent.name)
            self.assertEqual(len(data['frames']), count)
            self.assertEqual(len(data['layers']), 18)
            self.assertTrue(all('normal' in frame['maps'] for frame in data['frames']))
            self.assertEqual(data['godotSource']['lighting'], 'original-physical-relief-transformed-to-edited-pose')

    def test_loopback_host_origin_and_token_boundaries(self):
        with urlopen(self.url + '/api/godot/catalog') as response:
            catalog = json.load(response)
        self.assertEqual(catalog['bridge'], 'pixelstudio-godot-v1')
        for headers, route, body in [
            ({'Host': 'attacker.example'}, '/api/godot/catalog', None),
            ({'Origin': 'https://attacker.example'}, '/api/godot/catalog', None),
            ({'Content-Type': 'application/json'}, '/api/godot/open', b'{}'),
        ]:
            with self.subTest(headers=headers):
                with self.assertRaises(HTTPError) as error:
                    urlopen(Request(self.url + route, data=body, headers=headers))
                self.assertEqual(error.exception.code, 403)
                error.exception.close()
        # file:// editors can connect, but an arbitrary remote page cannot.
        with urlopen(Request(self.url + '/api/godot/catalog', headers={'Origin': 'null'})) as response:
            self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'null')
        headers = {'Content-Type': 'application/json', 'X-PixelStudio-Token': catalog['token']}
        for payload in [{'script': '../../other.gd'}, {'source': 'extends Node'}, {'animation': 'unknown'}]:
            with self.subTest(payload=payload):
                with self.assertRaises(HTTPError) as error:
                    urlopen(Request(self.url + '/api/godot/open', data=json.dumps(payload).encode(), headers=headers))
                self.assertEqual(error.exception.code, 400)
                error.exception.close()

    def test_staged_editor_patch_is_idempotent_and_includes_pose_roundtrip(self):
        text = (self.editor / 'index.html').read_text(encoding='utf-8')
        self.assertEqual(patch_editor(text), text)
        self.assertIn('out.attachmentAngle=p.attachmentAngle', text)
        self.assertIn('version:2,godotSource,', text)
        self.assertEqual(text.count('src="godot-character.js"'), 1)


if __name__ == '__main__':
    unittest.main()
