"""Install native 128px cop movement or the full strike clip at 24 fps.

Usage: python tools/pixelstudio/import_base_cop.py [ZIP] [--gait walk|run]
The original export is preserved; no resizing, recoloring or invented relief is applied.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
from zipfile import ZipFile

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path,
                        default=Path.home() / "Downloads/BASE_COP_frames.zip")
    parser.add_argument("--gait", choices=("walk", "run"),
                        help="Defaults to walk for a WALKING export, otherwise run")
    args = parser.parse_args()
    raw = args.source.read_bytes()
    with ZipFile(io.BytesIO(raw)) as source:
        metadata_names = [n for n in source.namelist() if n.endswith("_animation.json")]
        if len(metadata_names) != 1:
            raise ValueError("Expected one animation metadata file")
        metadata = json.loads(source.read(metadata_names[0]))
        names = sorted(n for n in source.namelist() if n.startswith("edited/") and n.endswith(".png"))
        frames = [Image.open(io.BytesIO(source.read(n))).convert("RGBA") for n in names]
    if (len(frames) < 7 or len(metadata["frames"]) != len(frames) or metadata["fps"] != 24
            or any(f.size != (128, 96) for f in frames)
            or any(f.get("durationTicks", 1) != 1 for f in metadata["frames"])):
        raise ValueError("Expected at least seven 128x96 frames, one tick each at 24 fps")
    gait = args.gait or ("attack" if "STRIKE" in metadata_names[0].upper() else
                         "walk" if "WALKING" in metadata_names[0].upper() else "run")
    if gait == "attack" and len(frames) != 33:
        raise ValueError("Expected the 33-frame double strike for hit frames 13 and 25")
    archive = ROOT / "export/pixelstudio" / {"walk": "base-cop-walking", "run": "base-cop", "attack": "base-cop-strike"}[gait]
    archive.mkdir(parents=True, exist_ok=True)
    archive_path = archive / args.source.name
    archive_path.write_bytes(raw)
    out = ROOT / "godot/art/enemies/cop"
    # Anchors are approximate until the artist supplies sockets; all are foot-relative.
    anchors = {"head": [0, -75], "eye": [11, -67], "eye_far": [2, -67],
               "chest": [0, -43], "hand_n": [25, -38], "hand_f": [-25, -35],
               "muzzle": [31, -45]}
    clips = {gait + "_start": range(3), gait: range(3, len(frames) - 3),
             gait + "_stop": range(len(frames) - 3, len(frames))}
    if gait == "run": clips["idle"] = [0]
    if gait == "attack": clips = {"attack": range(len(frames))}
    for state, indices in clips.items():
        indices = list(indices)
        art = Image.new("RGBA", (128 * len(indices), 96))
        normal = Image.new("RGBA", art.size)
        for slot, index in enumerate(indices):
            frame = frames[index]
            art.paste(frame, (slot * 128, 0))
            # This export has no authored normal map. Neutral normals retain the
            # supplied shading and receive scene lighting without guessed geometry.
            flat = Image.new("RGBA", frame.size, (128, 128, 255, 0))
            flat.putalpha(frame.getchannel("A"))
            normal.paste(flat, (slot * 128, 0))
        art.save(out / f"cop_{state}.png")
        normal.save(out / f"cop_{state}_n.png")
        # Keep the existing editor's "Open Godot character" source lookup working.
        empty_rgba = base64.b64encode(bytes(128 * 96 * 4)).decode()
        empty_mask = base64.b64encode(bytes(128 * 96)).decode()
        editor_frames = []
        for index in indices:
            pixels = base64.b64encode(frames[index].tobytes()).decode()
            editor_frames.append({"base": pixels, "original": pixels, "overlay": empty_rgba,
                                  "mask": empty_mask, "cels": {}, "poses": {}, "hold": 1,
                                  "socket": None, "maps": {}, "gradientBoxes": [], "gradientBoxIndex": -1})
        editor_path = archive / f"cop-{state}.pixelstudio"
        editor_path.write_text(json.dumps({"format": "pixel-motion-studio", "version": 2,
                              "godotSource": None, "width": 128, "height": 96, "fps": 24,
                              "currentFrame": 0, "activeLayer": "base", "palette": [],
                              "settings": {}, "frames": editor_frames,
                              "layers": [{"id": "base", "name": "Base", "visible": True, "locked": False, "opacity": 100},
                                         {"id": "art", "name": "Overlay", "visible": True, "locked": False, "opacity": 100}]},
                             separators=(",", ":")))
        clip = {"format": "enemy-edited-clip-v1", "kind": "cop", "animation": state,
                "frame_width": 128, "frame_height": 96, "frame_count": len(indices),
                "fps": 24, "holds": [1] * len(indices), "origin": [64, 96],
                "anchors": [anchors.copy() for _ in indices],
                "source_archive": archive_path.relative_to(ROOT).as_posix(),
                "source_project": editor_path.relative_to(ROOT).as_posix(),
                "source_sha256": hashlib.sha256(raw).hexdigest(),
                "source_frames": [i + 1 for i in indices], "normal_mode": "flat"}
        if state == "attack":
            clip.update(loop=False, hit_frames=[12, 24])  # zero-based; contacts on frames 13 and 25
        (out / f"cop_{state}.json").write_text(json.dumps(clip, indent=2) + "\n")
    manifest_path = ROOT / "godot/art/enemies/edited.json"
    manifest = json.loads(manifest_path.read_text())
    for state in clips:
        if state not in manifest.setdefault("cop", []):
            manifest["cop"].append(state)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    if gait == "attack":
        print("Installed native 128x96 cop strike: 33 frames, 24 fps; contacts on frames 13 and 25")
    else:
        print(f"Installed native 128x96 cop {gait}: start 1-3, loop 4-{len(frames)-3}, "
              f"stop {len(frames)-2}-{len(frames)}; 24 fps")


if __name__ == "__main__":
    main()
