extends SceneTree
## Integration checks for live weapons, shared sprite textures and reflection culling.
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _run() -> void:
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false)
	var run=root.get_node("Run"); run.build.items=["lens","sustain"]; run.recompute(); scene._start_wave()
	root.get_node("Controls").aim_src="pad"
	Input.action_press("fire"); a._process(1.0/60.0); Input.action_release("fire")
	var material: ShaderMaterial=a.arena_level._floor_sprite.material
	_check(not a.beams.is_empty() and material.get_shader_parameter("wet_ray_count")==a.beams.size(),"live laser rays reach the puddle shader")
	var rays=material.get_shader_parameter("wet_rays")
	_check(Vector2(rays[0].x,rays[0].y).distance_to(a.villain.muzzle_global())<0.01,"reflection starts at the current rendered muzzle")
	a.P.x+=30; a.P.aim=-0.4; a._sync(0.0)
	rays=material.get_shader_parameter("wet_rays")
	_check(Vector2(rays[0].x,rays[0].y).distance_to(a.villain.muzzle_global())<0.01,"reflection follows movement and a new aim angle")
	a.beams.clear(); a.projs.clear(); a._sync(0.0)
	_check(material.get_shader_parameter("wet_ray_count")==0,"expired laser reflections clear without leaving trails")
	a.projs=[{"type":"bullet","life":1.0},{"type":"bolt","life":1.0,"x":100.0,"y":200.0,"vx":900.0,"vy":0.0,"color":Color.RED}]
	a.arena_level.update_wet_reflections([],a.projs,2.0)
	rays=material.get_shader_parameter("wet_rays")
	_check(material.get_shader_parameter("wet_ray_count")==1 and rays[0].z==100.0 and rays[0].w==200.0,"laser bolts reflect their travelling head, ordinary bullets are excluded")
	var many: Array=[]
	for i in 40: many.append({"x1":0.0,"y1":0.0,"x2":500.0,"y2":100.0,"col":Color.RED,"t":0.5,"m":1.0})
	a.arena_level.update_wet_reflections(many,[],2.0)
	_check(material.get_shader_parameter("wet_ray_count")==16,"reflection ray work has a fixed budget")
	_check(is_equal_approx(material.get_shader_parameter("wet_ray_colors")[0].w,0.5),"fading beam opacity reaches the reflected light")
	a.projs.clear(); a._sync(0.0)
	var reflected=a.water_reflections
	var id: int=a.villain.get_instance_id()
	_check(reflected.entries.has(id),"the scientist is registered automatically")
	var entry: Dictionary=reflected.entries[id]
	_check(entry.material.get_shader_parameter("water_map")==material.get_shader_parameter("water_map"),"floor and sprite reflections share one water texture")
	var sprite: Sprite2D=entry.sprites[a.villain.rig.body.get_instance_id()]
	_check(sprite.texture==a.villain.rig.body.texture,"reflected body shares its live texture instead of copying image data")
	var gun: Sprite2D=entry.sprites[a.villain.rig.gun.get_instance_id()]
	_check(gun.texture==a.villain.rig.gun.texture and gun.visible,"the live weapon is reflected along with the body")
	var foot: Vector2=a.villain.ground_global()
	var source_point: Vector2=a.villain.rig.body.to_global(Vector2(64,40))
	var reflected_point: Vector2=sprite.to_global(Vector2(64,40))
	_check(absf(source_point.x-reflected_point.x)<0.01 and absf((reflected_point.y-foot.y)+(source_point.y-foot.y)*0.65)<0.01,"body reflection mirrors around the grounded feet")
	a.P.size_scale=1.6; a._sync(0.0)
	_check(sprite.global_scale.length()>a.villain.rig.body.global_scale.length()*0.7,"enlargement scales the same reflected rig")
	reflected.sync(a.actors,Rect2(10000,10000,200,200),a.time)
	_check(not entry.root.visible,"off-screen actors skip their reflection draws")
	var extra:=Node2D.new(); a.actors.add_child(extra); extra.position=a.villain.position
	var image:=Sprite2D.new(); image.texture=a.villain.rig.body.texture; extra.add_child(image)
	reflected.sync(a.actors,Rect2(0,0,3200,2200),a.time)
	_check(reflected.entries.has(extra.get_instance_id()),"additional sprite actors receive reflections automatically")
	var extra_id:=extra.get_instance_id(); a.actors.remove_child(extra); extra.free()
	reflected.sync(a.actors,Rect2(0,0,3200,2200),a.time)
	_check(not reflected.entries.has(extra_id),"removed actors release their reflection nodes")
	EnemyArt.build()
	var enemy=load("res://game/enemy.gd").new(); enemy.setup(a,"cop",a.P.x,a.P.y); a.actors.add_child(enemy); enemy.sync()
	reflected.sync(a.actors,Rect2(0,0,3200,2200),a.time)
	_check(reflected.entries.has(enemy.get_instance_id()) and reflected.entries[enemy.get_instance_id()].has("sheet"),"the existing enemy sheet renderer uses the same reflection system")
	a.actors.remove_child(enemy); enemy.free()
	print("WET REFLECTION TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
