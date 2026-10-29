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
	f.stop()
	_check(not f.is_showing(), "stop hides it at once")
	f.fire()
	remove_child(f)
	_check(not f.is_showing(), "leaving the tree hides it")
	f.free()
	DotMuzzleFlash.force_available = false
