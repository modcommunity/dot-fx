extends "res://examples/selftest/definition_tests.gd"
## Placement, beacon, weather, beam, goo and muzzle flash sections.


func _test_placed_before_entering() -> void:
	_section("An effect is where it was asked for on the frame it enters the tree")

	# A particle emitter fires on entering, so the transform it has THEN is where its
	# first burst goes. Read at `child_entered_tree`, which is after the child's own
	# `_enter_tree` and before anything else could have moved it.
	var m := _manager()
	var d2 := _def(&"ripple")
	d2.scene_path = "res://fixtures/blob_2d.tscn"
	m.catalogue.add(d2)
	var seen: Array = []
	var on_enter := func(child: Node) -> void:
		if child is Node3D:
			seen.append((child as Node3D).global_position)
		elif child is Node2D:
			seen.append([(child as Node2D).global_position, (child as Node2D).rotation])
	m.child_entered_tree.connect(on_enter)

	var at := Transform3D(Basis(Vector3.UP, 0.7), Vector3(5.0, 2.0, -3.0))
	var node := m.spawn(&"spark", at)
	_check(node != null and seen.size() == 1 and (seen[0] as Vector3).is_equal_approx(at.origin),
		"a 3D effect is at its transform when it enters, not at the origin")
	_check(node != null and (node as Node3D).global_transform.is_equal_approx(at),
		"and is still there afterwards, turned the way it was asked")

	seen.clear()
	var flat := m.spawn_2d(&"ripple", Vector2(40.0, -12.0), 0.5)
	_check(
		flat != null and seen.size() == 1
			and ((seen[0] as Array)[0] as Vector2).is_equal_approx(Vector2(40.0, -12.0))
			and is_equal_approx(float((seen[0] as Array)[1]), 0.5),
		"a 2D effect is at its position and rotation when it enters"
	)

	m.child_entered_tree.disconnect(on_enter)
	m.queue_free()


func _test_beacon() -> void:
	_section("A beacon pings once a period, and hides its column from its own player")

	var b := DotFxBeacon.new()
	b.period = 0.5
	b.colour = Color(0.2, 0.8, 0.3)
	add_child(b)

	_check(b.advance(0.0), "it pings as it comes on, not a period later")

	var pinged := 0
	# Eighths of a second, which add up to exactly one: sixtieths fall a hair short of it.
	for i in range(8):
		if b.advance(0.125):
			pinged += 1
	# One second at a half-second period: two more, not one per frame.
	_check(pinged == 2, "and once a period after that (%d in a second at 0.5 s)" % pinged)
	_check(b.pings == 3, "and counts what it played (%d)" % b.pings)

	_check(b.column_shown(), "the column is drawn for everybody else")
	b.local_view = true
	_check(not b.column_shown(), "and not in the marked player's own view")
	b.local_view = false

	var ring := b.get_node_or_null(^"Ring") as MeshInstance3D
	var colour := (ring.material_override as StandardMaterial3D).albedo_color if ring != null else Color.BLACK
	_check(ring != null and is_equal_approx(colour.g, 0.8) and is_equal_approx(colour.r, 0.2),
		"the ring is the colour it was given")

	_check(b.top_level, "it is top level, placed where the player is drawn")

	var ping := DotFxBeacon.synth_ping()
	_check(ping != null and ping.data.size() > 1000, "with no stream a ping is synthesised (%d bytes)" % ping.data.size())

	remove_child(b)
	b.free()

	# ping_enabled off: still ripples and counts, with no voice of its own to play, so a
	# game that plays the ping through its own catalogue is not heard twice.
	var quiet := DotFxBeacon.new()
	quiet.ping_enabled = false
	add_child(quiet)
	_check(quiet.advance(0.0) and quiet.get_node_or_null(^"Ping") == null,
		"with ping_enabled off it still reports the ripple and builds no voice")
	quiet.ring_radius = 2.0
	quiet.build()
	var big := quiet.get_node_or_null(^"Ring") as MeshInstance3D
	_check(big != null and quiet.advance(0.1) == false,
		"and rebuilding at a new size works without one")
	remove_child(quiet)
	quiet.free()

	# resize(): a live beacon changes size without being rebuilt, and keeps its phase.
	var live := DotFxBeacon.new()
	add_child(live)
	var _p := live.advance(0.0)
	var _q := live.advance(0.3)
	var ring_before := live.get_node(^"Ring")
	var voice_before := live.get_node_or_null(^"Ping")
	var phase_before := live._phase
	live.resize(5.0, 14.0, 4.0)
	var col := live.get_node(^"Column") as MeshInstance3D
	var torus := (live.get_node(^"Ring") as MeshInstance3D).mesh as TorusMesh
	_check(live.get_node(^"Ring") == ring_before and live.get_node_or_null(^"Ping") == voice_before
		and is_equal_approx(live._phase, phase_before),
		"resize() edits the meshes in place: same nodes, same voice, same phase")
	_check(is_equal_approx(torus.outer_radius, 5.0)
		and is_equal_approx((col.mesh as CylinderMesh).height, 14.0)
		and is_equal_approx(col.position.y, 11.0),
		"and the ring, the column's length and where it starts all follow")
	live.local_view = true
	live.resize(1.0, 3.0)
	_check(not live.column_shown() and is_equal_approx(live.column_base, 4.0),
		"a resize keeps the column hidden in the marked player's own view and the base it had")
	remove_child(live)
	live.free()


