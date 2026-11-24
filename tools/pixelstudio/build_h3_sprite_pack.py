"""Prepare REF2VA sprite experiments, deterministic motion guides and a shot list.

No model inference, downloads, ComfyUI installation changes or generation queue submissions.
The colored mannequin and grip proxies are geometric calibration diagrams, not final game art.
"""
from pathlib import Path
from PIL import Image, ImageDraw
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
import copy
import json
import math
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "export/comfyui/scientist-modular"
INPUT_SUBDIR = "MadVillain_Modular_20261123"
COMFY = Path.home() / "AppData/Local/Comfy-Desktop/ComfyUI-Installs/ComfyUI/ComfyUI"
SHARED = Path.home() / "AppData/Local/Comfy-Desktop/ComfyUI-Shared"
SOURCE = Path.home() / "Downloads/DaSiWa MiniMaxH3 MythicAlchemy C-MMH3-33.json"
PALETTE = {
    "head": "#f3cd36", "neck": "#9b59b6", "torso": "#7040dc", "pelvis": "#ec31a1",
    "near_shoulder": "#1f77ff", "near_upper_arm": "#fa3030", "near_forearm": "#ff8c21", "near_hand": "#f2b49b",
    "far_shoulder": "#a4e2ff", "far_upper_arm": "#13d6e7", "far_forearm": "#128884", "far_hand": "#b2ffe0",
    "near_thigh": "#8acc22", "near_shin": "#364fe5", "near_foot": "#fe7198",
    "far_thigh": "#7b8d23", "far_shin": "#9c246b", "far_foot": "#c2c9db",
}


def endpoint(p, angle, length):
    a = math.radians(angle)
    return (p[0] + math.cos(a) * length, p[1] + math.sin(a) * length)


def arm_pose(t, study, behind_head=False):
    if study == "natural-raise":
        # Forearm leads while the upper arm stays level, then the shoulder
        # raises as the elbow opens. The overhead hold is already straight.
        keys=[(0,0,0),(.75,0,0),(1.,0,-90),(1.4,-90,0),
              (2.2,-90,0),(3.2,0,0),(3.7,0,0),(3.95,0,-90),
              (4.35,-90,0),(5.,-90,0)]
        for (ta,a,b),(tb,c,d) in zip(keys,keys[1:]):
            if t<=tb:
                k=max(0,min(1,(t-ta)/(tb-ta)));k=k*k*(3-2*k)
                return a+(c-a)*k,b+(d-b)*k
        return -90,0
    if study.startswith("straight-recoil-"):
        base={"level":0,"up":-90,"down":90}[study.rsplit('-',1)[1]]
        kick=0.0
        for trigger in [1.0,2.25,3.5]:
            age=t-trigger
            if 0<=age<.25: kick=max(kick,min(age/.04,1)*max(0,1-(age-.04)/.21))
        return base+kick*(3 if base==-90 else -3),0
    if study == "straight-sweep":
        progress=max(0,min(1,(t-.5)/3.75))
        return 90-180*progress,0
    if study == "elbow":
        return 0, -120 * (0.5 - 0.5 * math.cos(t * math.tau / 2.5))
    keys = [(0, 25, -25), (.5, 25, -25), (1.0, 90, -25), (1.7, 45, -30),
            (2.3, 0, -30), (3.0, -45, -30), (3.6, -90, 30),
            (4.2, 0, -130 if behind_head else -110), (4.9, 25, -25)]
    for (ta, a, b), (tb, c, d) in zip(keys, keys[1:]):
        if t <= tb:
            k = max(0, min(1, (t - ta) / (tb - ta)))
            k = k * k * (3 - 2 * k)
            return a + (c-a)*k, b + (d-b)*k
    return 25, -25


