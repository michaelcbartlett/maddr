extends RefCounted
class_name EnemySheets
## Bakes every enemy sprite key into one atlas: albedo + OpenGL normal map (CanvasTexture) and a white
## silhouette used for the hit-flash / frozen / mind-control / sickness tints.
const Painter = preload("res://enemies/enemy_painter.gd")
const EditedArt = preload("res://enemies/edited_art.gd")
const COLUMNS := 8

## Edited clips may add states or replace the painter's original frame counts.
static func states(kind: String) -> Dictionary:
	var result: Dictionary = Painter.states(kind).duplicate()
	for state in EditedArt.manifest().get(kind, []):
		var source := EditedArt.clip(kind, state)
		if not source.is_empty(): result[state] = int(source.metadata.frame_count)
	return result

static func frame_origin(sheet: Dictionary, state: String) -> Vector2:
	var source := EditedArt.clip(sheet.kind, state)
	if source.is_empty(): return sheet.origin
	var point: Array = source.metadata.origin
	return Vector2(float(point[0]), float(point[1]))

## Sheet dictionary:
##   tex: CanvasTexture (diffuse + normal), sil: ImageTexture (white silhouette, same layout)
##   frames: {state: [Rect2, ...]}, anchors: {state: [{name: Vector2 relative to the foot point}, ...]}
##   origin: foot point inside a cell, foot: world px from the node origin down to the feet, cell: Vector2
static func build(kind: String) -> Dictionary:
	var painter := Painter.new()
	var states: Dictionary = states(kind)
	var cell: Dictionary = Painter.CELLS[Painter.family(kind)]
	var cw: int = cell.w + 2; var ch: int = cell.h + 2
	# Keep imported pixels at their native resolution; atlas slots fit the largest clip.
	for st in states:
		var source := EditedArt.clip(kind, st)
		if not source.is_empty():
			cw = maxi(cw, source.cell.x); ch = maxi(ch, source.cell.y)
	# Shelf packing: each state uses its own cell size, so a few wide death frames
	# do not inflate every walking frame.
	var sizes := {}; var width := cw * COLUMNS; var pen := Vector2i.ZERO; var shelf := 0
	var places := {}
	for st in states:
		var source := EditedArt.clip(kind, st)
		var slot: Vector2i = source.cell if not source.is_empty() else Vector2i(cell.w + 2, cell.h + 2)
		sizes[st] = slot; places[st] = []
		for i in int(states[st]):
			if pen.x + slot.x > width: pen = Vector2i(0, pen.y + shelf); shelf = 0
			places[st].append(pen); pen.x += slot.x; shelf = maxi(shelf, slot.y)
	var albedo := Image.create(width, pen.y + shelf, false, Image.FORMAT_RGBA8)
	var normal := Image.create(width, pen.y + shelf, false, Image.FORMAT_RGBA8)
	var origin := Vector2(cell.cx + 1, cell.fy + 1)
	var frames := {}; var anchors := {}
	var n := 0
	for st in states:
		frames[st] = []; anchors[st] = []
		for i in int(states[st]):
			var replacement := EditedArt.frame(kind, st, i)
			var img: Image
			var nrm: Image
			var local := {}
			if not replacement.is_empty():
				img = replacement.art
				nrm = replacement.normal
				local = replacement.anchors
			else:
				var canvas = painter.paint(kind, st, i)
				img = canvas.outlined_image()
				nrm = canvas.normal_image()
				for name in painter.anchors: local[name] = painter.anchors[name] + Vector2.ONE - origin
			var at: Vector2i = places[st][i]
			albedo.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
			normal.blit_rect(nrm, Rect2i(Vector2i.ZERO, nrm.get_size()), at)
			frames[st].append(Rect2(Vector2(at), Vector2(img.get_size())))
			anchors[st].append(local)
			n += 1
	return _finish({"kind": kind, "albedo": albedo, "normal": normal,
		"frames": frames, "anchors": anchors, "origin": origin, "foot": float(cell.foot), "cell": Vector2(cw, ch),
		"family": Painter.family(kind)})

## Adds the GPU textures: the right-facing atlas plus a baked mirror for left-facing sprites.
## (Godot does not flip a negative-width draw rect, and a mirrored normal map needs its x inverted.)
static func _finish(sheet: Dictionary) -> Dictionary:
	var albedo: Image = sheet.albedo; var normal: Image = sheet.normal
	sheet.tex = _canvas_texture(albedo, normal)
	sheet.sil = ImageTexture.create_from_image(silhouette(albedo))
	var albedo_l := albedo.duplicate() as Image; albedo_l.flip_x()
	var normal_l := normal.duplicate() as Image; normal_l.flip_x()
	var data := normal_l.get_data()
	for i in range(0, data.size(), 4):
		if data[i + 3] > 0: data[i] = 255 - data[i]
	normal_l = Image.create_from_data(normal_l.get_width(), normal_l.get_height(), false, Image.FORMAT_RGBA8, data)
	sheet.tex_l = _canvas_texture(albedo_l, normal_l)
	sheet.sil_l = ImageTexture.create_from_image(silhouette(albedo_l))
	sheet.width = float(albedo.get_width())
	return sheet