func _test_beam_and_thruster() -> void:
	_section("A beam is placed between two points, and a thruster clamps and breaks")

	var holder := Node3D.new()
	add_child(holder)
	var held := DotFxBeam.hold(holder)
	held.set_ends(Vector3.ZERO, Vector3(0.0, 0.0, 10.0))
	_check(held.visible, "a held beam shows between two points")
	_check(held.global_position.is_equal_approx(Vector3(0.0, 0.0, 5.0)), "centred between them")
	_check(is_equal_approx(held._mesh.scale.y, 10.0), "and as long as they are apart")
	held.set_ends(Vector3.ONE, Vector3.ONE)
	_check(not held.visible, "a zero-length beam hides")

	var shot := DotFxBeam.zap(holder, Vector3.ZERO, Vector3(0.0, 4.0, 0.0))
	_check(shot != null and shot.get_parent() == holder, "a zap is a child of the parent given")

	var jet := DotFxThruster.new()
	holder.add_child(jet)
	jet.throttle = 3.0
	_check(is_equal_approx(jet.throttle, 1.0), "throttle clamps to 1")
	jet.broken = true
	jet.spark()
	_check(jet.broken, "a thruster can be broken and sparks without error")
	holder.queue_free()


func _test_weather() -> void:
	_section("Weather is a validated document, falls only in its volumes, and is off without a display")

	var good := {
		"kind": "snow",
		"volumes": [
			{"min": [-10, 0, -10], "max": [10, 12, 10]},
			{"center": [40, 5, 0], "size": [8, 10, 8]},
		],
		"density": 1.5, "wind": [1, 0, 0], "colour": "#ddeeff", "sound": "amb_wind",
	}
	var res := DotFxWeatherDef.parse(good)
	_check(res.ok, "a good document parses")
	var def: DotFxWeatherDef = res.value
	_check(def.kind == &"snow" and def.volumes.size() == 2 and is_equal_approx(def.density, 1.5), "kind, volumes and density read back")
	_check(def.volumes[1].position.is_equal_approx(Vector3(36, 0, -4)) and def.sound == &"amb_wind", "a centre and size is a box; the sound id is kept")
	_check(DotFxWeatherDef.parse(def.to_dict()).ok, "to_dict parses again")

	var bad := good.duplicate(true)
	bad["kind"] = "hail"
	_check(DotFxWeatherDef.parse(bad).code() == DotError.CODE_INVALID, "an unknown kind is invalid")
	bad = good.duplicate(true)
	bad["volumes"] = [{"min": [0, 0, 0], "max": [0, 5, 5]}]
	_check(not DotFxWeatherDef.parse(bad).ok, "a flat volume is refused")
	bad = good.duplicate(true)
	bad["volums"] = []
	_check(not DotFxWeatherDef.parse(bad).ok, "a misspelt key is refused, not read as everywhere")
	bad = good.duplicate(true)
	bad["density"] = 9
	_check(not DotFxWeatherDef.parse(bad).ok, "density out of range is refused")
	_check(DotFxWeatherDef.parse({"kind": "rain"}).value.volumes.is_empty(), "no volumes means everywhere")

	# Which volumes reach the shader.
	var region := AABB(Vector3(5, 0, 0) - Vector3(14, 9, 14), Vector3(28, 18, 28))
	var picked := DotFxWeather.select_volumes(def.volumes, region, Vector3(5, 0, 0))
	_check(picked.size() == 1 and picked[0] == def.volumes[0], "only the volume the camera's box overlaps is picked")
	_check(DotFxWeather.select_volumes(def.volumes, AABB(Vector3(100, 0, 100), Vector3(5, 5, 5)), Vector3(100, 0, 100)).is_empty(), "far from every volume, none is picked")
	var many: Array[AABB] = []
	for i in range(40):
		many.append(AABB(Vector3(i, 0, 0), Vector3.ONE))
	var capped := DotFxWeather.select_volumes(many, AABB(Vector3(-5, -5, -5), Vector3(100, 10, 10)), Vector3.ZERO)
	_check(capped.size() == DotFxWeather.MAX_ACTIVE and capped[0] == many[0], "past the shader's limit the nearest are kept")
	_check(DotFxWeather.inside_any(def.volumes, Vector3(0, 5, 0)) and not DotFxWeather.inside_any(def.volumes, Vector3(20, 5, 0)), "inside_any says where the camera is")

	# Quality and density.
	var high := DotFxWeather.flakes_for(&"snow", 1.0, DotFxWeather.Quality.HIGH)
	var low := DotFxWeather.flakes_for(&"snow", 1.0, DotFxWeather.Quality.LOW)
	_check(DotFxWeather.flakes_for(&"snow", 1.0, DotFxWeather.Quality.OFF) == 0 and low > 0 and low < high, "off draws none, low fewer than high")
	_check(DotFxWeather.flakes_for(&"rain", 4.0, DotFxWeather.Quality.HIGH) <= DotFxWeather.MAX_FLAKES, "flakes are capped")

	var cfg := DotFxConfig.new()
	cfg.weather_quality = 1
	cfg.weather_density = 0.5
	var w := DotFxWeather.new()
	add_child(w)
	w.apply_config(cfg)
	_check(w.quality == DotFxWeather.Quality.LOW and is_equal_approx(w.density_scale, 0.5), "the config drives quality and density")

	# The sound hook, and the no-display rule. Headless here, so nothing is drawn.
	_check(not DotFxWeather.can_render(), "this suite runs without a display, so weather cannot render")
	_check(w.apply({"kind": "snow", "volumes": [{"min": [-10, 0, -10], "max": [10, 12, 10]}], "sound": "wind"}).ok, "apply accepts a document")
	var events: Array = []
	w.audible_changed.connect(func(id: StringName, inside_now: bool) -> void: events.append([id, inside_now]))
	w.advance(0.016, Vector3(0, 2, 0))
	w.advance(0.016, Vector3(50, 2, 0))
	_check(events == [[&"wind", true], [&"wind", false]], "the sound hook fires on entering and leaving a volume")
	_check(w.get_child_count() == 0 and w.describe().contains("not drawn"), "no display: nothing was built")
	_check(not w.apply({"kind": "fog"}).ok and w.definition.kind == &"snow", "a bad document leaves the old weather")
	w.set_gust(Vector3(3, 5, -2))
	_check(w.gust() == Vector3(3, 0, -2), "a gust leans the fall sideways only, never up or down")
	w.set_gust(Vector3.ZERO)
	_check(w.gust() == Vector3.ZERO, "and zero removes it")
	w.queue_free()