def mannequin(t, study, head_in_front=False, moving_arm="near", subject_layout=False):
    im = Image.new("RGB", (768, 768), "#14202b")
    d = ImageDraw.Draw(im)
    joints = {}
    def capsule(name, a, b, width):
        d.line([a, b], fill=PALETTE[name], width=width)
        r = width / 2
        for x, y in (a, b): d.ellipse((x-r, y-r, x+r, y+r), fill=PALETTE[name])
    def arm(side, shoulder, upper, bend, prop=False):
        elbow = endpoint(shoulder, upper, 84)
        wrist = endpoint(elbow, upper + bend, 96)
        capsule(side+"_upper_arm", shoulder, elbow, 30)
        capsule(side+"_forearm", elbow, wrist, 25)
        if prop:
            # Green calibration pistol: grip point at the wrist, barrel forward.
            local = [(-9,-36), (82,-36), (82,-10), (10,-10), (10,20), (-9,20)]
            angle = math.radians(upper + bend)
            poly = [(wrist[0]+x*math.cos(angle)-y*math.sin(angle), wrist[1]+x*math.sin(angle)+y*math.cos(angle)) for x,y in local]
            d.polygon(poly, fill="#00ff00")
        d.ellipse((wrist[0]-15,wrist[1]-16,wrist[0]+15,wrist[1]+16), fill=PALETTE[side+"_hand"])
        d.ellipse((shoulder[0]-18,shoulder[1]-18,shoulder[0]+18,shoulder[1]+18), fill=PALETTE[side+"_shoulder"])
        joints[side] = {"shoulder": shoulder, "elbow": elbow, "wrist": wrist}
    upper,bend = arm_pose(t,study,head_in_front) if study != "walk" else (25,-25)
    # A far-arm study is painted before the torso; its shoulder and elbow stay
    # behind the body. Near-arm studies retain the foreground draw pass.
    arm("far", (418 if subject_layout else 350,287), upper if moving_arm == "far" else 68,
        bend if moving_arm == "far" else -30, moving_arm == "far")
    phase = t * math.tau * 1.2
    for side, x, offset in [("far",367,math.pi),("near",405,0)]:
        stride = 38 * math.sin(phase+offset) if study == "walk" else 0
        lift = max(0, math.cos(phase+offset)) * 23 if study == "walk" else 0
        hip = (x,466); ankle = (x+stride,675-lift)
        # Exact two-bone IK: retain 112px thighs and shins throughout each stride.
        dx,dy=ankle[0]-hip[0],ankle[1]-hip[1]
        distance=math.hypot(dx,dy);half=distance*.5
        knee_bend=math.sqrt(112**2-half**2)
        knee=(hip[0]+dx*.5+dy/distance*knee_bend,hip[1]+dy*.5-dx/distance*knee_bend)
        capsule(side+"_thigh",hip,knee,46)
        capsule(side+"_shin",knee,ankle,36)
        d.rounded_rectangle((ankle[0]-20,ankle[1]-5,ankle[0]+45,ankle[1]+25),radius=9,fill=PALETTE[side+"_foot"])
        joints[side+"_leg"] = {"hip":hip,"knee":knee,"ankle":ankle}
    d.polygon([(341,443),(425,443),(431,480),(341,480)],fill=PALETTE["pelvis"])
    d.polygon([(331,278),(435,278),(422,446),(344,446)],fill=PALETTE["torso"])
    d.rectangle((369,235,401,281),fill=PALETTE["neck"])
    d.ellipse((310,118,458,246),fill=PALETTE["head"])
    arm("near",(350 if subject_layout else 418,287),upper if moving_arm == "near" else 68,
        bend if moving_arm == "near" else -30,moving_arm == "near")
    # The behind-head calibration motion explicitly requires the skull to occlude
    # the forearm, hand and prop. This is not a universal rule for all aiming poses.
    if head_in_front: d.ellipse((310,118,458,246),fill=PALETTE["head"])
    joints["head"] = (384,182); joints["pelvis"] = (384,464)
    return im,joints


