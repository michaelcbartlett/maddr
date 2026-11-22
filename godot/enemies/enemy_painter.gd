extends RefCounted
## Procedural enemy / NPC / boss pixel art at 1 px per world px, using the character's albedo+height
## rasterizer (res://character/pixel_canvas.gd), pen and height profiles, so enemies share the scientist's
## hue-shifted shading, selective outlines and OpenGL normal maps.
## paint(kind, state, frame) returns an un-outlined PixelCanvas; EnemySheets outlines it and builds maps.
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Profiles = preload("res://character/height_profiles.gd")
const Machines = preload("res://enemies/machine_painter.gd")

# ---------------------------------------------------------------- layout
## Cell size, foot point inside the cell (before the 1 px outline pad) and how far below the node origin
## the feet stand in the world (so y-sorting lines up with the scientist, whose feet are ~20 px below his origin).
const CELLS = {
	"human": {"w": 64, "h": 64, "cx": 30, "fy": 61, "foot": 15},
	"hero": {"w": 104, "h": 100, "cx": 50, "fy": 96, "foot": 24},
	"dog": {"w": 52, "h": 40, "cx": 26, "fy": 37, "foot": 9},
	"drone": {"w": 44, "h": 40, "cx": 22, "fy": 37, "foot": 9},
	"vehicle": {"w": 112, "h": 84, "cx": 55, "fy": 61, "foot": 0},
}

## Which states each family bakes, and how many frames each state has.
const HUMAN_STATES = {"idle": 4, "walk": 8, "attack": 3, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1}
const CIV_STATES = {"idle": 4, "walk": 8, "panic": 8, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1}
const DOG_STATES = {"idle": 2, "walk": 6, "attack": 3, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1}
const DRONE_STATES = {"idle": 4, "walk": 4, "attack": 2, "hurt": 1, "death": 4, "frozen": 1, "stunned": 2}
const HERO_STATES = {
	"vex": {"idle":2,"walk":6,"hurt":1,"death":4,"frozen":1,"stunned":1,"attack":3,"aim":2,"deploy":2},
	"ironclad": {"idle": 2, "walk": 6, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1, "windup": 2, "charge": 2, "air": 1, "slam": 1},
	"surge": {"idle": 2, "walk": 6, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1, "blink": 3, "cast": 2},
	"viper": {"idle":2, "walk":6, "hurt":1, "death":4, "frozen":1, "stunned":1, "windup":2, "charge":2, "cast":2},
	"glacia": {"idle": 2, "walk": 6, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1, "throw": 2, "nova": 3},
	"paragon": {"idle": 4, "walk": 4, "hurt": 1, "death": 4, "frozen": 1, "stunned": 1, "dive": 1, "laser": 2},
}

## Sprite keys (Enemy.spr values) -> family + spec.
const KINDS = ["cop", "swat", "det", "riot", "dog", "drone", "civ_suit", "civ_tourist", "civ_granny", "civ_jogger",
	"hero_ironclad", "hero_surge", "hero_glacia", "hero_paragon", "hero_viper", "hero_vex", "vex_sentry", "vex_mine",
	"undercover", "undercover_hood", "swat_shield", "guard", "interceptor", "robodog", "tank"]

static func family(kind: String) -> String:
	if kind.begins_with("hero_"): return "hero"
	if kind == "dog" or kind == "robodog": return "dog"
	if kind == "interceptor" or kind == "tank": return "vehicle"
	if kind in ["drone","vex_sentry","vex_mine"]: return "drone"
	return "human"

static func states(kind: String) -> Dictionary:
	if kind.begins_with("hero_"):
		var result: Dictionary = HERO_STATES[kind.substr(5)].duplicate()
		if kind != "hero_paragon": result.idle = 4; result.walk = 8
		return result
	if kind.begins_with("civ_"): return CIV_STATES
	if kind == "dog" or kind == "robodog" or family(kind) == "vehicle": return DOG_STATES
	if kind in ["drone","vex_sentry","vex_mine"]: return DRONE_STATES
	return HUMAN_STATES

# ---------------------------------------------------------------- palettes / specs
const SKIN = {"a": "#e8a878", "b": "#c58a5e", "c": "#f0c8a8", "d": "#8a5a3c", "e": "#e0a070"}
const SPECS = {
	"hero_vex": {"skin":"#e8b696","hair":"#582d62","hair_style":"long","hat":"","top":"#e4e9e6","sleeve":"#d4dfdc",
		"pants":"#40334f","shin":"#40334f","shoes":"#253545","belt":"#685077","badge":"#6bf5ef","prop":"dual_blaster","torso":"labcoat","hands":"#695078",
		"build":{"hr":9,"tw":21,"th":23,"leg":24,"arm":19,"aw":5,"lw":6,"fist":4}},
	"undercover": {"skin":"#c58a5e", "hair":"#201a18", "hair_style":"short", "hat":"",
		"top":"#9b6445", "sleeve":"#9b6445", "pants":"#416a9b", "shin":"#416a9b", "shoes":"#f0ede4", "belt":"#29252b",
		"badge":"#efc854", "prop":"revolver", "torso":"suit", "hands":"", "trainers":true, "shades":true},
	"undercover_hood": {"skin":"#e8b088", "hair":"#302728", "hair_style":"messy", "hat":"headband", "hat_col":"#233348",
		"top":"#607867", "sleeve":"#607867", "pants":"#313d59", "shin":"#313d59", "shoes":"#f8f2de", "belt":"#252c37",
		"badge":"#efc854", "prop":"revolver", "torso":"cardigan", "hands":"", "trainers":true},
	"swat_shield": {"skin":"#c58a5e", "hair":"#17171b", "hair_style":"none", "hat":"swat", "hat_col":"#222e3b",
		"top":"#283846", "sleeve":"#334553", "pants":"#222e3a", "shin":"#334553", "shoes":"#10151e", "belt":"#111a24",
		"badge":"#d1edf1", "prop":"rifle", "torso":"vest", "hands":"#161e28", "ballistic_shield":true, "build":{"tw":19}, "kneepads":true},
	"guard": {"skin":"#8a5a3c", "hair":"#211e18", "hair_style":"none", "hat":"swat", "hat_col":"#66744b",
		"top":"#78825b", "sleeve":"#69754d", "pants":"#69774c", "shin":"#69774c", "shoes":"#453b2d", "belt":"#464d33",
		"badge":"#ded8a0", "prop":"rifle", "torso":"vest", "hands":"#4a513a", "camo":true, "build":{"tw":19}, "kneepads":true, "chinstrap":true},
	"cop": {"skin": "#e8a878", "hair": "#3a2a1e", "hair_style": "short", "hat": "police",
		"top": "#3157c0", "sleeve": "#3157c0", "pants": "#1d2c6b", "shin": "#1d2c6b", "shoes": "#17171c", "belt": "#121420",
		"hat_col": "#1b2558", "badge": "#ffd23c", "prop": "baton", "torso": "uniform", "hands": ""},
	"swat": {"skin": "#c58a5e", "hair": "#1a1410", "hair_style": "none", "hat": "swat",
		"top": "#323844", "sleeve": "#3c4350", "pants": "#2a2f38", "shin": "#2a2f38", "shoes": "#0e0e12", "belt": "#16171b",
		"hat_col": "#2c313b", "badge": "#e4ecf4", "prop": "rifle", "torso": "vest", "hands": "#1a1a1e", "build": {"tw": 18}, "kneepads": true},
	"det": {"skin": "#f0c8a8", "hair": "#4a3420", "hair_style": "short", "hat": "fedora",
		"top": "#b08a52", "sleeve": "#b08a52", "pants": "#4a3a2e", "shin": "#4a3a2e", "shoes": "#2a1a12", "belt": "#5a3d22",
		"hat_col": "#5a3d22", "badge": "#c83030", "prop": "revolver", "torso": "trench", "hands": ""},
	"riot": {"skin": "#d89a6a", "hair": "#2a1a10", "hair_style": "none", "hat": "riot",
		"top": "#33405e", "sleeve": "#33405e", "pants": "#252e45", "shin": "#3a4866", "shoes": "#101218", "belt": "#151a26",
		"hat_col": "#2a3550", "badge": "#7ab8d8", "prop": "shield", "torso": "armor", "hands": "#181c26", "build": {"tw": 20, "aw": 6, "lw": 7}},
	"civ_suit": {"skin": "#e8b088", "hair": "#4a3020", "hair_style": "slick", "hat": "",
		"top": "#3a3f4a", "sleeve": "#3a3f4a", "pants": "#2a2e36", "shin": "#2a2e36", "shoes": "#111111", "belt": "#111111",
		"badge": "#c83030", "prop": "briefcase", "torso": "suit", "hands": ""},
	"civ_tourist": {"skin": "#f0b890", "hair": "#e8c860", "hair_style": "messy", "hat": "sunhat",
		"top": "#e85a9a", "sleeve": "#e85a9a", "pants": "#d8c090", "shin": "#f0b890", "shoes": "#8a5a30", "belt": "#8a5a30",
		"hat_col": "#e8d08a", "badge": "#ffd23c", "prop": "camera", "torso": "hawaiian", "hands": "", "short_sleeve": true},
	"civ_granny": {"skin": "#e8b8a0", "hair": "#e8e8f0", "hair_style": "bun", "hat": "",
		"top": "#8a5ab0", "sleeve": "#8a5ab0", "pants": "#6a4a8a", "shin": "#c8a8a0", "shoes": "#3a2a20", "belt": "#6a4a8a",
		"badge": "#d0b0e0", "prop": "handbag", "torso": "cardigan", "hands": "", "skirt": true, "glasses": true, "build": {"hr": 8, "th": 15, "leg": 15, "arm": 13}},
	"civ_jogger": {"skin": "#8a5a3c", "hair": "#2a1a10", "hair_style": "afro", "hat": "headband",
		"top": "#30c0a0", "sleeve": "#8a5a3c", "pants": "#222a3a", "shin": "#8a5a3c", "shoes": "#f0f0f0", "belt": "#222a3a",
		"hat_col": "#ffffff", "badge": "#ffffff", "prop": "", "torso": "tank", "hands": "", "short_sleeve": true},
	"hero_ironclad": {"skin": "#e0a070", "hair": "#3a2a1a", "hair_style": "none", "hat": "great_helm",
		"top": "#7488a0", "sleeve": "#6a7e96", "pants": "#3a4656", "shin": "#7a8ea6", "shoes": "#2e3846", "belt": "#e8b830",
		"hat_col": "#8a9eb4", "badge": "#e8b830", "cape": "#2448b0", "prop": "", "torso": "plate", "hands": "#9aaec4",
		"build": {"hr": 10, "tw": 30, "th": 24, "leg": 21, "arm": 21, "aw": 9, "lw": 10, "fist": 6}},
	"hero_surge": {"skin": "#d8a070", "hair": "#ffe14a", "hair_style": "spikes", "hat": "mask",
		"top": "#2030a0", "sleeve": "#2030a0", "pants": "#1a2680", "shin": "#ffd23c", "shoes": "#ffd23c", "belt": "#ffd23c",
		"hat_col": "#111122", "badge": "#fff36b", "prop": "", "torso": "bolt", "hands": "#ffd23c",
		"build": {"hr": 9, "tw": 21, "th": 22, "leg": 22, "arm": 20, "aw": 6, "lw": 7, "fist": 4}},
	"hero_viper": {"skin":"#e8b898", "hair":"#2a142e", "hair_style":"long", "hat":"mask", "hat_col":"#241e30",
		"top":"#392340", "sleeve":"#392340", "pants":"#76637b", "shin":"#76637b", "shoes":"#221a30", "belt":"#d74d96",
		"badge":"#ff90ca", "prop":"", "torso":"viper_suit", "hands":"#312538", "stockings":true,
		"build":{"hr":9, "tw":19, "th":23, "leg":25, "arm":19, "aw":5, "lw":6, "fist":4}},
	"hero_glacia": {"skin": "#f0c8b0", "hair": "#e8f8ff", "hair_style": "long", "hat": "ice_crown",
		"top": "#bfe8ff", "sleeve": "#8ccff4", "pants": "#bfe8ff", "shin": "#bfe8ff", "shoes": "#3a8ad0", "belt": "#3a8ad0",
		"hat_col": "#7ad0ff", "badge": "#3a8ad0", "prop": "", "torso": "gown", "hands": "#d8f4ff", "skirt": true, "gown": true,
		"cape": "#7ad0ff", "build": {"hr": 9, "tw": 20, "th": 21, "leg": 22, "arm": 19, "aw": 5, "lw": 6, "fist": 4}},
	"hero_paragon": {"skin": "#e0a070", "hair": "#f0f0f0", "hair_style": "swept", "hat": "visor", "hat_col": "#ff8a20",
		"top": "#3a1a5a", "sleeve": "#3a1a5a", "pants": "#3a1a5a", "shin": "#3a1a5a", "shoes": "#ff8a20", "belt": "#ff8a20",
		"badge": "#ff8a20", "cape": "#ff8a20", "prop": "", "torso": "omega", "hands": "#ff8a20", "eyes": "#ff8a20",
		"build": {"hr": 9, "tw": 26, "th": 23, "leg": 21, "arm": 20, "aw": 8, "lw": 8, "fist": 5}},
}
const DEFAULT_BUILD = {"hr": 8, "tw": 17, "th": 17, "leg": 17, "arm": 15, "aw": 5, "lw": 6, "fist": 3}

static func shade(hex: String, amount: float) -> String:
	return Pixels.shade(hex, amount)

# ---------------------------------------------------------------- entry
## Anchor points (cell pixels) of the most recent humanoid paint: hand_n, hand_f, head, eye, muzzle.
var anchors := {}

func paint(kind: String, state: String, i: int) -> Pixels:
	anchors = {}
	if kind in ["interceptor", "tank", "robodog", "vex_sentry", "vex_mine"]:
		var machine := Machines.new()
		var canvas: Pixels = machine.paint(kind, state, i)
		anchors = machine.anchors
		return canvas
	match family(kind):
		"dog": return _dog(state, i)
		"drone": return _drone(state, i)
	var cell: Dictionary = CELLS[family(kind)]
	var pose := _pose(kind, state, i)
	if state == "death":
		return _death(kind, pose, i, cell)
	var c := _humanoid(kind, pose, cell)
	if state == "frozen": _ice_crust(c, cell, 11 if kind.begins_with("hero_") else 7)
	if kind == "hero_surge" and state == "blink": _streak(c, i, "#fff36b")
	return c

