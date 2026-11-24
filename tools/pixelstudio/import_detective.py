"""Generates every detective ("det") enemy clip from the hand-drawn, rigged PixelStudio puppet.

Run: python tools/pixelstudio/import_detective.py [path/to/detective.pixelstudio]
Default source: export/pixelstudio/detective/detective.pixelstudio

Each state is posed by rotating/moving the puppet's parts (arm about the shoulder, forearm about the elbow,
upper body about the hip, legs striding, the whole figure toppling for death), then installed exactly like
a hand-edited clip: godot/art/enemies/det/det_<state>{.png,_n.png,.json} plus an entry in edited.json.
Normals come from a per-part height field using the same clamped Sobel filter as the game's pixel canvas.
A preview sheet is written to export/pixelstudio/detective/det_states_x3.png.
"""
import base64, hashlib, json, math, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "export", "pixelstudio", "detective", "detective.pixelstudio")
OUT = os.path.join(ROOT, "godot", "art", "enemies", "det")
MANIFEST = os.path.join(ROOT, "godot", "art", "enemies", "edited.json")
CELL = 66
ORIGIN = (31, 62)          # foot point inside the 66x66 cell (enemy_sheets origin)
OFFSET = (2, 15)           # source canvas -> cell: shoes land on row 62, centred on x 31

ARM = {"Near Upper Arm", "Near Forearm", "Near Hand", "Revolver"}
FOREARM = {"Near Forearm", "Near Hand", "Revolver"}
HEAD = {"Face", "Hat", "Mustache"}
UPPER = {"Torso", "Lower Front Coat", "Pelvis", "Rear Coat"} | HEAD | ARM
NEAR_LEG = {"thigh": "Near Upper Thigh", "shin": "Near Shin", "foot": "Near Shoe"}
FAR_LEG = {"thigh": "Far Thigh", "shin": "Far Shin", "foot": "Far Shoe"}
COAT_TAILS = {"Lower Front Coat", "Rear Coat"}

# Joints on the source canvas.
SHOULDER = (23.0, 28.0)
ELBOW = (31.0, 27.0)
HIP = (28.0, 40.0)
FEET = (29.5, 47.5)
NECK = (28.0, 25.0)
POINTS = {  # anchors on the source canvas and the part that carries them
    "head": ((28.0, 15.0), "Face"), "eye": ((35.0, 18.0), "Face"), "eye_far": ((29.0, 18.0), "Face"),
    "chest": ((28.0, 32.0), "Torso"), "hand_n": ((44.0, 25.0), "Near Hand"), "hand_f": ((20.0, 38.0), "Torso"),
    "muzzle": ((58.0, 19.0), "Revolver"),
}
BASE_HEIGHT = {"Rear Coat": 3, "Far Shoe": 5, "Far Shin": 5, "Far Thigh": 6, "Pelvis": 7, "Torso": 10,
               "Near Upper Thigh": 8, "Near Shin": 8, "Near Shoe": 8, "Lower Front Coat": 11, "Face": 14,
               "Mustache": 17, "Hat": 15, "Near Upper Arm": 13, "Near Forearm": 14, "Near Hand": 15, "Revolver": 16}

LOW_ARM = 34.0      # idle/walk: gun held low, about 34 degrees below the aim line
WALK_X = [2, 1, 0, -1, -2, -1, 0, 1]
WALK_LIFT = [0, 0, 0, 0, 0, 1, 2, 1]
WALK_BOB = [0, 1, 1, 0, 0, 1, 1, 0]


def pose(**kw):
    base = {"arm": LOW_ARM, "fore": 0.0, "bob": 0, "lean": 0.0, "dx": 0, "head_dy": 0, "hat": 0.0,
            "aF": 0, "lF": 0, "aN": 0, "lN": 0, "tail": 0, "whole": 0.0, "wdx": 0, "wdy": 0, "tint": None,
            "floor": False, "settle": 0}
    base.update(kw)
    return base


STATES = {
    "idle": (6, [pose(), pose(), pose(bob=1), pose()]),
    "walk": (7.2, [pose(aF=WALK_X[i], lF=WALK_LIFT[i], aN=WALK_X[(i + 4) % 8], lN=WALK_LIFT[(i + 4) % 8],
                        bob=WALK_BOB[i], tail=-(WALK_X[i] > 0) + (WALK_X[i] < 0), arm=LOW_ARM + WALK_X[i])
                   for i in range(8)]),
    "attack": (6, [pose(arm=0.0), pose(arm=-7.0, dx=-1), pose(arm=-2.0)]),
    "hurt": (6, [pose(arm=48.0, lean=-9.0, dx=-2, head_dy=0, hat=-8.0)]),
    "stunned": (6, [pose(arm=72.0, fore=10.0, bob=2, head_dy=1, hat=12.0, lean=4.0)]),
    "frozen": (6, [pose(arm=0.0, tint="ice")]),
    "death": (6, [pose(arm=-60.0, fore=-20.0, lean=-14.0, dx=-2, hat=-10.0),
                  pose(arm=-30.0, fore=-10.0, whole=-45.0, hat=-20.0, floor=True),
                  pose(arm=75.0, fore=-15.0, whole=-90.0, hat=-35.0, floor=True, settle=-1),
                  pose(arm=80.0, fore=-10.0, whole=-90.0, hat=-35.0, floor=True)]),
}


