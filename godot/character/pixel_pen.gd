extends RefCounted
## Same pixel primitives for baked Image art and live CanvasItem overlays.
const Pixels = preload("res://character/pixel_canvas.gd")
var target
var ox: float
var oy: float
var alpha := 1.0
var base := 0.0
var profile = null
var raised := 0.0

func _init(canvas, x = 0, y = 0) -> void:
	target = canvas; ox = float(x); oy = float(y)

func layer(height, shape = null) -> void:
	base = float(height); profile = shape; raised = 0.0
func lift(value = 0) -> void: raised = float(value)

func R(x, y, width, height, hex) -> void:
	if width <= 0 or height <= 0: return
	var rect = Rect2i(int(floor(x+ox+0.5)), int(floor(y+oy+0.5)), int(floor(width+0.5)), int(floor(height+0.5)))
	var color = Color.from_string(str(hex), Color.WHITE)
	if target is CanvasItem:
		color.a *= alpha
		target.draw_rect(Rect2(rect), color)
	else:
		color.a *= alpha
		target.rect(rect, color, base + raised, profile, ox, oy)

func P(x, y, color) -> void: R(x, y, 1, 1, color)
func clearRect(x, y, width, height) -> void:
	if not (target is CanvasItem): target.clearRect(x,y,width,height)
func box(x, y, width, height, color) -> void:
	R(x,y,width,height,color); R(x,y,width,1,Pixels.shade(color,0.32)); R(x,y+height-1,width,1,Pixels.shade(color,-0.38))
	if height > 2: R(x+width-1,y+1,1,height-2,Pixels.shade(color,-0.15))
func ell(cx, cy, rx, ry, color) -> void:
	var y = -ry
	while y <= ry:
		var width = floor(rx * sqrt(maxf(0.0, 1.0-pow(y/(ry+0.5),2))) + 0.5)
		R(cx-width,cy+y,2*width+1,1,color)
		y += 1
func line(x0, y0, x1, y1, color, width = 1) -> void:
	var steps = maxf(absf(x1-x0), absf(y1-y0))
	if steps == 0: steps = 1
	var i = 0
	while i <= steps:
		var x = x0+(x1-x0)*i/steps; var y = y0+(y1-y0)*i/steps
		R(floor(x-(width-1)/2.0+0.5), floor(y-(width-1)/2.0+0.5), width, width, color)
		i += 1
func ring(cx, cy, radius, color, start = 0) -> void:
	var angle = 0.0; var step = 0.7/(radius+1)
	while angle < 6.283:
		P(floor(cx+cos(angle+start)*radius+0.5), floor(cy+sin(angle+start)*radius+0.5), color)
		angle += step
