extends RefCounted
## Compact height profiles used by the procedural pixel painter.
static func dome(cx, cy, rx, ry, amp): return [0, cx, cy, rx, ry, amp]
static func cylV(cx, radius, amp): return [1, cx, radius, amp]
static func cylH(cy, radius, amp): return [2, cy, radius, amp]
static func cap(x0, y0, x1, y1, radius, amp): return [3, x0, y0, x1, y1, radius, amp]
static func slab(x0, y0, x1, y1, amp, bevel = 2): return [4, x0, y0, x1, y1, amp, bevel]

static func sample(profile, x: float, y: float) -> float:
	if profile == null: return 0.0
	if profile is Callable: return float(profile.call(x, y))
	var d: float
	match int(profile[0]):
		0:
			d = 1.0 - pow((x-profile[1])/(profile[3]+0.5), 2) - pow((y-profile[2])/(profile[4]+0.5), 2)
			return profile[5] * sqrt(d) if d > 0.0 else 0.0
		1, 2:
			var axis = x if int(profile[0]) == 1 else y
			d = 1.0 - pow((axis-profile[1])/(profile[2]+0.5), 2)
			return profile[3] * sqrt(d) if d > 0.0 else 0.0
		3:
			var dx: float = profile[3]-profile[1]; var dy: float = profile[4]-profile[2]
			var length_sq = maxf(0.00001, dx*dx + dy*dy)
			var weight = clampf(((x-profile[1])*dx + (y-profile[2])*dy)/length_sq, 0.0, 1.0)
			d = 1.0 - pow(Vector2(x-profile[1]-dx*weight, y-profile[2]-dy*weight).length()/(profile[5]+0.5), 2)
			return profile[6] * sqrt(d) if d > 0.0 else 0.0
		4:
			var edge = minf(minf(x-profile[1]+0.5, profile[3]-x+0.5), minf(y-profile[2]+0.5, profile[4]-y+0.5))
			return profile[5] * minf(1.0, sqrt(edge/profile[6])) if edge > 0.0 else 0.0
	return 0.0
