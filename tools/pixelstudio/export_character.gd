extends SceneTree
const Painter = preload("res://adapter_painter.gd")
const Original = preload("res://enemies/enemy_painter.gd")
const ORDER = ["far-upper-arm", "far-forearm", "far-hand", "far-thigh", "far-shin", "far-foot", "torso", "near-thigh", "near-shin", "near-foot", "head", "hair", "face", "hat", "near-upper-arm", "near-forearm", "near-hand", "baton"]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var animation := args[0] if not args.is_empty() else "walk"
	var out := args[1] if args.size() > 1 else "res://result.pixelstudio"
	if animation not in ["idle", "walk", "attack"]:
		push_error("The cop adapter supports idle, walk and attack.")
		quit(1)
		return
	var frames: Array = []
	var layers: Array = []
	var geometry_frames: Array = []
	var palette := {}
	var count: int = Original.states("cop")[animation]
	var size := Vector2i(66, 66)
	var empty := PackedByteArray()
	empty.resize(size.x * size.y * 4)
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for i in count:
		var painter := Painter.new()
		var canvas = painter.paint("cop", animation, i)
		var parts: Dictionary = canvas.export_parts()
		var composite := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var cels := {}
		var poses := {}
		for key in ORDER:
			if not parts.has(key): continue
			var id: String = "layer-" + key
			var img: Image = parts[key]
			composite.blend_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
			cels[id] = Marshalls.raw_to_base64(img.get_data())
			var pivot: Vector2 = canvas.joints[key]
			poses[id] = {"x": 0, "y": 0, "sx": 1, "sy": 1, "angle": 0, "px": pivot.x, "py": pivot.y}
			if i == 0:
				var layer := {"id": id, "name": key.capitalize(), "visible": true, "locked": false, "opacity": 100}
				if canvas.parents[key] != "": layer.parent = "layer-" + str(canvas.parents[key])
				layers.append(layer)
		# Verify against the unmodified game painter, including its selective outer outline.
		var expected: Image = Original.new().paint("cop", animation, i).outlined_image()
		if composite.get_data() != expected.get_data():
			push_error("Part reconstruction differs from the game: " + animation + " frame " + str(i))
			quit(1)
			return
		var pose: Dictionary = painter._pose("cop", animation, i)
		var direction := float(pose.an + pose.an_bend + (90.0 if pose.prop == "attack" else 25.0))
		var angle := 90.0 - direction
		poses["layer-baton"].attachmentAngle = angle
		var hand: Vector2 = canvas.joints.baton
		var rgba := composite.get_data()
		for pixel in range(0, rgba.size(), 4):
			if rgba[pixel + 3] > 0: palette["#%02x%02x%02x" % [rgba[pixel], rgba[pixel + 1], rgba[pixel + 2]]] = true
		frames.append({"base": Marshalls.raw_to_base64(empty), "original": Marshalls.raw_to_base64(rgba),
			"overlay": Marshalls.raw_to_base64(empty), "mask": Marshalls.raw_to_base64(mask),
			"cels": cels, "poses": poses, "hold": 1, "maps": {}, "gradientBoxes": [], "gradientBoxIndex": -1,
			"socket": {"x": hand.x, "y": hand.y, "angle": angle}})
		composite.save_png(out.get_base_dir().path_join("frame-%02d.png" % i))
		var geometry := {}
		for key in ORDER: geometry["layer-" + key] = Marshalls.raw_to_base64(canvas.exported_depths[key].to_byte_array())
		var source_anchors := {}
		for key in painter.anchors:
			var at: Vector2 = painter.anchors[key] + Vector2.ONE
			source_anchors[key] = [at.x, at.y]
		geometry_frames.append({"parts": geometry, "anchors": source_anchors,
			"depth": Marshalls.raw_to_base64(canvas.depth.to_byte_array()),
			"normal": Marshalls.raw_to_base64(canvas.normal_image().get_data())})
	var project := {"format": "pixel-motion-studio", "version": 2, "width": size.x, "height": size.y,
		"fps": 7.2 if animation == "walk" else 6.0, "currentFrame": 0, "activeLayer": "layer-baton",
		"layers": layers, "palette": palette.keys().slice(0, 64), "frames": frames, "reference": null,
		"settings": {"clipMask": false, "rigFollow": true, "rigBones": true, "showSocket": true, "exScale": 1},
		"godotSource": {"adapter": "mad-villain-cop-v1", "character": "cop", "animation": animation,
			"script": "enemies/enemy_painter.gd", "lighting": "generated-from-current-artwork"}}
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
	print("Exported ", count, " frames and ", layers.size(), " linked parts; every frame matches the game.")
	quit()