# ---------------------------------------------------------------- poses
const WALK_DX = [6, 3, 0, -3, -6, -3, 1, 5]
const WALK_LIFT = [0, 0, 0, 0, 0, 3, 5, 3]
const WALK_BOB = [0, 1, 1, 0, 0, 1, 1, 0]

func _pose(kind: String, state: String, i: int) -> Dictionary:
	var hero := kind.begins_with("hero_")
	var k := 1.35 if hero else 1.0
	var p := {"bob": 0, "lean": 0, "fdx": 0.0, "flift": 0.0, "bdx": 0.0, "blift": 0.0,
		"an": 8.0, "an_bend": 15.0, "af": -8.0, "af_bend": 15.0, "eyes": "open", "mouth": "flat",
		"head_dx": 0, "head_dy": 0, "prop": "carry", "crouch": 0, "cape": 0, "skirt": 0, "glow": 0.0, "hover": false, "pointed": false}
	if kind == "hero_paragon": p.hover = true
	match state:
		"idle":
			p.bob = [0, 0, 1, 0][i % 4]; p.cape = [0, 1, 2, 1][i % 4]; p.skirt = p.bob
			p.an_bend += p.bob * 3.0; p.af_bend -= p.bob * 3.0
			if p.hover: p.bob = [0, 1, 2, 1][i % 4]; p.cape = i; p.fdx = 1; p.bdx = -2
		"walk", "panic":
			var f := i % 8; var g := (i + 4) % 8
			var stride := k * (1.3 if state == "panic" else 1.0)
			p.fdx = WALK_DX[f] * stride; p.flift = WALK_LIFT[f] * stride
			p.bdx = WALK_DX[g] * stride; p.blift = WALK_LIFT[g] * stride
			p.bob = WALK_BOB[f]; p.an = -WALK_DX[f] * 4.0 - 4.0; p.af = WALK_DX[f] * 4.0 + 4.0
			p.cape = [1, 0, 0, 1, 2, 3, 3, 2][f]; p.skirt = [0, -1, -1, 0, 0, 1, 1, 0][f]
			p.an_bend = 12.0 + WALK_LIFT[g] * 5.0; p.af_bend = 12.0 + WALK_LIFT[f] * 5.0
			if state == "panic":
				p.lean = 2; p.eyes = "wide"; p.mouth = "open"; p.prop = "flail"
				p.an = 150.0 + (25.0 if f % 2 == 0 else -15.0); p.an_bend = -30.0
				p.af = 160.0 + (-20.0 if f % 2 == 0 else 20.0); p.af_bend = -30.0
			if kind == "hero_surge":
				p.lean = 4; p.an = -WALK_DX[f] * 7.0; p.af = WALK_DX[f] * 7.0; p.an_bend = 70.0; p.af_bend = 70.0
				p.mouth = "grin"
			if p.hover:
				f = i % 4; p.bob = [0, 1, 2, 1][f]; p.fdx = 2; p.bdx = -1; p.lean = 2; p.cape = f; p.an = -20.0; p.af = 30.0
		"attack":
			p.mouth = "grit"; p.prop = "attack"
			match kind:
				"cop":
					p.an = [200.0, 95.0, 40.0][i]; p.an_bend = [-40.0, 10.0, 10.0][i]; p.lean = [-1, 2, 2][i]
				"swat", "swat_shield", "guard":
					p.an = [66.0, 78.0, 58.0][i]; p.an_bend = [70.0, 0.0, 30.0][i]; p.lean = [-1, 3, 1][i]
					p.af = [80.0, 95.0, 70.0][i]; p.af_bend = [40.0, 0.0, 30.0][i]
				"det", "undercover", "undercover_hood":
					p.an = [74.0, 84.0, 76.0][i]; p.an_bend = [0.0, -14.0, 0.0][i]; p.lean = [0, -1, 0][i]; p.mouth = "flat"
					p.af = 20.0; p.prop = ["aim", "recoil", "aim"][i]
				"riot":
					p.an = [40.0, 80.0, 60.0][i]; p.an_bend = [60.0, 10.0, 40.0][i]; p.lean = [-1, 3, 1][i]; p.fdx = [0.0, 4.0, 2.0][i]
					p.af = [175.0, 120.0, 60.0][i]; p.af_bend = [-30.0, 0.0, 30.0][i]
		"hurt":
			p.lean = -2; p.eyes = "shut"; p.mouth = "open"; p.head_dx = -1; p.an = -25.0; p.af = -35.0; p.an_bend = 30.0
			p.fdx = -2; p.bdx = 2
		"frozen":
			p.eyes = "wide"; p.mouth = "open"; p.an = 30.0; p.af = 20.0; p.an_bend = 40.0; p.fdx = 3; p.bdx = -3
		"stunned":
			p.eyes = "dizzy"; p.mouth = "wobble"; p.head_dx = 1; p.head_dy = 1; p.lean = -1; p.an = -5.0; p.af = 5.0
			p.an_bend = 5.0; p.crouch = 1; p.prop = "limp"
		"death":
			p.eyes = "x"; p.mouth = "open"; p.an = 150.0; p.af = 130.0; p.an_bend = 10.0; p.prop = "drop"
		# ---- boss powers
		"windup":   # ironclad: crouch, both fists raised high behind the head
			p.crouch = [2, 4][i]; p.an = [160.0, 185.0][i]; p.af = [165.0, 190.0][i]; p.an_bend = 30.0; p.af_bend = 30.0
			p.mouth = "grit"; p.lean = [-1, -3][i]; p.fdx = 5; p.bdx = -6; p.glow = [0.4, 1.0][i]
		"charge":
			p.lean = 6; p.an = [60.0, 30.0][i]; p.af = [20.0, 60.0][i]; p.an_bend = 80.0; p.af_bend = 80.0
			p.fdx = [8.0, -4.0][i]; p.bdx = [-6.0, 7.0][i]; p.flift = [2.0, 0.0][i]; p.blift = [0.0, 3.0][i]; p.mouth = "grit"; p.cape = 3
		"air":
			p.an = 170.0; p.af = 175.0; p.an_bend = 20.0; p.af_bend = 20.0; p.flift = 9; p.blift = 7; p.fdx = 3; p.bdx = -2
			p.mouth = "grit"; p.cape = 4; p.crouch = 3
		"slam":
			p.crouch = 6; p.an = 25.0; p.af = 15.0; p.an_bend = -5.0; p.af_bend = -5.0; p.lean = 4; p.fdx = 8; p.bdx = -8
			p.mouth = "grit"; p.glow = 1.0
		"blink":
			p.lean = 5; p.an = -40.0; p.af = 40.0; p.an_bend = 60.0; p.af_bend = 60.0; p.fdx = 7; p.bdx = -7; p.mouth = "grin"
		"cast":   # surge: arm thrust forward, crackling
			p.an = [80.0, 95.0][i]; p.an_bend = [20.0, 0.0][i]; p.af = -20.0; p.lean = [1, 2][i]; p.mouth = "grin"; p.glow = [0.5, 1.0][i]
			p.fdx = 4; p.bdx = -4
		"throw":   # glacia: shard fan
			p.an = [150.0, 68.0][i]; p.an_bend = [-30.0, 0.0][i]; p.af = -15.0; p.lean = [-1, 2][i]; p.glow = [0.6, 0.3][i]; p.skirt = [-1, 1][i]
		"nova":   # glacia: arms sweep up and out
			p.an = [40.0, 110.0, 165.0][i]; p.af = [-40.0, -110.0, -165.0][i]; p.an_bend = -10.0; p.af_bend = 10.0
			p.glow = [0.4, 0.7, 1.0][i]; p.head_dy = [0, -1, -1][i]; p.skirt = i - 1; p.mouth = "open"
		"dive":
			p.lean = 9; p.an = 160.0; p.af = 150.0; p.an_bend = 0.0; p.af_bend = 0.0; p.fdx = -10; p.bdx = -12; p.flift = 8; p.blift = 6
			p.cape = 5; p.mouth = "grit"
		"laser":
			p.head_dx = 1; p.mouth = "grit"; p.an = -10.0; p.af = 10.0; p.an_bend = 40.0; p.af_bend = 40.0; p.glow = [0.6, 1.0][i]
			p.eyes = "glow"; p.cape = i * 2
	if kind == "hero_paragon" and state != "death" and state != "dive":
		p.fdx = 2.0 if state != "walk" else 3.0; p.bdx = 0.0; p.flift = 0; p.blift = 2
		p.pointed = true
		if state in ["idle", "walk"]:
			p.an = -30.0; p.an_bend = 45.0; p.af = 35.0; p.af_bend = -55.0
	if kind == "hero_vex":
		if state in ["attack","aim"]:
			p.an = 82.0; p.an_bend = -4.0; p.af = 72.0; p.af_bend = 8.0
			p.lean = -1 if state == "attack" and i == 1 else 1; p.prop = "aim"; p.mouth = "grin"
			p.head_dx = i%2
		elif state == "deploy":
			p.an = 35.0+i*12; p.an_bend = 50.0; p.af = 65.0; p.af_bend = -15.0
			p.crouch = 2+i; p.prop = "carry"; p.mouth = "grin"
	# Armed patrols keep their weapon in a ready carry while the legs walk beneath it.
	if state in ["idle", "walk"]:
		if kind in ["swat", "swat_shield", "guard"]:
			p.an = 58.0 + p.bob * 2.0; p.an_bend = 24.0; p.af = 50.0; p.af_bend = 55.0
		elif kind in ["det", "undercover", "undercover_hood"]:
			p.an = 25.0 + p.bob * 2.0; p.an_bend = 38.0
		elif kind == "riot":
			p.an = 18.0; p.an_bend = 45.0; p.af = -12.0; p.af_bend = 28.0
	return p

# ---------------------------------------------------------------- humanoid
func _humanoid(kind: String, pose: Dictionary, cell: Dictionary) -> Pixels:
	var s: Dictionary = SPECS[kind]
	var bd: Dictionary = DEFAULT_BUILD.duplicate(); bd.merge(s.get("build", {}), true)
	var c := Pixels.new(cell.w, cell.h); var p := Pen.new(c, 0, 0)
	var cx: float = cell.cx; var fy: float = cell.fy
	var hero := kind.begins_with("hero_")
	var crouch: float = pose.crouch
	var bob: float = pose.bob
	var lean: float = pose.lean
	if pose.hover: fy -= 6
	var hip_y: float = fy - bd.leg - 1 + crouch + bob
	var top_y: float = hip_y - bd.th
	var tw: float = bd.tw
	var tx := cx - tw / 2.0 + lean * 0.5
	var hr: float = bd.hr
	var head := Vector2(cx + 1 + lean + pose.head_dx, top_y - hr + 3 + pose.head_dy)
	# Same convention as the scientist: the arm drawn in front of the torso hangs from the back-side
	# shoulder, the arm behind the torso from the front-side shoulder (legs are not swapped).
	var sh_back := Vector2(tx + 3, top_y + 3)
	var sh_front := Vector2(tx + tw - 3, top_y + 3)
	var sh_f := sh_front
	var sh_n := sh_back
	var hip_f := Vector2(cx - tw * 0.22 + lean * 0.3, hip_y)
	var hip_n := Vector2(cx + tw * 0.18 + lean * 0.3, hip_y)
	var lw: float = bd.lw; var aw: float = bd.aw
	var leg_len: float = bd.leg + 1
	var foot_f := Vector2(hip_f.x + pose.bdx, fy - pose.blift)
	var foot_n := Vector2(hip_n.x + pose.fdx, fy - pose.flift)
	var arm_len: float = bd.arm
	# the front arm starts at the back shoulder, so it stretches when it reaches forward (aiming, swinging)
	var arm_n: float = arm_len + maxf(0.0, sin(deg_to_rad(pose.an + pose.an_bend * 0.5))) * bd.tw * 0.4
	var hand_n := _arm_end(sh_n, pose.an, pose.an_bend, arm_n)
	var hand_f := _arm_end(sh_f, pose.af, pose.af_bend, arm_len)

	# cape / long hair behind everything
	if s.has("cape"):
		if s.get("gown", false): p.alpha = 0.6
		_cape(p, s.cape, sh_back, sh_front, hip_y, fy, pose.cape, lean, hero)
		p.alpha = 1.0
	if s.hair_style == "long": _long_hair(p, s.hair, head, hr, hip_y)
	if kind == "hero_viper":
		# Shoulder-mounted seeker pods, visible above the bodysuit and long hair.
		p.layer(5, Profiles.slab(tx-7,top_y-8,tx+1,top_y+10,3,1))
		p.R(tx-7,top_y-8,8,18,"#39384c"); p.R(tx-6,top_y-7,2,15,"#9d8caa")
		for tube in 3:
			p.R(tx-4,top_y-6+tube*5,5,3,"#161827"); p.P(tx-2,top_y-5+tube*5,"#ff90ca")
	# far arm
	_arm(p, s, sh_f, pose.af, pose.af_bend, arm_len, aw, 4.0, true, bd.fist)
	if s.prop == "dual_blaster" and pose.prop != "drop": _blaster(p,hand_f,pose,"#ed87ff",8)
	if s.prop == "shield" and pose.prop != "drop": _baton(p, hand_f, _dir(pose.af + pose.af_bend), 6.0)
	# far leg
	if not s.get("gown", false): _leg(p, s, hip_f, foot_f, leg_len, lw, 5.0, true, pose.pointed)
	if kind == "civ_granny" or s.get("skirt", false) and not s.get("gown", false):
		pass
	# torso
	_torso(p, s, kind, tx, top_y, tw, bd.th, hip_y, lean)
	if s.get("camo", false):
		p.layer(14)
		for patch in [Vector2(2, 4), Vector2(10, 8), Vector2(5, 13)]:
			p.R(tx + patch.x, top_y + patch.y, 5, 3, "#414d34")
			p.R(tx + patch.x + 2, top_y + patch.y - 1, 3, 2, "#b3aa78")
	# near leg
	_costume_details(p, s, kind, tx, top_y, tw, bd.th)
	if s.get("gown", false): _gown(p, s, tx, hip_y, tw, fy, pose.skirt)
	else: _leg(p, s, hip_n, foot_n, leg_len, lw, 9.0, false, pose.pointed)
	if s.get("skirt", false) and not s.get("gown", false): _skirt(p, s, tx, hip_y, tw, pose.skirt)
	if s.torso in ["trench","labcoat"]: _coat_tail(p, s, tx, hip_y, tw, pose)
	# head
	_head(p, s, kind, head, hr, pose)
	if kind == "hero_vex":
		# Brass-framed green laboratory goggles, with long violet hair behind the coat.
		p.layer(29); p.R(head.x-7,head.y-1,16,5,"#4e4258")
		p.R(head.x-6,head.y,6,3,"#78e1d6"); p.R(head.x+2,head.y,6,3,"#78e1d6")
		p.R(head.x-5,head.y,4,1,"#e4ffea"); p.P(head.x+4,head.y,"#e4ffea")
	if kind == "civ_tourist": _camera_on_chest(p, tx + tw - 5, top_y + 7)
	# near arm + prop
	var prop: String = s.prop
	if prop == "shield":
		_arm(p, s, sh_n, pose.an, pose.an_bend, arm_n, aw, 16.0, false, bd.fist)
		_shield(p, hand_n, fy, pose)
	else:
		if prop != "": _prop_behind(p, prop, hand_n, pose)
		_arm(p, s, sh_n, pose.an, pose.an_bend, arm_n, aw, 16.0, false, bd.fist)
		if prop == "dual_blaster" and pose.prop != "drop": _blaster(p,hand_n,pose,"#6bf5ef",22)
		elif prop != "": _prop(p, prop, hand_n, pose)
	if s.get("ballistic_shield", false) and pose.prop != "drop":
		# A separate near-side shield leaves the assault rifle visible above and beyond it.
		var sx := cx + 4 + lean; var sy := fy - 32
		p.layer(25, Profiles.slab(sx, sy, sx + 12, fy - 2, 4, 2))
		p.box(sx, sy, 12, 30, "#233747")
		p.box(sx + 2, sy + 3, 8, 6, "#89b6c8")
		p.R(sx + 3, sy + 4, 6, 2, "#c3e9ed")
		p.R(sx + 2, sy + 15, 8, 4, "#b6cad0"); p.R(sx + 3, sy + 16, 6, 2, "#253442")
		p.P(sx + 2, sy + 26, "#93a7ad"); p.P(sx + 9, sy + 26, "#93a7ad")
	if pose.glow > 0.0: _power_glow(p, kind, hand_n, hand_f, pose.glow)
	var aim := _dir(pose.an + pose.an_bend)
	var muzzle := hand_n + aim * 9.0 + Vector2(0,-1)
	if prop == "revolver": muzzle = hand_n + aim * 8.0 + Vector2(0,-1)
	elif prop == "rifle":
		var rifle_dir := aim
		if pose.prop == "carry": rifle_dir = Vector2(0.92,-0.38)
		elif pose.prop == "attack": rifle_dir = Vector2(0.98,-0.1)
		muzzle = hand_n + rifle_dir * 14.0
	anchors = {"hand_n": hand_n, "hand_f": hand_f, "head": head, "eye": Vector2(head.x + hr * 0.55, head.y + 1),
		"eye_far": Vector2(head.x + hr * 0.05, head.y + 1), "muzzle": muzzle, "chest": Vector2(cx + lean, top_y + bd.th * 0.4)}
	if prop == "dual_blaster":
		anchors.muzzle = hand_n + Vector2(19,-3)
		anchors.muzzle_f = hand_f + Vector2(19,-3)
	return c