def render_guides(refs, behind_head=False, studies=None, moving_arm="near"):
    ffmpeg = next((COMFY/".venv/Lib/site-packages/imageio_ffmpeg/binaries").glob("ffmpeg*.exe"))
    for study in (studies if studies is not None else (("shoulder",) if behind_head else ("shoulder", "elbow", "walk"))):
        name=f"puppet-{'far-' if moving_arm == 'far' else ''}{study}"+("-behind-head-v2" if behind_head else "")
        video = refs/f"{name}.mp4"
        process = subprocess.Popen([str(ffmpeg),"-loglevel","error","-y","-f","rawvideo","-pixel_format","rgb24",
            "-video_size","768x768","-framerate","24","-i","-","-an","-c:v","libx264","-crf","12",
            "-pix_fmt","yuv420p","-movflags","+faststart",str(video)],stdin=subprocess.PIPE,stderr=subprocess.PIPE)
        frames=[]
        for i in range(120):
            im,joints=mannequin(i/24,study,behind_head,moving_arm)
            process.stdin.write(im.tobytes())
            frames.append({"frame":i,"time":i/24,"joints":joints})
            if i==0: im.save(refs/f"{name}.png")
        process.stdin.close()
        error=process.stderr.read();code=process.wait()
        if code: raise RuntimeError(error.decode(errors="replace"))
        (refs/f"{name}-joints.json").write_text(json.dumps(frames,indent=2))
    (refs/"puppet-palette.json").write_text(json.dumps(PALETTE,indent=2))


def prop_reference(refs, rod=False):
    im=Image.new("RGB",(768,768),"#14202b");d=ImageDraw.Draw(im)
    if rod: d.rounded_rectangle((210,348,610,396),radius=10,fill="#00ff00")
    else: d.polygon([(185,283),(610,283),(610,380),(330,380),(330,530),(242,530),(242,380),(185,380)],fill="#00ff00")
    im.save(refs/("proxy-rod.png" if rod else "proxy-grip.png"))


