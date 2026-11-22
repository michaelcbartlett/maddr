extends RefCounted
## Train heist wave (Run.heist_wave, levels/train_level.gd): the villain boards the caboose and fights east through
## the cars while the normal wave timer runs. Stepping into the vault strongroom at the front of the last car before
## the timer ends cracks the vault: the wave ends at once and Run.claim_heist() unlocks this difficulty's reward
## (once per difficulty, saved) and bolts a free copy onto the gun. If the timer runs out first the train gets away:
## the wave still counts as survived, but there is no reward.
## Cops board the car the villain is in and the cars ahead of it (spawn_point), so each car has to be fought through.

const TrainLevel = preload("res://levels/train_level.gd")

var active := false
var won := false
var failed := false
var reward := ""            # item id won this wave
var unlocked := false       # the reward was a first-time unlock
var message := ""           # HUD line after the heist resolves
var message_t := 0.0

func reset(a) -> void:
	active = a.level == "train"
	won = false; failed = false; reward = ""; unlocked = false; message = ""; message_t = 0.0
	if not active: return
	# carried blueprints are dropped next to the villain in the caboose
	var i := 0
	for p in a.pickups:
		p.x = a.P.x + 90 + i * 30; p.y = a.P.y; i += 1

func goal() -> Rect2: return TrainLevel.goal_rect()
func progress(x: float) -> float: return TrainLevel.progress(x)
func car_at(x: float) -> int: return TrainLevel.car_at(x)
func car_name(i: int) -> String: return TrainLevel.CARS[clampi(i, 0, TrainLevel.CARS.size() - 1)].name
func car_count() -> int: return TrainLevel.car_count()

## Called from Arena._update_play every frame. Returns true when the heist ended the wave.
func update(a, dt: float) -> bool:
	if message_t > 0.0: message_t -= dt
	if not active or won or failed: return false
	if goal().grow(-4.0).has_point(Vector2(a.P.x, a.P.y)):
		win(a); return true
	return false

func win(a) -> void:
	won = true
	var got: Dictionary = Run.claim_heist()
	reward = got.id; unlocked = got.unlocked
	a.end_wave()
	a.villain.set_items()
	var item_name: String = Run.ITEM[reward].name.to_upper() if Run.ITEM.has(reward) else "LOOT"
	a.banner_txt = "VAULT CRACKED!"; a.banner_t = 2.4
	message = ("🔓 %s UNLOCKED · INSTALLED" if unlocked else "%s INSTALLED") % item_name
	message_t = 4.0
	a.snd("vault"); a.shake = 10.0

## The wave timer ran out before the vault was reached (Arena._update_play, after end_wave()).
func timeout(a) -> void:
	if not active or won: return
	failed = true
	a.banner_txt = "THE TRAIN GOT AWAY!"; a.banner_t = 2.0
	message = "NO LOOT THIS TIME"; message_t = 3.0

## A spawn point inside the train: in the villain's car or up to two cars ahead (cops boarding),
## occasionally the car behind. Same contract as Arena._outside_spawn.
func spawn_point(a, radius_min: float) -> Vector2:
	var here := car_at(a.P.x)
	var point := Vector2(a.P.x, a.P.y)
	for attempt in 40:
		var car := clampi(here + [0, 0, 1, 1, 2, -1].pick_random(), 0, car_count() - 1)
		var r := TrainLevel.car_rect(car).grow(-30.0)
		point = Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		if point.distance_squared_to(Vector2(a.P.x, a.P.y)) >= radius_min * radius_min and not a.in_wall(point.x, point.y, 28): return point
	return point
