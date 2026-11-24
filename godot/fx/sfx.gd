extends Node
## Autoload "Sfx": the prototype's synth blips (index.html snd()), pre-rendered to AudioStreamWAV.
## play(name) — same frequency / duration / wave / volume / slide as the browser calls. Keyed sounds are throttled to 55 ms.
## "noise" is sample-and-hold white noise re-drawn at the sliding frequency (swishes, whip cracks, throws).

const RATE := 22050
# name: [freq, dur, wave, vol, slide, throttle]
const P := {
	"arrival": [720, .5, "saw", .035, 2.0, false],
	"break": [2400, .22, "saw", .045, .12, true],
	"las": [900, .07, "saw", .018, .5, true], "bul": [300, .05, "square", .02, .5, true], "raz": [1400, .06, "tri", .02, .6, true],
	"hum": [120, .12, "saw", .012, 1.1, true], "kill": [220, .06, "square", .03, .5, true], "bosskill": [80, .6, "square", .03, .5, false],
	"pick": [1200, .04, "square", .02, 1.3, true], "cash": [1600, .04, "square", .02, 1.3, true], "hurt": [150, .15, "saw", .06, .5, false],
	"boom": [90, .25, "saw", .06, .4, true], "zap": [1800, .05, "saw", .02, .4, true], "frz": [1200, .08, "tri", .04, 1.5, true],
	"mind": [330, .25, "sine", .05, 2.0, true], "ebul": [500, .05, "square", .015, .7, true], "slam": [50, .45, "saw", .08, .4, false],
	"charge": [120, .3, "saw", .05, 2.0, false], "leap": [220, .4, "square", .04, 2.0, false], "blink": [1600, .15, "saw", .05, .3, false],
	"shard": [1400, .08, "tri", .04, .6, false], "nova": [300, .5, "sine", .06, .3, false], "eyelaser": [200, .9, "saw", .06, 1.5, false],
	"moon": [60, .4, "saw", .07, .3, false], "crate": [660, .15, "square", .05, 1.5, false], "key": [880, .3, "tri", .06, 1.5, false],
	"gotkey": [1200, .3, "tri", .06, 1.5, false], "vault": [80, .6, "saw", .07, .5, false], "clear1": [523, .12, "square", .05, 0.0, false],
	"clear2": [784, .2, "square", .05, 0.0, false], "buy1": [880, .08, "square", .05, 0.0, false], "buy2": [1320, .1, "square", .04, 0.0, false],
	"ui": [500, .03, "square", .02, 0.0, true], "select": [440, .1, "square", .04, 0.0, false], "reroll": [600, .06, "square", .04, 0.0, false],
	"win": [660, .5, "saw", .06, 2.0, false], "lose": [200, .5, "saw", .06, .3, false], "siren": [700, .5, "tri", .04, 1.4, false],
	# bionic-arm melee: one swing per weapon, plus a body thud when it connects
	"punch": [140, .09, "square", .04, .5, true], "stab": [1700, .07, "tri", .03, .45, true],
	"slash": [2600, .16, "noise", .05, .25, true], "whip": [3400, .09, "noise", .06, .12, true], "thud": [95, .07, "square", .035, .6, true],
	"melt": [70, .5, "sine", .065, .25, false],         # radiation meltdown
	"throw": [700, .12, "noise", .03, .4, false],      # grenade toss
	"capshot": [1400, .18, "saw", .04, .3, true],      # Patience Capacitor charged laser
	"shrink": [900, .22, "sine", .05, .3, true], "squish": [180, .12, "noise", .06, .35, true],   # Shrink Ray
	"kick": [260, .1, "noise", .05, .5, true],   # Freeze Ray: booting an ice block
	"logo": [110, .35, "saw", .08, .5, false], "logo2": [1760, .25, "tri", .05, .6, false],   # AngryRatGames name sting
}

