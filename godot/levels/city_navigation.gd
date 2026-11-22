extends RefCounted
## A shared city grid, with staggered per-agent paths through real doorways.
const WallIndex = preload("res://levels/wall_index.gd")
const Geometry = preload("res://game/shot_geometry.gd")
const CELL = 32.0
var grid := AStarGrid2D.new()
var index = WallIndex.new()
var extent := Vector2(8192,8192)

func configure(walls: Array, size: Vector2) -> void:
	extent = size; index.rebuild(walls)
	grid.region = Rect2i(0,0,int(size.x/CELL)+1,int(size.y/CELL)+1)
	grid.cell_size = Vector2.ONE*CELL
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for wall in walls:
		if wall.open: continue
		var rect = (wall.rect as Rect2).grow(20.0)
		for y in range(maxi(0,ceili(rect.position.y/CELL)),mini(grid.region.end.y,floori(rect.end.y/CELL)+1)):
			for x in range(maxi(0,ceili(rect.position.x/CELL)),mini(grid.region.end.x,floori(rect.end.x/CELL)+1)):
				grid.set_point_solid(Vector2i(x,y))

func clear_segment(start: Vector2, finish: Vector2, radius: float = 14.0) -> bool:
	var bounds = Rect2(start,Vector2.ZERO).expand(finish).grow(radius+1.0)
	for wall in index.query(bounds):
		if not wall.open and not Geometry.rect_entry(start,finish,(wall.rect as Rect2).grow(radius)).is_empty(): return false
	return true

func _cell(point: Vector2) -> Vector2i:
	var center = Vector2i(roundi(point.x/CELL),roundi(point.y/CELL))
	center.x = clampi(center.x,0,grid.region.end.x-1); center.y = clampi(center.y,0,grid.region.end.y-1)
	if not grid.is_point_solid(center): return center
	var nearest = center; var distance = INF
	for y in range(-3,4):
		for x in range(-3,4):
			var cell = center+Vector2i(x,y)
			if not grid.region.has_point(cell) or grid.is_point_solid(cell): continue
			var d = (Vector2(cell)*CELL).distance_squared_to(point)
			if d<distance: nearest = cell; distance = d
	return nearest

func path(start: Vector2, finish: Vector2) -> PackedVector2Array:
	var first = _cell(start); var last = _cell(finish)
	if grid.is_point_solid(first) or grid.is_point_solid(last): return PackedVector2Array()
	return grid.get_point_path(first,last)

func waypoint(agent, target: Vector2, dt: float) -> Vector2:
	var start = Vector2(agent.x,agent.y)
	if clear_segment(start,target,agent.r+2.0):
		agent.nav_path = PackedVector2Array(); return target
	agent.nav_timer -= dt
	if agent.nav_timer<=0.0:
		# stuck check: barely moved since the last re-plan -> sidestep briefly, then re-plan
		if start.distance_to(agent.nav_last)<6.0 and not agent.nav_path.is_empty():
			agent.nav_side = 0.5; agent.nav_dir = Vector2.from_angle(randf()*TAU)
		agent.nav_last = start
		agent.nav_path = path(start,target); agent.nav_cursor = 0
		agent.nav_timer = randf_range(0.45,0.75)
	if agent.nav_side>0.0:
		agent.nav_side -= dt; return start+agent.nav_dir*40.0
	while agent.nav_cursor<agent.nav_path.size() and start.distance_to(agent.nav_path[agent.nav_cursor])<18.0:
		agent.nav_cursor += 1
	if agent.nav_path.is_empty(): return target   # no route found: push straight at it (walls slide us)
	if agent.nav_cursor>=agent.nav_path.size(): return target
	return agent.nav_path[agent.nav_cursor]
