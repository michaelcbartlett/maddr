extends RefCounted
## Compatibility wrapper: the cop's edited clips now load through the generic EditedArt loader.
const EditedArt = preload("res://enemies/edited_art.gd")

static func clip(state: String) -> Dictionary:
	return EditedArt.clip("cop", state)

static func frame(state: String, index: int) -> Dictionary:
	return EditedArt.frame("cop", state, index)

static func fps(state: String) -> float:
	return EditedArt.fps("cop", state, 6.0)

static func cache_signature() -> String:
	return EditedArt.cache_signature()
