extends Control
class_name VillainPreview
## The villain on a lab grid, idling and firing a burst every few seconds (index.html drawPreview()).
## Fits the current procedural build, including long and stacked weapons, into the preview.

var view: VillainView
var holder: Node2D
var t := 0.0
var zoom := 3.0
var aim_base := -0.06

func _init(z := 3.0, sz := Vector2(330, 230)) -> void:
	zoom = z; custom_minimum_size = sz; clip_contents = true

func _ready() -> void:
	holder = Node2D.new(); add_child(holder)
	view = VillainView.new(); holder.add_child(view)
	holder.scale = Vector2(zoom, zoom)
	resized.connect(_place); _place()

func _place() -> void:
	if view == null or view.rig == null: return
	var bounds = view.visual_bounds()
	var available = Vector2(maxf(1,size.x-24),maxf(1,size.y-48))
	var scale_factor = minf(zoom,minf(available.x/maxf(1,bounds.size.x),available.y/maxf(1,bounds.size.y)))
	holder.scale = Vector2.ONE*scale_factor
	holder.position = Vector2((size.x-bounds.size.x*scale_factor)/2.0-bounds.position.x*scale_factor,size.y-30-bounds.end.y*scale_factor)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0f1616"))
	for x in range(0, int(size.x), 16): draw_rect(Rect2(x, 0, 1, size.y), Color("#1a2424"))
	for y in range(0, int(size.y), 16): draw_rect(Rect2(0, y, size.x, 1), Color("#1a2424"))
	draw_rect(Rect2(0, size.y - 30, size.x, 30), Color("#2a3838"))
	draw_rect(Rect2(holder.position.x - 16 * zoom, size.y - 32, 32 * zoom, 5), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.LINE, false, 2)

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	t += dt
	var fire := fmod(t, 3.5) > 2.7; var ph := fmod(t * 12, 1.0)
	view.set_state({"aim": aim_base + sin(t * 0.9) * 0.05, "moving": false, "recoil": (1.0 - ph) if fire else 0.0,
		"flash": 0.05 if fire and ph < 0.35 else 0.0, "firing": fire, "armed": Run.build.off != null})
	_place()
	queue_redraw()