func _test_muzzle_flash() -> void:
	_section("muzzle flash: sizes, overrides, headless")
	var S := DotMuzzleFlash.Size
	_check(DotMuzzleFlash.size_for("pistol") == S.VERY_SMALL, "a pistol is very small")
	_check(DotMuzzleFlash.size_for("Shotgun") == S.BIG, "a shotgun is big, case ignored")
	_check(DotMuzzleFlash.size_for("rifle", {"muzzle_flash": "none"}) == S.NONE, "extra can switch it off")
	_check(DotMuzzleFlash.size_for("pistol", {"muzzle_flash": "big"}) == S.BIG, "extra overrides the category")
	_check(DotMuzzleFlash.size_for("rifle", {}, true) == S.NONE, "suppressed gives none")
	_check(DotMuzzleFlash.size_for("harpoon") == S.SMALL, "an unknown category is small")
	var f := DotMuzzleFlash.new()
	add_child(f)
	_check(not f.fire() and f.get_child_count() == 0, "headless: nothing built, fire is skipped")
	for s in [S.VERY_SMALL, S.SMALL, S.MEDIUM, S.BIG]:
		for v in range(1, DotMuzzleFlash.VARIANTS + 1):
			if not ResourceLoader.exists("%s%s%02d.tscn" % [DotMuzzleFlash.ROOT, DotMuzzleFlash.FOLDERS[s], v]):
				_check(false, "missing flash scene %d/%d" % [s, v])
	_check(true, "all 24 flash scenes exist")
	_check(DotMuzzleFlash.prewarm(f) == null, "headless: prewarm draws nothing")
	_check(f.is_ready(), "headless: a flash that can never draw counts as ready")
	_check(not f.is_processing(), "headless: it does not tick to build a pool")
	f.queue_free()