## Recorded or built weapon sounds: res://audio/weapons/<group>_1.wav (or .ogg) .. _N. Drop in replacements with
## the same names. group: [volume dB, throttle ms]
const GROUPS := {
	"gun_pistol": [-9.0, 45], "gun_blunder": [-7.0, 60], "gun_rifle": [-8.0, 60], "gun_repeater": [-11.0, 40],
	"blade": [-10.0, 45], "blade_ping": [-14.0, 60], "sword": [-9.0, 60], "knife": [-10.0, 50], "ricochet": [-17.0, 70], "bullet_hit": [-14.0, 45],
}
var _groups := {}
var _last_variant := {}
var _streams := {}
var _last := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 16:
		var p := AudioStreamPlayer.new(); add_child(p); _players.append(p)
	for k in P: _streams[k] = _render(P[k])
	for group in GROUPS:
		_groups[group] = []
		for i in range(1,17):
			for extension in ["wav","ogg"]:
				var path := "res://audio/weapons/%s_%d.%s" % [group,i,extension]
				if ResourceLoader.exists(path): _groups[group].append(load(path)); break

## Plays a random variant, never the same one twice in a row, with slight pitch and level drift.
func play_group(group: String) -> bool:
	var list: Array = _groups.get(group,[])
	if list.is_empty(): return false
	var now := Time.get_ticks_msec()
	if _last.has(group) and now-_last[group] < int(GROUPS[group][1]): return true
	_last[group] = now
	var index := randi()%list.size()
	if list.size()>1 and index == int(_last_variant.get(group,-1)): index = (index+1+randi()%(list.size()-1))%list.size()
	_last_variant[group] = index
	var p := _players[_next]; _next = (_next + 1) % _players.size()
	p.stream = list[index]; p.pitch_scale = randf_range(0.96,1.04); p.volume_db = float(GROUPS[group][0])+randf_range(-1.0,0.6); p.play()
	return true

func _render(d: Array) -> AudioStreamWAV:
	var f0: float = d[0]; var dur: float = d[1] + 0.02; var wave: String = d[2]; var vol: float = d[3]; var slide: float = d[4]
	var n := int(RATE * dur)
	var data := PackedByteArray(); data.resize(n * 2)
	var ph := 0.0
	var rng := RandomNumberGenerator.new(); rng.seed = int(f0 * 1000.0 + dur * 7919.0)
	var held := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := clampf(t / d[1], 0.0, 1.0)
		var f := f0 * (pow(maxf(20.0 / f0, slide), k) if slide > 0.0 else 1.0)   # exponential ramp, like the WebAudio call
		var wrapped := ph + f / RATE >= 1.0
		ph = fmod(ph + f / RATE, 1.0)
		if wave == "noise" and (wrapped or i == 0): held = rng.randf_range(-1.0, 1.0)
		var s := 0.0
		match wave:
			"square": s = 1.0 if ph < 0.5 else -1.0
			"saw": s = ph * 2.0 - 1.0
			"tri": s = 1.0 - 4.0 * absf(ph - 0.5)
			"noise": s = held
			_: s = sin(ph * TAU)
		var env := vol * pow(0.0001 / vol, k) if k < 1.0 else 0.0     # exponential decay to silence
		var v := clampi(int(s * env * 6.0 * 32767.0), -32767, 32767)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new(); w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = RATE; w.stereo = false; w.data = data
	return w

## Synth names that now have recordings.
const RECORDED := {"slash":"sword","stab":"knife"}

func play(name: String, pitch := 1.0) -> void:
	if not P.has(name): return
	if RECORDED.has(name) and play_group(RECORDED[name]): return
	var now := Time.get_ticks_msec()
	if P[name][5]:
		if _last.has(name) and now - _last[name] < 55: return
		_last[name] = now
	var p := _players[_next]; _next = (_next + 1) % _players.size()
	p.stream = _streams[name]; p.pitch_scale = pitch; p.volume_db = 0.0; p.play()