## Material accents follow the torso through every pose, including the death rotation.
func _costume_details(p: Pen, s: Dictionary, kind: String, x: float, y: float, w: float, h: float) -> void:
	p.layer(18)
	match kind:
		"cop":
			p.R(x+2,y+8,4,1,"#9fbcf4")
			p.R(x+w-6,y+10,4,2,"#182d63"); p.P(x+w-5,y+10,"#bed7ef")
			p.line(x+2,y+2,x+3,y+7,"#182d63")
		"swat", "swat_shield", "guard":
			for side in [3.0,w-5.0]:
				p.R(x+side,y+1,2,5,shade(s.belt,0.15)); p.P(x+side,y+2,"#a8b7b7")
			for mag in 3:
				p.R(x+4+mag*4,y+h-5,2,2,shade(s.top,-0.45))
				p.P(x+4+mag*4,y+h-5,"#8eaaa4" if kind=="guard" else "#829eb1")
		"det":
			p.line(x+2,y+2,x+3,y+9,"#e3bd7a")
			p.R(x+2,y+10,4,1,"#66472d"); p.P(x+w-4,y+3,"#f0d5a0")
		"riot":
			for rivet in [3.0,w-4.0]:
				for plate in 3: p.P(x+rivet,y+3+plate*5,"#b7d1df")
			p.R(x+w-7,y+8,4,2,"#90bdd1")
		"undercover", "undercover_hood":
			# Hanging badges distinguish the plainclothes officers from civilians.
			p.line(x+w*0.4,y+1,x+w*0.55,y+9,"#dac88e")
			p.line(x+w-3,y+1,x+w*0.55,y+9,"#dac88e")
			p.box(x+w*0.55-1,y+9,4,5,"#e6bd58"); p.P(x+w*0.55,y+10,"#fff0b4")
		"hero_ironclad":
			p.line(x+w-4,y+3,x+w-3,y+h-5,"#d3e2ed")
			for rivet in 4: p.P(x+3+rivet*6,y+h-5,"#f7d77c")
			p.line(x+4,y+4,x+7,y+8,"#43546e")
		"hero_surge":
			for side in [2.0,w-4.0]:
				p.line(x+side,y+3,x+side,y+h-5,"#5578d6",2); p.P(x+side,y+4,"#a7deff")
			p.R(x+3,y+h-4,4,2,"#fff1a0")
		"hero_glacia":
			for shard in 3: p.line(x+3+shard*6,y+2,x+6+shard*5,y+7,"#ffffff",2)
			p.ell(x+w*0.6,y+8,3,4,"#2e8ebd"); p.P(x+w*0.6-1,y+6,"#e7ffff")
			p.line(x+w-3,y+10,x+w-4,y+h-3,"#f4ffff")
		"hero_paragon":
			p.line(x+2,y+2,x+4,y+h-5,"#9858a4",2)
			p.line(x+w-3,y+3,x+w-4,y+h-5,"#c27db9")
			p.R(x+3,y+2,4,2,"#ffd49c"); p.R(x+w-7,y+2,4,2,"#ffd49c")
		"hero_viper":
			p.line(x+2,y+8,x+4,y+h-4,"#8c4d80",2)
			p.line(x+w-3,y+9,x+w-4,y+h-4,"#e7a5d1")
			p.P(x+w*0.6,y+9,"#fff2f7"); p.R(x+4,y+h-3,w-8,1,"#ff90ca")
		"hero_vex":
			p.line(x+w-3,y+5,x+w-3,y+h-4,"#96b6b6")
			p.box(x+w-8,y+11,5,6,"#c6d8d1")
			p.R(x+w-7,y+12,3,1,"#6bf5ef"); p.P(x+w-6,y+15,"#c568d9")
		"civ_suit": p.R(x+w-6,y+5,3,1,"#e9ece3")
		"civ_tourist": p.line(x+2,y+1,x+5,y+h-3,"#8b3a63")
		"civ_granny": p.R(x+2,y+8,3,1,"#d9a2d8"); p.P(x+3,y+7,"#ffdbec")
		"civ_jogger":
			p.box(x+w*0.4,y+7,7,5,"#e4f1df"); p.R(x+w*0.4+2,y+8,2,3,"#274c4e")

func _blaster(p: Pen, hand: Vector2, pose: Dictionary, glow: String, base: float) -> void:
	var x := hand.x; var y := hand.y-6
	p.layer(base,Profiles.slab(x-4,y,x+19,y+7,3,1))
	p.box(x-4,y,21,7,"#677e8b"); p.R(x-1,y+6,5,5,"#3d354f")
	p.R(x+3,y+1,10,4,"#3d3558")
	for coil in 3: p.R(x+3+coil*4,y+1,2,4,glow)
	p.box(x+15,y-1,5,9,"#40516a"); p.R(x+19,y+1,2,5,glow)
	p.P(x+18,y+1,"#f1ffe8")

func _baton(p: Pen, hand: Vector2, d: Vector2, base: float) -> void:
	p.layer(base, Profiles.cap(hand.x, hand.y, hand.x + d.x * 13, hand.y + d.y * 13, 1.5, 2))
	p.line(hand.x - d.x * 2, hand.y - d.y * 2, hand.x + d.x * 13, hand.y + d.y * 13, "#1c1c22", 3)
	p.line(hand.x + d.x, hand.y + d.y - 1, hand.x + d.x * 12, hand.y + d.y * 12 - 1, "#62626e", 1)