def rot(angle_deg, center):
    a = math.radians(angle_deg); c, s = math.cos(a), math.sin(a)
    cx, cy = center
    return np.array([[c, -s, cx - c * cx + s * cy], [s, c, cy - s * cx - c * cy], [0, 0, 1.0]])


def move(dx, dy):
    return np.array([[1, 0, dx], [0, 1, dy], [0, 0, 1.0]])


def layer_matrix(name, p):
    """Source canvas -> cell coordinates for one part in pose p (positive angles turn clockwise on screen)."""
    m = np.identity(3)
    for leg, a, lift in ((FAR_LEG, p["aF"], p["lF"]), (NEAR_LEG, p["aN"], p["lN"])):
        if name in (leg["shin"], leg["foot"]): m = move(a, -lift) @ m
        elif name == leg["thigh"]: m = move(round(a * 0.5), -round(lift * 0.5)) @ m
    if name in FOREARM: m = rot(p["fore"], ELBOW) @ m
    if name in ARM: m = rot(p["arm"], SHOULDER) @ m
    if name in HEAD:
        if name == "Hat": m = rot(p["hat"], (28.0, 12.0)) @ m
        m = move(0, p["head_dy"]) @ m
    if name in COAT_TAILS: m = move(p["tail"], 0) @ m
    if name in UPPER:
        m = rot(p["lean"], HIP) @ m
        m = move(p["dx"], p["bob"]) @ m
    m = rot(p["whole"], FEET) @ m
    m = move(p["wdx"] + OFFSET[0], p["wdy"] + OFFSET[1]) @ m
    return m


def load_layers(path):
    d = json.load(open(path))
    w, h = d["width"], d["height"]
    frame = d["frames"][0]
    layers = []
    for layer in d["layers"]:
        cel = frame["cels"].get(layer["id"])
        if not cel or not layer.get("visible", True): continue
        im = np.frombuffer(base64.b64decode(cel), np.uint8).reshape(h, w, 4)
        if not im[:, :, 3].any(): continue
        layers.append((layer["name"], im))
    return layers, open(path, "rb").read()


def bevel(alpha):
    h, w = alpha.shape; out = np.zeros((h, w))
    for y, x in zip(*np.nonzero(alpha)):
        best = 3
        for r in range(1, 4):
            if any(not (0 <= x + dx < w and 0 <= y + dy < h) or alpha[y + dy, x + dx] == 0
                   for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r))):
                best = r - 1; break
        out[y, x] = best
    return out


def render(layers, heights, p):
    color = np.zeros((CELL, CELL, 4), np.uint8); depth = np.zeros((CELL, CELL)); occupied = np.zeros((CELL, CELL), bool)
    ys, xs = np.mgrid[0:CELL, 0:CELL]
    for name, im in layers:
        inv = np.linalg.inv(layer_matrix(name, p))
        sx = inv[0, 0] * (xs + 0.5) + inv[0, 1] * (ys + 0.5) + inv[0, 2]
        sy = inv[1, 0] * (xs + 0.5) + inv[1, 1] * (ys + 0.5) + inv[1, 2]
        ix = np.floor(sx + 1e-6).astype(int); iy = np.floor(sy + 1e-6).astype(int)
        ok = (ix >= 0) & (iy >= 0) & (ix < im.shape[1]) & (iy < im.shape[0])
        ix = np.clip(ix, 0, im.shape[1] - 1); iy = np.clip(iy, 0, im.shape[0] - 1)
        hit = ok & (im[iy, ix, 3] > 0)
        color[hit] = im[iy[hit], ix[hit]]
        depth[hit] = BASE_HEIGHT.get(name, 10) + heights[name][iy[hit], ix[hit]] * 1.5
        occupied |= hit
    if p["tint"] == "ice":
        rgb = color[:, :, :3].astype(float)
        grey = rgb.mean(axis=2, keepdims=True)
        ice = np.array([190, 232, 255], float)
        color[:, :, :3] = np.where(occupied[:, :, None], (grey * 0.45 + ice * 0.55).clip(0, 255), rgb).astype(np.uint8)
        for x in range(19, 44):   # ice block round the shoes
            for y in range(55, 63):
                if (x in (19, 43) or y == 55) and not occupied[y, x]:
                    color[y, x] = (110, 170, 210, 255); occupied[y, x] = True; depth[y, x] = 9
                elif not occupied[y, x]:
                    color[y, x] = (168, 224, 248, 255) if (x + y) % 5 else (236, 250, 255, 255); occupied[y, x] = True; depth[y, x] = 12
    color[~occupied] = 0
    return color, depth, occupied


