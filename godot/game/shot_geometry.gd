extends RefCounted
## Swept shot intersections; fractions are along the segment in 0..1.
static func circle_fraction(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> float:
	var offset = start-center; var delta = finish-start
	var c = offset.length_squared()-radius*radius
	if c<=0.0: return 0.0
	var a = delta.length_squared()
	if a<0.000001: return -1.0
	var b = offset.dot(delta); var discriminant = b*b-a*c
	if discriminant<0.0: return -1.0
	var fraction = (-b-sqrt(discriminant))/a
	return fraction if fraction>=0.0 and fraction<=1.0 else -1.0

static func rect_entry(start: Vector2, finish: Vector2, rect: Rect2) -> Dictionary:
	var delta = finish-start; var enter = -INF; var leave = INF; var normal = Vector2.ZERO
	for axis in 2:
		if absf(delta[axis])<0.000001:
			if start[axis]<rect.position[axis] or start[axis]>rect.end[axis]: return {}
			continue
		var near = (rect.position[axis]-start[axis])/delta[axis]
		var far = (rect.end[axis]-start[axis])/delta[axis]
		var facing = Vector2.ZERO; facing[axis] = -1.0 if delta[axis]>0.0 else 1.0
		if near>far: var swap = near; near = far; far = swap
		if near>enter: enter = near; normal = facing
		leave = minf(leave,far)
		if enter>leave: return {}
	if leave<0.0 or enter>1.0: return {}
	if enter<0.0: return {"fraction":0.0,"normal":-delta.normalized()}
	return {"fraction":enter,"normal":normal}

## Swept hit on an upright body: a vertical capsule from `low` (feet) to `high` (head), same x.
static func capsule_fraction(start: Vector2, finish: Vector2, low: Vector2, high: Vector2, radius: float) -> float:
	var best := circle_fraction(start,finish,low,radius)
	if low.is_equal_approx(high): return best
	var top := circle_fraction(start,finish,high,radius)
	if top>=0.0 and (best<0.0 or top<best): best = top
	var contact := rect_entry(start,finish,Rect2(high.x-radius,minf(high.y,low.y),radius*2.0,absf(low.y-high.y)))
	if not contact.is_empty() and (best<0.0 or contact.fraction<best): best = contact.fraction
	return best

## `shape` is {low, high, r} from EnemyView.hurt_shape().
static func body_fraction(start: Vector2, finish: Vector2, shape: Dictionary, extra := 0.0) -> float:
	return capsule_fraction(start,finish,shape.low,shape.high,float(shape.r)+extra)