func _dir(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(sin(a), cos(a))

func _arm_end(sh: Vector2, ang: float, bend: float, length: float) -> Vector2:
	var u := length * 0.5
	var elbow := sh + _dir(ang) * u
	return elbow + _dir(ang + bend) * u

## Skin and fur get gentler, less saturated shadows (the hue-shifted shade turns them orange-red otherwise).
static func _soft(col: String) -> float:
	var c := Color(col)
	return 0.5 if c.h > 0.02 and c.h < 0.12 and c.s > 0.18 and c.s < 0.62 and c.v > 0.45 else 1.0

func _seg(p: Pen, a: Vector2, b: Vector2, w: float, col: String, base: float) -> void:
	p.layer(base, Profiles.cap(a.x, a.y, b.x, b.y, w / 2.0, maxf(2.0, w * 0.55)))
	p.line(a.x, a.y, b.x, b.y, shade(col, -0.34 * _soft(col)), w)
	var d := b - a
	var off := Vector2(0, -1) if absf(d.x) > absf(d.y) else Vector2(1, 0)
	if w >= 3: p.line(a.x + off.x, a.y + off.y, b.x + off.x, b.y + off.y, col, maxf(1.0, w - 2))
	if w >= 5: p.line(a.x + off.x * 2, a.y + off.y * 2, b.x + off.x * 2, b.y + off.y * 2, shade(col, 0.22), 1)

func _blob(p: Pen, cx: float, cy: float, rx: float, ry: float, col: String, base: float, amp: float, hi := true) -> void:
	p.layer(base, Profiles.dome(cx, cy, rx, ry, amp))
	p.ell(cx, cy, rx, ry, shade(col, -0.3 * _soft(col)))
	p.ell(cx + 1, cy - 1, maxf(0.0, rx - 1), maxf(0.0, ry - 1), col)
	if hi and rx >= 3: p.ell(cx + rx * 0.35, cy - ry * 0.45, maxf(0.0, rx * 0.3), maxf(0.0, ry * 0.22), shade(col, 0.3))

func _arm(p: Pen, s: Dictionary, sh: Vector2, ang: float, bend: float, length: float, w: float, base: float, far: bool, fist: float) -> void:
	var u := length * 0.5
	var elbow := sh + _dir(ang) * u
	var hand := elbow + _dir(ang + bend) * u
	var sleeve: String = s.sleeve
	if far: sleeve = shade(sleeve, -0.18)
	var fore: String = s.skin if s.get("short_sleeve", false) else sleeve
	if far and s.get("short_sleeve", false): fore = shade(s.skin, -0.08)
	_seg(p, sh, elbow, w, sleeve, base)
	_seg(p, elbow, hand, maxf(3.0, w - 1), fore, base + 1)
	if s.torso == "plate":   # gold-rimmed pauldron + elbow cop
		var pc := shade(s.hat_col, 0.05 if not far else -0.2)
		_blob(p, sh.x, sh.y - 1, w * 0.95, w * 0.7, pc, base + 2, 5)
		p.layer(base + 3)
		p.R(sh.x - w * 0.8, sh.y + w * 0.55, w * 1.6, 1, s.badge if not far else shade(s.badge, -0.3))
		p.R(sh.x - w * 0.5, sh.y - w * 0.45, w * 0.8, 1, shade(pc, 0.4))
		p.P(sh.x, sh.y, s.badge)
		_blob(p, elbow.x, elbow.y, 3, 3, shade(s.pants, 0.1), base + 2, 2)
	if s.torso == "armor":
		_blob(p, sh.x, sh.y, 4, 3, shade(s.top, 0.1 if not far else -0.1), base + 2, 3)
	var hcol: String = s.hands if s.hands != "" else s.skin
	if far: hcol = shade(hcol, -0.15 * _soft(hcol))
	var fd := _dir(ang + bend)
	if not s.get("short_sleeve", false) and s.hands == "":   # shirt cuff at the wrist
		var cuff := hand - fd * (fist + 1)
		p.layer(base + 1.5); p.line(cuff.x - fd.y * 2, cuff.y + fd.x * 2, cuff.x + fd.y * 2, cuff.y - fd.x * 2, shade(fore, -0.38), 1)
	_blob(p, hand.x, hand.y, fist, fist, hcol, base + 2, 2, fist >= 4)
	if s.torso == "plate":   # gauntlet: gold knuckle bar and cuff
		p.layer(base + 3); p.R(hand.x - 2, hand.y - fist + 1, 5, 1, s.badge); p.R(hand.x - 1, hand.y - fist + 2, 3, 1, shade(s.badge, -0.3))
		var cf := hand - fd * (fist + 1)
		p.line(cf.x - fd.y * 3, cf.y + fd.x * 3, cf.x + fd.y * 3, cf.y - fd.x * 3, s.badge if not far else shade(s.badge, -0.3), 2)
	p.layer(base + 3); p.P(hand.x + 1 + int(fist * 0.5), hand.y - fist + 1, shade(hcol, 0.25))   # knuckle / thumb

func _leg(p: Pen, s: Dictionary, hip: Vector2, foot: Vector2, length: float, w: float, base: float, far: bool, pointed := false) -> void:
	var d := foot - hip
	var dist := d.length()
	var knee := hip + d * 0.5
	if dist < length:
		var push := sqrt(maxf(0.0, length * length * 0.25 - dist * dist * 0.25))
		knee += Vector2(push * 0.9, 0)
	var pants: String = s.pants; var shin: String = s.shin; var shoe: String = s.shoes
	if far: pants = shade(pants, -0.18 * _soft(pants)); shin = shade(shin, -0.18 * _soft(shin)); shoe = shade(shoe, -0.15)
	_seg(p, hip, knee, w, pants, base)
	_seg(p, knee, foot - Vector2(0, 2), maxf(3.0, w - 1), shin, base + 1)
	if s.get("stockings",false):
		p.layer(base + 1.3)
		var band := hip.lerp(knee,0.22)
		p.line(band.x-w*0.45,band.y,band.x+w*0.45,band.y,"#302436",2)
		# Diamond knit follows each bent limb rather than a rectangular screen pattern.
		for segment in [[hip.lerp(knee,0.35),knee],[knee,foot-Vector2(0,4)]]:
			for stitch in 3:
				var center: Vector2 = segment[0].lerp(segment[1],(stitch+0.5)/3.0)
				p.line(center.x-2,center.y-1,center.x,center.y+1,"#49384f",1)
				p.line(center.x,center.y+1,center.x+2,center.y-1,"#49384f",1)
	if s.torso == "plate":
		_blob(p, knee.x, knee.y, 4, 3, shade(s.hat_col, -0.05 if not far else -0.25), base + 2, 3)
		p.layer(base + 3); p.P(knee.x, knee.y, s.badge if not far else shade(s.badge, -0.3))
		var sd := (foot - knee).normalized()
		p.line(knee.x + 2 + sd.x * 4, knee.y + sd.y * 4, foot.x + 1, foot.y - 5, shade(shin, 0.35), 1)   # greave ridge
	elif s.shin == s.pants:
		p.layer(base + 1.5); p.R(foot.x - w / 2.0, foot.y - 4, w, 1, shade(shin, -0.35))   # trouser hem
	if not far and s.shin != s.skin: p.layer(base + 1.2); p.P(knee.x + 1, knee.y, shade(pants, 0.3))   # knee catch-light
	if s.get("kneepads", false):
		var kp := shade(s.belt, 0.05 if not far else -0.1)
		_blob(p, knee.x + 1, knee.y, maxf(2.0, w * 0.5), 2.5, kp, base + 2.5, 2, false)
		p.layer(base + 3); p.R(knee.x - 1, knee.y - 2, 3, 1, shade(kp, 0.45))
	if pointed:   # flying: boot hangs toe-down
		p.layer(base + 2, Profiles.cylV(foot.x, w / 2.0, 2))
		p.R(foot.x - w / 2.0, foot.y - 5, w, 5, shoe); p.R(foot.x - w / 2.0 + 1, foot.y, w - 2, 2, shoe); p.P(foot.x + 1, foot.y + 2, shoe)
		p.R(foot.x - w / 2.0 + 1, foot.y - 5, 1, 6, shade(shoe, 0.3)); p.R(foot.x + w / 2.0 - 1, foot.y - 5, 1, 5, shade(shoe, -0.3))
		p.R(foot.x - w / 2.0, foot.y - 6, w, 1, shade(shoe, -0.2))
		return
	# shoe, toe forward (+x)
	var sw := w + 2.0
	p.layer(base + 2, Profiles.slab(foot.x - w / 2.0, foot.y - 3, foot.x - w / 2.0 + sw, foot.y, 2, 1))
	p.R(foot.x - w / 2.0, foot.y - 3, sw, 3, shoe)
	p.R(foot.x - w / 2.0, foot.y - 3, sw - 1, 1, shade(shoe, 0.3))
	p.R(foot.x - w / 2.0, foot.y - 1, sw, 1, shade(shoe, -0.35))
	if s.get("trainers", false):
		p.R(foot.x - w / 2.0, foot.y, sw + 1, 1, "#fff8e8")
		p.R(foot.x - 1, foot.y - 2, 3, 1, "#dd574b")

func _torso(p: Pen, s: Dictionary, kind: String, x: float, y: float, w: float, h: float, hip_y: float, lean: float) -> void:
	var col: String = s.top
	p.layer(12, Profiles.dome(x + w / 2.0 + 1, y + h / 2.0, w / 2.0 + 1, h / 2.0 + 2, 6))
	# shaped torso: rounded shoulders, chest, nipped waist; back in shadow, front rim-lit, chest catches light
	var dk := shade(col, -0.28); var md := shade(col, -0.12); var lt := shade(col, 0.16); var hl := shade(col, 0.3)
	for r in int(h):
		var inset := 0.0
		if r == 0: inset = 2.0
		elif r == 1: inset = 1.0
		elif r > h * 0.55 and r < h - 2: inset = 1.0
		var lx := x + inset; var rw := w - inset * 2.0
		p.R(lx, y + r, rw, 1, col)
		p.R(lx, y + r, 2, 1, dk)
		p.R(lx + 2, y + r, 1, 1, md)
		if r >= 1 and r < h * 0.45: p.R(lx + rw * 0.45, y + r, rw * 0.35, 1, lt)
		if r >= 2 and r < h - 3: p.P(lx + rw - 1, y + r, lt)
		if r >= h - 3: p.R(lx + 2, y + r, rw - 2, 1, md)
	p.R(x + 3, y + 1, w - 7, 1, hl)
	p.R(x + 2, y + h * 0.5, 1, h * 0.3, shade(col, -0.4))   # arm shadow on the flank
	var mid := x + w * 0.6
	match s.torso:
		"labcoat":
			p.layer(15)
			p.R(mid-3,y+2,6,h-3,"#5b3b70")
			p.line(mid-4,y+1,mid-1,y+10,"#ffffff",3)
			p.line(mid+4,y+1,mid+1,y+10,"#ffffff",3)
			p.R(x+2,y+8,5,6,"#a1b9b7"); p.R(x+2,y+7,5,2,"#f2f5ec")
			p.R(x+3,y+4,1,4,"#7e4faf"); p.R(x+5,y+3,1,5,"#55bcb5")
			for button in 3: p.P(mid+3,y+11+button*4,"#657d84")
		"viper_suit":
			p.layer(14)
			p.line(mid,y+2,mid-2,y+h-3,"#b56c9c",1)
			p.line(x+3,y+3,mid,y+8,s.badge,2); p.line(mid,y+8,x+w-3,y+3,s.badge,2)
			p.R(mid-1,y+8,3,4,"#f5c4e4"); p.P(mid,y+10,"#402b50")
			p.R(x+2,y+h-5,w-4,3,s.top)
		"uniform":
			p.R(mid, y + 1, 1, h - 3, shade(col, -0.25))                     # placket
			for b in 3: p.P(mid + 1, y + 3 + b * 4, "#e8e8f0")
			p.R(x + 3, y + 4, 4, 3, shade(col, -0.15)); p.R(x + 3, y + 4, 4, 1, shade(col, 0.1))   # pocket
			p.layer(15, Profiles.dome(mid + 4, y + 5, 2, 2, 2))
			p.R(mid + 3, y + 4, 3, 3, s.badge); p.P(mid + 3, y + 4, shade(s.badge, 0.5)); p.P(mid + 5, y + 6, shade(s.badge, -0.35))
			p.layer(12); p.R(x + 1, y + 1, 3, 2, "#ffd23c")                   # shoulder patch
			p.layer(16, Profiles.slab(x + w - 5, y + 2, x + w - 2, y + 7, 2, 1))
			p.R(x + w - 5, y + 2, 3, 5, "#16181f"); p.P(x + w - 4, y + 3, "#7aff8a"); p.R(x + w - 4, y + 5, 1, 1, "#3a3e4a")   # shoulder radio
			p.R(mid - 1, y, 3, 2, "#121a40")                                 # tie knot
		"vest":
			p.layer(14, Profiles.slab(x + 2, y + 2, x + w - 1, y + h - 1, 2, 2))
			p.R(x + 2, y + 2, w - 3, h - 3, shade(col, 0.08))
			p.R(x + 3, y + 6, w - 5, 3, shade(s.badge, -0.25)); p.R(x + 4, y + 7, w - 7, 1, s.badge)      # reflective band
			for k in int((w - 8) / 3): p.P(x + 5 + k * 3, y + 7, shade(s.badge, -0.45))           # lettering
			p.layer(16, Profiles.slab(x + w - 5, y, x + w - 2, y + 5, 2, 1))
			p.R(x + w - 5, y, 3, 5, "#14161b"); p.P(x + w - 4, y + 1, "#5aff7a"); p.line(x + w - 3, y, x + w - 2, y - 4, "#14161b")   # radio
			for b in 3:
				p.layer(15, Profiles.slab(x + 3 + b * 4, y + h - 6, x + 6 + b * 4, y + h - 2, 2, 1))
				p.R(x + 3 + b * 4, y + h - 6, 3, 4, shade(col, -0.12)); p.R(x + 3 + b * 4, y + h - 6, 3, 1, shade(col, 0.2))
		"trench":
			p.R(mid - 2, y, 4, 5, "#e8e4da"); p.R(mid - 1, y + 1, 2, 6, s.badge)            # shirt + tie
			p.line(mid - 3, y, mid + 1, y + 8, shade(col, -0.3)); p.line(mid + 3, y, mid + 1, y + 8, shade(col, 0.25))
			for b in 2: p.P(mid + 3, y + 9 + b * 4, "#3a2614")
		"armor":
			for r in 3:
				p.layer(14 + r, Profiles.slab(x + 2, y + 2 + r * 5, x + w - 2, y + 6 + r * 5, 3, 1))
				p.R(x + 2, y + 2 + r * 5, w - 4, 4, shade(col, 0.05 * r)); p.R(x + 2, y + 2 + r * 5, w - 4, 1, shade(col, 0.3))
				p.R(x + 2, y + 5 + r * 5, w - 4, 1, shade(col, -0.35))
			p.R(x + w - 6, y + 3, 3, 2, s.badge)
		"suit":
			p.R(mid - 2, y, 5, 8, "#f0f0f0"); p.R(mid - 1, y + 1, 2, 9, s.badge)
			p.line(mid - 3, y, mid, y + 9, shade(col, -0.35)); p.line(mid + 4, y, mid + 1, y + 9, shade(col, 0.25))
			p.P(mid + 2, y + 11, "#111111")
		"hawaiian":
			for f in [[2, 3], [7, 6], [4, 10], [10, 2], [11, 11], [6, 13], [w - 4, 8]]:
				p.R(x + f[0], y + f[1], 2, 2, "#ffd23c"); p.P(x + f[0] + 1, y + f[1] + 1, "#ff8a20")
			p.line(mid - 2, y, mid, y + 4, shade(col, -0.3)); p.line(mid + 3, y, mid + 1, y + 4, shade(col, -0.3))
		"cardigan":
			p.R(mid, y + 1, 1, h - 2, shade(col, -0.3))
			for b in 3: p.P(mid + 1, y + 3 + b * 4, s.badge)
			p.R(mid - 2, y, 4, 2, "#f0e8f0")   # blouse collar
		"tank":
			p.R(x + 2, y, 3, 2, s.skin); p.R(x + w - 5, y, 3, 2, s.skin)
			p.R(x + 1, y + h * 0.45, w - 2, 2, "#ffffff")
		"plate":
			# gorget, breastplate dome, segmented fauld, gold trim
			p.layer(13); p.R(x + 3, y, w - 6, 3, "#2a323e"); p.R(x + 4, y + 2, w - 8, 1, s.badge)
			p.layer(16, Profiles.dome(x + w * 0.58, y + h * 0.42, w * 0.34, h * 0.4, 6))
			p.ell(x + w * 0.58, y + h * 0.42, w * 0.33, h * 0.36, shade(col, -0.05))
			p.ell(x + w * 0.62, y + h * 0.36, w * 0.28, h * 0.28, shade(col, 0.14))
			p.ell(x + w * 0.7, y + h * 0.26, w * 0.1, h * 0.08, shade(col, 0.45))
			p.layer(15)
			for b in 3: p.R(x + 3, y + h - 9 + b * 3, w - 5, 1, "#2a323e")
			p.R(x + 3, y + h - 3, w - 5, 1, s.badge)
			# emblem: a gold rivet-ringed shield plate
			p.layer(19, Profiles.slab(mid - 3, y + 4, mid + 4, y + 11, 2, 1))
			p.R(mid - 4, y + 3, 9, 6, "#2a323e"); p.R(mid - 3, y + 9, 7, 1, "#2a323e"); p.R(mid - 2, y + 10, 5, 1, "#2a323e"); p.P(mid, y + 11, "#2a323e")
			p.R(mid - 3, y + 4, 7, 5, s.badge); p.R(mid - 2, y + 9, 5, 1, s.badge); p.P(mid, y + 10, s.badge)
			p.R(mid - 3, y + 4, 7, 1, shade(s.badge, 0.45)); p.R(mid - 1, y + 5, 3, 3, "#2448b0"); p.P(mid, y + 6, "#9ef0ff")
			p.layer(14)
			for b in 5: p.P(x + 4 + b * (w - 7) / 4.0, y + h - 7, s.badge)
			for r in 3: p.P(x + 3, y + 5 + r * 4, s.badge)
		"bolt":
			p.layer(15)
			var pts := [Vector2(x + w - 3, y + 1), Vector2(x + w * 0.45, y + h * 0.45), Vector2(x + w * 0.7, y + h * 0.5), Vector2(x + 3, y + h - 2)]
			for k in 3: p.line(pts[k].x, pts[k].y, pts[k + 1].x, pts[k + 1].y, s.badge, 3)
			for k in 3: p.line(pts[k].x, pts[k].y, pts[k + 1].x, pts[k + 1].y, "#ffffd0", 1)
		"gown":
			p.R(mid - 3, y, 6, 3, s.skin); p.P(mid, y + 3, s.skin)          # neckline
			p.line(x + 2, y + 3, mid - 3, y, shade(col, 0.3)); p.line(x + w - 2, y + 3, mid + 3, y, shade(col, 0.3))
			for k in 4: p.P(x + 3 + k * 4, y + h - 4 + (k % 2), "#ffffff")
		"omega":
			p.layer(16, Profiles.dome(mid, y + 7, 6, 5, 3))
			p.ell(mid, y + 7, 6, 5, "#ffd0a0"); p.ell(mid, y + 7, 5, 4, s.badge)
			# Ω: ring open at the bottom with two little feet
			p.layer(18)
			p.ring(mid, y + 6, 3, "#3a1a5a"); p.R(mid - 1, y + 9, 3, 1, s.badge)
			p.R(mid - 4, y + 9, 2, 1, "#3a1a5a"); p.R(mid + 3, y + 9, 2, 1, "#3a1a5a")
	# belt
	p.layer(13)
	if s.torso != "gown" and s.torso != "trench":
		p.R(x, hip_y - 2, w, 3, s.belt); p.R(x, hip_y - 2, w, 1, shade(s.belt, 0.25))
		if s.torso in ["uniform", "vest", "armor"]:
			p.R(x + w * 0.55, hip_y - 2, 3, 3, "#c0c4cc")
			p.R(x + 1, hip_y - 1, 4, 4, shade(s.belt, 0.1))   # holster
		if s.torso == "plate" or s.torso == "omega" or s.torso == "bolt":
			p.R(x + w * 0.5 - 2, hip_y - 2, 5, 3, shade(s.belt, 0.35))

func _coat_tail(p: Pen, s: Dictionary, x: float, hip_y: float, w: float, pose: Dictionary) -> void:
	var col: String = s.top
	p.layer(11, Profiles.slab(x - 1, hip_y - 3, x + w + 1, hip_y + 10, 3, 2))
	var flare: float = pose.fdx * 0.3
	for r in 11:
		var spread := r * 0.25
		p.R(x - spread - (flare if flare < 0 else 0), hip_y - 3 + r, w + spread * 2 + absf(flare), 1, col if r < 9 else shade(col, -0.2))
	p.R(x - 1, hip_y - 3, 2, 12, shade(col, -0.3))
	p.R(x + w * 0.6, hip_y - 3, 1, 12, shade(col, -0.32))
	p.R(x, hip_y - 3, w, 2, s.belt); p.R(x + w * 0.55, hip_y - 3, 2, 2, "#c9a227")   # belt + buckle

func _skirt(p: Pen, s: Dictionary, x: float, hip_y: float, w: float, sway: float) -> void:
	var col: String = s.pants
	p.layer(11, Profiles.slab(x - 2, hip_y - 2, x + w + 2, hip_y + 9, 3, 2))
	for r in 9:
		var spread := r * 0.35
		p.R(x - spread + (sway if r > 5 else 0), hip_y - 2 + r, w + spread * 2, 1, col if r < 7 else shade(col, -0.25))
	p.R(x - 2, hip_y - 2, 2, 9, shade(col, -0.3))

func _gown(p: Pen, s: Dictionary, x: float, hip_y: float, w: float, fy: float, sway: float) -> void:
	var col: String = s.pants
	var rows := int(fy - hip_y + 2)
	p.layer(10, Profiles.slab(x - 8, hip_y - 2, x + w + 8, fy, 4, 3))
	for r in rows:
		var spread := r * 0.32
		var wave := sway * (r / float(rows)) * 2.0
		var lx := x - spread + wave; var lw := w + spread * 2
		var c2 := col
		if r > rows - 4: c2 = shade(col, -0.18)
		p.R(lx, hip_y - 2 + r, lw, 1, c2)
		p.R(lx, hip_y - 2 + r, 2, 1, shade(col, -0.32))
		p.R(lx + lw * 0.55, hip_y - 2 + r, 1, 1, shade(col, 0.28))
	# frosted hem: icicle teeth
	for k in int((w + rows * 0.64) / 3):
		var hx := x - rows * 0.32 + sway * 2 + k * 3
		p.R(hx, fy - 1, 2, 2, "#ffffff"); p.P(hx + 1, fy + 1, "#7ad0ff")
	p.layer(12)
	p.R(x - 1, hip_y - 2, w + 2, 2, s.belt)

func _cape(p: Pen, col: String, sh_f: Vector2, sh_n: Vector2, hip_y: float, fy: float, phase: int, lean: float, hero: bool) -> void:
	var top := sh_f.y - 2
	var bottom := fy - 8 if hero else hip_y + 6
	var rows := int(bottom - top)
	p.layer(3, Profiles.slab(sh_f.x - 16, top, sh_n.x + 2, bottom, 3, 3))
	for r in rows:
		var t := r / float(maxi(1, rows))
		var billow := t * t * (6.0 + phase * 1.6 + lean * 1.2) + sin(t * 5.0 + phase * 1.3) * t * 2.0
		var lx := sh_f.x - 3 - billow
		var rw := (sh_n.x - sh_f.x) + 3 + t * 4.0
		var cc := col if r % 6 != 3 else shade(col, -0.1)
		p.R(lx, top + r, rw, 1, cc)
		p.R(lx, top + r, 2, 1, shade(col, -0.35))
		p.R(lx + 3, top + r, 1, 1, shade(col, 0.2))
	p.R(sh_f.x - 3 - (6.0 + phase * 1.6 + lean * 1.2), bottom - 1, (sh_n.x - sh_f.x) + 7, 1, shade(col, -0.4))

func _long_hair(p: Pen, col: String, head: Vector2, hr: float, hip_y: float) -> void:
	p.layer(5, Profiles.slab(head.x - hr - 2, head.y, head.x, hip_y - 4, 3, 2))
	var rows := int(hip_y - 4 - head.y)
	for r in rows:
		var w2 := hr * 0.9 - r * 0.12
		p.R(head.x - hr - 1 + sin(r * 0.5) * 0.8, head.y + r, w2, 1, col if r % 5 != 2 else shade(col, -0.15))
		p.P(head.x - hr - 1 + sin(r * 0.5) * 0.8, head.y + r, shade(col, -0.3))

func _head(p: Pen, s: Dictionary, kind: String, h: Vector2, r: float, pose: Dictionary) -> void:
	var skin: String = s.skin
	# neck
	p.layer(11); p.R(h.x - 3, h.y + r - 2, 6, 3, shade(skin, -0.12))
	# ear behind, then skull
	_blob(p, h.x, h.y, r, r, skin, 15, 8)
	p.layer(23); p.ell(h.x - r * 0.3, h.y + 2, 2, 3, shade(skin, -0.1)); p.P(h.x - r * 0.3, h.y + 2, shade(skin, -0.22))
	# chin shadow
	p.layer(16); p.R(h.x - r * 0.4, h.y + r - 1, r * 0.9, 1, shade(skin, -0.12))
	_hair(p, s, h, r)
	_face(p, s, kind, h, r, pose)
	_hat(p, s, h, r)

func _hair(p: Pen, s: Dictionary, h: Vector2, r: float) -> void:
	var col: String = s.hair
	match s.hair_style:
		"short":
			p.layer(22, Profiles.dome(h.x - 1, h.y - r * 0.5, r, r * 0.6, 3))
			p.ell(h.x - 1, h.y - r * 0.45, r, r * 0.55, col); p.R(h.x - r, h.y - r * 0.4, 3, r * 0.9, col)
			p.R(h.x - r + 1, h.y - r * 0.6, r, 1, shade(col, 0.25))
		"slick":
			p.layer(22, Profiles.dome(h.x - 1, h.y - r * 0.55, r, r * 0.55, 3))
			p.ell(h.x - 1, h.y - r * 0.5, r + 1, r * 0.55, col)
			p.R(h.x - r - 1, h.y - r * 0.4, 4, r * 0.8, col)
			for k in 3: p.R(h.x - r + 2 + k * 4, h.y - r * 0.8, 3, 1, shade(col, 0.35))
		"messy":
			p.layer(22, Profiles.dome(h.x - 1, h.y - r * 0.4, r + 1, r * 0.7, 3))
			p.ell(h.x - 1, h.y - r * 0.45, r + 1, r * 0.6, col)
			for k in 5: p.R(h.x - r + k * 4, h.y - r * 0.1 + (k % 2), 2, 3, col)
			p.R(h.x - r - 1, h.y - r * 0.3, 3, r, shade(col, -0.2))
		"bun":
			_blob(p, h.x - r * 0.55, h.y - r * 0.95, r * 0.45, r * 0.4, col, 21, 4)
			p.layer(22, Profiles.dome(h.x - 1, h.y - r * 0.4, r, r * 0.65, 3))
			p.ell(h.x - 1, h.y - r * 0.4, r + 1, r * 0.6, col); p.R(h.x - r - 1, h.y - r * 0.3, 4, r, col)
			for k in 4: p.P(h.x - r + 2 + k * 3, h.y - r * 0.7 + (k % 2), shade(col, -0.25))
		"afro":
			_blob(p, h.x - 2, h.y - r * 0.75, r + 1, r * 0.6, col, 20, 6)
			p.R(h.x - r - 2, h.y - r * 0.5, 5, r * 0.9, col)
			for k in 6: p.P(h.x - r + k * 3, h.y - r * 1.15 + (k * 7 % 3), shade(col, 0.25))
		"spikes":
			p.layer(23)
			for k in 5:   # zig-zag lightning spikes swept back
				var b0 := Vector2(h.x - r + 2 + k * r * 0.42, h.y - r * 0.5)
				var b1 := b0 + Vector2(-3, -5 - (k % 2) * 2)
				var b2 := b1 + Vector2(2, -2)
				var b3 := b2 + Vector2(-7 - k * 0.8, -5 + absf(k - 2) * 1.2)
				for seg in [[b0, b1], [b1, b2], [b2, b3]]:
					p.line(seg[0].x, seg[0].y, seg[1].x, seg[1].y, col, 3)
				p.line(b0.x, b0.y, b1.x, b1.y, "#fffbe0", 1); p.line(b2.x, b2.y, b3.x, b3.y, "#fffbe0", 1)
			p.ell(h.x - 1, h.y - r * 0.45, r, r * 0.55, col)
			p.R(h.x - r - 1, h.y - r * 0.5, r * 0.6, 3, shade(col, -0.2))
		"long":
			p.layer(22, Profiles.dome(h.x - 1, h.y - r * 0.45, r + 1, r * 0.6, 3))
			p.ell(h.x - 1, h.y - r * 0.45, r + 1, r * 0.6, col); p.R(h.x - r - 1, h.y - r * 0.4, 5, r * 1.2, col)
			p.R(h.x - r + 3, h.y - r * 0.85, r, 1, "#ffffff")
		"swept":
			p.layer(22, Profiles.dome(h.x - 2, h.y - r * 0.5, r + 1, r * 0.6, 4))
			p.ell(h.x - 2, h.y - r * 0.55, r + 1, r * 0.55, col)
			for k in 4: p.line(h.x + r * 0.5 - k * 4, h.y - r * 0.95, h.x - r - 3 - k, h.y - r * 0.3 + k, shade(col, -0.18 + k * 0.08), 2)
			p.R(h.x - r - 2, h.y - r * 0.4, 4, r * 0.8, col)

## Face in the scientist's style: 3x3 eyes with a glint, shaded sockets, expressive brows, a nose that
## breaks the silhouette, and per-character touches (moustache, stubble, blush, sunburn).
func _face(p: Pen, s: Dictionary, kind: String, h: Vector2, r: float, pose: Dictionary) -> void:
	var skin: String = s.skin
	var D := shade(skin, -0.16); var DD := shade(skin, -0.32); var L := shade(skin, 0.3)
	var ey := h.y + 1
	var ef := h.x + 1.0; var en := h.x + r * 0.62 + 1.0   # far / near eye centres
	var dark := "#1c1214"
	var helmet: bool = s.hat in ["great_helm", "riot", "swat"]
	p.layer(24)
	if not helmet:
		p.lift(0.5); p.R(h.x, h.y - r * 0.5, 4, 1, L); p.P(h.x + r - 2, h.y - r * 0.3, L); p.lift(0)
	if helmet:
		pass   # helmets draw their own visor
	elif s.hat == "mask":
		p.R(ef - 3, ey - 2, en - ef + 6, 5, s.hat_col); p.R(ef - 3, ey - 2, en - ef + 6, 1, shade(s.hat_col, 0.4))
		p.P(en + 3, ey - 2, s.hat_col); p.P(en + 4, ey - 3, s.hat_col)   # swept mask tip
		_eyes(p, pose.eyes, ef, en, ey, "#fff36b", true)
	else:
		# sockets
		p.lift(-1)
		p.R(ef - 2, ey - 1, 1, 3, D); p.R(ef - 1, ey + 2, 2, 1, D); p.R(en - 1, ey + 2, 3, 1, D); p.P(en + 2, ey + 1, D)
		p.lift(0)
		var mode: String = pose.eyes
		if mode == "open" and kind == "det": mode = "squint"
		_eyes(p, mode, ef, en, ey, s.get("eyes", dark), s.has("eyes"))
		if s.get("shades", false) and mode in ["open", "squint"]:
			p.layer(26); p.R(ef - 2, ey - 1, en - ef + 5, 3, "#101014"); p.R(ef - 2, ey - 1, en - ef + 5, 1, "#2a2a34")
			p.P(en + 1, ey - 1, "#c8e8ff"); p.P(ef, ey - 1, "#6a7488"); p.layer(24)
		# brows
		var bcol := shade(s.hair, -0.4) if s.hair_style != "none" else DD
		if s.hair in ["#e8e8f0", "#f0f0f0", "#e8f8ff"]: bcol = shade(s.hair, -0.25)
		var style := "neutral"
		if pose.mouth == "grit" or kind in ["cop", "det", "civ_jogger"] or kind.begins_with("hero_"): style = "angry"
		if pose.eyes in ["wide", "shut", "dizzy"] or kind == "civ_granny" or kind == "civ_tourist": style = "worried"
		if kind == "civ_suit" and pose.eyes == "open": style = "smug"
		p.lift(1.5)
		match style:
			"angry":
				p.R(en - 1, ey - 3, 3, 1, bcol); p.P(en - 2, ey - 2, bcol); p.P(en + 2, ey - 4, bcol)
				p.R(ef - 2, ey - 3, 2, 1, bcol); p.P(ef, ey - 2, bcol)
			"worried":
				p.R(en, ey - 3, 2, 1, bcol); p.P(en - 1, ey - 4, bcol)
				p.R(ef - 2, ey - 3, 2, 1, bcol); p.P(ef, ey - 4, bcol)
			"smug":
				p.R(en - 1, ey - 4, 3, 1, bcol); p.P(en + 2, ey - 3, bcol)
				p.R(ef - 2, ey - 3, 3, 1, bcol)
			_:
				p.R(en - 1, ey - 3, 3, 1, bcol); p.R(ef - 2, ey - 3, 3, 1, bcol)
		if kind == "cop": p.R(en - 1, ey - 4, 3, 1, bcol)   # bushy
		p.lift(0)
		if s.get("glasses", false):
			p.layer(26)
			p.ring(en, ey, 2, "#c8ccd8"); p.ring(ef, ey, 2, "#c8ccd8"); p.R(ef + 2, ey - 1, en - ef - 3, 1, "#c8ccd8")
			p.P(en + 1, ey - 1, "#ffffff")
			p.layer(24)
	# nose: breaks the face silhouette like the scientist's
	if s.hat != "great_helm":
		p.layer(25, Profiles.dome(h.x + r, h.y + 3, 2, 2, 2))
		p.R(h.x + r - 1, h.y + 1, 2, 4, skin); p.R(h.x + r + 1, h.y + 2, 1, 2, skin)
		p.P(h.x + r - 1, h.y + 1, L); p.P(h.x + r, h.y + 5, DD); p.P(h.x + r - 2, h.y + 4, D)
		if kind == "civ_tourist": p.R(h.x + r, h.y + 2, 2, 2, "#f08878")   # sunburn
	p.layer(24)
	if kind in ["civ_granny", "civ_tourist"]: p.R(en, ey + 3, 2, 1, "#f09890")
	if s.hat == "great_helm": return
	var mx := h.x + r * 0.5 + 1; var my := h.y + r * 0.62 + 1
	if kind == "det":   # five o'clock shadow
		for k in 4: p.P(mx - 1 + k * 2, my + 1 + (k % 2), "#b88c70")
		p.R(h.x - 1, h.y + r - 2, 2, 2, "#b88c70")
	match pose.mouth:
		"flat":
			p.R(mx - 2, my, 5, 1, DD); p.P(mx + 3, my - 1, DD)
			if kind == "civ_suit": p.P(mx - 2, my, D)
		"grit": p.R(mx - 2, my - 1, 6, 3, dark); p.R(mx - 1, my, 4, 1, "#f0f0f0"); p.P(mx + 3, my - 2, DD)
		"open": p.R(mx - 1, my - 1, 4, 4, dark); p.R(mx, my + 1, 2, 2, "#c84050"); p.R(mx - 1, my - 1, 4, 1, "#f0f0f0")
		"grin": p.R(mx - 2, my - 1, 6, 2, "#f0f0f0"); p.R(mx - 2, my + 1, 6, 1, dark); p.P(mx + 4, my - 2, DD)
		"wobble": p.P(mx - 2, my, dark); p.P(mx - 1, my + 1, dark); p.P(mx, my, dark); p.P(mx + 1, my + 1, dark); p.P(mx + 2, my, dark)
	if kind == "cop":   # moustache
		p.lift(1); p.R(mx - 3, my - 2, 6, 2, shade(s.hair, -0.1)); p.P(mx + 3, my - 1, shade(s.hair, -0.1)); p.R(mx - 2, my - 2, 4, 1, shade(s.hair, 0.2)); p.lift(0)
	if kind == "civ_suit" and pose.mouth == "flat": p.R(mx - 2, my - 2, 5, 1, shade(s.hair, -0.1))
	p.R(mx - 2, h.y + r, 4, 1, D)   # chin

func _eyes(p: Pen, mode: String, ef: float, en: float, ey: float, col: String, glow: bool) -> void:
	var dark := "#1c1214"
	for k in 2:
		var ex: float = ef if k == 0 else en
		var w := 2 if k == 0 else 3   # far eye is foreshortened
		var x0 := ex - 1
		match mode:
			"open":
				p.R(x0, ey - 1, w, 3, col)
				if not glow: p.P(x0 + w - 1, ey - 1, "#ffffff"); p.P(x0, ey + 1, "#5a3a3a")
				else: p.P(x0 + w - 1, ey - 1, "#fff6d8")
			"glow":
				p.R(x0 - 1, ey - 1, w + 2, 3, col); p.R(x0, ey - 1, w, 2, "#fff0c0"); p.P(x0 + w - 1, ey - 1, "#ffffff")
			"squint":
				p.R(x0, ey, w, 2, dark); p.P(x0 + w - 1, ey, "#ffffff"); p.R(x0 - 1, ey - 1, w + 1, 1, "#7a5a48")
			"shut": p.R(x0 - 1, ey + 1, w + 1, 1, dark); p.P(x0 - 1, ey, dark); p.P(x0 + w, ey, dark)
			"wide":
				p.R(x0, ey - 2, w, 4, "#ffffff"); p.P(x0 + w - 1, ey - 1, dark)
				if w == 3: p.P(x0 + 2, ey, dark)
			"x":
				p.P(x0, ey - 1, dark); p.P(x0 + 2, ey - 1, dark); p.P(x0 + 1, ey, dark); p.P(x0, ey + 1, dark); p.P(x0 + 2, ey + 1, dark)
			"dizzy":
				p.R(x0, ey - 1, 3, 1, dark); p.P(x0 + 2, ey, dark); p.R(x0, ey + 1, 3, 1, dark); p.P(x0 + 1, ey, "#ffffff")

func _hat(p: Pen, s: Dictionary, h: Vector2, r: float) -> void:
	var col: String = s.get("hat_col", "#333333")
	match s.hat:
		"police":
			p.layer(26, Profiles.dome(h.x - 1, h.y - r * 0.6, r + 1, r * 0.5, 4))
			p.ell(h.x - 1, h.y - r * 0.65, r + 1, r * 0.45, col)
			p.R(h.x - r - 1, h.y - r * 0.95, r * 2 + 1, 3, col); p.R(h.x - r, h.y - r * 0.95, r * 2, 1, shade(col, 0.35))
			for k in int(r * 2):                                                   # chequered band
				p.P(h.x - r + k, h.y - r * 0.35, "#f0f2f8" if (k / 2) % 2 == 0 else "#0d0f1c")
				p.P(h.x - r + k, h.y - r * 0.35 + 1, "#0d0f1c" if (k / 2) % 2 == 0 else "#f0f2f8")
			p.layer(28); p.R(h.x + r * 0.2, h.y - r * 0.35 + 1, r + 3, 2, "#0b0c14")   # visor forward
			p.R(h.x + r * 0.2, h.y - r * 0.35 + 1, r + 2, 1, "#3a3e58")
			p.layer(29, Profiles.dome(h.x + r * 0.35, h.y - r * 0.75, 2, 2, 2))
			p.R(h.x + r * 0.25, h.y - r * 0.85, 3, 3, s.badge); p.P(h.x + r * 0.25, h.y - r * 0.85, "#fff6c0")
		"fedora":
			p.layer(27, Profiles.dome(h.x - 1, h.y - r * 0.7, r * 0.8, r * 0.5, 4))
			p.ell(h.x - 1, h.y - r * 0.8, r * 0.8, r * 0.45, col)
			p.R(h.x - r * 0.6, h.y - r * 1.2, r * 1.1, 1, shade(col, -0.3))   # crease
			p.R(h.x - r * 0.8, h.y - r * 0.5, r * 1.6, 2, "#2a1a10")          # band
			p.layer(28); p.R(h.x - r - 3, h.y - r * 0.4, r * 2 + 6, 2, col); p.R(h.x - r - 3, h.y - r * 0.4, r * 2 + 6, 1, shade(col, 0.3))
			p.P(h.x - r - 3, h.y - r * 0.4 - 1, col); p.P(h.x + r + 2, h.y - r * 0.4 - 1, col)
		"swat":
			p.layer(26, Profiles.dome(h.x - 1, h.y - r * 0.35, r + 1, r * 0.8, 6))
			p.ell(h.x - 1, h.y - r * 0.35, r + 1, r * 0.75, col)
			p.R(h.x - r * 0.9, h.y - r * 0.95, r * 0.9, 1, shade(col, 0.3))
			# goggles
			p.layer(29, Profiles.cylH(h.y + 1, 2, 3))
			p.R(h.x - r * 0.1, h.y - 1, r * 1.1, 4, "#1d3a48"); p.R(h.x, h.y - 1, r * 0.9, 1, "#7ad0ee"); p.P(h.x + r * 0.7, h.y, "#e8faff")
			p.R(h.x - r, h.y, r * 0.9, 2, "#111114")
			p.layer(24); p.R(h.x + r * 0.2, h.y + r * 0.45, r * 0.8, 3, "#1a1a1e")   # balaclava
			if s.get("chinstrap", false): p.layer(25); p.line(h.x - r * 0.6, h.y + 1, h.x + r * 0.1, h.y + r * 0.9, shade(col, -0.35), 1)
			p.R(h.x - 2, h.y + r * 0.6, 3, 4, "#111114")
		"riot":
			p.layer(26, Profiles.dome(h.x - 1, h.y - r * 0.3, r + 2, r * 0.9, 7))
			p.ell(h.x - 1, h.y - r * 0.3, r + 2, r * 0.85, col)
			p.R(h.x - r * 0.8, h.y - r * 1.0, r, 1, shade(col, 0.35))
			p.R(h.x - r - 1, h.y + 1, r * 0.8, r * 0.6, shade(col, -0.2))          # neck guard
			# face, then a curved clear shield over it, hinged at the temple
			_eyes(p, "open", h.x + 1, h.x + r * 0.62 + 1, h.y + 1, "#1a1420", false)
			p.R(h.x + r * 0.5, h.y + r * 0.62 + 1, 4, 1, "#3a2420")
			p.layer(30, Profiles.dome(h.x + r * 0.35, h.y + 1, r * 0.95, r * 0.95, 3))
			var a0 := p.alpha; p.alpha = 0.4
			p.ell(h.x + r * 0.4, h.y + 1, r * 0.9 + 1, r * 0.95, "#9ad8f0")
			p.alpha = a0
			p.R(h.x - r * 0.4, h.y - r * 0.55, r * 1.7, 1, "#202a3e")                 # visor brow rim
			p.line(h.x + r * 1.1, h.y - r * 0.3, h.x + r * 1.25, h.y + r * 0.5, "#e8faff")   # front glare
			p.line(h.x + r * 0.2, h.y - r * 0.4, h.x + r * 0.6, h.y - r * 0.4, "#d8f4ff")
			p.layer(31, Profiles.dome(h.x - r * 0.45, h.y - 1, 2, 2, 2))
			p.ell(h.x - r * 0.45, h.y - 1, 1, 1, "#9aa4b8")                           # hinge bolt
		"sunhat":
			p.layer(27, Profiles.dome(h.x - 1, h.y - r * 0.75, r * 0.7, r * 0.45, 3))
			p.ell(h.x - 1, h.y - r * 0.8, r * 0.7, r * 0.4, col)
			p.R(h.x - r * 0.6, h.y - r * 0.55, r * 1.2, 2, "#e85a9a")
			p.layer(28); p.R(h.x - r - 4, h.y - r * 0.4, r * 2 + 8, 2, col); p.R(h.x - r - 4, h.y - r * 0.4 + 1, r * 2 + 8, 1, shade(col, -0.3))
		"headband":
			p.layer(26, Profiles.cylH(h.y - r * 0.45, 1, 2))
			p.R(h.x - r - 1, h.y - r * 0.6, r * 2 + 1, 2, col); p.R(h.x - r - 3, h.y - r * 0.45, 3, 3, col)
		"great_helm":
			p.layer(26, Profiles.dome(h.x, h.y - 1, r + 1, r + 1, 9))
			p.ell(h.x, h.y - 1, r + 1, r + 1, shade(col, -0.3)); p.ell(h.x + 1, h.y - 2, r, r, col)
			p.ell(h.x + r * 0.35, h.y - r * 0.5, r * 0.3, r * 0.25, shade(col, 0.35))
			p.layer(29, Profiles.cylV(h.x, 1.5, 3))
			p.R(h.x - 2, h.y - r - 4, 3, r * 0.9, s.badge); p.R(h.x - 3, h.y - r - 3, 1, r * 0.6, shade(s.badge, -0.35))   # crest fin
			p.P(h.x - 1, h.y - r - 4, shade(s.badge, 0.5))
			p.layer(28)
			p.R(h.x - r * 0.3, h.y - 1, r * 1.4, 4, "#141820")           # visor slit
			p.R(h.x - r * 0.1, h.y, r * 1.15, 2, "#3ab8e8"); p.R(h.x + r * 0.2, h.y, r * 0.7, 1, "#dffaff")
			p.R(h.x - r * 0.3, h.y + 3, r * 1.4, 1, s.badge)
			p.R(h.x + r * 0.2, h.y + 4, r * 0.8, 1, "#141820"); p.R(h.x + r * 0.3, h.y + 6, r * 0.6, 1, "#141820")
			for k in 3: p.P(h.x - r * 0.6 + k * 4, h.y + r * 0.5, s.badge)
		"visor":
			p.layer(27, Profiles.cylH(h.y + 1, 2, 2))
			p.R(h.x - r * 0.4, h.y - 1, r * 1.5 + 1, 4, col); p.R(h.x - r * 0.4, h.y - 1, r * 1.5 + 1, 1, shade(col, 0.4))
			p.R(h.x - r * 0.4, h.y + 2, r * 1.5 + 1, 1, shade(col, -0.35))
			p.P(h.x + r + 1, h.y, col); p.P(h.x - r * 0.4 - 1, h.y, shade(col, -0.2))
			# glowing eye lenses cut into the band
			p.R(h.x + 1 - 1, h.y, 2, 1, "#fff0c0"); p.R(h.x + r * 0.62, h.y, 3, 1, "#fff0c0")
		"ice_crown":
			p.layer(28)
			for k in 5:
				var bx := h.x - r * 0.75 + k * r * 0.4
				var tall := 6 - absi(k - 2) * 2
				p.line(bx, h.y - r * 0.8, bx, h.y - r * 0.8 - tall, col, 2); p.P(bx, h.y - r * 0.8 - tall, "#ffffff")
			p.R(h.x - r * 0.8, h.y - r * 0.85, r * 1.7, 2, "#e8f8ff"); p.P(h.x + r * 0.1, h.y - r * 0.85, s.badge)

func _camera_on_chest(p: Pen, x: float, y: float) -> void:
	p.layer(20, Profiles.slab(x - 2, y, x + 5, y + 5, 2, 1))
	p.R(x - 2, y, 7, 5, "#333338"); p.R(x - 2, y, 7, 1, "#6a6a74"); p.ell(x + 2, y + 2, 1, 1, "#88aadd"); p.P(x + 4, y + 1, "#ffffff")
	p.layer(18); p.line(x - 6, y - 8, x - 1, y, "#222222")

func _prop_behind(p: Pen, prop: String, hand: Vector2, pose: Dictionary) -> void:
	if prop == "rifle" and pose.prop != "attack":
		pass

func _prop(p: Pen, prop: String, hand: Vector2, pose: Dictionary) -> void:
	var mode: String = pose.prop
	if mode == "drop": return
	match prop:
		"baton":
			var ang := deg_to_rad(pose.an + pose.an_bend + 25.0) if mode != "attack" else deg_to_rad(pose.an + pose.an_bend + 90.0)
			if mode == "flail" or mode == "limp": ang = deg_to_rad(pose.an + pose.an_bend)
			var d := Vector2(sin(ang), cos(ang))
			p.layer(20, Profiles.cap(hand.x, hand.y, hand.x + d.x * 12, hand.y + d.y * 12, 1.5, 2))
			p.line(hand.x - d.x * 2, hand.y - d.y * 2, hand.x + d.x * 12, hand.y + d.y * 12, "#202024", 3)
			p.line(hand.x, hand.y - 1, hand.x + d.x * 11, hand.y + d.y * 11 - 1, "#5a5a66", 1)
			var perp := Vector2(d.y, -d.x)
			p.line(hand.x + perp.x * 3, hand.y + perp.y * 3, hand.x + perp.x * 1, hand.y + perp.y * 1, "#202024", 2)
		"rifle":
			var ang2 := deg_to_rad(pose.an + pose.an_bend)
			var d2 := Vector2(sin(ang2), cos(ang2))
			if mode == "carry": d2 = Vector2(0.92, -0.38)
			elif mode == "attack": d2 = Vector2(0.98, -0.1)
			var back := hand - d2 * 9; var front := hand + d2 * 14
			p.layer(21, Profiles.cap(back.x, back.y, front.x, front.y, 2, 3))
			p.line(back.x, back.y, front.x, front.y, "#1c1d22", 4)
			p.line(back.x, back.y - 1, front.x, front.y - 1, "#4a4e58", 1)
			p.R(hand.x + d2.x * 2 - 1, hand.y + 2, 3, 5, "#24262c")       # magazine
			p.P(front.x, front.y - 2, "#8a8e98")
			var lamp := hand + d2 * 8 + Vector2(0, 2)                         # weapon light
			p.layer(22); p.R(lamp.x - 1, lamp.y, 3, 2, "#2a2c32"); p.P(lamp.x + 1, lamp.y, "#f4fbff")
		"revolver":
			var ang3 := deg_to_rad(pose.an + pose.an_bend)
			var d3 := Vector2(sin(ang3), cos(ang3))
			p.layer(21, Profiles.cap(hand.x, hand.y, hand.x + d3.x * 8, hand.y + d3.y * 8, 1.5, 2))
			p.line(hand.x + d3.x * 1, hand.y + d3.y * 1 - 1, hand.x + d3.x * 8, hand.y + d3.y * 8 - 1, "#2a2c32", 3)
			p.line(hand.x + d3.x * 2, hand.y + d3.y * 2 - 2, hand.x + d3.x * 8, hand.y + d3.y * 8 - 2, "#9aa0ac", 1)
			p.R(hand.x - 1, hand.y, 3, 4, "#5a3a20")
		"briefcase":
			if mode == "flail": return
			p.layer(19, Profiles.slab(hand.x - 5, hand.y + 2, hand.x + 6, hand.y + 10, 2, 1))
			p.R(hand.x - 5, hand.y + 2, 11, 8, "#5a3a1a"); p.R(hand.x - 5, hand.y + 2, 11, 1, "#8a6030"); p.R(hand.x - 5, hand.y + 9, 11, 1, "#3a2410")
			p.R(hand.x - 2, hand.y, 5, 2, "#3a2410"); p.R(hand.x, hand.y + 4, 2, 1, "#c9a227")
		"handbag":
			if mode == "flail":
				p.layer(19); p.R(hand.x - 4, hand.y - 8, 8, 6, "#c84a8a"); p.R(hand.x - 4, hand.y - 8, 8, 1, "#e87ab0"); return
			p.layer(19, Profiles.slab(hand.x - 4, hand.y + 3, hand.x + 4, hand.y + 9, 2, 1))
			p.line(hand.x - 3, hand.y + 3, hand.x, hand.y, "#ffd23c"); p.line(hand.x + 3, hand.y + 3, hand.x, hand.y, "#ffd23c")
			p.R(hand.x - 4, hand.y + 3, 9, 6, "#c84a8a"); p.R(hand.x - 4, hand.y + 3, 9, 1, "#e87ab0"); p.R(hand.x - 4, hand.y + 8, 9, 1, "#8a2a5a")
			p.P(hand.x, hand.y + 5, "#ffd23c")
		"camera":
			pass

func _shield(p: Pen, hand: Vector2, fy: float, pose: Dictionary) -> void:
	if pose.prop == "drop": return
	var x := hand.x - 1; var top := hand.y - 25; var h := 42.0; var w := 11.0
	if pose.prop == "attack": x += 3; top -= 1
	if pose.prop == "limp": top += 4
	if pose.prop == "flail": top -= 4
	h = minf(h, fy - top - 1)
	p.layer(24, Profiles.slab(x, top, x + w, top + h, 4, 2))
	var a0 := p.alpha
	p.alpha = 0.82
	p.R(x, top, w, h, "#6f93ad")
	p.alpha = 0.55
	p.R(x + 2, top + 3, w - 4, h * 0.3, "#b8def0")                                  # viewport
	p.alpha = a0
	p.R(x, top, w, 1, "#e0f4fc"); p.R(x, top + h - 1, w, 1, "#24303e")
	p.R(x, top, 1, h, "#24303e"); p.R(x + w - 1, top, 1, h, "#4a6078")
	p.R(x + 1, top + 1, 1, h - 2, "#9cc4da")
	p.R(x + 3, top + 4, 1, h * 0.25, "#f4fcff"); p.P(x + 4, top + 4, "#ffffff")       # glare
	var band := top + h * 0.48
	p.R(x + 1, band, w - 2, 5, "#16244a"); p.R(x + 1, band, w - 2, 1, "#3a5490")
	for k in int((w - 4) / 2): p.R(x + 2 + k * 2, band + 2, 1, 2, "#f0f4ff")          # POLICE lettering
	p.R(x + 2, top + h - 5, w - 4, 1, "#3a4c60")

func _power_glow(p: Pen, kind: String, hn: Vector2, hf: Vector2, g: float) -> void:
	# baked glow accents on the fists (live emissive overlays add the real light)
	var col := "#fff36b"
	match kind:
		"hero_glacia": col = "#bff4ff"
		"hero_ironclad": col = "#ffd890"
		"hero_paragon": col = "#ffb060"
	p.layer(30)
	var rr := 1 + int(g * 2)
	p.ell(hn.x, hn.y, rr, rr, col); p.P(hn.x, hn.y, "#ffffff")
	if kind == "hero_ironclad" or kind == "hero_glacia": p.ell(hf.x, hf.y, rr, rr, col)

# ---------------------------------------------------------------- post effects
func _ice_crust(c: Pixels, cell: Dictionary, base_h: float) -> void:
	# glaze every painted pixel toward pale ice and wrap the feet in a block of ice
	var ice := Color("#bfefff")
	for y in c.height:
		for x in c.width:
			var col := c.image.get_pixel(x, y)
			if col.a <= 0.0: continue
			var k := 0.35 + 0.1 * float((x + y) % 3 == 0)
			c.image.set_pixel(x, y, Color(col.lerp(ice, k), col.a))
	var p := Pen.new(c, 0, 0)
	var fy: float = cell.fy; var cx: float = cell.cx
	var w := base_h * 2.6
	p.layer(base_h + 8, Profiles.slab(cx - w / 2, fy - base_h * 1.5, cx + w / 2, fy, 4, 3))
	p.alpha = 0.7
	p.R(cx - w / 2, fy - base_h * 1.5, w, base_h * 1.5 + 1, "#9adfff")
	p.alpha = 1.0
	p.R(cx - w / 2, fy - base_h * 1.5, w, 1, "#f0fcff")
	p.line(cx - w / 2 + 2, fy - base_h * 1.5 + 2, cx - w / 2 + 6, fy - 2, "#ffffff")
	p.line(cx + w / 4, fy - base_h * 1.2, cx + w / 4 + 3, fy - base_h, "#e8faff")
	for k in 4:   # shoulder icicles
		var ix := cx - w / 2 + 3 + k * w / 4
		p.R(ix, fy - base_h * 1.5 - 3 - (k % 2) * 2, 2, 3 + (k % 2) * 2, "#e8faff")

func _streak(c: Pixels, i: int, hex: String) -> void:
	# speedster blink: the body thins into trailing after-images that burn to lightning yellow
	var src := c.image.duplicate()
	var src_depth := c.depth.duplicate(); var src_occ := c.occupied.duplicate()
	c.depth.fill(0.0); c.occupied.fill(0)
	c.image.fill(Color.TRANSPARENT)
	var y_col := Color(hex)
	var body_a: float = [0.9, 0.55, 0.2][i]
	for ghost in range(3, -1, -1):   # back-most ghost first, the body last (on top)
		var off := -ghost * (4 + i * 3)
		var a: float = body_a if ghost == 0 else body_a * (0.55 - ghost * 0.13)
		var tintk: float = 0.2 + i * 0.25 if ghost == 0 else 0.85
		for y in c.height:
			if ghost > 0 and y % 2 == 1: continue   # ghosts are scanned, the body stays solid
			for x in c.width:
				var col: Color = src.get_pixel(x, y)
				if col.a <= 0.0: continue
				var nx := x + off
				if nx < 0 or nx >= c.width: continue
				var out: Color = col.lerp(y_col, tintk); out.a = col.a * a
				c.image.set_pixel(nx, y, out)
				c.depth[y * c.width + nx] = src_depth[y * c.width + x]; c.occupied[y * c.width + nx] = maxi(1, src_occ[y * c.width + x])

## Rotate the painted pixels (albedo, height, occupancy) about `pivot` and drop them onto the ground line.
func _rotated(c: Pixels, deg: float, pivot: Vector2, fy: float, shift_x: float) -> Pixels:
	var out := Pixels.new(c.width, c.height)
	var a := deg_to_rad(deg); var ca := cos(a); var sa := sin(a)
	var pts: Array = []
	var lowest := -100000; var minx := 100000; var maxx := -100000
	for y in range(-c.height, c.height * 2):
		for x in range(-c.width, c.width * 2):
			var dx := x - pivot.x; var dy := y - pivot.y
			var sx := int(floor(pivot.x + dx * ca + dy * sa + 0.5)); var sy := int(floor(pivot.y - dx * sa + dy * ca + 0.5))
			if sx < 0 or sy < 0 or sx >= c.width or sy >= c.height: continue
			var si := sy * c.width + sx
			var col := c.image.get_pixel(sx, sy)
			if col.a <= 0.0: continue
			pts.append([x, y, col, c.depth[si], c.occupied[si]])
			lowest = maxi(lowest, y); minx = mini(minx, x); maxx = maxi(maxx, x)
	if pts.is_empty(): return out
	var dy2 := int(fy) - lowest
	# slide horizontally so the body stays inside the cell, centred on the foot point plus shift_x
	var dx2 := int(pivot.x + shift_x - (minx + maxx) / 2.0)
	dx2 = clampi(dx2, -minx + 1, c.width - 2 - maxx)
	for q in pts:
		var tx: int = q[0] + dx2; var ty: int = q[1] + dy2
		if tx < 0 or ty < 0 or tx >= c.width or ty >= c.height: continue
		out.image.set_pixel(tx, ty, q[2])
		out.depth[ty * c.width + tx] = q[3]; out.occupied[ty * c.width + tx] = q[4]
	return out

func _death(kind: String, pose: Dictionary, i: int, cell: Dictionary) -> Pixels:
	# 0: knocked back, 1: toppling, 2: hits the floor (bounce), 3: lying still
	var fy: float = cell.fy; var cx: float = cell.cx
	var hero := kind.begins_with("hero_")
	if i == 0:
		var hp := _pose(kind, "hurt", 0); hp.lean = -3; hp.eyes = "x"; hp.an = 160.0; hp.af = 140.0
		hp.prop = "drop" if kind != "det" else "limp"
		return _humanoid(kind, hp, cell)
	var c := _humanoid(kind, pose, cell)
	var angles := [0.0, -50.0, -84.0, -90.0]
	var bounce := [0, 0, 2, 0]
	var r := _rotated(c, angles[i], Vector2(cx, fy), fy - bounce[i], -(3 if not hero else 5) * (i / 3.0))
	return r

# ---------------------------------------------------------------- K9
func _dog(state: String, i: int) -> Pixels:
	var cell: Dictionary = CELLS.dog
	var c := Pixels.new(cell.w, cell.h); var p := Pen.new(c, 0, 0)
	var fy: float = cell.fy; var cx: float = cell.cx
	var fur := "#b07a40"; var saddle := "#2a2018"; var belly := "#d8a868"; var vest := "#1d2c6b"
	var bob := 0.0; var stretch := 0.0; var head_dy := 0.0; var mouth := false; var tongue := false
	var legs := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]   # fx/lift for far-front, far-back, near-front, near-back
	var eyes := "open"; var tail := 0.0; var lying := false; var snarl := false
	match state:
		"idle":
			bob = i % 2; tongue = true; mouth = true; tail = i
		"walk":
			var gx := [5.0, 3.0, -1.0, -5.0, -2.0, 3.0]; var gl := [0.0, 2.0, 3.0, 0.0, 0.0, 0.0]
			var f := i % 6; var g := (i + 3) % 6
			legs = [[gx[f], gl[f]], [gx[g], gl[g]], [gx[(f + 1) % 6], gl[(f + 1) % 6]], [gx[(g + 1) % 6], gl[(g + 1) % 6]]]
			bob = [0, 1, 2, 1, 0, 1][f]; stretch = [1, 2, 1, -1, -2, 0][f]; tongue = true; mouth = true; tail = f % 3
		"attack":
			stretch = [-3.0, 5.0, 2.0][i]; head_dy = [3.0, -3.0, 0.0][i]; mouth = true; bob = [2.0, -2.0, 0.0][i]; snarl = true; eyes = "angry"; tail = 2
			legs = [[-3.0, 0.0], [-4.0, 0.0], [8.0, 4.0], [-2.0, 0.0]] if i == 1 else [[-1.0, 0.0], [-3.0, 0.0], [1.0, 0.0], [-2.0, 0.0]]
		"hurt":
			eyes = "shut"; head_dy = -2; bob = 1; tail = -2; mouth = true
		"frozen":
			eyes = "wide"; legs = [[3.0, 0.0], [-3.0, 0.0], [4.0, 0.0], [-4.0, 0.0]]
		"stunned":
			eyes = "dizzy"; bob = 2; head_dy = 3; tail = -2; mouth = true; tongue = true
		"death":
			eyes = "x"; lying = i >= 2; bob = [1.0, 3.0, 0.0, 0.0][i]; mouth = true; tongue = i >= 2
	var body_y := fy - 15 + bob
	if lying:
		return _dog_lying(cell, fur, saddle, belly, vest, i)
	var hx := cx + 12 + stretch; var hy := body_y - 6 + head_dy
	# tail (behind)
	p.layer(4)
	p.line(cx - 13 - stretch * 0.5, body_y - 2, cx - 18 - stretch * 0.5, body_y - 7 - tail * 2, fur, 3)
	p.line(cx - 17 - stretch * 0.5, body_y - 6 - tail * 2, cx - 19 - stretch * 0.5, body_y - 9 - tail * 2, saddle, 2)
	# far legs
	_dog_leg(p, Vector2(cx + 8 + stretch * 0.5, body_y + 2), legs[0], fy, shade(fur, -0.2), 5.0)
	_dog_leg(p, Vector2(cx - 9 - stretch * 0.5, body_y + 2), legs[1], fy, shade(fur, -0.2), 5.0)
	# body
	_blob(p, cx - stretch * 0.25, body_y, 14 + stretch * 0.5, 6, fur, 10, 6)
	p.layer(15, Profiles.dome(cx - 2, body_y - 3, 10, 3, 2))
	p.ell(cx - 3, body_y - 3, 10 + stretch * 0.4, 3, saddle)
	p.R(cx - 8, body_y + 3, 16, 2, belly)
	if snarl:
		p.layer(16)
		for k in 4: p.R(cx - 6 + k * 3, body_y - 7 - (k % 2), 2, 2, saddle)
	# K9 vest
	p.layer(16, Profiles.slab(cx - 4, body_y - 5, cx + 6, body_y + 4, 2, 1))
	p.R(cx - 4, body_y - 5, 10, 9, vest); p.R(cx - 4, body_y - 5, 10, 1, shade(vest, 0.3))
	p.R(cx - 2, body_y - 2, 6, 2, "#ffd23c")
	p.R(cx-3,body_y-4,2,8,"#101b3d"); p.R(cx+3,body_y-4,2,8,"#101b3d")
	p.R(cx-1,body_y+1,3,2,"#b7c8d4"); p.P(cx,body_y+1,"#f5ead0")
	p.R(cx-1,body_y-2,4,1,"#fff0a0")
	# near legs
	_dog_leg(p, Vector2(cx + 10 + stretch * 0.5, body_y + 2), legs[2], fy, fur, 12.0)
	_dog_leg(p, Vector2(cx - 7 - stretch * 0.5, body_y + 2), legs[3], fy, fur, 12.0)
	# neck + head
	p.layer(14); p.line(cx + 8 + stretch * 0.5, body_y - 2, hx - 2, hy + 2, fur, 6)
	_blob(p, hx, hy, 5, 5, fur, 16, 5)
	p.layer(20, Profiles.dome(hx + 5, hy + 2, 4, 2, 2))
	p.R(hx + 2, hy + 1, 7, 4, fur); p.R(hx + 2, hy + 1, 7, 1, shade(fur, 0.25))    # muzzle
	p.R(hx + 8, hy + 1, 2, 2, "#111111")                                           # nose
	p.layer(18); p.R(hx - 1, hy - 4, 6, 2, saddle)
	for e in [[hx - 3, 0.0, shade(saddle, -0.1)], [hx + 1, 1.0, saddle]]:   # upright pointed ears, far one darker
		var ex: float = e[0]
		p.layer(18 + e[1] * 2)
		p.R(ex - 1, hy - 6, 4, 2, e[2]); p.R(ex - 1, hy - 8, 3, 2, e[2]); p.R(ex - 1, hy - 10, 2, 2, e[2]); p.P(ex - 1, hy - 11, e[2])
		p.R(ex, hy - 7, 1, 3, "#c87a6a")
	if snarl:   # bared fangs, wrinkled muzzle
		p.layer(21); p.R(hx + 2, hy + 4, 8, 4, "#2a1410"); p.R(hx + 3, hy + 6, 5, 1, "#a83040")
		p.R(hx + 3, hy + 4, 7, 1, "#f4f0e0"); p.P(hx + 4, hy + 5, "#f4f0e0"); p.P(hx + 8, hy + 5, "#f4f0e0")
		p.R(hx + 3, hy + 7, 6, 1, "#f4f0e0"); p.P(hx + 5, hy + 6, "#f4f0e0")
		p.P(hx + 4, hy + 1, shade(fur, -0.35)); p.P(hx + 6, hy + 1, shade(fur, -0.35))
	elif mouth:
		p.layer(20); p.R(hx + 3, hy + 5, 6, 2, "#2a1410"); p.P(hx + 6, hy + 5, "#ffffff"); p.P(hx + 8, hy + 5, "#ffffff")
		if tongue: p.R(hx + 4, hy + 6, 3, 3, "#e86070")
	p.layer(20)
	match eyes:
		"open": p.R(hx + 1, hy - 1, 2, 2, "#111111"); p.P(hx + 1, hy - 1, "#ffffff")
		"angry":
			p.R(hx + 1, hy - 1, 2, 2, "#111111"); p.P(hx + 2, hy - 1, "#ff5a3a")
			p.R(hx, hy - 3, 3, 1, shade(saddle, -0.2)); p.P(hx + 3, hy - 2, shade(saddle, -0.2))   # furrowed brow
		"shut": p.R(hx, hy, 3, 1, "#111111")
		"wide": p.R(hx, hy - 2, 3, 3, "#ffffff"); p.P(hx + 1, hy - 1, "#111111")
		"dizzy": p.ring(hx + 1, hy, 1, "#111111")
		"x": p.P(hx, hy - 1, "#111"); p.P(hx + 2, hy - 1, "#111"); p.P(hx + 1, hy, "#111"); p.P(hx, hy + 1, "#111"); p.P(hx + 2, hy + 1, "#111")
	p.layer(17); p.R(hx - 3, hy + 3, 3, 3, "#c83030"); p.P(hx - 2, hy + 5, "#ffd23c")   # collar + tag
	if state == "frozen": _ice_crust(c, cell, 6)
	return c

