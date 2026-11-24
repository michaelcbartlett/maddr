extends RefCounted
## The blade's measured local centerline drives both the sweep and its fading ribbon.
const TRAIL_LIFE := 0.28
const CUT_SPEED := 2.5  # radians per second; holding a blade still never deals contact damage.
const TURN_SPEED := 14.0

static func world_points(sample: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in sample.points: result.append(sample.origin + point.rotated(sample.angle))
	return result

static func sweep(previous: Dictionary, current: Dictionary) -> Array:
	if previous.is_empty() or current.is_empty(): return []
	var delta := wrapf(float(current.angle) - float(previous.angle), -PI, PI)
	var steps := clampi(ceili(maxf(absf(delta) / 0.07, previous.origin.distance_to(current.origin) / 6.0)), 1, 64)
	var result: Array = []
	for i in range(steps + 1):
		var weight := float(i) / steps
		var local := PackedVector2Array()
		for j in current.points.size():
			local.append(previous.points[j].lerp(current.points[j], weight))
		result.append(world_points({"origin":previous.origin.lerp(current.origin, weight), "angle":previous.angle + delta * weight, "points":local}))
	return result

static func draw_trail(g: Node2D, field: Dictionary, fade: float) -> void:
	var color: Color = field.col
	var previous: PackedVector2Array = field.previous
	var current: PackedVector2Array = field.current
	# Fade brightness and width together; the old samples stay where the blade passed.
	var alpha := fade * fade
	for j in range(current.size() - 1):
		var quad := PackedVector2Array([previous[j], previous[j+1], current[j+1], current[j]])
		if absf((quad[1]-quad[0]).cross(quad[2]-quad[0])) > 0.01:
			g.draw_colored_polygon(quad, Color(color, 0.16 * alpha))
		g.draw_line(previous[j+1], current[j+1], Color(color, 0.7 * alpha), maxf(0.5, 3.0 * fade), true)
	g.draw_polyline(current, Color(color, 0.28 * alpha), maxf(0.5, 2.0 * fade), true)
