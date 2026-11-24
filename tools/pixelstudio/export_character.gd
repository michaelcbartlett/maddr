extends SceneTree
## Exports any enemy_painter kind/state as a PixelStudio v2 project.
## Humanoids become linked puppets (arms, legs, head, prop...). Anything whose parts cannot
## reproduce the game pixel-for-pixel (dogs, drones, machines, death tumbles) opens as one
## flat, fully paintable "art" layer instead, so every clip in the game is editable.
const Painter = preload("res://adapter_painter.gd")
const Original = preload("res://enemies/enemy_painter.gd")
const ORDER = ["cape", "back-hair", "far-upper-arm", "far-forearm", "far-hand", "far-thigh", "far-shin", "far-foot", "torso", "near-thigh", "near-shin", "near-foot", "head", "hair", "face", "hat", "near-upper-arm", "near-forearm", "near-hand", "baton"]
const FPS = {"walk": 7.2, "panic": 9.0}
var geometry_frames: Array = []
var expected_painters: Array = []

func _anchors(painter) -> Dictionary:
	var result := {}
	for key in painter.anchors:
		var at: Vector2 = painter.anchors[key] + Vector2.ONE
		result[key] = [at.x, at.y]
	return result

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == "--catalog":
		var catalog := []
		for kind in Original.KINDS:
			var cell: Dictionary = Original.CELLS[Original.family(kind)]
			catalog.append({"id": kind, "family": Original.family(kind), "states": Original.states(kind),
				"cell": [cell.w + 2, cell.h + 2], "origin": [cell.cx + 1, cell.fy + 1]})
		print("CATALOG:" + JSON.stringify(catalog))
		quit()
		return
	var kind := args[0] if args.size() > 0 else "cop"
	var animation := args[1] if args.size() > 1 else "walk"
	var out := args[2] if args.size() > 2 else "res://result.pixelstudio"
	if kind not in Original.KINDS or not Original.states(kind).has(animation):
		push_error("Unknown character clip: " + kind + " " + animation)
		quit(1)
		return
	var count: int = Original.states(kind)[animation]
	var expected_frames: Array = []
	expected_painters = []
	for i in count:
		var original := Original.new()
		expected_frames.append(original.paint(kind, animation, i))
		expected_painters.append(original)
	var first: Image = expected_frames[0].outlined_image()
	var size := first.get_size()
	geometry_frames = []
	var project = _layered(kind, animation, count, size, expected_frames)
	if project == null:
		geometry_frames = []
		project = _flat(kind, animation, count, size, expected_frames)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if not file:
		push_error("Could not write the editable project.")
		quit(1)
		return
	file.store_string(JSON.stringify(project))
	file.close()
	var geometry_file := FileAccess.open(out.get_base_dir().path_join("source-geometry.json"), FileAccess.WRITE)
	geometry_file.store_string(JSON.stringify({"width": size.x, "height": size.y, "frames": geometry_frames}))
	geometry_file.close()
	for i in count:
		var strip_frame: Dictionary = project.frames[i]
		var png := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, Marshalls.base64_to_raw(strip_frame.original))
		png.save_png(out.get_base_dir().path_join("frame-%02d.png" % i))
	print("Exported ", kind, " ", animation, ": ", count, " frames, ", project.layers.size(), " layers.")
	quit()

func _empty(size: Vector2i, channels: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * channels)
	return Marshalls.raw_to_base64(bytes)

func _palette(palette: Dictionary, rgba: PackedByteArray) -> void:
	for pixel in range(0, rgba.size(), 4):
		if rgba[pixel + 3] > 0: palette["#%02x%02x%02x" % [rgba[pixel], rgba[pixel + 1], rgba[pixel + 2]]] = true

func _project(kind: String, animation: String, size: Vector2i, layers: Array, frames: Array, palette: Dictionary, active: String, adapter: String) -> Dictionary:
	return {"format": "pixel-motion-studio", "version": 2, "width": size.x, "height": size.y,
		"fps": FPS.get(animation, 6.0), "currentFrame": 0, "activeLayer": active,
		"layers": layers, "palette": palette.keys().slice(0, 64), "frames": frames, "reference": null,
		"settings": {"clipMask": false, "rigFollow": true, "rigBones": true, "showSocket": true, "exScale": 1},
		"godotSource": {"adapter": adapter, "character": kind, "animation": animation,
			"script": "enemies/enemy_painter.gd", "lighting": "generated-from-current-artwork"}}

