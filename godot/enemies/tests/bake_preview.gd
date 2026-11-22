extends SceneTree
## Dev helper: bakes sheets (no cache) and saves albedo/normal atlases to test-results/enemies/.
## Usage: godot --headless --script res://enemies/tests/bake_preview.gd -- [kind ...]
func _init() -> void:
	var kinds: Array = Array(OS.get_cmdline_user_args())
	if kinds.is_empty(): kinds = preload("res://enemies/enemy_painter.gd").KINDS
	var out := "res://test-results/enemies"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for k in kinds:
		var s: Dictionary = preload("res://enemies/enemy_sheets.gd").build(k)
		s.albedo.save_png(out + "/" + k + ".png"); s.normal.save_png(out + "/" + k + "_n.png")
	quit()