func _test_muzzle_flash_lifetime() -> void:
	_section("muzzle flash: short lifetime, reset on every shot")
	DotMuzzleFlash.force_available = true
	var f := DotMuzzleFlash.new()
	f.size = DotMuzzleFlash.Size.SMALL
	add_child(f)
	_check(f.fire(), "a forced-available flash fires")
	_check(f.is_showing(), "it shows right after the shot")
	await get_tree().create_timer(0.1).timeout
	_check(not f.is_showing(), "100 ms later it is hidden")
	f.fire()
	f.fire()
	f.fire()
	var shown := 0
	for n in f.get_children():
		if n is Node3D and (n as Node3D).visible:
			shown += 1
	_check(shown == 1, "three quick shots leave one flash, not a stack (%d)" % shown)
	var lit := false
	for n in f.get_children():
		if n is Node3D and (n as Node3D).visible:
			lit = bool(n.get("light_enable"))
	_check(lit, "by default the shot carries a light")
	f.stop()
	_check(not f.is_showing(), "stop hides it at once")
	f.fire()
	remove_child(f)
	_check(not f.is_showing(), "leaving the tree hides it")
	f.free()

	var dark := DotMuzzleFlash.new()
	dark.size = DotMuzzleFlash.Size.SMALL
	dark.light = false
	add_child(dark)
	var before := DotFxLightBudget.live()
	dark.fire()
	var dark_lit := false
	for n in dark.get_children():
		dark_lit = dark_lit or bool(n.get("light_enable"))
	_check(not dark_lit, "light = false: no instance carries a light")
	_check(DotFxLightBudget.live() == before, "and it takes nothing from the light cap")
	dark.free()

	DotMuzzleFlash.force_available = false


## 32 bots, 100 shots: nodes built and ms per shot with the old three-per-flash pool against the world pool, plus the distance cull.
func _test_muzzle_flash_bench() -> void:
	_section("muzzle flash bench: 32 bot muzzles, 100 shots")
	DotMuzzleFlash.force_available = true
	var report := {}
	for pool: int in [3, 1]:
		var cfg := DotMuzzleFlashConfig.new()
		cfg.world_pool = pool
		var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var flashes: Array[DotMuzzleFlash] = []
		for i in 32:
			var f := DotMuzzleFlash.new()
			f.size = DotMuzzleFlash.Size.SMALL
			f.config = cfg
			add_child(f)
			flashes.append(f)
		var t0 := Time.get_ticks_usec()
		for shot in 100:
			flashes[shot % 32].fire()
		var us := Time.get_ticks_usec() - t0
		var made := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - before)
		report[pool] = made
		print("[bench] world_pool=%d: %d nodes for 32 muzzles after 100 shots, %.3f ms per shot" % [pool, made, us / 1000.0 / 100.0])
		for f in flashes:
			f.free()
		DotFxLightBudget.reset()
	_check(int(report[1]) < int(report[3]), "a world pool of one builds fewer nodes (%d < %d)" % [report[1], report[3]])
	# Cull and light distance: a camera at the origin, a flash 200 m and 50 m away.
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var far := DotMuzzleFlash.new()
	far.size = DotMuzzleFlash.Size.SMALL
	add_child(far)
	far.position = Vector3(0, 0, -200)
	_check(not far.fire() and far.culled == 1, "a bot flash 200 m away is not drawn")
	far.position = Vector3(0, 0, -50)
	_check(far.fire(), "a bot flash 50 m away draws")
	var lit := false
	for n in far.get_children():
		lit = lit or (n is Node3D and (n as Node3D).visible and bool(n.get("light_enable")))
	_check(not lit, "but carries no light past the light distance")
	far.first_person = true
	far.position = Vector3(0, 0, -200)
	_check(far.fire(), "the first-person gun is never culled")
	far.free()
	cam.free()
	DotMuzzleFlash.force_available = false


