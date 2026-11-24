"""Loopback-only Godot adapter and PixelStudio launcher. Uses only Python's standard library."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import webbrowser

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SOURCE = Path("enemies/enemy_painter.gd")
DOCTOR_SOURCE = Path("character/villain.gd")
DOCTOR_SETUPS = ("primary-sword", "primary-knife", "dual-sword", "dual-knife")
PORT = 8766


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError("The enemy painter changed; its PixelStudio adapter needs updating: " + old[:65])
    return text.replace(old, new, 1)


def instrument(source: str) -> str:
    """Capture drawing stages without modifying the original project or guessing pixel masks."""
    source = replace_once(source, 'const Pixels = preload("res://character/pixel_canvas.gd")',
                          'const Pixels = preload("res://character/pixel_canvas.gd")\nconst Capture = preload("res://capture_canvas.gd")')
    start = source.index("func _humanoid(")
    end = source.index("\nfunc ", start + 1)
    humanoid = replace_once(source[start:end], 'var c := Pixels.new(cell.w, cell.h); var p := Pen.new(c, 0, 0)',
                            'var c := Capture.new(cell.w, cell.h); var p := Pen.new(c, 0, 0)')
    source = source[:start] + humanoid + source[end:]
    source = replace_once(source, '\t\t_cape(p, s.cape, sh_back, sh_front, hip_y, fy, pose.cape, lean, hero)',
                          '\t\tc.part("cape", sh_back, "torso")\n\t\t_cape(p, s.cape, sh_back, sh_front, hip_y, fy, pose.cape, lean, hero)')
    source = replace_once(source, '\tif s.hair_style == "long": _long_hair(p, s.hair, head, hr, hip_y)',
                          '\tif s.hair_style == "long":\n\t\tc.part("back-hair", head, "torso")\n\t\t_long_hair(p, s.hair, head, hr, hip_y)')
    source = replace_once(source, '\t# torso\n\t_torso', '\t# torso\n\tc.part("torso", Vector2(cx, hip_y))\n\t_torso')
    source = replace_once(source, '\t# head\n\t_head', '\t# head\n\tc.part("head", Vector2(head.x, top_y + 2), "torso")\n\t_head')
    for call, key in [('_hair(p, s, h, r)', 'hair'), ('_face(p, s, kind, h, r, pose)', 'face'), ('_hat(p, s, h, r)', 'hat')]:
        source = replace_once(source, '\t' + call + '\n', '\tp.target.part("' + key + '", h, "head")\n\t' + call + '\n')
    source = replace_once(source, '\t\telif prop != "": _prop(p, prop, hand_n, pose)',
                          '\t\telif prop != "":\n\t\t\tc.part("baton", hand_n, "near-hand")\n\t\t\t_prop(p, prop, hand_n, pose)')
    source = replace_once(source, '\t_seg(p, sh, elbow, w, sleeve, base)',
                          '\tvar side := "far" if far else "near"\n\tp.target.part(side + "-upper-arm", sh, "torso")\n\t_seg(p, sh, elbow, w, sleeve, base)')
    source = replace_once(source, '\t_seg(p, elbow, hand, maxf(3.0, w - 1), fore, base + 1)',
                          '\tp.target.part(side + "-forearm", elbow, side + "-upper-arm")\n\t_seg(p, elbow, hand, maxf(3.0, w - 1), fore, base + 1)')
    source = replace_once(source, '\tvar hcol: String = s.hands if s.hands != "" else s.skin',
                          '\tp.target.part(side + "-hand", hand, side + "-forearm")\n\tvar hcol: String = s.hands if s.hands != "" else s.skin')
    source = replace_once(source, '\t_seg(p, hip, knee, w, pants, base)',
                          '\tvar side := "far" if far else "near"\n\tp.target.part(side + "-thigh", hip, "torso")\n\t_seg(p, hip, knee, w, pants, base)')
    source = replace_once(source, '\t_seg(p, knee, foot - Vector2(0, 2), maxf(3.0, w - 1), shin, base + 1)',
                          '\tp.target.part(side + "-shin", knee, side + "-thigh")\n\t_seg(p, knee, foot - Vector2(0, 2), maxf(3.0, w - 1), shin, base + 1)')
    source = replace_once(source, '\tif pointed:   # flying: boot hangs toe-down',
                          '\tp.target.part(side + "-foot", foot, side + "-shin")\n\tif pointed:   # flying: boot hangs toe-down')
    return source


def find_godot(explicit: str | None = None) -> str:
    candidates = [explicit, os.environ.get("GODOT_PATH"), shutil.which("godot"), shutil.which("godot4")]
    installed = Path.home() / "Tools" / "Godot"
    if installed.exists():
        candidates += [str(p) for p in sorted(installed.glob("**/*console.exe"), reverse=True)]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(Path(candidate).resolve())
    raise ValueError("Godot was not found. Set GODOT_PATH or launch with --godot PATH.")


def copy_dependencies(project: Path, destination: Path, relative: Path, seen: set[str]) -> None:
    key = relative.as_posix()
    if key in seen:
        return
    path = (project / relative).resolve()
    if not path.is_relative_to(project) or path.suffix != ".gd" or not path.is_file():
        raise ValueError("Missing or unsupported Godot dependency: " + key)
    seen.add(key)
    text = path.read_text(encoding="utf-8-sig")
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    for dependency in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', text):
        copy_dependencies(project, destination, Path(dependency), seen)


def _job(project: Path, parent: Path, adapted: str) -> tempfile.TemporaryDirectory:
    temp = tempfile.TemporaryDirectory(prefix="godot-character-", dir=parent)
    job = Path(temp.name)
    copy_dependencies(project, job, SOURCE, set())
    (job / "project.godot").write_text('config_version=5\n[application]\nconfig/name="PixelStudio Character Bridge"\n', encoding="utf-8")
    (job / "adapter_painter.gd").write_text(adapted, encoding="utf-8")
    for name in ["capture_canvas.gd", "export_character.gd"]:
        shutil.copyfile(HERE / name, job / name)
    return temp


def _run(godot: str, job: Path, *args: str) -> str:
    command = [godot, "--headless", "--path", str(job), "--log-file", str(job / "godot.log"),
               "--script", "res://export_character.gd", "--", *args]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    log = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR:" in log or "ERROR:" in log:
        raise ValueError("Godot could not export the character. " + log[-3500:])
    return log


def character_catalog(project: Path, godot: str) -> list[dict]:
    """Every kind and state the game's enemy painter bakes, read from the painter itself."""
    parent = REPO / ".local"
    parent.mkdir(exist_ok=True)
    adapted = instrument((project / SOURCE).read_text(encoding="utf-8-sig"))
    with _job(project, parent, adapted) as temp:
        log = _run(godot, Path(temp), "--catalog")
    line = next(l for l in log.splitlines() if l.startswith("CATALOG:"))
    return json.loads(line[len("CATALOG:"):])


