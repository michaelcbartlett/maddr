extends SceneTree
## Run with Godot --headless --path godot --script ../export/cop-walk/export_cop_walk.gd
const Painter = preload("res://enemies/enemy_painter.gd")

func _init() -> void:
	var out: String = get_script().resource_path.get_base_dir()
	var frames: Array = []
	var palette := {}
	var sheet := Image.create(66 * 8, 66, false, Image.FORMAT_RGBA8)
	var blank := PackedByteArray()
	blank.resize(66 * 66 * 4)
	var mask := PackedByteArray()
	mask.resize(66 * 66)
	for i in int(Painter.states("cop").walk):
		var painter := Painter.new()
		var canvas = painter.paint("cop", "walk", i)
		var image: Image = canvas.outlined_image()
		var normal: Image = canvas.normal_image()
		assert(image.get_size() == Vector2i(66, 66))
		assert(image.save_png(out.path_join("cop_walk_%02d.png" % (i + 1))) == OK)
		assert(normal.save_png(out.path_join("cop_walk_%02d_n.png" % (i + 1))) == OK)
		sheet.blit_rect(image, Rect2i(0, 0, 66, 66), Vector2i(i * 66, 0))
		var rgba := Marshalls.raw_to_base64(image.get_data())
		for y in 66:
			for x in 66:
				var color := image.get_pixel(x, y)
				if color.a > 0: palette["#" + color.to_html(false)] = true
		frames.append({
			"base": rgba, "original": rgba, "overlay": Marshalls.raw_to_base64(blank),
			"mask": Marshalls.raw_to_base64(mask), "hold": 1, "cels": {}, "poses": {},
			"maps": {"normal": Marshalls.raw_to_base64(normal.get_data())}, "socket": null,
			"gradientBoxes": [], "gradientBoxIndex": -1
		})
	var project := {
		"format": "pixel-motion-studio", "version": 2, "width": 66, "height": 66,
		"fps": 7.2, "currentFrame": 0, "activeLayer": "base", "palette": palette.keys().slice(0, 64),
		"layers": [
			{"id": "base", "name": "Cop artwork", "visible": true, "locked": false, "opacity": 100},
			{"id": "art", "name": "Overlay", "visible": true, "locked": false, "opacity": 100}
		],
		"settings": {"clipMask": false, "showSocket": false}, "reference": null, "frames": frames
	}
	var file := FileAccess.open(out.path_join("cop-walk.pixelstudio"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(project))
	file.close()
	assert(sheet.save_png(out.path_join("cop-walk-sheet.png")) == OK)
	print("Exported cop-walk.pixelstudio: 8 frames, 66 x 66, 7.2 FPS, original game art and normals.")
	quit()