func _solid(body: PhysicsBody3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)


func _decal_from_above(m: DotFxManager, x: float, y: float) -> Node:
	return m.spawn_decal(&"bullet_hole", Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.RIGHT), Vector3(x, y, 0)))


func _test_decal_surfaces() -> void:
	_section("decals sit on a surface: never in air, never on a character, and follow a prop")
	var floor_body := StaticBody3D.new()
	_solid(floor_body, Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	var crate := RigidBody3D.new()
	crate.freeze = true
	_solid(crate, Vector3(1, 1, 1), Vector3(5, 0.5, 0))
	var person := CharacterBody3D.new()
	_solid(person, Vector3(0.6, 1.8, 0.6), Vector3(-5, 0.9, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var cfg := DotFxConfig.new()
	cfg.quality = 3
	cfg.frame_budget = 0
	var m := _manager(cfg)
	var why: Array[StringName] = []
	m.spawned.connect(func(_id: StringName, _n: Node, r: StringName) -> void: why.append(r))

	var near_floor := 0
	var worst := 0.0
	for height: float in [0.0, 0.1, 0.2, 0.25]:
		var node := _decal_from_above(m, 0.0, height) as Node3D
		if node != null:
			near_floor += 1
			worst = maxf(worst, absf(node.global_position.y))
	_check(near_floor == 4 and worst < 0.001, "within reach of the floor: kept and snapped onto it (worst %.4f m off)" % worst)

	var floating := 0
	for height: float in [0.4, 0.6, 1.0, 5.0, 100.0]:
		if _decal_from_above(m, 0.0, height) != null:
			floating += 1
	_check(floating == 0, "in the air (a miss's endpoint, a body that moved): none kept (%d)" % floating)
	_check(why.count(&"no_surface") == 5, "and each refusal says no_surface")
	_check(m.decal_count() == 4, "so the ring holds only the four on the floor")

	_check(_decal_from_above(m, -5.0, 1.8) == null, "on a character's body: refused, it would walk away")

	var on_crate := _decal_from_above(m, 5.0, 1.0) as Node3D
	_check(on_crate != null and on_crate.get_parent() == crate, "on a rigid prop: kept, and parented to it")
	crate.global_position = Vector3(5, 3.5, 0)
	_check(absf(on_crate.global_position.y - 4.0) < 0.001, "the prop moves 3 m up and the decal goes with it (y %.3f)" % on_crate.global_position.y)
	crate.free()
	m.advance(0.016)
	_check(not is_instance_valid(on_crate) and m.decal_count() == 4, "the prop is freed: its decal goes too, and leaves the ring")

	var oblique := m.spawn_decal(&"bullet_hole", Transform3D(
		Basis.looking_at(Vector3(1, -1, 0).normalized(), Vector3.UP), Vector3(2, 0.1, 0))) as Node3D
	var down := -oblique.global_transform.basis.z
	_check(oblique != null and down.dot(Vector3.DOWN) > 0.999, "an oblique shot is turned flat onto the surface it hit")

	var down_at := Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.RIGHT), Vector3(0, 0.1, 0))
	var surf := m.surface_at(down_at)
	_check(not surf.is_empty() and absf((surf["position"] as Vector3).y) < 0.001, "surface_at is public and returns the floor under a point")
	_check(m.surface_at(Transform3D(down_at.basis, Vector3(0, 50, 0))).is_empty(), "and nothing in open air")
	_check(m.surface_at(Transform3D(down_at.basis, Vector3(-5, 1.8, 0))).is_empty(), "nor on a character")
	var held := RigidBody3D.new()
	held.freeze = true
	_solid(held, Vector3(1, 1, 1), Vector3(10, 0.5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(m.spawn_on_surface(&"bullet_hole", Transform3D(down_at.basis, Vector3(0, 50, 0))) == null, "spawn_on_surface refuses open air")
	var on_c := m.spawn_on_surface(&"bullet_hole", Transform3D(down_at.basis, Vector3(10, 1.0, 0))) as Node3D
	_check(on_c != null and on_c.get_parent() == held, "and an effect on a rigid prop is parented to it")

	m.queue_free()
	floor_body.queue_free()
	person.queue_free()
	held.queue_free()


func _test_muzzle_flash_follows() -> void:
	_section("muzzle flash follows its weapon and does not outlive its shot")
	DotMuzzleFlash.force_available = true
	var muzzle := Node3D.new()
	add_child(muzzle)
	var f := DotMuzzleFlash.new()
	f.size = DotMuzzleFlash.Size.SMALL
	muzzle.add_child(f)
	f.fire()
	var shown: Node3D = null
	for n in f.get_children():
		if n is Node3D and (n as Node3D).visible:
			shown = n
	_check(shown != null, "a flash is showing")
	muzzle.global_position = Vector3(7, 2, -3)
	_check(shown != null and shown.global_position.distance_to(Vector3(7, 2, -3)) < 0.01, "the weapon moves and the flash is still on its muzzle")
	await get_tree().create_timer(0.15).timeout
	_check(not f.is_showing(), "and 150 ms after the shot nothing of it is left")
	muzzle.queue_free()
	DotMuzzleFlash.force_available = false


func _test_light_cap_and_pools() -> void:
	_section("light cap and node pools")
	var cfg := DotFxPoolConfig.new()
	cfg.max_lights = -1
	var cap := cfg.effective_max_lights()
	var expect := 2 if DotPlatform.is_web() else (3 if DotPlatform.is_mobile() else 8)
	_check(cap == expect, "default cap follows the platform (%d)" % cap)
	cfg.max_lights = 5
	_check(cfg.effective_max_lights() == 5, "an explicit cap wins")

	DotFxLightBudget.config.max_lights = 2
	DotFxLightBudget.reset()
	var pool := DotFxLightPool.new()
	add_child(pool)
	pool.prewarm(3, 0)
	_check(pool.built() == 3 and pool.idle() == 3, "prewarm builds three idle lights")
	var a := pool.flash(Vector3.ZERO, Color.WHITE, 2.0, 4.0, 0.1)
	var b := pool.flash(Vector3.ONE, Color.WHITE, 2.0, 4.0, 0.1)
	var c := pool.flash(Vector3.ONE, Color.WHITE, 2.0, 4.0, 0.1)
	_check(a != null and b != null and c == null, "the third light is refused at a cap of two")
	_check(pool.built() == 3 and DotFxLightBudget.live() == 2, "no node was built beyond the prewarm")
	await get_tree().create_timer(0.2).timeout
	_check(pool.idle() == 3 and not a.visible, "lights return to the pool when done")
	var d := pool.flash(Vector3.ZERO, Color.RED, 1.0, 3.0, 0.1)
	_check(d == a or d == b or pool.built() == 3, "a later flash reuses a pooled light")
	_check(pool.built() == 3, "still three lights built")

	DotFxLightBudget.config.max_lights = 0
	DotFxLightBudget.reset()
	_check(pool.flash(Vector3.ZERO, Color.WHITE, 1.0, 3.0, 0.1) == null, "a cap of zero lights nothing")
	DotFxLightBudget.config.max_lights = -1
	DotFxLightBudget.reset()
	pool.queue_free()

	var meshes := DotFxMeshPool.new()
	add_child(meshes)
	var quad := QuadMesh.new()
	await meshes.prewarm(quad, null, 2, 0)
	_check(meshes.built() == 2 and meshes.idle() == 2, "mesh prewarm builds two idle instances")
	var m1 := meshes.acquire(quad, Transform3D.IDENTITY)
	var m2 := meshes.acquire(quad, Transform3D.IDENTITY)
	_check(meshes.built() == 2 and m1 != m2 and m1.visible, "acquire reuses the prewarmed pair")
	meshes.release(m1)
	meshes.release(m1)
	_check(meshes.idle() == 1 and not m1.visible, "release hides and pools once, even when called twice")
	var m3 := meshes.acquire(quad, Transform3D.IDENTITY)
	_check(m3 == m1 and meshes.built() == 2, "the released instance is the one reused")
	DotFxMeshPool.max_idle = 0
	meshes.release(m3)
	_check(meshes.idle() == 0 and meshes.built() == 1 and m3.is_queued_for_deletion(),
		"max_idle frees a release past the cap instead of pooling it")
	DotFxMeshPool.max_idle = -1
	meshes.queue_free()
