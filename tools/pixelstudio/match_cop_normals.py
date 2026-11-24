"""Rebuild physical normals for an edited character clip and install it in the game.

Works for any enemy_painter kind (the name is historical). Relief comes from the game's own
height fields: moved parts carry theirs along; repainted pixels keep the original relief at
that spot, and newly painted pixels borrow the nearest original relief in the same layer.
All saved per-frame transforms, visibility, order, artwork and timing are preserved.
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

from bridge import REPO, character_catalog, export_character, find_godot


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


def nearest_fill(values: np.ndarray, known: np.ndarray, fallback: float) -> np.ndarray:
    """Give every unknown pixel the value of the nearest known pixel (city-block growth)."""
    if known.all():
        return values
    if not known.any():
        return np.full_like(values, fallback)
    out, have = values.copy(), known.copy()
    while not have.all():
        grown, grown_have = out.copy(), have.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(out, (dy, dx), axis=(0, 1))
            shifted_have = np.roll(have, (dy, dx), axis=(0, 1))
            if dy == 1: shifted_have[0, :] = False
            if dy == -1: shifted_have[-1, :] = False
            if dx == 1: shifted_have[:, 0] = False
            if dx == -1: shifted_have[:, -1] = False
            take = shifted_have & ~grown_have
            grown[take] = shifted[take]
            grown_have |= take
        if (grown_have == have).all():
            break
        out, have = grown, grown_have
    return out


def composite(project: dict, frame: dict, geometry: dict, baseline_frame: dict | None = None, stats: dict | None = None):
    width, height = project['width'], project['height']
    image = np.zeros((height, width, 4), dtype=np.uint8)
    depth = np.zeros((height, width), dtype=np.float32)
    known_depths = [np.frombuffer(base64.b64decode(v), dtype='<f4').reshape(height, width) for v in geometry['parts'].values()]
    occupied = [d[d != 0] for d in known_depths]
    fallback = float(np.median(np.concatenate(occupied))) if any(o.size for o in occupied) else 8.0
    for layer in project['layers']:
        if not layer.get('visible', True) or layer.get('opacity', 100) == 0:
            continue
        if layer.get('opacity', 100) != 100:
            raise ValueError('Physical relief matching expects layers at 100% opacity (layer: %s).' % layer.get('name'))
        key = layer['id']
        encoded = frame.get('cels', {}).get(key)
        if encoded is None:
            continue
        pixels = rgba(encoded, width, height)
        if key in geometry['parts']:
            physical = np.frombuffer(base64.b64decode(geometry['parts'][key]), dtype='<f4').reshape(height, width)
        else:
            physical = np.zeros((height, width), dtype=np.float32)
        if baseline_frame is not None:
            # Relief is authored only where the game drew this part; estimate the rest.
            original = baseline_frame.get('cels', {}).get(key)
            known = rgba(original, width, height)[:, :, 3] > 0 if original else np.zeros((height, width), bool)
            new = (pixels[:, :, 3] > 0) & ~known
            if new.any():
                physical = nearest_fill(physical, known, fallback)
                if stats is not None: stats['estimated'] = stats.get('estimated', 0) + int(new.sum())
        sx, sy, valid = sampling_grid(frame.get('poses', {}).get(key, {}), width, height)
        sampled = pixels[sy, sx]
        filled = valid & (sampled[:, :, 3] > 0)
        opaque = filled & (sampled[:, :, 3] == 255)
        image[opaque] = sampled[opaque]
        soft = filled & ~opaque
        if soft.any():
            # Straight-alpha "over"; onto empty pixels the source is copied exactly.
            src = sampled[soft].astype(np.float64)
            dst = image[soft].astype(np.float64)
            sa, da = src[:, 3:4] / 255, dst[:, 3:4] / 255
            oa = sa + da * (1 - sa)
            rgb = (src[:, :3] * sa + dst[:, :3] * da * (1 - sa)) / np.maximum(oa, 1e-9)
            blended = np.concatenate([rgb, oa * 255], axis=1)
            blended[da[:, 0] == 0] = src[da[:, 0] == 0]
            image[soft] = np.floor(blended + .5).clip(0, 255).astype(np.uint8)
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
    output[:, :, 3] = np.where(filled, 255, 0)  # the game's normals are opaque under translucent art
    return output


def lit_preview(art: np.ndarray, normal: np.ndarray, light: tuple[float, float, float]):
    vectors = normal[:, :, :3].astype(float) / 127.5 - 1
    direction = np.array(light, dtype=float)
    direction /= np.linalg.norm(direction)
    lambert = np.maximum(0, np.sum(vectors * direction, axis=-1))
    value = np.clip(art[:, :, :3].astype(float) * (.3 + .85 * lambert[:, :, None]), 0, 255).astype(np.uint8)
    return np.dstack([value, art[:, :, 3]])


PART_OF_ANCHOR = {'head': 'head', 'eye': 'face', 'eye_far': 'face', 'hand_n': 'near-hand', 'hand_f': 'far-hand',
                  'chest': 'torso', 'muzzle': 'baton'}


def process(source: Path, animation: str | None, godot: str, kind: str | None = None):
    original_bytes = source.read_bytes()
    project = json.loads(original_bytes)
    if project.get('format') != 'pixel-motion-studio' or project.get('version') != 2:
        raise ValueError('Expected a layered PixelStudio v2 project.')
    origin_info = project.get('godotSource', {})
    kind = kind or origin_info.get('character') or 'cop'
    animation = animation or origin_info.get('animation')
    if not animation:
        raise ValueError('This project does not say which animation it is; pass --animation.')
    catalog = {entry['id']: entry for entry in character_catalog(REPO / 'godot', godot)}
    if kind not in catalog or animation not in catalog[kind]['states']:
        raise ValueError(f'{kind} has no {animation} clip in the game.')
    width, height = catalog[kind]['cell']
    count = catalog[kind]['states'][animation]
    if (project.get('width'), project.get('height'), len(project.get('frames', []))) != (width, height, count):
        raise ValueError(f'The {kind} {animation} must have {count} frames of {width} x {height} pixels.')
    if any(frame.get('hold', 1) != 1 for frame in project['frames']):
        raise ValueError('The game plays one tick per frame; set every frame hold to 1.')
    with tempfile.TemporaryDirectory(prefix='relief-', dir=REPO / '.local') as temporary:
        temp = Path(temporary)
        baseline = export_character(REPO / 'godot', godot, animation, temp / 'baseline.pixelstudio', kind)
        geometry = json.loads((temp / 'source-geometry.json').read_text())
    if (baseline['width'], baseline['height']) != (width, height):
        raise ValueError(f'The game draws {kind} {animation} at {baseline["width"]} x {baseline["height"]}, not the cell size.')
    baseline_ids = {layer['id'] for layer in baseline['layers']}
    if not {layer['id'] for layer in project['layers']} & baseline_ids:
        raise ValueError(f'This project has none of the {kind} {animation} layers; open the clip from the Godot picker and edit that.')
    # Check the original relief reproduces the game's normals before reusing it for the edit.
    for i, (edited, base) in enumerate(zip(project['frames'], baseline['frames'])):
        for field in ['base', 'overlay']:
            if any(base64.b64decode(edited[field])):
                raise ValueError('Paint on the character layers, not the base/overlay surfaces: they have no relief.')
        before, before_depth = composite(baseline, base, geometry['frames'][i])
        exact = np.frombuffer(base64.b64decode(geometry['frames'][i]['depth']), dtype='<f4').reshape(height, width)
        np.testing.assert_array_equal(before_depth[before[:, :, 3] > 0], exact[before[:, :, 3] > 0])
        expected = rgba(geometry['frames'][i]['normal'], width, height)
        rebuilt = normals(before_depth, before[:, :, 3])
        if np.max(np.abs(expected.astype(int) - rebuilt.astype(int))) > 1:
            raise ValueError('The reconstructed relief does not reproduce the original Godot normal map.')
    corrected = copy.deepcopy(project)
    output = REPO / 'export' / 'pixelstudio' / f'{kind}-{animation}-improved'
    output.mkdir(parents=True, exist_ok=True)
    (output / f'{kind}-{animation}-user-edit.pixelstudio').write_bytes(original_bytes)
    art_frames, normal_frames, anchor_frames = [], [], []
    origin = np.array(catalog[kind]['origin'], dtype=float)
    stats = {}
    for i, frame in enumerate(project['frames']):
        art, depth = composite(project, frame, geometry['frames'][i], baseline['frames'][i], stats)
        normal = normals(depth, art[:, :, 3])
        corrected['frames'][i].setdefault('maps', {})['normal'] = base64.b64encode(normal.tobytes()).decode()
        for name, data in [('art', art), ('normal', normal)]:
            Image.fromarray(data).save(output / f'{kind}_{animation}_{i + 1:02}_{name}.png')
        art_frames.append(art)
        normal_frames.append(normal)
        anchors = {}
        poses = frame.get('poses', {})
        for name, point in geometry['frames'][i]['anchors'].items():
            # Anchors follow the part they sit on; on a single flat layer they follow that layer.
            part = 'layer-' + PART_OF_ANCHOR.get(name, '')
            pose = poses.get(part) or poses.get('layer-art') or {}
            if kind == 'cop' and name not in PART_OF_ANCHOR:
                continue
            anchors[name] = (np.array(transform(pose, *point)) - origin).tolist()
        baton = poses.get('layer-baton')
        if baton is not None and (kind == 'cop' or 'muzzle' not in anchors):
            grip = np.array(transform(baton, baton['px'], baton['py']))
            angle = baton.get('attachmentAngle', frame.get('socket', {}).get('angle', 0)) + baton.get('angle', 0)
            direction = np.array([math.cos(math.radians(angle)), math.sin(math.radians(angle))])
            anchors['muzzle'] = (grip + direction * 12 - origin).tolist()
            corrected['frames'][i]['socket'] = {'x': float(grip[0]), 'y': float(grip[1]), 'angle': angle}
        anchor_frames.append(anchors)
    corrected.setdefault('godotSource', {})['lighting'] = 'original-physical-relief-transformed-to-edited-pose'
    corrected['godotSource']['editedSourceSHA256'] = hashlib.sha256(original_bytes).hexdigest()
    project_path = output / f'{kind}-{animation}-matched-normals.pixelstudio'
    project_path.write_text(json.dumps(corrected, separators=(',', ':')), encoding='utf-8')
    asset_dir = REPO / 'godot' / 'art' / 'enemies' / kind
    asset_dir.mkdir(parents=True, exist_ok=True)
    art_strip = np.concatenate(art_frames, axis=1)
    normal_strip = np.concatenate(normal_frames, axis=1)
    Image.fromarray(art_strip).save(asset_dir / f'{kind}_{animation}.png')
    Image.fromarray(normal_strip).save(asset_dir / f'{kind}_{animation}_n.png')
    metadata = {'format': 'enemy-edited-clip-v1', 'kind': kind, 'animation': animation, 'frame_width': width, 'frame_height': height,
                'frame_count': len(art_frames), 'fps': project['fps'], 'holds': [frame.get('hold', 1) for frame in project['frames']],
                'origin': origin.tolist(), 'anchors': anchor_frames,
                'source_project': str(project_path.relative_to(REPO)).replace('\\', '/'),
                'source_sha256': hashlib.sha256(original_bytes).hexdigest()}
    (asset_dir / f'{kind}_{animation}.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    manifest_path = REPO / 'godot' / 'art' / 'enemies' / 'edited.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.is_file() else {}
    states = manifest.setdefault(kind, [])
    if animation not in states:
        states.append(animation)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
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
        tile = Image.new('RGBA', (width, height), '#232833')
        tile.alpha_composite(Image.fromarray(lit_preview(art, normal, (-1, .3, 1))))
        previews.append(tile.convert('RGB').resize((width * 4, height * 4), Image.Resampling.NEAREST))
    board.save(output / 'normal-alignment.png')
    durations = [round(1000 / project['fps']) * frame.get('hold', 1) for frame in project['frames']]
    previews[0].save(output / f'{kind}-{animation}-lit.gif', save_all=True, append_images=previews[1:], duration=durations, loop=0)
    # Verify that generating the normals did not change any artwork, ordering, poses or timing.
    for field in ['layers', 'fps', 'width', 'height']:
        assert corrected[field] == project[field]
    for i, (new, old) in enumerate(zip(corrected['frames'], project['frames'])):
        for field in ['base', 'original', 'overlay', 'cels', 'poses', 'hold']:
            assert new.get(field) == old.get(field), field
        mapped = rgba(new['maps']['normal'], width, height)
        assert np.array_equal(mapped[:, :, 3] > 0, art_frames[i][:, :, 3] > 0)
        filled = mapped[:, :, 3] > 0
        unit = mapped[:, :, :3][filled].astype(float) / 127.5 - 1
        assert np.max(np.abs(np.linalg.norm(unit, axis=-1) - 1)) < .015
        assert np.all(mapped[:, :, 2][filled] >= 128)
    if stats.get('estimated'):
        print(f'{stats["estimated"]} newly painted pixels took relief from the nearest original pixel in their layer.')
    print(f'{kind} {animation}: matched {len(art_frames)} frames from physical relief; installed in godot/art/enemies/{kind}/; saved {project_path}')
    return project_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--animation', help='defaults to the animation saved in the project')
    parser.add_argument('--character', help='enemy_painter kind; defaults to the character saved in the project')
    parser.add_argument('--godot')
    args = parser.parse_args()
    process(args.source.resolve(), args.animation, find_godot(args.godot), args.character)


if __name__ == '__main__':
    main()
