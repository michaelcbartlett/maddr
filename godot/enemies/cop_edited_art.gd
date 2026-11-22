extends RefCounted
## User-authored PixelStudio poses, with physical normals rebuilt in the same transformed space.
const ART = {
	"idle": preload("res://art/enemies/cop/cop_idle.png"),
	"walk": preload("res://art/enemies/cop/cop_walk.png"),
	"attack": preload("res://art/enemies/cop/cop_attack.png")
}
const NORMAL = {
	"idle": preload("res://art/enemies/cop/cop_idle_n.png"),
	"walk": preload("res://art/enemies/cop/cop_walk_n.png"),
	"attack": preload("res://art/enemies/cop/cop_attack_n.png")
}
const META = {
	"idle": "res://art/enemies/cop/cop_idle.json",
	"walk": "res://art/enemies/cop/cop_walk.json",
	"attack": "res://art/enemies/cop/cop_attack.json"
}
static var _clips := {}
static var _signature := ""

static func clip(state: String) -> Dictionary:
	if not META.has(state): return {}
	if _clips.has(state): return _clips[state]
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(META[state]))
	var art: Image = ART[state].get_image()
	var normal: Image = NORMAL[state].get_image()
	if not metadata is Dictionary or art == null or normal == null:
		push_error("Could not load edited cop " + state)
		return {}
	art.convert(Image.FORMAT_RGBA8)
	normal.convert(Image.FORMAT_RGBA8)
	var count := int(metadata.frame_count)
	var cell := Vector2i(int(metadata.frame_width), int(metadata.frame_height))
	if art.get_size() != Vector2i(cell.x * count, cell.y) or normal.get_size() != art.get_size() or metadata.anchors.size() != count:
		push_error("Edited cop art, normals and anchors must have matching frames: " + state)
		return {}
	_clips[state] = {"art": art, "normal": normal, "metadata": metadata, "cell": cell}
	return _clips[state]

static func frame(state: String, index: int) -> Dictionary:
	var source := clip(state)
	if source.is_empty(): return {}
	var i := posmod(index, int(source.metadata.frame_count))
	var rect := Rect2i(Vector2i(i * source.cell.x, 0), source.cell)
	var anchors := {}
	for name in source.metadata.anchors[i]:
		var point: Array = source.metadata.anchors[i][name]
		anchors[name] = Vector2(float(point[0]), float(point[1]))
	return {"art": source.art.get_region(rect), "normal": source.normal.get_region(rect), "anchors": anchors}

static func fps(state: String) -> float:
	var source := clip(state)
	return float(source.metadata.fps) if not source.is_empty() else 6.0

static func cache_signature() -> String:
	if _signature != "": return _signature
	var data := ""
	for state in META:
		var source := clip(state)
		data += FileAccess.get_file_as_string(META[state])
		if not source.is_empty():
			data += source.art.get_data().hex_encode().sha256_text()
			data += source.normal.get_data().hex_encode().sha256_text()
	_signature = data.sha256_text()
	return _signature