func _layered(kind: String, animation: String, count: int, size: Vector2i, expected_frames: Array):
	if Original.family(kind) not in ["human", "hero"] or kind in ["interceptor", "tank", "robodog", "vex_sentry", "vex_mine"] or animation == "death":
		return null
	var frames: Array = []
	var layers: Array = []
	var seen := {}
	var palette := {}
	var empty := _empty(size, 4)
	var mask := _empty(size, 1)
	for i in count:
		var painter := Painter.new()
		var canvas = painter.paint(kind, animation, i)
		if not canvas.has_method("export_parts"): return null
		var parts: Dictionary = canvas.export_parts()
		var composite := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var cels := {}
		var poses := {}
		for key in ORDER:
			if not parts.has(key): continue
			var id: String = "layer-" + key
			var img: Image = parts[key]
			if img.get_size() != size: return null
			composite.blend_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
			cels[id] = Marshalls.raw_to_base64(img.get_data())
			var pivot: Vector2 = canvas.joints[key]
			poses[id] = {"x": 0, "y": 0, "sx": 1, "sy": 1, "angle": 0, "px": pivot.x, "py": pivot.y}
			if not seen.has(key):
				seen[key] = true
				var name: String = key.capitalize()
				if key == "baton" and kind != "cop": name = "Held prop"
				var layer := {"id": id, "name": name, "visible": true, "locked": false, "opacity": 100}
				if canvas.parents[key] != "": layer.parent = "layer-" + str(canvas.parents[key])
				layers.append(layer)
		# Verify against the unmodified game painter, including its selective outer outline.
		if composite.get_data() != expected_frames[i].outlined_image().get_data():
			return null
		var frame := {"base": empty, "original": Marshalls.raw_to_base64(composite.get_data()),
			"overlay": empty, "mask": mask, "cels": cels, "poses": poses, "hold": 1, "maps": {},
			"gradientBoxes": [], "gradientBoxIndex": -1}
		if poses.has("layer-baton"):
			var pose: Dictionary = painter._pose(kind, animation, i)
			var direction := float(pose.an + pose.an_bend + (90.0 if pose.prop == "attack" else 25.0))
			var angle := 90.0 - direction
			poses["layer-baton"].attachmentAngle = angle
			var hand: Vector2 = canvas.joints.baton
			frame.socket = {"x": hand.x, "y": hand.y, "angle": angle}
		_palette(palette, composite.get_data())
		frames.append(frame)
		var geometry := {}
		for key in parts: geometry["layer-" + key] = Marshalls.raw_to_base64(canvas.exported_depths[key].to_byte_array())
		geometry_frames.append({"parts": geometry, "anchors": _anchors(painter),
			"depth": Marshalls.raw_to_base64(canvas.depth.to_byte_array()),
			"normal": Marshalls.raw_to_base64(canvas.normal_image().get_data())})
	# Every frame needs a cel for every layer, even where that part is not drawn.
	var ids := layers.map(func(l): return l.id)
	ids.sort_custom(func(a, b): return ORDER.find(a.substr(6)) < ORDER.find(b.substr(6)))
	var ordered: Array = []
	for id in ids: ordered.append(layers.filter(func(l): return l.id == id)[0])
	for frame in frames:
		for id in ids:
			if not frame.cels.has(id):
				frame.cels[id] = empty
				frame.poses[id] = {"x": 0, "y": 0, "sx": 1, "sy": 1, "angle": 0, "px": 0, "py": 0}
	var active: String = "layer-baton" if ids.has("layer-baton") else "layer-torso"
	return _project(kind, animation, size, ordered, frames, palette, active, "mad-villain-%s-v1" % ("cop" if kind == "cop" else "humanoid"))

func _flat(kind: String, animation: String, count: int, size: Vector2i, expected_frames: Array) -> Dictionary:
	var frames: Array = []
	var palette := {}
	var empty := _empty(size, 4)
	var mask := _empty(size, 1)
	for i in count:
		var source = expected_frames[i]
		var img: Image = source.outlined_image()
		var cropped := PackedFloat32Array()
		cropped.resize(size.x * size.y)
		for y in mini(size.y, source.height):
			for x in mini(size.x, source.width):
				cropped[y * size.x + x] = source.depth[y * source.width + x]
		var normal: Image = source.normal_image()
		var normal_fit := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		normal_fit.blit_rect(normal, Rect2i(Vector2i.ZERO, normal.get_size()), Vector2i.ZERO)
		geometry_frames.append({"parts": {"layer-art": Marshalls.raw_to_base64(cropped.to_byte_array())},
			"anchors": _anchors(expected_painters[i]), "depth": Marshalls.raw_to_base64(cropped.to_byte_array()),
			"normal": Marshalls.raw_to_base64(normal_fit.get_data())})
		if img.get_size() != size:
			var padded := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			padded.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
			img = padded
		var rgba := img.get_data()
		_palette(palette, rgba)
		frames.append({"base": empty, "original": Marshalls.raw_to_base64(rgba), "overlay": empty, "mask": mask,
			"cels": {"layer-art": Marshalls.raw_to_base64(rgba)},
			"poses": {"layer-art": {"x": 0, "y": 0, "sx": 1, "sy": 1, "angle": 0, "px": size.x / 2.0, "py": size.y / 2.0}},
			"hold": 1, "maps": {}, "gradientBoxes": [], "gradientBoxIndex": -1})
	var layers := [{"id": "layer-art", "name": kind.capitalize() + " art", "visible": true, "locked": false, "opacity": 100}]
	return _project(kind, animation, size, layers, frames, palette, "layer-art", "mad-villain-flat-v1")