SHOT_ROWS = [
 ("01-near-shoulder",5,"shoulder","Only the foreground near arm moves. Follow the shoulder sweep and elbow positions in <Video 1>. All other body parts, feet and expression stay still. Grip the proxy throughout."),
 ("02-near-elbow",5,"elbow","Only the near forearm and hand move. Keep its upper arm horizontal toward screen-right. Repeatedly bend the elbow to bring the hand toward the shoulder, then straighten, slowly, with brief holds. Follow <Video 1>."),
 ("03-near-elbow-up",5,None,"Only the near arm moves. Hold the upper arm 45 degrees upward toward screen-right. Slowly fold and straighten the elbow twice, with brief holds at both extremes. Keep the shoulder rooted."),
 ("04-near-elbow-down",5,None,"Only the near arm moves. Hold the upper arm 45 degrees downward toward screen-right. Slowly fold and straighten the elbow twice, with brief holds at both extremes. Keep the shoulder rooted."),
 ("05-near-wrist",5,None,"Only the near wrist and hand move. Keep the upper arm and elbow stationary in a forward aiming pose. Slowly tilt the grip up, level, and down, then return level. Retain the same fingers around the same handle."),
 ("06-far-shoulder",5,None,"Only the background far arm moves. Slowly aim down, diagonally down-right, horizontally right, diagonally up-right and upward, then return horizontal. Keep the near arm, torso, head, feet and expression fixed. Respect occlusion behind the body."),
 ("07-far-elbow",5,None,"Only the far forearm and hand move. Keep its upper arm horizontal toward screen-right. Slowly fold the elbow, hold, straighten, hold, repeat once. Keep the near arm and all other body parts still."),
 ("08-far-wrist",5,None,"Only the far wrist and hand move. Hold its upper arm and elbow fixed in a forward aiming pose. Slowly tilt the held grip up, level and down, then return level. Preserve hand anatomy and grip."),
 ("09-idle",5,None,"Hold a relaxed ready stance in place. Subtle breathing only; feet stay planted, arms retain their fixed aiming position, expression remains unchanged. End in the initial pose. Do not blink or speak in this take."),
 ("10-blink",5,None,"Keep the entire body and arms stationary. Make one brief natural blink behind the glasses in the middle of the take, then hold the original face. Do not change the grin or add facial hair."),
 ("11-walk",5,"walk","Walk in place facing screen-right, following the stepping rhythm of <Video 1>. The pelvis stays centered; alternate grounded foot contacts and lifted recovery feet. Keep both arms in the same aiming pose. The coat tails and hair move subtly."),
 ("12-run",5,None,"Run in place facing screen-right at a steady pace for several complete strides. Use clear push-off, airborne and landing poses. Keep the pelvis centered and the arms in their fixed aiming position. Hair and coat tails follow the motion."),
 ("13-backpedal",5,None,"Walk backward in place while still facing and aiming screen-right. Show a controlled backward stepping cycle with alternating foot contacts. Keep framing, body scale and pelvis location fixed. Arms retain the same aiming pose."),
 ("14-start-stop",6,None,"Hold the ready pose for one second. Start walking in place with a small weight shift, complete several strides, slow naturally and return to the identical ready stance for the final second. Keep aiming arms steady."),
 ("15-hurt",4,None,"Hold ready for one second. Make one brief readable recoil from a harmless impact: shoulders pull back, knees flex, expression tightens. Recover fully to the same ready pose and hold. Keep both feet near their original positions. No blood or added effects."),
 ("16-fall",6,None,"Hold ready for one second, stagger, bend the knees and fall sideways onto the ground in one continuous motion. Settle and hold the final fallen pose for the last second. Keep the camera fixed and the entire fallen body inside the original canvas. No blood or disintegration."),
 ("17-stunned",5,None,"Stand in place with knees slightly bent and a gentle unsteady sway, retaining the same identity and clothing. Recover to ready at the end. No stars, electricity, halos or other added visual effects."),
 ("18-near-recoil",5,None,"Only the near arm performs three separate firing-recoil actions aimed horizontally screen-right. Each action is a quick backward hand movement with a small elbow bend, followed by a complete return and a clear pause. Keep the proxy rigid. No flash, projectile or smoke."),
 ("19-far-recoil",5,None,"Only the far arm performs three separate firing-recoil actions aimed horizontally screen-right. Each action has a quick hand kick, small elbow bend, full return and clear pause. Keep the near arm and body still. No flash, projectile or smoke."),
 ("20-dual-recoil",5,None,"Hold one identical proxy in each hand, both aimed screen-right. Recoil the near hand, settle, recoil the far hand, settle, then recoil both together and settle. Keep feet and torso still; retain two distinct arms and grips. No muzzle effects."),
 ("21-charge-release",5,None,"Hold the proxy aimed screen-right. Slowly brace the near arm and tense the elbow for a charged shot, pause, make one stronger recoil, and fully recover. Keep feet planted. No glow, flash, projectile or smoke."),
 ("22-grapple-cast",5,None,"Hold ready for one second. Extend the near arm diagonally upward-right to cast a grapple, pause with a firm grip, then retract to ready. The proxy stays attached and rigid. No generated hook, rope, cable, projectile or effects."),
 ("23-grapple-brace",5,None,"Brace as if a taut cable were pulling from the near hand diagonally upward-right. Lean back slightly, bend both knees with feet planted, and hold the arm under tension. Release the tension and return ready. Keep the proxy rigid. Do not draw a cable."),
 ("24-near-thrust",5,None,"Grip the green rod firmly in the near hand. Hold ready for one second, draw the elbow back, make one clear forward thrust, pause at extension, then recover and hold. Keep the rod rigid and the hand attached; do not add a blade or effects."),
 ("25-near-slash",5,None,"Grip the green rod in the near hand. Raise that hand above the shoulder, briefly hold the anticipation pose, make one clear diagonal downward slash toward screen-right, follow through and recover fully. Feet remain planted. No slash trails or added weapon details."),
 ("26-near-reverse-slash",5,None,"Grip the green rod in the near hand. Prepare low beside the hip, sweep upward diagonally toward screen-right, follow through above shoulder height, then recover ready. Show one complete action with clear anticipation and recovery. No added effects."),
 ("27-near-whip-cast",5,None,"Keep a rigid grip on the green proxy. Draw the near hand backward with a bent elbow, then cast it forward with a clear wrist snap and recover. Show one complete whip-casting arm motion. Do not generate a whip, rope, cable, trail or projectile."),
 ("28-far-thrust",5,None,"Grip the green rod in the far hand. Hold ready, draw that elbow back, make one forward thrust toward screen-right, then recover fully. Keep the near arm steady. Respect occlusion and preserve the rigid prop and attached hand."),
 ("29-far-slash",5,None,"Grip the green rod in the far hand. Raise it above that shoulder, pause, make one diagonal downward slash toward screen-right, follow through and recover. Keep the near arm steady and feet planted. No added effects."),
 ("30-far-whip-cast",5,None,"Only the far arm performs one whip-casting gesture: draw its hand backward with a bent elbow, snap forward, then recover. Maintain a firm grip on the rigid green proxy. Keep the near arm still. Do not generate a whip or effects."),
 ("31-kick",5,None,"Hold ready, shift weight onto the far leg, lift the near knee, extend one forward kick toward screen-right, retract the knee and put the foot back in its original place. Recover and hold. Keep the aiming arms stable."),
 ("32-stomp",5,None,"Hold ready, lift the near knee high while balancing on the far leg, pause, then stamp the near foot down firmly onto its original ground position. Recover ready. No target, debris, shockwave or camera shake."),
 ("33-leap-land",6,None,"Hold ready, crouch, jump vertically without sideways travel, show a clear airborne pose, land with bent knees, then return to the same ready position. Keep the full body visible. No dust, shockwave or camera movement."),
 ("34-airborne",5,None,"Hold a stable airborne pose with both knees bent and feet clear of the ground. Keep the body centered, arms aimed screen-right, with only slight coat and hair motion. No flames, jets, glowing boots or generated effects."),
 ("35-dash",5,None,"Hold ready, make a quick forward-leaning acceleration pose with tucked arms and a long rear-leg extension, then decelerate and recover. Perform the motion in place without changing canvas position. No streaks or camera motion."),
 ("36-device-activate",5,None,"Hold ready. Bring the near hand toward the chest, make one clear deliberate thumb-button activation gesture while gripping the same proxy, then return to ready. Keep the head, far arm and feet still. No new device, hologram or effects."),
]

