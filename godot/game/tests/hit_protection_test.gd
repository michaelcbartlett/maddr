extends SceneTree
## Damage-based shared i-frames, armor, modifier stacking, shop buy/sell and UI.
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)

func _run() -> void:
	var run=root.get_node("Run"); run.new_run()
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false); scene._start_wave()
	run.S.armor=0.0; run.D.maxHp=100
	# Brotato: 0.4s * (damage / max HP) / 15%, clamped to 0.2–0.4s.
	for row in [[1,0.2],[7.5,0.2],[8,0.4*8/15],[10,0.4*10/15],[12,0.32],[15,0.4],[50,0.4]]:
		_check(is_equal_approx(run.hit_protection_duration(row[0]),row[1]),"base timing at %s%% maximum HP"%row[0])
	for damage in [1.,8.,10.,12.,15.,50.]:
		a.P.inv=0; a.P.hp=100; a.state="play"; a.dash.reset()
		_check(a.hurt_player(damage),"first hit is accepted")
		var grace: float=run.hit_protection_duration(damage)
		_check(is_equal_approx(a.P.inv,grace),"actual HP loss assigns the damage-based timer")
		a.P.inv=grace/2
		_check(not a.hurt_player(damage),"every attacker respects the active timer")
		a.P.inv=0.00000001
		_check(a.hurt_player(1),"float residue at the expiry boundary does not discard the next hit")
	# Armor changes the damage taken; current health does not change the formula.
	run.S.armor=15.; a.P.hp=100; a.P.inv=0; a.hurt_player(20)
	_check(a.P.hp==90 and is_equal_approx(a.P.inv,0.4*10/15),"armor-reduced damage determines protection")
	a.P.hp=20; a.P.inv=0; a.hurt_player(20)
	_check(is_equal_approx(a.P.inv,0.4*10/15),"low current HP does not inflate protection")
	run.S.armor=0
	var base_attack_speed: float=run.S.atkSpd
	# The stat modifies the clamped baseline, so extensions can exceed 0.4s and reductions can go below 0.2s.
	run.build.items=["shock_buffer"]; run.recompute()
	_check(is_equal_approx(run.D.hitProtection,1.25),"Shock Buffer extends protection by 25%")
	_check(is_equal_approx(run.hit_protection_duration(1),0.25),"positive modifier extends the minimum")
	_check(is_equal_approx(run.hit_protection_duration(run.D.maxHp),0.5),"positive modifier extends the maximum")
	run.build.items=["overclocked_nerves"]; run.recompute()
	_check(is_equal_approx(run.D.hitProtection,0.75),"Overclocked Nerves reduces protection by 25%")
	_check(is_equal_approx(run.S.atkSpd,base_attack_speed+0.3),"the reduced protection pays for a fire-rate bonus")
	_check(is_equal_approx(run.hit_protection_duration(1),0.15),"negative modifier reduces the minimum")
	_check(is_equal_approx(run.hit_protection_duration(run.D.maxHp),0.3),"negative modifier reduces the maximum")
	run.build.items=["shock_buffer","shock_buffer","overclocked_nerves"]; run.recompute()
	_check(is_equal_approx(run.S.hitProtection,0.25),"positive and negative copies stack additively")
	_check(run.stats_rows().any(func(row): return row[0]=="Hit protection" and row[1].contains("+25%") and row[1].contains("0.25")),"the stat panel shows the effective modifier and timing range")
	run.build.items=["overclocked_nerves","overclocked_nerves","overclocked_nerves","overclocked_nerves","overclocked_nerves"]; run.recompute()
	_check(run.D.hitProtection==0 and run.hit_protection_duration(5)==0,"reductions clamp at zero instead of producing negative grace")
	a.P.hp=30; a.P.inv=0; a.state="play"
	_check(a.hurt_player(1) and a.hurt_player(1),"zero protection deliberately permits immediate repeated hits")
	a.dash.safe_t=1
	_check(not a.hurt_player(1),"Hit Protection modifiers never remove phase-dash invulnerability")
	a.dash.reset(); a.P.inv=1000
	_check(not a.hurt_player(1),"explicit long immunity still blocks damage")
	# Use the real shop transactions, so buying/selling cannot leave stale derived timing.
	run.new_run(); run.scrap=100; run.offers=[{"it":run.ITEM.shock_buffer,"price":18,"sold":false}]
	_check(run.item_available(run.ITEM.shock_buffer) and run.item_available(run.ITEM.overclocked_nerves),"both modifiers are available in the regular shop")
	_check(run.buy(0) and is_equal_approx(run.D.hitProtection,1.25),"buying recomputes the stat immediately")
	_check(run.sell("shock_buffer")>0 and is_equal_approx(run.D.hitProtection,1),"selling restores the base duration")
	run.build.items=["shock_buffer"];run.recompute();scene._start_wave()
	_check(is_equal_approx(run.D.hitProtection,1.25),"the owned modifier survives the next wave")
	run.new_run()
	_check(run.D.hitProtection==1 and run.S.hitProtection==0,"a fresh run resets Hit Protection")
	scene.free()
	print("HIT PROTECTION TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
