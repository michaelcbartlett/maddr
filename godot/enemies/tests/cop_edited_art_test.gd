extends SceneTree
const Sheets = preload("res://enemies/enemy_sheets.gd")
const Painter = preload("res://enemies/enemy_painter.gd")
const Edited = preload("res://enemies/cop_edited_art.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	var sheet := Sheets.build("cop")
	for state in Sheets.EditedArt.manifest().cop:
		var source := Edited.clip(state)
		_check(sheet.frames[state].size() == int(source.metadata.frame_count), state + " frame count")
		for i in sheet.frames[state].size():
			var expected := Edited.frame(state, i)
			var rect := Rect2i(sheet.frames[state][i])
			var art: Image = sheet.albedo.get_region(rect)
			var normal: Image = sheet.normal.get_region(rect)
			_check(art.get_data() == expected.art.get_data(), "%s/%d uses the edited artwork" % [state, i])
			_check(normal.get_data() == expected.normal.get_data(), "%s/%d uses matched normals" % [state, i])
			_check(sheet.anchors[state][i] == expected.anchors, "%s/%d uses edited joint anchors" % [state, i])
			var alpha_bad := 0
			var normal_bad := 0
			for y in art.get_height():
				for x in art.get_width():
					var a := art.get_pixel(x, y)
					var n := normal.get_pixel(x, y)
					if a.a != n.a: alpha_bad += 1
					if a.a > 0:
						var vector := Vector3(n.r * 2 - 1, n.g * 2 - 1, n.b * 2 - 1)
						if absf(vector.length() - 1.0) > 0.015 or vector.z < 0.0: normal_bad += 1
			_check(alpha_bad == 0, "%s/%d normals match the edited silhouette" % [state, i])
			_check(normal_bad == 0, "%s/%d normals are unit length and front facing" % [state, i])
			var mirrored: Image = sheet.tex_l.normal_texture.get_image()
			var mirror_rect := Rect2i(int(sheet.width) - rect.position.x - rect.size.x, rect.position.y, rect.size.x, rect.size.y)
			var mirror := mirrored.get_region(mirror_rect)
			mirror.flip_x()
			var data := mirror.get_data()
			for pixel in range(0, data.size(), 4):
				if data[pixel + 3] > 0: data[pixel] = 255 - data[pixel]
			_check(data == normal.get_data(), "%s/%d left-facing normals mirror correctly" % [state, i])
	for state in Painter.states("cop"): _check(Sheets.EditedArt.has("cop",state),state+" has imported art")
	_check(Edited.fps("walk") == 24.0 and Edited.fps("idle") == 24.0, "new cop uses 24 fps")
	var cached := Sheets.cached("cop")
	_check(cached.albedo.get_data() == sheet.albedo.get_data(), "disk cache includes edited artwork")
	_check(cached.normal.get_data() == sheet.normal.get_data(), "disk cache includes matched normals")
	print("EDITED COP ART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