COMMON = ("One continuous fixed-camera sprite animation study. Preserve the scientist from <Picture 1>: "
    "same face, wild white hair, black glasses, grin, burgundy shirt, white laboratory coat, trousers, shoes, "
    "proportions, palette and pixel-art shading. Do not add a mustache or redesign any part. "
    "Use <Picture 2> only for the held calibration prop. Keep it matte green, rigid and at a consistent size; "
    "fingers wrap around its handle and correctly occlude it. The prop must not merge with the hand or sleeve. "
    "The near arm is the foreground arm; the far arm is behind the torso. "
    "Use the same three-quarter right-facing view throughout. Locked orthographic-style camera, identical "
    "zoom and framing, no cuts, no orbit, no tracking, no perspective change. Full character occupies about "
    "75 percent of the square canvas height, centered, with the ground line at 91 percent from the top. "
    "Leave room for fully extended arms and props. Flat uniform dark blue-gray background. "
    "Keep identity, body scale and limb lengths stable. Move only the parts explicitly requested below. "
    "No extra fingers or limbs, detached parts, costume changes, dialogue, text or logos.")


def fields_for(row):
    name,seconds,motion,action=row
    definitions = ("<Subject 1> is the mad scientist shown in <Picture 1>.\n"
                   "<Picture 1> defines the scientist's appearance and visual style.\n"
                   "<Picture 2> defines only the held green calibration prop.")
    retention = ("<Picture 1> (character appearance): fully_preserved - retain face, hair, glasses, clothing, proportions and pixel-art style.\n"
                 "<Picture 2> (held object): fully_preserved - retain prop shape, matte green color, scale and grip orientation.")
    if motion:
        definitions += "\n<Video 1> is a colored mannequin motion guide, not the target character."
        retention += "\n<Video 1> (motion and composition): partially_preserved - transfer joint poses, motion timing, fixed camera and grounding; ignore mannequin colors, shapes and surface appearance."
    detail=COMMON+"\n[Shot 1] "+action
    if motion: detail+=" Transfer motion only from <Video 1>; never render the colored mannequin in the output."
    return {"subject_definitions": definitions,
            "summary": "[reference generation] Animate <Subject 1> using the supplied character, prop and optional motion references.",
            "retention_analysis": retention,"detailed_description": detail,
            "overall_soundscape":"Silent. No speech, sound effects or music.","non_diegetic_music":"N/A"}


