extends RefCounted
## Bounded, time-driven blaster sparks, hot impacts and small local lights.
## Runs in the simulation, so drawing a frame never emits extra particles.
const MAX_PARTICLES = 220
const MAX_IMPACTS = 24
var particles: Array = []
var impacts: Array = []

func clear() -> void: particles.clear(); impacts.clear()

func muzzle(position: Vector2, direction: Vector2, color: Color, continuous: bool = false) -> void:
	for i in (2 if continuous else 4):
		var velocity = direction.rotated(randf_range(-0.8,0.8))*randf_range(45,130)
		_emit(position,velocity,color,randf_range(0.08,0.19),randf_range(1.0,2.2))

func impact(position: Vector2, normal: Vector2, color: Color, continuous: bool = false) -> void:
	var lifetime = 0.10 if continuous else 0.16
	impacts.append({"position":position,"color":color,"time":lifetime,"life":lifetime})
	if impacts.size()>MAX_IMPACTS: impacts.pop_front()
	for i in (3 if continuous else 7):
		_emit(position,normal.rotated(randf_range(-1.4,1.4))*randf_range(35,150),color,randf_range(0.10,0.27),randf_range(1.0,2.4))

func _emit(position: Vector2, velocity: Vector2, color: Color, lifetime: float, size: float) -> void:
	particles.append({"position":position,"previous":position,"velocity":velocity,"color":color,"time":lifetime,"life":lifetime,"size":size})
	if particles.size()>MAX_PARTICLES: particles.pop_front()

func update(dt: float) -> void:
	for particle in particles:
		particle.previous = particle.position
		particle.position += particle.velocity*dt
		particle.velocity *= exp(-5.0*dt)
		particle.time -= dt
	particles = particles.filter(func(p): return p.time>0.0)
	for flash in impacts: flash.time -= dt
	impacts = impacts.filter(func(p): return p.time>0.0)

func draw_glow(canvas: Node2D) -> void:
	for particle in particles:
		var fade: float = particle.time/particle.life
		canvas.draw_circle(particle.position,particle.size*2.5,Color(particle.color,0.13*fade))
	for flash in impacts:
		var fade: float = flash.time/flash.life
		canvas.draw_circle(flash.position,5.0+9.0*(1.0-fade),Color(flash.color,0.2*fade))
		canvas.draw_circle(flash.position,3.0*fade,Color(1,1,1,0.75*fade))

func draw_core(canvas: Node2D) -> void:
	for particle in particles:
		var fade: float = particle.time/particle.life
		canvas.draw_line(particle.previous,particle.position,Color(particle.color,fade),particle.size)
		canvas.draw_rect(Rect2(particle.position-Vector2.ONE*0.5,Vector2.ONE),Color(1,1,1,fade))

func add_lights(pool) -> void:
	# Limit lighting separately from visible particles, preserving headroom for gameplay lights.
	for i in mini(impacts.size(),6):
		var flash: Dictionary = impacts[impacts.size()-1-i]
		var fade: float = flash.time/flash.life
		pool.add(flash.position,flash.color,0.9*fade,36,12)
	for i in mini(particles.size(),3):
		var particle: Dictionary = particles[particles.size()-1-i]
		pool.add(particle.position,particle.color,0.22*particle.time/particle.life,20,10)
