"""Turns the hand-drawn scientist puppet (.pixelstudio) into the villain body skin the game loads.

Run: python tools/pixelstudio/import_scientist.py [path/to/scientist.pixelstudio]
Default source: export/pixelstudio/scientist/scientist.pixelstudio

Writes godot/character/art/scientist/:
  body.png         19 frames x 2 rows (row 0: off hand free, row 1: armed, no off arm), 60x68 grid frames
  body_height.png  matching height map, 0..255 = 0..40 px toward the viewer (same scale as the villain)
  body.json        per-frame anchors in the renderer's grid coordinates

The game draws the gun arm separately, so the blaster and the arm holding it are left out of the body.
Idle, blink and walk frames are posed from the puppet layers by offsetting parts; the frame numbering and
timing match art_renderer.gd pose_at() (walk6 0-5, idle 6-9, blink 10, walk8 11-18).
"""
import base64, json, math, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "export", "pixelstudio", "scientist", "scientist.pixelstudio")
OUT = os.path.join(ROOT, "godot", "character", "art", "scientist")
GW, GH = 60, 68          # renderer grid (VG.w, VG.h); the game adds the 1px outline itself
OFFSET = (7, 15)         # source canvas -> grid: puts the feet on grid row 62 and the hip near x30

# Source-canvas layer names, grouped by how they move.
GUN_ARM = {"Base Blaster", "Near Upper Arm", "Near Forearm", "Near Hand"}   # replaced by the game's gun arm
OFF_ARM = {"Far Upper Arm", "Far Forearm", "Far Hand"}                    # hidden when the off hand is armed
OFF_LOWER = {"Far Forearm", "Far Hand"}
FRONT_LEG = {"thigh": "Far Thigh", "shin": "Far Shin", "foot": "Far Shoe"}
BACK_LEG = {"thigh": "Near Thigh", "shin": "Near Shin", "foot": "Near Shoeii"}
LEGS = set(FRONT_LEG.values()) | set(BACK_LEG.values())
HAIR = {"Hair"}
BROWS = {"EyeBrows"}
COAT_TAILS = {"Lower Front Coat", "Lower Rear Coat"}

# Height (px toward the viewer) per layer before the edge bevel.
BASE_HEIGHT = {
    "Lower Rear Coat": 3, "Near Shoeii": 5, "Near Shin": 5, "Near Thigh": 6, "Pelvis": 7,
    "Far Thigh": 8, "Far Shin": 8, "Far Shoe": 8, "Torso": 10, "Lower Front Coat": 11,
    "Far Upper Arm": 13, "Far Forearm": 14, "Far Hand": 15, "Face": 14, "Hair": 13,
    "EyeBrows": 18, "glasses": 19,
}

# Anchors on the source canvas (same names the procedural body exports).
ANCHORS = {
    "head": (23, 11), "helmet": (23, 3), "brow": (24, 8), "eyeFar": (19, 12), "eyeNear": (26, 12),
    "nose": (28, 14), "mouth": (24, 16), "ear": (14, 12), "neck": (22, 19), "chest": (23, 24),
    "belt": (23, 31), "hip": (23, 34), "back": (11, 24), "backpack": (7, 25),
    "shoulderFar": (16, 24), "shoulderNear": (29, 21), "elbowOff": (31, 26), "handOff": (36, 28),
    "kneeBack": (17, 39), "footBack": (16, 46), "kneeFront": (30, 39), "footFront": (32, 46),
}
UPPER = {"head", "helmet", "brow", "eyeFar", "eyeNear", "nose", "mouth", "ear", "neck", "chest", "belt",
         "hip", "back", "backpack", "shoulderFar", "shoulderNear", "elbowOff", "handOff"}

# Same tables as art_renderer.gd, scaled for the scientist's shorter legs.
WALK_X = [5, 3, 0, -3, -5, -3, 0, 3]
WALK_LIFT = [0, 0, 0, 0, 0, 2, 3, 2]
WALK_BOB = [0, 1, 1, 0, 0, 1, 1, 0]
STRIDE = 0.6


def walk_key(values, phase):
    f = (phase % 1.0) * 8.0
    i = int(math.floor(f)); w = f - i
    return values[i] + (values[(i + 1) % 8] - values[i]) * w


def jsround(v):
    return math.floor(v + 0.5)


def pose_at(index):
    if index < 6 or index >= 11:
        phase = index / 6.0 if index < 6 else (index - 11) / 8.0
        front = walk_key(WALK_X, phase) * STRIDE; back = walk_key(WALK_X, phase + 0.5) * STRIDE
        return {"aF": jsround(front), "aB": jsround(back),
                "lF": jsround(walk_key(WALK_LIFT, phase) * 0.67), "lB": jsround(walk_key(WALK_LIFT, phase + 0.5) * 0.67),
                "bob": jsround(walk_key(WALK_BOB, phase)), "swing": -jsround(front * 0.5),
                "hair": jsround(walk_key(WALK_BOB, phase - 0.125)) - jsround(walk_key(WALK_BOB, phase)),
                "tail": jsround(-front * 0.3), "blink": False}
    idle = 0 if index == 10 else index - 6
    return {"aF": 0, "aB": 0, "lF": 0, "lB": 0, "bob": 1 if idle >= 2 else 0, "swing": 0,
            "hair": 1 if idle == 2 else (-1 if idle == 3 else 0), "tail": 0, "blink": index == 10}


