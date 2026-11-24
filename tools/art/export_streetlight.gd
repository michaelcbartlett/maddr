extends SceneTree
## Export the actual game lamp, isolated from runtime lighting and atmosphere.
const Prop=preload("res://levels/prop_view.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var output:=ProjectSettings.globalize_path("res://../export/props/streetlight")
	DirAccess.make_dir_recursive_absolute(output)
	var native:=SubViewport.new(); native.size=Vector2i(128,192)
	native.transparent_bg=true; native.world_2d=World2D.new(); native.disable_3d=true
	native.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(native)
	var post:=Prop.new()
	post.setup({"rect":Rect2(-1,-1,2,2),"kind":"lamp_post","color":Color("#2a3038"),"h":64.0},{"lamp":Color("#ffd9a0")})
	post.position=Vector2(44,163); post.scale=Vector2.ONE*1.9
	var material:=CanvasItemMaterial.new(); material.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	post.material=material; native.add_child(post)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	native.get_texture().get_image().save_png(output.path_join("streetlight-native-128x192.png"))
	var large:=SubViewport.new(); large.size=Vector2i(768,1152)
	large.transparent_bg=true; large.world_2d=World2D.new(); large.disable_3d=true
	large.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(large)
	var background:=ColorRect.new(); background.size=Vector2(large.size); background.color=Color("#888888")
	background.visible=false; large.add_child(background)
	var sprite:=Sprite2D.new(); sprite.centered=false; sprite.texture=native.get_texture()
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; sprite.scale=Vector2.ONE*6.0; large.add_child(sprite)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	large.get_texture().get_image().save_png(output.path_join("streetlight-transparent-768x1152.png"))
	background.visible=true
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	large.get_texture().get_image().save_png(output.path_join("streetlight-moge-768x1152.png"))
	print("STREETLIGHT EXPORTED: ",output)
	quit()
