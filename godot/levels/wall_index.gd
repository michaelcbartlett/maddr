extends RefCounted
## Spatial buckets keep city collision and shot queries local to their segment.
const CELL = 256.0
var buckets: Dictionary = {}
var records: Array = []

func rebuild(walls: Array) -> void:
	buckets.clear(); records = walls
	for index in walls.size():
		var rect: Rect2 = walls[index].rect
		for y in range(floori(rect.position.y/CELL),floori(rect.end.y/CELL)+1):
			for x in range(floori(rect.position.x/CELL),floori(rect.end.x/CELL)+1):
				var key = Vector2i(x,y)
				if not buckets.has(key): buckets[key] = []
				buckets[key].append(index)

func query(rect: Rect2) -> Array:
	var result: Array = []; var seen = {}
	for y in range(floori(rect.position.y/CELL),floori(rect.end.y/CELL)+1):
		for x in range(floori(rect.position.x/CELL),floori(rect.end.x/CELL)+1):
			for index in buckets.get(Vector2i(x,y),[]):
				if not seen.has(index): result.append(records[index]); seen[index] = true
	return result