def export_character(project: Path, godot: str, animation: str, output: Path, kind: str = "cop") -> dict:
    if not re.fullmatch(r"[a-z_]+", kind) or not re.fullmatch(r"[a-z_]+", animation):
        raise ValueError("Unknown character or animation.")
    source = (project / SOURCE).read_text(encoding="utf-8-sig")
    adapted = instrument(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    # The isolated helper contains only required drawing scripts: no game's autoloads,
    # project import, user saves, or changes to the game's resource cache.
    output.unlink(missing_ok=True)
    with _job(project, output.parent, adapted) as temp:
        _run(godot, Path(temp), kind, animation, str(output))
    if not output.is_file():
        raise ValueError("Godot did not write the character project.")
    data = json.loads(output.read_text(encoding="utf-8"))
    data["godotSource"].update(project=str(project), sha256=hashlib.sha256(source.encode()).hexdigest())
    output.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    return data


def current_edited_character(project: Path, animation: str, kind: str = 'cop'):
    """Prefer the editable source that is installed in the game's current art metadata."""
    if not re.fullmatch(r"[a-z_]+", kind) or not re.fullmatch(r"[a-z_]+", animation):
        raise ValueError("Unknown character or animation.")
    metadata_file = project / 'art' / 'enemies' / kind / f'{kind}_{animation}.json'
    if not metadata_file.is_file():
        return None
    metadata = json.loads(metadata_file.read_text(encoding='utf-8'))
    root = project.parent.resolve()
    relative = Path(metadata.get('source_project', ''))
    source = (root / relative).resolve()
    if relative.is_absolute() or not source.is_relative_to(root) or source.suffix != '.pixelstudio' or not source.is_file():
        raise ValueError(f'The edited {kind} source project is missing. Restore the source_project named in its game art metadata.')
    data = json.loads(source.read_text(encoding='utf-8'))
    if (data.get('format'), data.get('version'), data.get('width'), data.get('height'), len(data.get('frames', []))) != (
            'pixel-motion-studio', 2, metadata['frame_width'], metadata['frame_height'], metadata['frame_count']):
        raise ValueError(f'The edited {kind} source does not match the installed game clip.')
    return data, source


def export_doctor(project: Path, godot: str, setup: str, output: Path) -> dict:
    if setup not in DOCTOR_SETUPS:
        raise ValueError("Choose a primary or dual sword/knife setup.")
    source = (project / DOCTOR_SOURCE).read_text(encoding='utf-8-sig')
    marker = 'for segment in [[Vector2.ZERO,elbow],[elbow,grip]]:'
    capture = '''var part_index := 0
\tfor segment in [[Vector2.ZERO,elbow],[elbow,grip]]:
\t\tif p.target.has_method("part"):
\t\t\tvar prefix: String = p.target.get_meta("hand")
\t\t\tvar joint := Vector2(p.ox,p.oy)+(Vector2.ZERO if part_index == 0 else elbow)
\t\t\tp.target.part(prefix+("upper-arm" if part_index == 0 else "forearm"),joint,"doctor-body" if part_index == 0 else prefix+"upper-arm")
\t\tpart_index += 1'''
    adapted = replace_once(source, marker, capture)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='godot-doctor-', dir=output.parent) as temp:
        job = Path(temp)
        copy_dependencies(project, job, DOCTOR_SOURCE, set())
        (job / DOCTOR_SOURCE).write_text(adapted, encoding='utf-8')
        gear = job / 'character' / 'art' / 'gear.json'
        gear.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / 'character' / 'art' / 'gear.json', gear)
        for name in ['capture_canvas.gd', 'export_doctor.gd']:
            shutil.copyfile(HERE / name, job / name)
        (job / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Doctor Melee Editor"\n', encoding='utf-8')
        # Hand-drawn body skins (art_renderer.gd body_skin) are textures, so they must be imported first.
        for skin in (project / 'character' / 'art').iterdir():
            if skin.is_dir() and (skin / 'body.json').is_file():
                target = job / 'character' / 'art' / skin.name
                target.mkdir(parents=True, exist_ok=True)
                for name in ['body.json', 'body.png', 'body_height.png']:
                    shutil.copyfile(skin / name, target / name)
                subprocess.run([godot, '--headless', '--path', str(job), '--import'], capture_output=True, text=True, timeout=120,
                               creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
                break
        result = subprocess.run([godot, '--headless', '--path', str(job), '--log-file', str(job / 'godot.log'),
                                 '--script', 'res://export_doctor.gd', '--', setup, str(output)],
                                capture_output=True, text=True, timeout=90,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        log = result.stdout + result.stderr
        if result.returncode or 'SCRIPT ERROR:' in log or 'ERROR:' in log or not output.is_file():
            raise ValueError('Could not export the doctor: ' + log[-3500:])
    data = json.loads(output.read_text(encoding='utf-8'))
    data['godotSource'].update(project=str(project), sha256=hashlib.sha256(source.encode()).hexdigest())
    output.write_text(json.dumps(data, separators=(',', ':')), encoding='utf-8')
    return data


NAMES = {"cop": "Basic cop", "swat": "SWAT", "det": "Detective", "riot": "Riot cop", "dog": "K9 dog",
         "drone": "Police drone", "undercover_hood": "Undercover (hood)", "swat_shield": "SWAT shield",
         "robodog": "Robo-dog", "vex_sentry": "Vex sentry", "vex_mine": "Vex mine"}


def display_name(kind: str) -> str:
    if kind in NAMES:
        return NAMES[kind]
    if kind.startswith("hero_"):
        return "Hero · " + kind[5:].capitalize()
    if kind.startswith("civ_"):
        return "Civilian · " + kind[4:].capitalize()
    return kind.replace("_", " ").capitalize()


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, project: Path, editor: Path, godot: str):
        super().__init__(address, Handler)
        self.project, self.editor, self.godot = project, editor, godot
        self.token = secrets.token_urlsafe(32)
        self.export_lock = threading.Lock()
        self.kinds = {entry["id"]: entry for entry in character_catalog(project, godot)}


class Handler(BaseHTTPRequestHandler):
    server: BridgeServer

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

    def permitted(self) -> bool:
        host = self.headers.get("Host", "")
        origin = self.headers.get("Origin")
        port = self.server.server_port
        return host in {f"127.0.0.1:{port}", f"localhost:{port}"} and origin in {
            None, "null", f"http://127.0.0.1:{port}", f"http://localhost:{port}"}

    def send(self, status: int, value, mime="application/json"):
        raw = json.dumps(value).encode() if mime == "application/json" else value
        self.send_response(status)
        self.send_header("Content-Type", mime + "; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if self.permitted() and self.headers.get("Origin"):
            self.send_header("Access-Control-Allow-Origin", self.headers["Origin"])
            self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self):
        if not self.permitted():
            self.send(403, {"error": "Only the local PixelStudio editor can use this bridge."})
            return
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "null"))
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-PixelStudio-Token")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if not self.permitted():
            self.send(403, {"error": "This bridge only accepts local editor requests."})
            return
        route = urlsplit(self.path).path
        if route == "/api/godot/catalog":
            self.send(200, {"bridge": "pixelstudio-godot-v1", "token": self.server.token,
                            "project": str(self.server.project), "script": SOURCE.as_posix(),
                            "characters": [
                                {"id": kind, "name": display_name(kind), "script": SOURCE.as_posix(),
                                 "family": entry["family"], "animations": list(entry["states"]),
                                 "frames": entry["states"]} for kind, entry in self.server.kinds.items()] + [
                                {"id": "doctor", "name": "Doctor · editable melee", "script": DOCTOR_SOURCE.as_posix(),
                                 "animations": list(DOCTOR_SETUPS)}]})
        elif route in {"/", "/index.html"}:
            text = (self.server.editor / "index.html").read_text(encoding="utf-8-sig")
            if 'src="godot-character.js"' not in text:
                text = text.replace("</body>", '<script src="godot-character.js"></script>\n</body>')
            self.send(200, text.encode(), "text/html")
        elif route == "/godot-character.js":
            self.send(200, (HERE / "godot-character.js").read_bytes(), "text/javascript")
        elif route == "/favicon.ico":
            self.send(204, b"", "image/x-icon")
        else:
            self.send(404, {"error": "Not found"})

    def do_POST(self):
        if not self.permitted() or self.headers.get("X-PixelStudio-Token") != self.server.token:
            self.send(403, {"error": "Reconnect to the local Godot bridge."})
            return
        if urlsplit(self.path).path != "/api/godot/open":
            self.send(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 300_000:
                raise ValueError("The Godot request is too large or empty.")
            request = json.loads(self.rfile.read(length))
            character = request.get('character', 'cop')
            if character != 'doctor' and character not in self.server.kinds:
                raise ValueError('Choose a character from the list.')
            source_path = DOCTOR_SOURCE if character == 'doctor' else SOURCE
            if request.get('script', source_path.as_posix()) != source_path.as_posix():
                raise ValueError('Choose the matching character script: ' + source_path.as_posix())
            if request.get("source") is not None:
                selected = request["source"].replace("\r\n", "\n").lstrip("\ufeff")
                actual = (self.server.project / source_path).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
                if selected != actual:
                    raise ValueError("Choose this project's " + source_path.as_posix() + '. The selected file does not match it.')
            if not self.server.export_lock.acquire(blocking=False):
                self.send(409, {"error": "Godot is already preparing a character. Wait for that import to finish."})
                return
            try:
                animation = request.get('animation', 'dual-sword' if character == 'doctor' else 'walk')
                if character == 'doctor':
                    if animation not in DOCTOR_SETUPS:
                        raise ValueError('Choose a primary or dual sword/knife setup.')
                    output = REPO / 'export' / 'pixelstudio' / 'doctor-melee' / f'doctor-{animation}.pixelstudio'
                    if output.is_file():
                        data = json.loads(output.read_text(encoding='utf-8'))
                    else:
                        data = export_doctor(self.server.project,self.server.godot,animation,output)
                else:
                    if animation not in self.server.kinds[character]['states']:
                        raise ValueError('Choose one of ' + ', '.join(self.server.kinds[character]['states']))
                    current = current_edited_character(self.server.project, animation, character)
                    if current is not None:
                        data, output = current
                    else:
                        output = REPO / 'export' / 'pixelstudio' / f'{character}-{animation}' / f'{character}-{animation}.pixelstudio'
                        data = export_character(self.server.project, self.server.godot, animation, output, character)
                self.send(200, {"project": data, "file": str(output)})
            finally:
                self.server.export_lock.release()
        except (ValueError, OSError, subprocess.TimeoutExpired) as error:
            self.send(400, {"error": str(error)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=REPO / "godot")
    parser.add_argument("--editor", type=Path, default=REPO.parent / "video to frames")
    parser.add_argument("--godot")
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--open", action="store_true")
    parser.add_argument("--export", metavar="STATE", help="export one clip, e.g. walk; use with --character")
    parser.add_argument('--export-doctor', choices=DOCTOR_SETUPS)
    parser.add_argument('--character', default='cop', help="doctor, or any enemy_painter kind (cop, swat, hero_vex...)")
    parser.add_argument('--animation')
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    project = args.project.resolve()
    if not (project / SOURCE).is_file():
        parser.error("Project must contain enemies/enemy_painter.gd.")
    godot = find_godot(args.godot)
    if args.export_doctor:
        output = (args.output or REPO / 'export' / 'pixelstudio' / 'doctor-melee' / f'doctor-{args.export_doctor}.pixelstudio').resolve()
        data = export_doctor(project,godot,args.export_doctor,output)
        print(f'Saved {output}: {len(data["layers"])} editable layers.')
        return
    if args.export:
        kind = args.character
        output = (args.output or REPO / "export" / "pixelstudio" / f"{kind}-{args.export}" / f"{kind}-{args.export}.pixelstudio").resolve()
        data = export_character(project, godot, args.export, output, kind)
        print(f"Saved {output}: {len(data['frames'])} frames, {len(data['layers'])} linked parts.")
        return
    editor = args.editor.resolve()
    animation = args.animation or ('dual-sword' if args.character == 'doctor' else 'walk')
    if args.character == 'doctor' and animation not in DOCTOR_SETUPS:
        parser.error('Choose a valid doctor setup.')
    editor_url = f'http://127.0.0.1:{args.port}/?godot={args.character}&animation={animation}'
    if not (editor / "index.html").is_file():
        parser.error("PixelStudio index.html was not found. Supply --editor FOLDER.")
    try:
        server = BridgeServer(("127.0.0.1", args.port), project, editor, godot)
    except OSError as error:
        # A second launcher should reuse our existing server, not start a duplicate.
        from urllib.request import urlopen
        try:
            with urlopen(f"http://127.0.0.1:{args.port}/api/godot/catalog", timeout=2) as response:
                existing = json.load(response)
            if existing.get("bridge") != "pixelstudio-godot-v1" or Path(existing["project"]) != project:
                raise ValueError("A different service is using the bridge port.")
        except Exception:
            raise SystemExit(f"Could not start PixelStudio on port {args.port}: {error}") from error
        if args.open: webbrowser.open(editor_url)
        return
    print(f"PixelStudio + Godot: http://127.0.0.1:{args.port}/", flush=True)
    if args.open: webbrowser.open(editor_url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