def load_layers(path):
    d = json.load(open(path))
    w, h = d["width"], d["height"]
    frame = d["frames"][0]
    layers = []
    for layer in d["layers"]:
        cel = frame["cels"].get(layer["id"])
        if not cel or not layer.get("visible", True):
            continue
        im = Image.frombytes("RGBA", (w, h), base64.b64decode(cel))
        p = frame.get("poses", {}).get(layer["id"], {})
        if p.get("angle"):
            im = im.rotate(-p["angle"], resample=Image.NEAREST, center=(p.get("px", w / 2), p.get("py", h / 2)))
        if p.get("x") or p.get("y"):
            moved = Image.new("RGBA", (w, h)); moved.alpha_composite(im, (int(p.get("x", 0)), int(p.get("y", 0))))
            im = moved
        layers.append((layer["name"], im))
    return layers


def bevel(im):
    """Distance (capped at 3) from each opaque pixel to the layer edge."""
    w, h = im.size; a = im.getchannel("A").load()
    dist = {}
    for y in range(h):
        for x in range(w):
            if a[x, y] == 0:
                continue
            best = 3
            for r in range(1, 4):
                if any(not (0 <= x + dx < w and 0 <= y + dy < h) or a[x + dx, y + dy] == 0
                       for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r))):
                    best = r - 1; break
            dist[(x, y)] = best
    return dist


def offsets(name, pose):
    """Pixel offset (dx, dy) of a source layer in this pose."""
    dx = dy = 0
    if name not in LEGS:
        dy += pose["bob"]
    for leg, a, lift in ((FRONT_LEG, pose["aF"], pose["lF"]), (BACK_LEG, pose["aB"], pose["lB"])):
        if name == leg["foot"] or name == leg["shin"]:
            dx += a; dy -= lift
        elif name == leg["thigh"]:
            dx += jsround(a * 0.5); dy -= jsround(lift * 0.5)
    if name in HAIR:
        dy += pose["hair"]
    if name in BROWS and pose["blink"]:
        dy += 1
    if name in COAT_TAILS:
        dx += pose["tail"]
    if name in OFF_LOWER:
        dx += jsround(pose["swing"] * 0.5)
    return dx, dy


def render(layers, bevels, pose, armed):
    color = Image.new("RGBA", (GW, GH))
    height = Image.new("L", (GW, GH))
    hp = height.load(); cp = color.load()
    for name, im in layers:
        if name in GUN_ARM or (armed and name in OFF_ARM):
            continue
        dx, dy = offsets(name, pose)
        dx += OFFSET[0]; dy += OFFSET[1]
        src = im.load(); base = BASE_HEIGHT.get(name, 10)
        for (x, y), edge in bevels[name].items():
            gx, gy = x + dx, y + dy
            if 0 <= gx < GW and 0 <= gy < GH:
                cp[gx, gy] = src[x, y]
                hp[gx, gy] = min(255, int(round((base + edge * 1.5) / 40.0 * 255)))
    return color, height


def anchors_for(pose):
    out = {}
    for key, (x, y) in ANCHORS.items():
        dx = dy = 0
        if key in UPPER:
            dy += pose["bob"]
        if key == "kneeFront": dx += jsround(pose["aF"] * 0.5); dy -= jsround(pose["lF"] * 0.5)
        if key == "footFront": dx += pose["aF"]; dy -= pose["lF"]
        if key == "kneeBack": dx += jsround(pose["aB"] * 0.5); dy -= jsround(pose["lB"] * 0.5)
        if key == "footBack": dx += pose["aB"]; dy -= pose["lB"]
        if key == "handOff": dx += jsround(pose["swing"] * 0.5)
        out[key] = {"x": x + dx + OFFSET[0], "y": y + dy + OFFSET[1]}
    return out


def main():
    layers = load_layers(SRC)
    bevels = {name: bevel(im) for name, im in layers}
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (GW * 19, GH * 2))
    heights = Image.new("L", (GW * 19, GH * 2))
    frames = []
    for index in range(19):
        pose = pose_at(index)
        for row, armed in enumerate((False, True)):
            c, h = render(layers, bevels, pose, armed)
            sheet.alpha_composite(c, (index * GW, row * GH)); heights.paste(h, (index * GW, row * GH))
        frames.append({"anchors": anchors_for(pose)})
    sheet.save(os.path.join(OUT, "body.png"))
    heights.save(os.path.join(OUT, "body_height.png"))
    meta = {"format": "villain-body-skin-v1", "source": os.path.basename(SRC), "frameW": GW, "frameH": GH,
            "frames": 19, "rows": {"free": 0, "armed": 1},
            "poses": {"walk6": [0, 1, 2, 3, 4, 5], "idle": [6, 7, 8, 9], "blink": 10, "walk8": list(range(11, 19))},
            "heightScale": 40, "perFrame": frames}
    with open(os.path.join(OUT, "body.json"), "w") as f:
        json.dump(meta, f, indent=1)
    preview = Image.new("RGBA", sheet.size, (52, 56, 52, 255)); preview.alpha_composite(sheet)
    preview.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(
        os.path.join(ROOT, "export", "pixelstudio", "scientist", "body_preview_x3.png"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
