extends Node2D
## Mirrors live Sprite2D layers using their existing textures. No viewports,
## animation copies, image readbacks or per-frame texture uploads.
const ReflectionShader = preload("res://fx/water_reflection.gdshader")
const Sheets = preload("res://enemies/enemy_sheets.gd")
const EnemyViewAdapter = preload("res://enemies/enemy_view.gd")
const FLATTEN := 0.65
const RainyStreet = preload("res://levels/rainy_street.gd")
var entries := {}
var enabled := true
var water_texture: Texture2D

class SheetReflection extends Node2D:
	var source: WeakRef
	func _draw() -> void:
		var actor=source.get_ref()
		if actor==null or actor.dead or actor.vehicle or not actor.gfx.has("state"): return
		var sheet: Dictionary = EnemyArt.sheet(EnemyViewAdapter.sprite_key(actor))
		var at := Vector2(0,float(sheet.foot)-float(actor.gfx.lift))+Vector2(actor.gfx.jitter)
		draw_set_transform(at,0.0,EnemyViewAdapter._squash(actor))
		EnemyViewAdapter.draw_sprite(self,sheet,actor.gfx.state,actor.gfx.frame,Vector2.ZERO,actor.face,actor.gfx.tint)

func _sprites(node: Node, result: Array) -> void:
	if node is Sprite2D: result.append(node)
	for child in node.get_children(): _sprites(child,result)

func sync(actor_layer: Node2D, view: Rect2, clock: float) -> void:
	visible=enabled
	if not enabled: return
	var live := {}
	for actor in actor_layer.get_children():
		if not actor is Node2D: continue
		var id: int=actor.get_instance_id(); live[id]=true
		if not actor.is_visible_in_tree() or not view.grow(160).has_point(actor.global_position) or not RainyStreet.water_near(Rect2(actor.global_position-Vector2(160,0),Vector2(320,180))):
			if entries.has(id): entries[id].root.visible=false
			continue
		var sources: Array=[]; _sprites(actor,sources)
		var sheet_actor: bool=actor is Enemy and not actor.vehicle and not actor.dead
		if sources.is_empty() and not sheet_actor: continue
		if not entries.has(id):
			var group:=Node2D.new(); add_child(group)
			var material:=ShaderMaterial.new(); material.shader=ReflectionShader
			entries[id]={"root":group,"material":material,"sprites":{}}
			if sheet_actor:
				var sheet:=SheetReflection.new(); sheet.source=weakref(actor); sheet.material=material
				group.add_child(sheet); entries[id].sheet=sheet
		var entry: Dictionary=entries[id]; entry.root.visible=true
		var foot: Vector2=actor.global_position
		if actor is VillainView: foot=actor.ground_global()
		elif sheet_actor: foot+=Vector2(0,EnemyArt.sheet(EnemyViewAdapter.sprite_key(actor)).foot)
		else: foot+=Vector2(actor.get_meta("reflection_foot_offset",Vector2.ZERO))
		var mirror:=Transform2D(Vector2(1,0),Vector2(0,-FLATTEN),Vector2(0,foot.y*(1.0+FLATTEN)))
		entry.material.set_shader_parameter("ground_y",foot.y)
		entry.material.set_shader_parameter("clock",clock)
		entry.material.set_shader_parameter("water_map",water_texture)
		entry.material.set_shader_parameter("use_water_map",water_texture!=null)
		entry.material.set_shader_parameter("water_world_size",Vector2(RainyStreet.SIZE))
		var order:=0
		var live_sprites := {}
		for source: Sprite2D in sources:
			var sprite_id:=source.get_instance_id()
			live_sprites[sprite_id]=true
			if not entry.sprites.has(sprite_id):
				var sprite:=Sprite2D.new(); sprite.material=entry.material
				sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
				entry.root.add_child(sprite); entry.sprites[sprite_id]=sprite
			var sprite: Sprite2D=entry.sprites[sprite_id]
			sprite.visible=source.is_visible_in_tree() and source.texture!=null
			if not sprite.visible: continue
			sprite.texture=source.texture; sprite.centered=source.centered; sprite.offset=source.offset
			sprite.flip_h=source.flip_h; sprite.flip_v=source.flip_v
			sprite.hframes=source.hframes; sprite.vframes=source.vframes; sprite.frame=source.frame
			sprite.region_enabled=source.region_enabled; sprite.region_rect=source.region_rect
			sprite.global_transform=mirror*source.global_transform
			sprite.modulate=source.modulate*source.self_modulate*actor.modulate
			entry.root.move_child(sprite,order); order+=1
		for sprite_id in entry.sprites.keys():
			if not live_sprites.has(sprite_id):
				entry.sprites[sprite_id].queue_free(); entry.sprites.erase(sprite_id)
		if entry.has("sheet"):
			entry.sheet.global_transform=mirror*actor.global_transform; entry.sheet.queue_redraw()
	for id in entries.keys():
		if not live.has(id): entries[id].root.queue_free(); entries.erase(id)
