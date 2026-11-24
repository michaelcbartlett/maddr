"""Builds the redesigned (charcoal uniform, sunglasses, pistol) cop as a layered
66x66 PixelStudio project, plus flattened preview PNGs.

Run: python tools/pixelstudio/make_cop_redesign.py
Output: export/pixelstudio/cop-redesign/
"""
import base64, json, os, uuid
from PIL import Image

W = H = 66
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "export", "pixelstudio", "cop-redesign")

PAL = {
    "k": "#100d14",  # outline
    "U": "#2e2c39", "u": "#43404f", "v": "#5a5669", "w": "#6f6b80",  # uniform
    "H": "#33313d", "h": "#474453", "j": "#5f5b70",  # hat
    "b": "#5e3820", "B": "#9a6234",  # hat band
    "g": "#a87a26", "G": "#efbf52", "Y": "#ffe6a0",  # gold
    "d": "#8a4a2e", "s": "#bf7650", "S": "#e49e6e", "L": "#f8c194",  # skin
    "m": "#6e3d22", "n": "#4a2614",  # moustache
    "r": "#3b2519",  # hair
    "o": "#0d0b11", "O": "#34323f", "q": "#77758a",  # sunglasses
    "t": "#e8e8f0",  # name tag
    "l": "#18161d",  # belt
    "e": "#16141a", "E": "#3c3a45",  # shoes
    "p": "#2a2e36", "P": "#66727f", "Q": "#a5b4c2", "R": "#dce7ef", "x": "#4a3020",  # pistol
}

# (layer id, name, parent, pivot, origin x, origin y, rows). Listed bottom -> top.
PARTS = [
    ("layer-far-upper-arm", "Far Upper Arm", "layer-torso", (18, 34), 15, 33, [
        "..kkkkk",
        ".kUuuvk",
        "kUuuuvk",
        "kUuuuuk",
        "kUuuuuk",
        "kUUuuuk",
        "kUUUuuk",
        "kkkkkkk",
    ]),
    ("layer-far-forearm", "Far Forearm", "layer-far-upper-arm", (18, 41), 15, 40, [
        "kSLLLsk",
        "kSLLSsk",
        "kSLSSsk",
        "kSSSSsk",
        "kSSSssk",
        "ksSSSsk",
        "kSLLSsk",
        "kSLSSsk",
        "ksSSssk",
        ".kdsdk.",
        "..kkk..",
    ]),
    ("layer-far-thigh", "Far Thigh", "layer-torso", (28, 49), 25, 48, [
        "kUuuuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
    ]),
    ("layer-far-shin", "Far Shin", "layer-far-thigh", (28, 55), 25, 55, [
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuuuUk",
        "kUUUUUk",
    ]),
    ("layer-far-foot", "Far Foot", "layer-far-shin", (28, 60), 23, 59, [
        "..kkkkkkk.",
        ".kEEeeeeek",
        "keeeeeeeek",
        "kkkkkkkkkk",
    ]),
    ("layer-near-thigh", "Near Thigh", "layer-torso", (35, 49), 32, 48, [
        "kUuuuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
    ]),
    ("layer-near-shin", "Near Shin", "layer-near-thigh", (35, 55), 32, 55, [
        "kUuvuUk",
        "kUuvuUk",
        "kUuvuUk",
        "kUuuuUk",
        "kUUUUUk",
    ]),
    ("layer-near-foot", "Near Foot", "layer-near-shin", (35, 60), 32, 59, [
        "kkkkkkkk..",
        "kEEeeeeekk",
        "keeeeeeeeek",
        "kkkkkkkkkkk",
    ]),
    ("layer-torso", "Torso", None, (31, 48), 19, 30, [
        "........kkkkkkk.......",
        ".......kdSSSSSdk......",
        ".....kkUkdSSSdkUkk....",
        "...kkUUuvkdsdkvuUUkk..",
        "..kUUuuuuvkkkvuuuuuUk.",
        ".kUuuuuuuuuvkuuuuGGuUk",
        ".kUuuuuuuuuukuuuuGYguk",
        ".kUuuuuuuuuuvuuuuggUuk",
        ".kUuutttuuuukuuuuuuuUk",
        ".kUUuuuuuuuuvuuuuuuUUk",
        "..kUuuuuuuuukuuuuuuUk.",
        "..kUUuuuuuuuvuuuuuUUk.",
        "..kUUuuuuuuukuuuuuUUk.",
        "..kUUuuuuuuuvuuuuuUUk.",
        "..kUUUuuuuuukuuuuUUUk.",
        "..kUUUuuuuuuvuuuuUUUk.",
        "..kkllllllllllllllllk.",
        "..klllllllgGGgllllllk.",
        "..kllllllgGYGgllllllk.",
        "..klllllllgggllllllk..",
        "..kUUUUUUUuUUUUUUUUk..",
    ]),
    ("layer-head", "Head", "layer-torso", (32, 31), 21, 17, [
        "....kkkkkkkkkkkkkk....",
        "...kSSSSSSSSSSSSSSk...",
        "..krrrSSSSSSSSSSSSSk..",
        ".krrrrrLLLLLLLLLLLLSk.",
        ".krrrrsLLLLLLLLLLLLLk.",
        ".krrrssLLLLLLLLLLLLLk.",
        ".krrsSssLLLLLLLLLLLLSk",
        ".krsSLSsLLLLLLLLLLLLSk",
        ".krsSSssLLLLLLLLLLLLSk",
        "..krssSSLLLLLLLLLLLLSk",
        "..kdsSSSSLLLLLLmmmmmSk",
        "...kdsSSSSLLLmnnnnnmk.",
        "....kdsSSSSSLLSSSSSSk.",
        ".....kddsSSSSSSSSssk..",
        "......kkkdddssssskk...",
    ]),
    ("layer-glasses", "Glasses", "layer-head", (32, 31), 24, 22, [
        "...kkkkkkk.kkkkkk",
        "kkkoOqqooookoOqook",
        "...kooOqoook.ooOok",
        "....kooooook.koook",
        ".....kkkkk....kkk.",
    ]),
    ("layer-hat", "Hat", "layer-head", (32, 31), 18, 9, [
        ".......kkkkkkkkkkkkkkk.......",
        "....kkkhhhhhhhhhhhhhhhkkk....",
        "..kkhhjjjjjjjjjjjjjjjhhhhkk..",
        ".khhhhhhhhhhhhhGGhhhhhhhhhhk.",
        "kHhhhhhhhhhhhhGYGhhhhhhhhhhHk",
        ".kHHhhhhhhhhhhgGghhhhhhhhHHk.",
        "..kHHHHHHHHHHHHgHHHHHHHHHHk..",
        "...kbbbbbbbBBBBBBBBBbbbbbk...",
        "...kbBBBBBBBBBBBBBBBBBBbbk...",
        "...kHHHHHHHHHHHHHHHHHHHHHkkk.",
        "....kkkkkkkkoooooHHHHHHHHHHHk",
        "...............kkkkkkkkkkkkk.",
    ]),
    ("layer-near-upper-arm", "Near Upper Arm", "layer-torso", (40, 35), 38, 33, [
        ".kkkkkkkk",
        "kuvvvvvvk",
        "kuuuuuuuk",
        "kUuuuuuuk",
        "kUUUUUUUk",
        ".kkkkkkkk",
    ]),
    ("layer-primary-weapon", "Weapon", "layer-near-forearm", (55, 34), 50, 28, [
        ".kkkkkkkkkkkkk.",
        "kPRRRRRRRRQQRRk",
        "kPQQQQQQQQQQQPk",
        "kpppppppppppppk",
        "...kkpxxkpk....",
        "....kxxxkk.....",
        "....kxxxk......",
        "....kxxxk......",
        "....kkkkk......",
    ]),
    ("layer-near-forearm", "Near Forearm", "layer-near-upper-arm", (47, 35), 46, 32, [
        "......kkkkk.",
        "......kLLLSk",
        "kkkkkkkLLSSk",
        "kLLLLLLSLLsk",
        "kSSSSSSkSSsk",
        "ksssssskSssk",
        "kkkkkkkksssk",
        ".......kdddk",
        "........kkk.",
    ]),
]


