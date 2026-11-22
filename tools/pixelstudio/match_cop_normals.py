"""Rebuild physical normals for an edited cop puppet and export its game clip.

The source cels must still match the procedural cop; all saved per-frame transforms,
visibility, order, artwork and timing are preserved in the delivered project.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import math
from pathlib import Path
import tempfile

import numpy as np
from PIL import Image, ImageDraw

from bridge import REPO, export_character, find_godot


def rgba(encoded: str, width: int, height: int) -> np.ndarray:
    data = np.frombuffer(base64.b64decode(encoded, validate=True), dtype=np.uint8)
    return data.reshape(height, width, 4).copy()


def transform(pose: dict, x, y):
    radians = math.radians(pose.get('angle', 0))
    cos, sin = math.cos(radians), math.sin(radians)
    sx, sy, px, py = pose.get('sx', 1), pose.get('sy', 1), pose.get('px', 0), pose.get('py', 0)
    a, b, c, d = cos * sx, sin * sx, -sin * sy, cos * sy
    e = pose.get('x', 0) + sx * px - a * px - c * py
    f = pose.get('y', 0) + sy * py - b * px - d * py
    return a * x + c * y + e, b * x + d * y + f


def sampling_grid(pose: dict, width: int, height: int):
    # PixelStudio's inverse affine, nearest-neighbor rasterizer uses pixel centers.
    y, x = np.mgrid[0:height, 0:width]
    ex, ey = transform(pose, 0, 0)
    ax, ay = transform(pose, 1, 0)
    bx, by = transform(pose, 0, 1)
    a, b, c, d = ax - ex, ay - ey, bx - ex, by - ey
    determinant = a * d - b * c
    source_x = np.floor((d * (x + .5 - ex) - c * (y + .5 - ey)) / determinant + 1e-10).astype(int)
    source_y = np.floor((-b * (x + .5 - ex) + a * (y + .5 - ey)) / determinant + 1e-10).astype(int)
    valid = (source_x >= 0) & (source_x < width) & (source_y >= 0) & (source_y < height)
    return source_x.clip(0, width - 1), source_y.clip(0, height - 1), valid


def composite(project: dict, frame: dict, geometry: dict):
    width, height = project['width'], project['height']
    image = np.zeros((height, width, 4), dtype=np.uint8)
    depth = np.zeros((height, width), dtype=np.float32)
    for layer in project['layers']:
        if not layer.get('visible', True) or layer.get('opacity', 100) == 0:
            continue
        if layer.get('opacity', 100) != 100:
            raise ValueError('Physical relief matching currently expects opaque body-part layers.')
        key = layer['id']
        encoded = frame.get('cels', {}).get(key)
        if encoded is None:
            continue
        pixels = rgba(encoded, width, height)
        physical = np.frombuffer(base64.b64decode(geometry['parts'][key]), dtype='<f4').reshape(height, width)
        sx, sy, valid = sampling_grid(frame.get('poses', {}).get(key, {}), width, height)
        sampled = pixels[sy, sx]
        filled = valid & (sampled[:, :, 3] > 0)
        if np.any(sampled[:, :, 3][filled] != 255):
            raise ValueError('Physical relief matching currently expects opaque part pixels.')
        image[filled] = sampled[filled]
        depth[filled] = physical[sy, sx][filled]
    return image, depth


def normals(depth: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    height, width = depth.shape
    filled = alpha > 0
    def difference(dx, dy):
        shifted = np.roll(depth, (-dy, -dx), axis=(0, 1))
        available = np.roll(filled, (-dy, -dx), axis=(0, 1))
        if dx > 0: available[:, width-dx:] = False
        if dx < 0: available[:, :-dx] = False
        if dy > 0: available[height-dy:, :] = False
        if dy < 0: available[:-dy, :] = False
        return np.where(available, np.clip(shifted - depth, -2.5, 2.5), -2.5)
    gx = difference(1, -1) + 2 * difference(1, 0) + difference(1, 1) - difference(-1, -1) - 2 * difference(-1, 0) - difference(-1, 1)
    gy = difference(-1, 1) + 2 * difference(0, 1) + difference(1, 1) - difference(-1, -1) - 2 * difference(0, -1) - difference(1, -1)
    vectors = np.stack([-gx / 8, gy / 8, np.ones_like(depth)], axis=-1)
    vectors /= np.linalg.norm(vectors, axis=-1, keepdims=True)
    rgb = np.floor((vectors * .5 + .5) * 255 + .5).clip(0, 255).astype(np.uint8)
    output = np.zeros((height, width, 4), dtype=np.uint8)
    output[:, :, :3][filled] = rgb[filled]
    output[:, :, 3] = alpha
    return output


def lit_preview(art: np.ndarray, normal: np.ndarray, light: tuple[float, float, float]):
    vectors = normal[:, :, :3].astype(float) / 127.5 - 1
    direction = np.array(light, dtype=float)
    direction /= np.linalg.norm(direction)
    lambert = np.maximum(0, np.sum(vectors * direction, axis=-1))
    value = np.clip(art[:, :, :3].astype(float) * (.3 + .85 * lambert[:, :, None]), 0, 255).astype(np.uint8)
    return np.dstack([value, art[:, :, 3]])


def process(source: Path, animation: str, godot: str):
    original_bytes = source.read_bytes()
    project = json.loads(original_bytes)
    counts = {'walk': 8, 'attack': 3, 'idle': 4}
    if project.get('format') != 'pixel-motion-studio' or project.get('version') != 2:
        raise ValueError('Expected a layered PixelStudio v2 project.')
    if (project.get('width'), project.get('height'), len(project.get('frames', []))) != (66, 66, counts[animation]):
        raise ValueError(f'The cop {animation} must have {counts[animation]} frames of 66 x 66 pixels.')
    if any(frame.get('hold', 1) != 1 for frame in project['frames']):
        raise ValueError('The current game cop clip requires one tick per frame.')
    with tempfile.TemporaryDirectory(prefix='cop-relief-', dir=REPO / '.local') as temporary:
        temp = Path(temporary)
        baseline = export_character(REPO / 'godot', godot, animation, temp / 'baseline.pixelstudio')
        geometry = json.loads((temp / 'source-geometry.json').read_text())
    # Do not infer geometry from color or accidentally use heights for a different drawing.
    for i, (edited, base) in enumerate(zip(project['frames'], baseline['frames'])):
        if edited['cels'] != base['cels']:
            raise ValueError(f'{animation} frame {i + 1} has repainted pixels; it needs authored relief for those edits.')
        for field in ['base', 'overlay']:
            if any(base64.b64decode(edited[field])):
                raise ValueError('Additional base/overlay artwork needs its own authored relief.')
        before, before_depth = composite(baseline, base, geometry['frames'][i])
        exact = np.frombuffer(base64.b64decode(geometry['frames'][i]['depth']), dtype='<f4').reshape(66, 66)
        np.testing.assert_array_equal(before_depth[before[:, :, 3] > 0], exact[before[:, :, 3] > 0])
        expected = rgba(geometry['frames'][i]['normal'], 66, 66)
        rebuilt = normals(before_depth, before[:, :, 3])
        if np.max(np.abs(expected.astype(int) - rebuilt.astype(int))) > 1:
            raise ValueError('The reconstructed relief does not reproduce the original Godot normal map.')
    corrected = copy.deepcopy(project)
    output = REPO / 'export' / 'pixelstudio' / f'cop-{animation}-improved'
    output.mkdir(parents=True, exist_ok=True)
    (output / f'cop-{animation}-user-edit.pixelstudio').write_bytes(original_bytes)
    art_frames, normal_frames, anchor_frames = [], [], []
    origin = np.array([31., 62.])
    for i, frame in enumerate(project['frames']):
        art, depth = composite(project, frame, geometry['frames'][i])
        normal = normals(depth, art[:, :, 3])
        corrected['frames'][i].setdefault('maps', {})['normal'] = base64.b64encode(normal.tobytes()).decode()
        for name, data in [('art', art), ('normal', normal)]:
            Image.fromarray(data).save(output / f'cop_{animation}_{i + 1:02}_{name}.png')
        art_frames.append(art)
        normal_frames.append(normal)
        anchors = {}
        for name, point in geometry['frames'][i]['anchors'].items():
            part = {'head': 'head', 'eye': 'face', 'eye_far': 'face', 'hand_n': 'near-hand', 'hand_f': 'far-hand', 'chest': 'torso'}.get(name)
            if part:
                at = np.array(transform(frame['poses'].get('layer-' + part, {}), *point)) - origin
                anchors[name] = at.tolist()
        baton = frame['poses']['layer-baton']
        grip = np.array(transform(baton, baton['px'], baton['py']))
        angle = baton.get('attachmentAngle', frame['socket']['angle']) + baton.get('angle', 0)
        direction = np.array([math.cos(math.radians(angle)), math.sin(math.radians(angle))])
        anchors['muzzle'] = (grip + direction * 12 - origin).tolist()
        anchor_frames.append(anchors)
        corrected['frames'][i]['socket'] = {'x': float(grip[0]), 'y': float(grip[1]), 'angle': angle}
    corrected.setdefault('godotSource', {})['lighting'] = 'original-physical-relief-transformed-to-edited-pose'
    corrected['godotSource']['editedSourceSHA256'] = hashlib.sha256(original_bytes).hexdigest()
    project_path = output / f'cop-{animation}-matched-normals.pixelstudio'
    project_path.write_text(json.dumps(corrected, separators=(',', ':')), encoding='utf-8')
    asset_dir = REPO / 'godot' / 'art' / 'enemies' / 'cop'
    asset_dir.mkdir(parents=True, exist_ok=True)
    art_strip = np.concatenate(art_frames, axis=1)
    normal_strip = np.concatenate(normal_frames, axis=1)
    Image.fromarray(art_strip).save(asset_dir / f'cop_{animation}.png')
    Image.fromarray(normal_strip).save(asset_dir / f'cop_{animation}_n.png')
    metadata = {'format': 'cop-edited-clip-v1', 'animation': animation, 'frame_width': 66, 'frame_height': 66,
                'frame_count': len(art_frames), 'fps': project['fps'], 'holds': [frame.get('hold', 1) for frame in project['frames']],
                'origin': origin.tolist(), 'anchors': anchor_frames,
                'source_project': str(project_path.relative_to(REPO)).replace('\\', '/'),
                'source_sha256': hashlib.sha256(original_bytes).hexdigest()}
    (asset_dir / f'cop_{animation}.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    validation = {'source_sha256': hashlib.sha256(original_bytes).hexdigest(), 'frames': [
        {'art_sha256': hashlib.sha256(art.tobytes()).hexdigest(), 'normal_sha256': hashlib.sha256(normal.tobytes()).hexdigest()}
        for art, normal in zip(art_frames, normal_frames)]}
    (output / 'validation.json').write_text(json.dumps(validation, indent=2), encoding='utf-8')
    # A lit contact sheet and animated preview make alignment visible from both light directions.
    board = Image.new('RGB', (len(art_frames) * 198, 4 * 214), '#232833')
    draw = ImageDraw.Draw(board)
    previews = []
    for i, (art, normal) in enumerate(zip(art_frames, normal_frames)):
        versions = [('Artwork', art), ('OpenGL normal', normal), ('Light from left', lit_preview(art, normal, (-1, .3, 1))), ('Light from right', lit_preview(art, normal, (1, .3, 1)))]
        for row, (label, pixels) in enumerate(versions):
            tile = Image.fromarray(pixels).resize((198, 198), Image.Resampling.NEAREST)
            board.paste(tile, (i * 198, row * 214 + 16), tile)
            draw.text((i * 198 + 3, row * 214 + 2), f'{label} {i + 1}', fill='white')
        tile = Image.new('RGBA', (66, 66), '#232833')
        tile.alpha_composite(Image.fromarray(lit_preview(art, normal, (-1, .3, 1))))
        previews.append(tile.convert('RGB').resize((264, 264), Image.Resampling.NEAREST))
    board.save(output / 'normal-alignment.png')
    durations = [round(1000 / project['fps']) * frame.get('hold', 1) for frame in project['frames']]
    previews[0].save(output / f'cop-{animation}-lit.gif', save_all=True, append_images=previews[1:], duration=durations, loop=0)
    # Verify that generating the normals did not change any artwork, ordering, poses or timing.
    for field in ['layers', 'fps', 'width', 'height']:
        assert corrected[field] == project[field]
    for i, (new, old) in enumerate(zip(corrected['frames'], project['frames'])):
        for field in ['base', 'original', 'overlay', 'cels', 'poses', 'hold']:
            assert new.get(field) == old.get(field), field
        mapped = rgba(new['maps']['normal'], 66, 66)
        assert np.array_equal(mapped[:, :, 3], art_frames[i][:, :, 3])
        filled = mapped[:, :, 3] > 0
        unit = mapped[:, :, :3][filled].astype(float) / 127.5 - 1
        assert np.max(np.abs(np.linalg.norm(unit, axis=-1) - 1)) < .015
        assert np.all(mapped[:, :, 2][filled] >= 128)
    print(f'{animation}: matched {len(art_frames)} frames from physical relief; saved {project_path}')
    return project_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--animation', choices=['walk', 'attack', 'idle'], required=True)
    parser.add_argument('--godot')
    args = parser.parse_args()
    process(args.source.resolve(), args.animation, find_godot(args.godot))


if __name__ == '__main__':
    main()
