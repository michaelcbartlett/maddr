extends SceneTree
## Every clip listed in art/enemies/edited.json replaces its procedural frames in the baked sheet,
## with matching normals and anchors; unlisted states of the same kind keep the painter's art.
const Sheets = preload("res://enemies/enemy_sheets.gd")
const Painter = preload("res://enemies/enemy_painter.gd")
const Edited = preload("res://enemies/edited_art.gd")
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
	var manifest := Edited.manifest()
	for kind in manifest:
		_check(kind in Painter.KINDS, kind + " is a game character")
		var sheet := Sheets.build(kind)
		for state in Sheets.states(kind):
			var edited := Edited.has(kind, state)
			if edited:
				_check(not Edited.clip(kind, state).is_empty(), "%s %s loads" % [kind, state])
				_check(sheet.frames[state].size() == int(Edited.clip(kind, state).metadata.frame_count), "%s %s frame count" % [kind, state])
			for i in sheet.frames[state].size():
				var rect := Rect2i(sheet.frames[state][i])
				var art: Image = sheet.albedo.get_region(rect)
				var normal: Image = sheet.normal.get_region(rect)
				if edited:
					var expected := Edited.frame(kind, state, i)
					_check(art.get_data() == expected.art.get_data(), "%s %s/%d uses the edited artwork" % [kind, state, i])
					_check(normal.get_data() == expected.normal.get_data(), "%s %s/%d uses matched normals" % [kind, state, i])
					_check(sheet.anchors[state][i] == expected.anchors, "%s %s/%d uses edited anchors" % [kind, state, i])
					var bad := 0
					for y in art.get_height():
						for x in art.get_width():
							if (art.get_pixel(x, y).a > 0) != (normal.get_pixel(x, y).a > 0): bad += 1
					_check(bad == 0, "%s %s/%d normals match the silhouette" % [kind, state, i])
				else:
					var original = Painter.new().paint(kind, state, i)
					_check(art.get_data() == original.outlined_image().get_data(), "%s %s/%d keeps procedural art" % [kind, state, i])
	print("EDITED ART: %d kinds, %d checks, %d failures" % [manifest.size(), checks, failures])
	quit(1 if failures else 0)
