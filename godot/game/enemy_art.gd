extends RefCounted
class_name EnemyArt
## Enemy / civilian / hero sprite sheets. The art is painted procedurally in res://enemies/enemy_painter.gd
## (1 px per world px, height-mapped, normal-mapped, multi-frame states) and baked/cached by
## res://enemies/enemy_sheets.gd. Drawing lives in res://enemies/enemy_view.gd. See res://enemies/README.md.
const Sheets = preload("res://enemies/enemy_sheets.gd")
const Painter = preload("res://enemies/enemy_painter.gd")

## Civilian kinds; Enemy.setup() picks one of these keys (sprite key "civ_<kind>").
const CIVPALS := {"suit": {}, "tourist": {}, "granny": {}, "jogger": {}}

## sprite key -> sheet (see EnemySheets.build for the layout)
static var SPR: Dictionary = {}

## Loads (or bakes and caches) every sheet up front so no sprite is generated mid-combat.
static func build() -> void:
	for kind in Painter.KINDS: sheet(kind)

static func sheet(kind: String) -> Dictionary:
	if kind == "": kind = "drone"
	# Enemy definitions can arrive before their optional sheet. Keep combat rendering valid
	# until that kind is registered by the painter, without caching a failed sheet.
	if not Painter.KINDS.has(kind):
		kind = {"undercover":"det", "swat_shield":"riot", "guard":"swat", "robodog":"dog"}.get(kind, "cop")
	if not SPR.has(kind): SPR[kind] = Sheets.cached(kind)
	return SPR[kind]
