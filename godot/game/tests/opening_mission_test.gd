extends SceneTree
## Run with -- --character-studio --mission --wave 1.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _run() -> void:
	var scene = load("res://game/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	var a = scene.arena
	a.set_process(false)
	var mission = a.opening_mission
	check(mission != null and a.wave_t == 0, "Mission starts without a countdown")
	if mission == null:
		quit(1)
		return
	for kind in ["cop", "det"]:
		var e = a.make_enemy(kind, 200, 1110)
		check(EnemyView.native(e), kind + " loads its imported full-body clips")
		e.dead = true
	check(a.arena_level.props.size() > mission.BLOCKS, "Street includes staggered multi-car roadblocks")
	var previous := Vector2(a.P.x,a.P.y)
	for block in mission.BLOCKS:
		var exit_point := Vector2((block + 1) * mission.WIDTH - 52,1146)
		check(not a.in_wall(exit_point.x,exit_point.y,18) and not a.nav.path(previous,exit_point).is_empty(), "Intact cars leave a route through block %d" % block)
		previous = exit_point
		a.P.x = (block + 1) * mission.WIDTH
		mission.update(a, 10)
		check(a.P.x < (block + 1) * mission.WIDTH, "Active roadblock stops advancement")
		if block == mission.RADIO_BLOCK:
			a.P.x = mission.RADIO.x; a.P.y = mission.RADIO.y
			mission.update(a,0.01)
			check(mission.radio_cut and mission.rounds() == mission.STOPS[block].rounds - 2, "Disabling dispatch cancels the last two patrols")
		for patrol in mission.rounds():
			for marker in a.markers:
				check(not a.in_wall(marker.x,marker.y,18), "Street reinforcements arrive in a free lane")
			a.markers.clear()
			mission.update(a, 10)
		check(mission.block == block + 1, "Block opens after its final patrol")
	var before: float = a.P.hp
	a.P.x = mission.ENTRY.x
	a.P.y = mission.ENTRY.y
	mission.update(a, 0.05)
	var bank = mission.bank
	check(bank.room == "Lobby" and a.P.hp == before, "Street enters lobby with HP intact")
	for name in bank.ROOMS:
		var origin: Vector2 = bank.ROOMS[name]
		var goal: Vector2 = origin + bank.PEDESTAL
		for wall: Rect2 in bank.FITTINGS[name]:
			var at := origin + wall.get_center()
			check(a.in_wall(at.x,at.y), "Furniture has collision in " + name)
		for link in bank.LINKS[name]:
			check(not a.nav.path(bank.door(name,link),goal).is_empty(), "Door connects to objective in " + name)
		for spawn: Vector2 in bank.SPAWNS[name]:
			check(not a.in_wall(origin.x+spawn.x,origin.y+spawn.y,20), "Bank deployment clears furniture")
	for next in ["Deposit boxes", "Lobby", "Teller hall", "Security", "Teller hall", "Vault"]:
		var previous_room: String = bank.room
		var gate: Vector2 = bank.door(previous_room, next)
		if not bank.cleared.has(previous_room):
			a.P.x = gate.x; a.P.y = gate.y
			bank.update(a)
			check(bank.room == previous_room, "Combat locks exits")
		a.markers.clear()
		if previous_room == "Deposit boxes" or previous_room == "Security":
			var pickup: Vector2 = bank.ROOMS[previous_room] + bank.PEDESTAL
			a.P.x = pickup.x; a.P.y = pickup.y
			bank.update(a)
		if previous_room == "Teller hall" and not bank.keycard:
			var locked: Vector2 = bank.door(previous_room, "Vault")
			a.P.x = locked.x; a.P.y = locked.y
			bank.update(a)
			check(bank.room == previous_room, "Vault requires security keycard")
		a.P.x = gate.x; a.P.y = gate.y
		bank.update(a)
		check(bank.room == next, "Door leads to " + next)
	check(bank.deposit_taken and bank.keycard, "Optional reserve and required keycard are collected")
	a.markers.clear()
	bank.update(a)
	check(a.live_foes().any(func(e): return e.type == "det" and EnemyView.native(e)), "Vault captain uses the detective clip set")
	var bullion: Vector2 = bank.ROOMS["Vault"] + bank.PEDESTAL
	a.P.x = bullion.x; a.P.y = bullion.y
	bank.update(a)
	check(a.state == "play", "Captain guards the bullion")
	for e in a.enemies: e.dead = true
	a.markers.clear()
	bank.update(a)
	check(a.state == "clear", "Taking guarded bullion completes the mission")
	print("OPENING MISSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