def workflow_for(original,row):
    result=copy.deepcopy(original);result['id']=str(uuid.uuid4());result['revision']=0
    row_id,seconds,motion,action=row;fields=fields_for(row)
    prompt="\n\n".join(f"{key}:\n{value}" for key,value in fields.items())
    ref={**fields,"soundscape":fields['overall_soundscape'],"music":"N/A"}
    builder={"version":2,"mode":"REF2VA","prompt_mode":"simple","simple_prompt":prompt,"duration":seconds,"ref":ref}
    item_name="proxy-rod.png" if any(k in row_id for k in ('thrust','slash')) else "proxy-grip.png"
    items=[]
    for slot,(filename,label,instructions) in enumerate([
        ("scientist.png","character-1","Use only this scientist's identity, costume, proportions and pixel-art style."),
        (item_name,"custom","Use only the green prop design and grip geometry. Do not transfer the background.")]):
        items.append({"id":"sprite-subject" if slot==0 else "sprite-item","type":"image","value":f"{INPUT_SUBDIR}/{filename}",
            "enabled":True,"order":slot,"slot":slot,"start":slot,"duration":1,
            "source_width":1254 if slot==0 else 768,"source_height":1254 if slot==0 else 768,
            "prompt":instructions,"forge_label":label,"forge_role":"subject" if slot==0 else "custom",
            "forge_subject_group":"A" if slot==0 else "","forge_instructions":instructions})
    # A disabled placeholder keeps the video lane visible without contaminating unrelated shots.
    items.append({"id":"sprite-motion","type":"video","value":f"{INPUT_SUBDIR}/puppet-{motion or 'shoulder'}.mp4",
        "enabled":bool(motion),"order":2,"slot":0,"start":0,"duration":5,"source_duration":5,
        "source_width":768,"source_height":768,"trim_start":0,"trim_end":5,"media_mode":"video",
        "prompt":"Motion and fixed camera only. Can be replaced by a Blender-rendered Mixamo animation.",
        "forge_role":"pose","forge_instructions":"Transfer skeletal movement, timing and framing only. Ignore the mannequin's identity and colors."})
    timeline={"version":1,"items":items,"prompt_blocks":[],"builder_state":builder,"resolved_prompt":prompt,
        "resolution":{"aspect":"1:1","resolution":"custom","input_scaling":"Auto","custom_mode":"fixed","custom_width":768,"custom_height":768},
        "refmods":[],"continuity":{"version":3,"output_mode":"full","source_kind":"checkpoint","source_id":"","source_video_id":"","source_video":None,
            "use_references":False,"operation":"new","capture":False,"session":"sprite_"+uuid.uuid4().hex,
            "overlap_frames":22,"continuation_prompt":"","idea":""}}
    director=next(n for n in result['nodes'] if n['type']=='MiniMaxH3Director')
    director['title']="Scientist: Subject + Item + Motion / "+row_id
    values={"mode":"REF2VA","prompt":prompt,"width":768,"height":768,"duration":seconds,"ref_image_size":"match",
        "timeline_data":json.dumps(timeline,separators=(',',':')),"builder_state":json.dumps(builder,separators=(',',':')),
        "frame_rate":24,"minimax_h3_director_ui":""}
    director['widgets_values_named']=values
    director['widgets_values']=[values[k] for k in values]
    settings=next(n for n in result['nodes'] if n.get('title')=='Settings')
    mapping={
        "unet_name":"dasiwa_minimax_h3_ref2va_v5xs_pruned_graviton_int8_row-wise_convrot_runtime_mixed.safetensors",
        "unet_name_1":"dasiwa_minimax_h3_ref2va_v5xs_pruned_graviton_int8_row-wise_convrot_runtime_mixed.safetensors",
        "clip_name":"qwen3vl_32b_heretic_minimax_h3_nvfp4.safetensors",
        "vae_name":"minimax_h3_video_vae_fp16.safetensors","vae_name_1":"minimax_h3_audio_vae_fp32.safetensors"}
    keys=list(settings['widgets_values_named'])
    for key,value in mapping.items():
        settings['widgets_values_named'][key]=value;settings['widgets_values'][keys.index(key)]=value
    combine=next(n for n in result['nodes'] if n['type']=='DaSiWa_EnhancedVideoCombine')
    combine['widgets_values'][8]="video/mad-villain-sprite/"+row_id+"/%date:hhmmss%"
    if 'widgets_values_named' in combine: combine['widgets_values_named']['filename_prefix']=combine['widgets_values'][8]
    # Change the existing quick-start note rather than installing an extra custom node.
    note=next(n for n in result['nodes'] if n.get('title')=='🚀 Quick Start Guide')
    note['title']="Sprite reference test: read first"
    note['widgets_values']=["Subject = Picture 1; held item = Picture 2; optional motion = Video 1.\n\n"
        "This copy uses REF2VA and installed model filenames. Keep the scientist and prop as two separate image tiles. "
        "Replace the video tile with a fixed-camera, 24fps Mixamo/Blender render to transfer its motion. Set duration/trim to match. "
        "The guide video transfers poses and framing, not guaranteed pixel-exact skeletal control.\n\n"
        "Select a tile and paste/upload a replacement to preserve its reference order. Keep motion disabled for unrelated animation prompts. "
        "All output is 24fps with interpolation and upscaling left disabled. Green is a removable grip proxy; hand extraction and sockets still need cleanup."]
    return result,prompt,item_name


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--skip-guides',action='store_true');args=parser.parse_args()
    PACK.mkdir(parents=True,exist_ok=True);refs=PACK/'references';refs.mkdir(exist_ok=True)
    original=json.loads(SOURCE.read_text(encoding='utf-8-sig'))
    shutil.copyfile(Path.home()/'Downloads/mad scientist.png',refs/'scientist.png')
    prop_reference(refs);prop_reference(refs,True)
    if not args.skip_guides: render_guides(refs)
    manifest=[];text=[]
    with ZipFile(PACK/'shot-workflows.zip','w',ZIP_DEFLATED) as z:
        for row in SHOT_ROWS:
            workflow,prompt,item=workflow_for(original,row)
            data=json.dumps(workflow,ensure_ascii=False,indent=2)
            z.writestr(row[0]+'.json',data)
            if row[0]=='01-near-shoulder': (PACK/'Scientist-Subject-Item-Motion-REF2VA.json').write_text(data,encoding='utf-8')
            manifest.append({"id":row[0],"seconds":row[1],"fps":24,"item_reference":item,
                "motion_reference":"puppet-"+row[2]+".mp4" if row[2] else None,"prompt":prompt})
            text.append(f"{row[0]} | {row[1]} seconds | 24 fps | prop: {item} | motion: {row[2] or 'DISABLED'}\n\n{prompt}\n")
    (PACK/'animation-commissions.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (PACK/'animation-prompts.txt').write_text('\n'+'\n'.join(text),encoding='utf-8')
    print(f"Prepared {len(manifest)} shots, {sum(r[1] for r in SHOT_ROWS)} requested seconds; {PACK}")


if __name__=='__main__': main()