def hexrgba(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)


def cel(ox, oy, rows):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c != ".":
                im.putpixel((ox + x, oy + y), hexrgba(PAL[c]))
    return im


def composite(cels):
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for im in cels:
        out.alpha_composite(im)
    return out


def b64(im):
    return base64.b64encode(im.tobytes()).decode()


def main():
    os.makedirs(OUT, exist_ok=True)
    cels = {p[0]: cel(p[4], p[5], p[6]) for p in PARTS}
    flat = composite([cels[p[0]] for p in PARTS])
    flat.save(os.path.join(OUT, "cop_redesign.png"))
    flat.resize((W * 6, H * 6), Image.NEAREST).save(os.path.join(OUT, "cop_redesign_x6.png"))

    # Exploded view: each layer on its own tile, for checking the cut.
    cols = 5
    rows = (len(PARTS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * W, rows * H), (70, 74, 82, 255))
    for i, p in enumerate(PARTS):
        sheet.alpha_composite(cels[p[0]], ((i % cols) * W, (i // cols) * H))
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(os.path.join(OUT, "cop_redesign_layers_x4.png"))

    # Reuse the settings block of the existing cop edit so the editor opens it the same way.
    src = json.load(open(os.path.join(ROOT, "export", "pixelstudio", "cop-idle-improved", "cop-idle-user-edit.pixelstudio")))
    empty = b64(Image.new("RGBA", (W, H), (0, 0, 0, 0)))
    poses = {}
    for lid, _, _, (px, py), *_ in PARTS:
        poses[lid] = {"x": 0, "y": 0, "sx": 1, "sy": 1, "angle": 0, "px": px, "py": py}
    poses["layer-primary-weapon"]["attachmentAngle"] = 0
    grip = PARTS[[p[0] for p in PARTS].index("layer-primary-weapon")][3]
    palette = list(dict.fromkeys(PAL.values()))
    project = {
        "format": "pixel-motion-studio",
        "version": 2,
        "width": W, "height": H, "fps": 6, "currentFrame": 0,
        "palette": palette,
        "layers": [
            dict({"id": lid, "name": name, "visible": True, "locked": False, "opacity": 100},
                 **({"parent": parent} if parent else {}))
            for lid, name, parent, *_ in PARTS
        ],
        "activeLayer": "layer-torso",
        "settings": src["settings"],
        "reference": None,
        "frames": [{
            "cels": {lid: b64(cels[lid]) for lid in cels},
            "poses": poses,
            "base": empty, "original": b64(flat), "overlay": empty,
            "mask": base64.b64encode(bytes(W * H)).decode(),
            "hold": 1,
            "socket": {"x": grip[0], "y": grip[1], "angle": 0},
            "gradientBoxes": [], "gradientBoxIndex": -1, "maps": {},
        }],
    }
    with open(os.path.join(OUT, "cop-redesign.pixelstudio"), "w") as f:
        json.dump(project, f, separators=(",", ":"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
