extends RefCounted
## User-authored PixelStudio clips for any enemy kind, with physical normals rebuilt in the edited pose.
## tools/pixelstudio/match_cop_normals.py installs a clip as art/enemies/<kind>/<kind>_<state>{.png,_n.png,.json}
## and lists it in MANIFEST. Clips not listed there keep their procedural art.
const MANIFEST := "res://art/enemies/edited.json"
static var _clips := {}
static var _manifest = null
static var _signature := ""

static func manifest() -> Dictionary:
	if _manifest == null:
		_manifest = {}
		if FileAccess.file_exists(MANIFEST):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
			if parsed is Dictionary: _manifest = parsed
	return _manifest

static func has(kind: String, state: String) -> bool:
	return state in manifest().get(kind, [])

static func _path(kind: String, state: String, suffix: String) -> String:
	return "res://art/enemies/%s/%s_%s%s" % [kind, kind, state, suffix]

static func _image(path: String) -> Image:
	# Imported textures in the editor/exports; raw PNGs for freshly installed clips not yet imported.
	if ResourceLoader.exists(path):
		var texture = load(path)
		if texture is Texture2D: return texture.get_image()
	return Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null

static func clip(kind: String, state: String) -> Dictionary:
	var key := kind + "/" + state
	if _clips.has(key): return _clips[key]
	if not has(kind, state): return {}
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(_path(kind, state, ".json")))
	var art := _image(_path(kind, state, ".png"))
	var normal := _image(_path(kind, state, "_n.png"))
	if not metadata is Dictionary or art == null or normal == null:
		push_error("Could not load edited " + key)
		_clips[key] = {}
		return {}
	art.convert(Image.FORMAT_RGBA8)
	normal.convert(Image.FORMAT_RGBA8)
	var count := int(metadata.frame_count)
	var cell := Vector2i(int(metadata.frame_width), int(metadata.frame_height))
	if art.get_size() != Vector2i(cell.x * count, cell.y) or normal.get_size() != art.get_size() or metadata.anchors.size() != count:
		push_error("Edited art, normals and anchors must have matching frames: " + key)
		_clips[key] = {}
		return {}
	_clips[key] = {"art": art, "normal": normal, "metadata": metadata, "cell": cell}
	return _clips[key]

static func frame(kind: String, state: String, index: int) -> Dictionary:
	var source := clip(kind, state)
	if source.is_empty(): return {}
	var i := posmod(index, int(source.metadata.frame_count))
	var rect := Rect2i(Vector2i(i * source.cell.x, 0), source.cell)
	var anchors := {}
	for name in source.metadata.anchors[i]:
		var point: Array = source.metadata.anchors[i][name]
		anchors[name] = Vector2(float(point[0]), float(point[1]))
	return {"art": source.art.get_region(rect), "normal": source.normal.get_region(rect), "anchors": anchors}

static func fps(kind: String, state: String, fallback: float) -> float:
	var source := clip(kind, state)
	return float(source.metadata.fps) if not source.is_empty() else fallback

static func cache_signature() -> String:
	if _signature != "": return _signature
	var data := JSON.stringify(manifest())
	for kind in manifest():
		for state in manifest()[kind]:
			data += FileAccess.get_file_as_string(_path(kind, state, ".json"))
			var source := clip(kind, state)
			if not source.is_empty():
				data += source.art.get_data().hex_encode().sha256_text()
				data += source.normal.get_data().hex_encode().sha256_text()
	_signature = data.sha256_text()
	return _signature
