extends "res://character/pixel_canvas.gd"
## Records complete, occluded parts while retaining the original painter's combined canvas.
var parts := {}
var joints := {}
var parents := {}
var part_name := "torso"
var owners := PackedStringArray()
var part_depths := {}
var exported_depths := {}

func _init(w: int, h: int) -> void:
	super(w, h)
	owners.resize(w * h)

func part(key: String, pivot: Vector2, parent: String = "") -> void:
	part_name = key
	joints[key] = pivot + Vector2.ONE
	parents[key] = parent
	if not parts.has(key):
		parts[key] = Image.create(width, height, false, Image.FORMAT_RGBA8)
		var values := PackedFloat32Array()
		values.resize(width * height)
		part_depths[key] = values

func rect(bounds: Rect2i, color: Color, base: float, shape, ox: float, oy: float) -> void:
	if not parts.has(part_name): part(part_name, Vector2.ZERO)
	var region := bounds.intersection(Rect2i(0, 0, width, height))
	if region.size.x <= 0 or region.size.y <= 0: return
	var img: Image = parts[part_name]
	var values: PackedFloat32Array = part_depths[part_name]
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			img.set_pixel(x, y, img.get_pixel(x, y).blend(color))
			if color.a > 0: owners[y * width + x] = part_name
			values[y * width + x] = base + Profiles.sample(shape, x - ox, y - oy)
	part_depths[part_name] = values
	super.rect(bounds, color, base, shape, ox, oy)

func export_parts() -> Dictionary:
	var original_width := width
	var original_height := height
	var original := image.get_data()
	var outlined := outlined_image()
	var result := {}
	for key in parts:
		var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
		img.blit_rect(parts[key], Rect2i(0, 0, original_width, original_height), Vector2i.ONE)
		result[key] = img
		var values := PackedFloat32Array()
		values.resize(width * height)
		for y in original_height:
			for x in original_width:
				values[(y + 1) * width + x + 1] = part_depths[key][y * original_width + x]
		exported_depths[key] = values
	# Give each outer outline pixel to the part that generated it. Internal boundaries stay
	# unoutlined, preserving the exact original composite while retaining hidden artwork.
	for y in height:
		for x in width:
			var sx := x - 1
			var sy := y - 1
			if sx >= 0 and sy >= 0 and sx < original_width and sy < original_height:
				if original[(sy * original_width + sx) * 4 + 3] > 0: continue
			var color := outlined.get_pixel(x, y)
			if color.a == 0: continue
			var best := -1
			var owner := ""
			for delta in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var q: Vector2i = Vector2i(sx, sy) + delta
				if q.x < 0 or q.y < 0 or q.x >= original_width or q.y >= original_height: continue
				var index: int = q.y * original_width + q.x
				var alpha_value := int(original[index * 4 + 3])
				if alpha_value > 0 and alpha_value > best:
					best = alpha_value
					owner = owners[index]
			if result.has(owner):
				result[owner].set_pixel(x, y, color)
				var values: PackedFloat32Array = exported_depths[owner]
				values[y * width + x] = depth[y * width + x]
				exported_depths[owner] = values
	return result