func _dog_leg(p: Pen, hip: Vector2, g: Array, fy: float, col: String, base: float) -> void:
	var foot := Vector2(hip.x + g[0], fy - g[1])
	var knee := (hip + foot) * 0.5 + Vector2(-1, 0)
	_seg(p, hip, knee, 4, col, base); _seg(p, knee, foot - Vector2(0, 1), 3, col, base + 1)
	p.layer(base + 2); p.R(foot.x - 1, foot.y - 2, 4, 2, shade(col, -0.3))

func _dog_lying(cell: Dictionary, fur: String, saddle: String, belly: String, vest: String, i: int) -> Pixels:
	var c := Pixels.new(cell.w, cell.h); var p := Pen.new(c, 0, 0)
	var fy: float = cell.fy; var cx: float = cell.cx
	var by := fy - 6.0 - (1 if i == 2 else 0)
	p.layer(4); p.line(cx - 14, by, cx - 21, by + 2, fur, 3)
	for k in 2: _seg(p, Vector2(cx + 6 + k * 3, by + 2), Vector2(cx + 13 + k * 3, by + 4), 3, shade(fur, -0.2), 5)
	_blob(p, cx - 2, by, 14, 5, fur, 9, 5)
	p.layer(13); p.ell(cx - 3, by - 3, 10, 2, saddle)
	p.R(cx - 5, by - 4, 9, 7, vest); p.R(cx - 3, by - 2, 5, 2, "#ffd23c")
	for k in 2: _seg(p, Vector2(cx - 8 + k * 14, by + 3), Vector2(cx - 4 + k * 14, by + 6), 3, fur, 12)
	_blob(p, cx + 15, by + 1, 5, 4, fur, 14, 4)
	p.layer(18); p.R(cx + 17, by + 1, 6, 3, fur); p.R(cx + 22, by + 1, 2, 2, "#111")
	p.line(cx + 13, by - 2, cx + 10, by - 5, saddle, 3)
	var e := Vector2(cx + 15, by - 1)
	p.P(e.x, e.y, "#111"); p.P(e.x + 2, e.y, "#111"); p.P(e.x + 1, e.y + 1, "#111"); p.P(e.x, e.y + 2, "#111"); p.P(e.x + 2, e.y + 2, "#111")
	if i >= 2: p.R(cx + 19, by + 4, 2, 3, "#e86070")
	return c

