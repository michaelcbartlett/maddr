"""Stage the narrowly scoped PixelStudio additions before installing them in its repository."""
from pathlib import Path
import argparse
import shutil
import hashlib
import json
from bridge import replace_once


def patch_editor(text: str) -> str:
    if 'src="godot-character.js"' in text:
        return text
    text = replace_once(text, 'let W = 0, H = 0, cur = 0, fps = 12;',
                        'let W = 0, H = 0, cur = 0, fps = 12;\nlet godotSource = null;')
    text = replace_once(text, "const project={format:'pixel-motion-studio',version:2,width:W,height:H,fps,currentFrame:cur,palette,layers:layerDefs",
                        "const project={format:'pixel-motion-studio',version:2,godotSource,width:W,height:H,fps,currentFrame:cur,palette,layers:layerDefs")
    text = replace_once(text, 'function initializeProject(imgs,w,h){stopPlay();',
                        'function initializeProject(imgs,w,h){godotSource=null;stopPlay();')
    text = replace_once(text, "dirtyProject=false;status('Project restored with layers, maps, timing and weapon anchors.');",
                        "godotSource=p.godotSource&&typeof p.godotSource==='object'?p.godotSource:null;dirtyProject=false;status('Project restored with layers, maps, timing and weapon anchors.');")
    start = text.index('function validatePose(')
    end = text.index('\nconst bodyPartNames=', start)
    validator = replace_once(text[start:end], '  return out;',
                            "  if(p.attachmentAngle!==undefined){if(!Number.isFinite(p.attachmentAngle)||Math.abs(p.attachmentAngle)>1e7)throw Error('Invalid weapon direction');out.attachmentAngle=p.attachmentAngle;}\n  return out;")
    text = text[:start] + validator + text[end:]
    return replace_once(text, '</body>', '<script src="godot-character.js"></script>\n</body>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--editor', type=Path, default=Path(r'E:\repos\video to frames'))
    parser.add_argument('--stage', type=Path, default=Path(__file__).resolve().parents[2] / '.local' / 'pixelstudio-editor')
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=True)
    (args.stage / 'index.html').write_text(patch_editor((args.editor / 'index.html').read_text(encoding='utf-8-sig')), encoding='utf-8')
    shutil.copyfile(Path(__file__).with_name('godot-character.js'), args.stage / 'godot-character.js')
    readme = (args.editor / 'PIXEL-STUDIO-README.md').read_text(encoding='utf-8-sig')
    section = Path(__file__).with_name('EDITOR-README.md').read_text(encoding='utf-8')
    if '## Open a Godot character' not in readme:
        readme += '\n\n' + section
    (args.stage / 'PIXEL-STUDIO-README.md').write_text(readme, encoding='utf-8')
    manifest = {name: hashlib.sha256((args.editor / name).read_bytes()).hexdigest()
                for name in ['index.html', 'PIXEL-STUDIO-README.md']}
    (args.stage / 'original-hashes.json').write_text(json.dumps(manifest), encoding='utf-8')
    launcher = '@echo off\ncall "%~dp0..\\mad villain\\Open PixelStudio.bat"\n'
    (args.stage / 'Open PixelStudio with Godot.bat').write_text(launcher, encoding='utf-8')
    print(args.stage)


if __name__ == '__main__':
    main()
