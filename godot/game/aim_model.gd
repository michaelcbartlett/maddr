extends RefCounted
## How hard a target is to hit, by Fitts's law on the aim angle (Shannon form). A rough planning tool: the law was
## made for still targets, and the seconds below are typical thumb-stick figures, not measurements of this player.
const EnemyView := preload("res://enemies/enemy_view.gd")
const SETTLE := 0.15          # seconds before the thumb moves
const PER_BIT := 0.13         # seconds per bit of difficulty
const FLICK := PI / 2.0       # a quarter turn: the next threat is off to one side

## Half the gap a shot of `shot_r` may miss the middle by, for a shot flying along `heading`.
static func half_width(e, shot_r: float, heading := 0.0) -> float:
	var shape: Dictionary = EnemyView.hurt_shape(e)
	var tall := absf(float(shape.low.y) - float(shape.high.y)) * 0.5
	return tall * absf(cos(heading)) + float(shape.r) + shot_r

## The hardest heading: straight up or down, where only the body's width helps.
static func bits(e, shot_r: float, distance: float, flick := FLICK) -> float:
	var target := 2.0 * atan(half_width(e, shot_r, PI / 2.0) / distance)
	return log(flick / target + 1.0) / log(2.0)

static func seconds(difficulty: float) -> float: return SETTLE + PER_BIT * difficulty

## Aim, let the shots fly and repeat until it falls. Follow-up shots are assumed on target.
static func kill_seconds(e, shot_r: float, distance: float, damage: float, cooldown: float, shot_speed: float) -> float:
	return seconds(bits(e, shot_r, distance)) + distance / shot_speed + (ceilf(e.max_hp / damage) - 1.0) * cooldown
