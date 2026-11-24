extends SceneTree
var checks:=0
var failures:=0
const Street=preload("res://levels/rainy_street.gd")
const Vehicles=preload("res://levels/parked_vehicle.gd")
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _run() -> void:
	_check(Vehicles.catalog().size()==7,"seven matching vehicle models are available")
	for model in Vehicles.catalog():
		_check(model.frames.size()==8 and ResourceLoader.exists(model.sheet),"%s has eight views and an imported sheet"%model.id)
	for value in 48:
		var layout: Array=Street.parking_layout(value); var clear:=true; var types: Dictionary={}; var police:=0
		for i in layout.size():
			var car: Dictionary=layout[i]; types[car.vehicle_id]=true
			if car.vehicle_id=="police-sedan": police+=1
			clear=clear and Rect2(Vector2.ZERO,Vector2(Street.SIZE)).encloses(car.rect)
			clear=clear and not car.rect.grow(24).has_point(Street.SPAWN)
			for crossing in Street.crosswalks(): clear=clear and not crossing.grow(16).intersects(car.rect)
			for lamp in Street.lamp_positions(): clear=clear and not car.rect.grow(18).has_point(lamp)
			for j in range(i): clear=clear and not layout[j].rect.grow(14).intersects(car.rect)
		_check(layout.size()>=14 and layout.size()<=20 and clear,"seed %d leaves crossings, lamps, spawn and adjacent cars clear"%value)
		_check(types.size()==7 and police>=2,"seed %d includes all models and at least two cruisers"%value)
	_check(JSON.stringify(Street.parking_layout(12))==JSON.stringify(Street.parking_layout(12)),"a saved parking seed preserves the arrangement across lab changes")
	_check(JSON.stringify(Street.parking_layout(12))!=JSON.stringify(Street.parking_layout(13)),"new seeds vary placement and model choice")
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false)
	_check(a.arena_level.props.size()+a.arena_level.lamps.size()==a.walls.size() and a.arena_level.props.size()>=14,"cars and lamp bases have separate real collision records")
	_check(a.arena_level.navigation.clear_segment(Vector2(60,1100),Vector2(3140,1100),18),"the east/west driving corridor stays open")
	_check(a.arena_level.navigation.clear_segment(Vector2(1600,60),Vector2(1600,2140),18),"the north/south driving corridor stays open")
	var cruiser
	for prop in a.arena_level.prop_nodes:
		if prop is Vehicles and prop.record.police: cruiser=prop; break
	_check(cruiser!=null,"the map creates sprite police cruisers")
	cruiser._phase=0.0
	for row in [[0.05,true,false],[0.27,true,false],[0.5,false,true],[0.7,false,true],[0.87,false,false]]:
		cruiser.update_visual(row[0])
		_check(cruiser.lens_red.visible==row[1] and cruiser.lens_blue.visible==row[2],"roof lenses follow the alternating double-flash at %.2f"%row[0])
		_check(cruiser.glows().size()==int(row[1])+int(row[2]),"flashes emit world lighting only while the lens is on")
		_check(cruiser.wet_emissions().size()==cruiser.glows().size(),"puddle light emissions follow the same flash timing")
	cruiser.update_visual(0.05)
	var light: Dictionary=cruiser.glows()[0]
	_check(light.pos.distance_to(cruiser.lens_red.to_global(cruiser.lens_red.get_meta("emitter_pixel")))<0.01,"the red light is anchored to its painted roof lens")
	var reflection: Dictionary=cruiser.wet_emissions()[0]
	_check(absf(reflection.pos.y-(cruiser.global_position.y*1.65-light.pos.y*0.65))<0.01,"water reflections use the same mirrored foot plane as the vehicle")
	_check(light.r>=200.0 and light.height>=50.0,"the light reaches nearby normal-mapped characters at roof height")
	a.arena_level.update_wet_reflections([],[],0.05,cruiser.wet_emissions())
	var floor_material: ShaderMaterial=a.arena_level._floor_sprite.material
	_check(floor_material.get_shader_parameter("wet_glow_count")==1,"an active roof flash reaches the water shader")
	a.arena_level.break_prop(cruiser.record); cruiser.update_visual(0.05)
	_check(cruiser.glows().is_empty() and not cruiser.lens_red.visible and not cruiser.lens_blue.visible,"destroyed cruisers stop flashing")
	a.arena_level.update_wet_reflections([],[],0.05,cruiser.wet_emissions())
	_check(floor_material.get_shader_parameter("wet_glow_count")==0,"stopped flashes clear from the puddle shader")
	_check(a.walls.any(func(w): return w.rect==cruiser.record.rect and w.open),"destroyed parked vehicles release their collision footprint")
	_check(a.enemies.is_empty() and a.make_enemy("cop",900,550)==null,"parked cruisers do not enable enemy spawns")
	# Reproduce the hood overlap using actual rendered sprite extents, not the
	# nominal model dimensions that caused the original collision mismatch.
	for entry in Vehicles.catalog():
		for view in ["left","right","front","rear"]:
			var size:=Vehicles.footprint(entry.id,view)
			var rect:=Rect2(Vector2(1600,1100)-size/2.0,size)
			var car:=Vehicles.new(); car.setup({"rect":rect,"vehicle_id":entry.id,"view":view})
			a.actors.add_child(car); a.walls=[{"rect":rect,"open":false}]
			var visual_left: float=car.global_position.x+car.sprite.position.x
			var visual_right: float=visual_left+car.sprite.region_rect.size.x*car.sprite.scale.x
			var probe: Dictionary={"x":rect.position.x+2,"y":rect.get_center().y}
			a.collide_walls(probe,11.0)
			var left_clear: bool=probe.x+18.0<=visual_left
			probe={"x":rect.end.x-2,"y":rect.get_center().y}; a.collide_walls(probe,11.0)
			_check(left_clear and probe.x-18.0>=visual_right,"%s / %s keeps the scientist clear of both rendered body edges"%[entry.id,view])
			a.actors.remove_child(car); car.free()
	print("PARKED VEHICLE TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