static func _canvas_texture(albedo: Image, normal: Image) -> CanvasTexture:
	var tex := CanvasTexture.new()
	tex.diffuse_texture = ImageTexture.create_from_image(albedo)
	tex.normal_texture = ImageTexture.create_from_image(normal)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tex

static func silhouette(src: Image) -> Image:
	var data := src.get_data()
	for i in range(0, data.size(), 4):
		if data[i + 3] > 0: data[i] = 255; data[i + 1] = 255; data[i + 2] = 255
	return Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8, data)

## Frame rect + anchors for a state, looping `index`.
static func frame(sheet: Dictionary, state: String, index: int) -> Rect2:
	var list: Array = sheet.frames.get(state, sheet.frames.idle)
	return list[posmod(index, list.size())]

static func anchor(sheet: Dictionary, state: String, index: int, name: String, fallback := Vector2.ZERO) -> Vector2:
	var list: Array = sheet.anchors.get(state, sheet.anchors.idle)
	if list.is_empty(): return fallback
	return list[posmod(index, list.size())].get(name, fallback)

# ---------------------------------------------------------------- disk cache
## Baking every sheet takes a few seconds of GDScript pixel work, so finished atlases are cached in
## user://enemy_sheets/. The key covers the painter/sheet sources (when readable) plus ART_VERSION;
## bump ART_VERSION after art changes if scripts are exported as binary tokens.
const ART_VERSION := 8
static var _cache_dir := ""

static func cache_dir() -> String:
	if _cache_dir != "": return _cache_dir
	var src := FileAccess.get_file_as_string("res://enemies/enemy_painter.gd") + FileAccess.get_file_as_string("res://enemies/enemy_sheets.gd") + FileAccess.get_file_as_string("res://enemies/machine_painter.gd")
	src += EditedArt.cache_signature()
	_cache_dir = "user://enemy_sheets/v%d_%x" % [ART_VERSION, src.hash() & 0x7fffffff]
	return _cache_dir

static func cached(kind: String, use_cache := true) -> Dictionary:
	var dir := cache_dir()
	if use_cache and FileAccess.file_exists(dir + "/" + kind + ".json"):
		var loaded := _load(dir, kind)
		if not loaded.is_empty(): return loaded
	var sheet := build(kind)
	if use_cache: _save(dir, sheet)
	return sheet

static func _save(dir: String, sheet: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var kind: String = sheet.kind
	sheet.albedo.save_png(dir + "/" + kind + ".png"); sheet.normal.save_png(dir + "/" + kind + "_n.png")
	var frames := {}; var anchors := {}
	for st in sheet.frames:
		frames[st] = []; anchors[st] = []
		for r in sheet.frames[st]: frames[st].append([r.position.x, r.position.y, r.size.x, r.size.y])
		for a in sheet.anchors[st]:
			var d := {}
			for n in a: d[n] = [a[n].x, a[n].y]
			anchors[st].append(d)
	var meta := {"frames": frames, "anchors": anchors, "origin": [sheet.origin.x, sheet.origin.y], "foot": sheet.foot,
		"cell": [sheet.cell.x, sheet.cell.y], "family": sheet.family}
	var f := FileAccess.open(dir + "/" + kind + ".json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(meta))

static func _load(dir: String, kind: String) -> Dictionary:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + kind + ".json"))
	var albedo := Image.load_from_file(dir + "/" + kind + ".png")
	var normal := Image.load_from_file(dir + "/" + kind + "_n.png")
	if not (meta is Dictionary) or albedo == null or normal == null: return {}
	albedo.convert(Image.FORMAT_RGBA8); normal.convert(Image.FORMAT_RGBA8)
	var frames := {}; var anchors := {}
	for st in meta.frames:
		frames[st] = []; anchors[st] = []
		for r in meta.frames[st]: frames[st].append(Rect2(r[0], r[1], r[2], r[3]))
		for a in meta.anchors[st]:
			var d := {}
			for n in a: d[n] = Vector2(a[n][0], a[n][1])
			anchors[st].append(d)
	return _finish({"kind": kind, "albedo": albedo, "normal": normal,
		"frames": frames, "anchors": anchors, "origin": Vector2(meta.origin[0], meta.origin[1]), "foot": float(meta.foot),
		"cell": Vector2(meta.cell[0], meta.cell[1]), "family": meta.family})
