extends SceneTree
## Visual check for arena dressing: every theme with props, pickups, a plutonium crate and a scorch mark.
##   Godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script res://game/tests/arena_showcase.gd
## Writes test-results/showcase-<theme>.png (needs a real renderer, not --headless).
var scene
var arena
var run

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	seed(77)
	run = root.get_node("Run"); run.new_run()
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	arena = scene.arena; arena.set_process(false)
	scene._enter_lab(); scene._open_difficulty(); scene.difficulty_s.buttons[0].pressed.emit()
	var spots := {"street": Vector2(470, 330), "bank": Vector2(470, 330), "rooftop": Vector2(470, 330), "police": Vector2(470, 330),
		"museum": Vector2(470, 330), "harbour": Vector2(470, 380), "spyhq": Vector2(470, 330)}
	for theme in ["street", "bank", "rooftop", "police", "museum", "harbour", "spyhq"]:
		arena.start_wave(); _force(theme)
		arena.P.inv = 1000.0
		for e in arena.enemies: e.dead = true
		var at: Vector2 = spots[theme]
		arena.P.x = at.x; arena.P.y = at.y + 90
		arena.pickups.clear(); arena.crates.clear(); arena.decals.clear()
		for i in 7: arena.pickups.append({"x": at.x + 40 + i * 16, "y": at.y + 150 + (i % 2) * 10, "v": [1.0, 2.0, 4.0][i % 3], "vx": 0.0, "vy": 0.0, "mag": false, "age": 1.0})
		for i in 3: arena.pickups.append({"x": at.x - 80 + i * 22, "y": at.y + 170, "v": 5.0, "vx": 0.0, "vy": 0.0, "cash": 1, "age": 1.0})
		arena.crates.append({"x": at.x + 200, "y": at.y + 120, "v": 6, "t": 2.0, "got": false})
		arena.decals.append({"x": at.x - 140, "y": at.y + 60, "r": 40.0, "t": 20.0, "a": 0.3})
		arena.state = "play"
		for f in 90:
			arena.time += 1.0 / 60.0; arena.lights.begin(); arena._sync(1.0 / 60.0)
		arena.banner_t = 0; arena.siren_t = 0.0; arena.lights.begin(); arena._sync(1.0 / 60.0); arena.cam.force_update_scroll()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/showcase-%s.png" % theme)
	print("SHOWCASE DONE")
	quit(0)

func _force(theme: String) -> void:
	arena.arena_level.build(theme); arena.level = theme
	arena.ambient.color = arena.arena_level.theme.ambient; arena.walls = arena.arena_level.walls
	arena.ambient_fx.reset(arena, arena.arena_level)
