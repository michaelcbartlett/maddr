extends SceneTree
## Loot left on the floor at wave end is partly "seized as evidence" (rules.json economy.leftover_rate), so picking it
## up mid-fight pays more. Blueprints are never seized.
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start() -> void:
	run.new_run(); scene._start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.P.inv = 1000
	for e in a.enemies: e.dead = true
	a.pickups.clear(); a.crates.clear()
	run.scrap = 0; run.scrap_f = 0.0

func _finish_wave() -> void:
	a.end_wave()
	for i in 200:
		if a.state != "clear": break
		a._process(1.0 / 30.0)

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	var rate: float = run.leftover_rate()
	_check(rate > 0.0 and rate < 1.0, "leftover loot pays only part of its value")

	# picked up during the fight: full value
	_start()
	a.pickups.append({"x": a.P.x, "y": a.P.y, "v": 20.0, "vx": 0.0, "vy": 0.0, "mag": false})
	a._update_play(1.0 / 60.0)
	var full: int = run.scrap
	_check(full >= int(run.scrap_value(20.0)) - 1 and full > 0, "loot grabbed mid-fight pays in full")

	# left on the floor until the wave ends: reduced
	_start()
	a.pickups.append({"x": a.P.x + 600, "y": a.P.y, "v": 20.0, "vx": 0.0, "vy": 0.0, "mag": false})
	a.crates.append({"x": a.P.x - 600, "y": a.P.y, "v": 10.0, "t": 0.0})
	_finish_wave()
	var expected: float = run.scrap_value(30.0) * rate
	_check(absf(run.scrap - expected) <= 1.0, "leftover loot and crates pay %.0f%% at wave end (%d vs %.1f)" % [rate * 100.0, run.scrap, expected])
	_check(run.scrap < full + int(run.scrap_value(10.0)), "leaving loot costs you scrap")

	# blueprints are never seized
	_start()
	a.pickups.append({"x": a.P.x + 600, "y": a.P.y, "v": 0.0, "vx": 0.0, "vy": 0.0, "age": 0.0, "blueprint": "disint"})
	a.end_wave()
	_check(a.pickups.any(func(p): return p.has("blueprint")), "uncollected blueprints survive the wave end untouched")

	print("LOOT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