def normals(depth, occupied):
    """pixel_canvas.gd normal_image(): clamped Sobel on the height field, OpenGL convention."""
    h, w = depth.shape; out = np.zeros((h, w, 4), np.uint8)
    def diff(x, y, center):
        if x < 0 or y < 0 or x >= w or y >= h or not occupied[y, x]: return -2.5
        return max(-2.5, min(2.5, depth[y, x] - center))
    for y, x in zip(*np.nonzero(occupied)):
        c = depth[y, x]
        gx = diff(x+1, y-1, c) + 2*diff(x+1, y, c) + diff(x+1, y+1, c) - diff(x-1, y-1, c) - 2*diff(x-1, y, c) - diff(x-1, y+1, c)
        gy = diff(x-1, y+1, c) + 2*diff(x, y+1, c) + diff(x+1, y+1, c) - diff(x-1, y-1, c) - 2*diff(x, y-1, c) - diff(x+1, y-1, c)
        n = np.array([-gx / 8.0, gy / 8.0, 1.0]); n /= np.linalg.norm(n)
        out[y, x] = [int(math.floor((v * 0.5 + 0.5) * 255 + 0.5)) for v in n] + [255]
    return out


def place_on_floor(layers, heights, p):
    """Toppled frames: rest the lowest pixel on the foot line and centre the body on the foot point."""
    if not p["floor"]: return p
    p = dict(p, wdx=0, wdy=0)
    _, _, occupied = render(layers, heights, dict(p, wdy=-30))
    ys, xs = np.nonzero(occupied)
    p["wdx"] = int(round(ORIGIN[0] - (xs.min() + xs.max()) / 2.0))
    p["wdy"] = int(ORIGIN[1] - (ys.max() + 30)) + p["settle"]
    return p


def anchors_for(p):
    result = {}
    for name, ((x, y), part) in POINTS.items():
        m = layer_matrix(part, p)
        cx, cy, _ = m @ np.array([x + 0.5, y + 0.5, 1.0])
        result[name] = [round(cx - 0.5 - ORIGIN[0], 3), round(cy - 0.5 - ORIGIN[1], 3)]
    return result


def main():
    layers, raw = load_layers(SRC)
    heights = {name: bevel(im[:, :, 3]) for name, im in layers}
    os.makedirs(OUT, exist_ok=True)
    rel_src = os.path.relpath(SRC, ROOT).replace("\\", "/")
    digest = hashlib.sha256(raw).hexdigest()
    preview_rows = []
    for state, (fps, poses) in STATES.items():
        arts, norms, anchors = [], [], []
        for p in poses:
            p = place_on_floor(layers, heights, p)
            color, depth, occupied = render(layers, heights, p)
            arts.append(color); norms.append(normals(depth, occupied)); anchors.append(anchors_for(p))
        Image.fromarray(np.concatenate(arts, axis=1), "RGBA").save(os.path.join(OUT, f"det_{state}.png"))
        Image.fromarray(np.concatenate(norms, axis=1), "RGBA").save(os.path.join(OUT, f"det_{state}_n.png"))
        meta = {"format": "enemy-edited-clip-v1", "kind": "det", "animation": state, "frame_width": CELL,
                "frame_height": CELL, "frame_count": len(poses), "fps": fps, "holds": [1] * len(poses),
                "origin": [float(ORIGIN[0]), float(ORIGIN[1])], "anchors": anchors,
                "source_project": rel_src, "source_sha256": digest, "generated_by": "tools/pixelstudio/import_detective.py"}
        with open(os.path.join(OUT, f"det_{state}.json"), "w") as f:
            json.dump(meta, f, indent=2)
        preview_rows.append(arts)
    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}
    manifest["det"] = list(STATES)
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2); f.write("\n")
    width = max(len(r) for r in preview_rows) * CELL
    sheet = Image.new("RGBA", (width, CELL * len(preview_rows)), (40, 46, 46, 255))
    for row, arts in enumerate(preview_rows):
        for i, a in enumerate(arts):
            sheet.alpha_composite(Image.fromarray(a, "RGBA"), (i * CELL, row * CELL))
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(
        os.path.join(ROOT, "export", "pixelstudio", "detective", "det_states_x3.png"))
    print("installed", ", ".join(STATES), "->", OUT)


if __name__ == "__main__":
    main()