# ---------------------------------------------------------------- drone
func _drone(state: String, i: int) -> Pixels:
	var cell: Dictionary = CELLS.drone
	var c := Pixels.new(cell.w, cell.h); var p := Pen.new(c, 0, 0)
	var cx: float = cell.cx; var fy: float = cell.fy
	var body := "#4a5560"; var arm := "#2a3038"
	var y := fy - 22.0; var tilt := 0.0; var rotor := i % 4; var broken := false; var lens := "#ff3a3a"
	match state:
		"idle", "walk": y += [0.0, -1.0, 0.0, 1.0][i % 4]; tilt = 1.0 if state == "walk" else 0.0
		"attack": tilt = 3.0; lens = "#ffffff"; y += i
		"hurt": tilt = -2.0; rotor = 0; lens = "#ffd23c"
		"frozen": rotor = 0
		"stunned": tilt = [-3.0, 3.0][i]; rotor = i
		"death":
			broken = true; tilt = [-4.0, 6.0, 0.0, 0.0][i]; y = [fy - 18, fy - 10, fy - 5, fy - 5][i]; rotor = -1; lens = "#3a1010"
	# arms + rotors
	for side in [-1, 1]:
		var ax: float = cx + side * 13; var ay: float = y - 4 + side * tilt * 0.5
		if broken and i >= 2 and side == 1: ax -= 3; ay += 3
		_seg(p, Vector2(cx + side * 4, y - 1 + side * tilt * 0.2), Vector2(ax, ay), 3, arm, 6)
		p.layer(9, Profiles.dome(ax, ay - 1, 2, 2, 2)); p.R(ax - 1, ay - 3, 3, 3, "#1a1e24")
		if rotor >= 0:
			p.layer(10)
			var blades := [[9, 1], [6, 1], [3, 1], [6, 1]]
			var bw: int = blades[rotor][0]
			p.alpha = 0.55 if state != "frozen" else 1.0
			p.R(ax - bw, ay - 4, bw * 2 + 1, 1, "#c8ccd4" if state != "frozen" else "#e8faff")
			p.alpha = 1.0
			p.P(ax - bw, ay - 4, "#e8ecf0"); p.P(ax + bw, ay - 4, "#e8ecf0")
			p.layer(11); p.R(ax - 9, ay - 3, 2, 2, arm); p.R(ax + 8, ay - 3, 2, 2, arm); p.R(ax - 8, ay - 2, 17, 1, shade(arm, 0.15))   # rotor guard
		elif not (broken and i >= 2 and side == 1):
			p.layer(10); p.line(ax - 4, ay - 4, ax + 3, ay - 3 + side, "#7a7e88")
	# body pod
	_blob(p, cx, y, 10, 6, body, 12, 6)
	p.layer(18, Profiles.slab(cx - 7, y - 4, cx + 7, y - 2, 2, 1))
	p.R(cx - 6, y - 4, 13, 2, "#6a7684"); p.R(cx - 4, y - 6, 9, 2, "#2a3038")    # top plate, light-bar mount
	var lit := -1 if broken or state == "frozen" else i % 2
	p.layer(20, Profiles.slab(cx - 4, y - 8, cx + 5, y - 6, 2, 1))
	p.R(cx - 4, y - 8, 4, 2, "#ff4a4a" if lit == 0 else "#6a1a22"); p.R(cx + 1, y - 8, 4, 2, "#4a8cff" if lit == 1 else "#1a2a5a")
	if lit == 0: p.P(cx - 3, y - 8, "#ffd0d0")
	if lit == 1: p.P(cx + 2, y - 8, "#d0e4ff")
	# camera eye on the front
	p.layer(20, Profiles.dome(cx + 5, y + 1, 3, 3, 3))
	p.ell(cx + 5, y + 1, 3, 3, "#14181e"); p.ell(cx + 6, y + 1, 1, 1, lens); p.P(cx + 5, y, "#ffffff")
	# police stripe
	p.layer(16); p.R(cx - 8, y + 2, 10, 1, "#2f4fb8"); p.R(cx - 8, y + 3, 10, 1, "#e8e8f0")
	# landing skids
	p.layer(21)
	for vent in 3: p.R(cx-7+vent*3,y-2,1,2,"#202b3b")
	p.R(cx-6,y-4,5,1,"#a4bcc9"); p.P(cx-8,y,"#d6e3e7"); p.P(cx+1,y+4,"#8297a8")
	p.layer(8); p.R(cx - 6, y + 5, 2, 3, arm); p.R(cx + 4, y + 5, 2, 3, arm); p.R(cx - 8, y + 8, 16, 1, arm)
	if broken:
		p.layer(22)
		p.line(cx - 4, y - 3, cx, y + 2, "#111111"); p.line(cx, y + 2, cx - 2, y + 4, "#111111")
		if i >= 2: p.R(cx + 9, fy - 1, 3, 1, "#3a4048"); p.R(cx - 14, fy - 1, 2, 1, "#3a4048")
	var out := c
	if absf(tilt) > 0.5 and not (broken and i >= 2):
		out = _rotated(c, -tilt * 3.0, Vector2(cx, y), fy, 0)
		# _rotated grounds the sprite; lift it back to hover height
		out = _lift(out, int(fy - _bottom(c)))
	if state == "frozen": _ice_crust(out, {"fy": y + 9, "cx": cx}, 5)
	return out

func _bottom(c: Pixels) -> int:
	for y in range(c.height - 1, -1, -1):
		for x in c.width:
			if c.image.get_pixel(x, y).a > 0.0: return y
	return c.height - 1

func _lift(c: Pixels, dy: int) -> Pixels:
	if dy == 0: return c
	var out := Pixels.new(c.width, c.height)
	for y in c.height:
		var sy := y + dy
		if sy < 0 or sy >= c.height: continue
		for x in c.width:
			var col := c.image.get_pixel(x, sy)
			if col.a <= 0.0: continue
			out.image.set_pixel(x, y, col); out.depth[y * c.width + x] = c.depth[sy * c.width + x]; out.occupied[y * c.width + x] = c.occupied[sy * c.width + x]
	return out
