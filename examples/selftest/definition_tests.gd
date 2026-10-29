extends "res://examples/selftest/harness.gd"
## Definition, catalogue, budget, decal, shake and flash sections.


func _test_definitions() -> void:
	_section("An effect is a document that names a scene")

	var d := DotFxDef.new()
	_check(not d.validate().ok, "an effect with no id is refused")
	d.id = &"x"
	_check(not d.validate().ok, "and a scene effect that names no scene")
	d.scene_path = "res://not_here.tscn"
	_check(
		d.validate().ok,
		"while one naming a scene that does not exist validates, because a server has none"
	)

	var shake := DotFxDef.new()
	shake.id = &"s"
	shake.kind = DotFxDef.Kind.SHAKE
	_check(
		not shake.validate().ok,
		"a shake with no trauma is refused, because it is guaranteed to do nothing"
	)
	shake.shake_trauma = 0.3
	_check(shake.validate().ok, "and one with some is fine")

	var screen := DotFxDef.new()
	screen.id = &"f"
	screen.kind = DotFxDef.Kind.SCREEN
	screen.flash_peak = 0.0
	_check(not screen.validate().ok, "and a flash with no opacity, for the same reason")


func _test_catalogue() -> void:
	_section("A catalogue a server with no renderer can check")

	var c := _catalogue()
	_check(c.validate().ok, "it validates")
	_check(c.ids().size() == 5, "and enumerates")
	_check(c.find(&"spark") != null, "and finds")
	_check(c.find(&"nope") == null, "and does not invent")

	var dupe := DotFxCatalogue.new()
	dupe.add(_def(&"twice")).add(_def(&"twice"))
	_check(not dupe.validate().ok, "a duplicate id is refused")

	# `missing_scenes` is a different question from `validate`: a server without the content and
	# a client with a broken export both look like well-formed documents with absent scenes.
	_check(c.missing_scenes().is_empty(), "a catalogue whose scenes are all here is missing none")

	var absent := DotFxCatalogue.new()
	var gone := _def(&"gone")
	gone.scene_path = "res://fixtures/there_is_no_such_scene.tscn"
	absent.add(gone)
	_check(
		absent.validate().ok,
		"a catalogue naming a scene that is not here is still VALID, which is the point"
	)
	_check(
		Array(absent.missing_scenes()) == [gone.scene_path],
		"and says which one is missing, because that is a different question from validity"
	)
	var bodiless := DotFxCatalogue.new()
	bodiless.add(_def(&"shake_only", DotFxDef.Kind.SHAKE))
	bodiless.defs[0].scene_path = ""
	_check(
		bodiless.missing_scenes().is_empty(),
		"while an effect that names no scene is not missing one"
	)

	var m := _manager()
	_check(m.describe()["live"] == 0, "a fresh manager has nothing live")
	_check(m.describe_lines().size() > 2, "and describes itself")
	m.queue_free()


func _test_quality_gate() -> void:
	_section("A low tier is missing effects, not running them badly")

	var cfg := DotFxConfig.new()
	cfg.quality = 0
	cfg.frame_budget = 0
	var m := _manager(cfg)
	var refusals := []
	m.spawned.connect(func(id: StringName, node: Node, why: StringName) -> void:
		if node == null:
			refusals.append([id, why])
	)

	_check(m.spawn(&"collapse", Transform3D.IDENTITY) == null, "the expensive effect is refused")
	_check(refusals.size() == 1 and refusals[0][1] == &"quality", "because of the tier")
	_check(m.spawn(&"spark", Transform3D.IDENTITY) != null, "while the cheap one still appears")

	# Halving a particle count on the effect that is killing the frame does not save the
	# frame. Not spawning it does.
	m.config.quality = 3
	_check(
		m.spawn(&"collapse", Transform3D.IDENTITY) != null,
		"and raising the tier makes it exist again, with no restart"
	)

	_check(m.spawn(&"no_such_effect", Transform3D.IDENTITY) == null, "an unknown id is refused")
	_check(
		refusals.back()[1] == &"unknown",
		"and says so, rather than looking like a budget refusal"
	)

	m.queue_free()


func _test_budget_and_culling() -> void:
	_section("A frame's worth, and no further")

	var cfg := DotFxConfig.new()
	cfg.quality = 3
	cfg.frame_budget = 10
	cfg.max_instances = 1000
	var m := _manager(cfg)
	m.viewer_position = Vector3.ZERO

	var made := 0
	for _i in range(30):
		if m.spawn(&"spark", Transform3D.IDENTITY) != null:
			made += 1
	_check(made == 10, "the budget stops at what a frame can afford")
	_check(m.budget_left() == 0, "with nothing left")

	m.advance(0.016)
	_check(m.budget_left() == 10, "and the next frame refills it")
	_check(
		m.spawn(&"spark", Transform3D.IDENTITY) != null,
		"so an effect refused this frame is not refused for ever"
	)

	_budget_priority(m)

	# A refused request retires nothing: the budget is asked before the instance cap recycles.
	var tight := DotFxConfig.new()
	tight.quality = 3
	tight.frame_budget = 1
	tight.max_instances = 1
	var t := _manager(tight)
	var first := t.spawn(&"spark", Transform3D.IDENTITY)
	_check(
		t.spawn(&"spark", Transform3D.IDENTITY) == null and is_instance_valid(first)
			and not first.is_queued_for_deletion(),
		"a request the budget refuses has not already retired a live effect"
	)
	t.queue_free()

	# This is only safe because of the one invariant the whole addon rests on: an effect
	# never changes the simulation, so a client that dropped one and a client that did not
	# are playing the same game.
	var far := Transform3D.IDENTITY
	far.origin = Vector3(0, 0, 400)
	m.advance(0.016)
	_check(m.spawn(&"spark", far) == null, "a distant effect is culled")
	m.config.distance_scale = 20.0
	_check(
		m.spawn(&"spark", far) != null,
		"and the cull distance is a setting, so a high-end machine can keep them"
	)

	m.config.distance_scale = 1.0
	m.config.cull_behind = true
	m.viewer_forward = Vector3(0, 0, 1)
	var behind := Transform3D.IDENTITY
	behind.origin = Vector3(0, 0, -10)
	m.advance(0.016)
	_check(m.spawn(&"spark", behind) == null, "and something behind the camera can be skipped")
	m.config.cull_behind = false
	m.advance(0.016)
	_check(
		m.spawn(&"spark", behind) != null,
		"though it is off by default, because turning round after an explosion should show smoke"
	)

	_lifetime_ceiling()

	m.queue_free()


func _budget_priority(m: DotFxManager) -> void:
	# Priority decides what a full frame keeps: the collapse (40, priority 90) asked for after
	# ten sparks (1 each, priority 20) takes the room of five of them, in the same frame.
	m.config.frame_budget = 45
	m.advance(0.016)
	var sparks: Array[Node] = []
	for _i in range(10):
		sparks.append(m.spawn(&"spark", Transform3D.IDENTITY))
	var collapse := m.spawn(&"collapse", Transform3D.IDENTITY)
	var kept := 0
	for spark in sparks:
		if is_instance_valid(spark) and not spark.is_queued_for_deletion():
			kept += 1
	_check(collapse != null and kept == 5, "a higher priority takes a full frame's room from lower ones started in it")
	_check(m.spawn(&"spark", Transform3D.IDENTITY) == null, "and a lower one never takes it back")
	m.advance(0.016)
	m.config.frame_budget = 10
	m.advance(0.016)
	_check(
		m.spawn(&"collapse", Transform3D.IDENTITY) == null and is_instance_valid(collapse)
			and not collapse.is_queued_for_deletion(),
		"while one too dear for the whole frame is refused, displacing nothing"
	)
	m.clear()


func _lifetime_ceiling() -> void:
	# A lifetime is a ceiling, not a hint: one effect that forgets to free itself is a leak
	# that reads as a slow memory problem in the game.
	var short := _manager()
	short.config.frame_budget = 0
	var d := short.catalogue.find(&"spark")
	d.lifetime_ms = 1
	short.spawn(&"spark", Transform3D.IDENTITY)
	_check(short.live_count() == 1, "an effect is live")
	OS.delay_msec(5)
	short.advance(0.016)
	_check(short.live_count() == 0, "and is taken back when its lifetime is up, whatever it thinks")
	short.queue_free()


func _test_decal_ring() -> void:
	_section("Decals are a ring, because an unbounded list grows with the round")

	var cfg := DotFxConfig.new()
	cfg.quality = 3
	cfg.frame_budget = 0
	cfg.max_decals = 4
	var m := _manager(cfg)
	m.decal_surface_mask = 0

	for _i in range(10):
		m.spawn_decal(&"bullet_hole", Transform3D.IDENTITY)
	_check(m.decal_count() == 4, "the ring holds exactly its capacity")
	_check(m.live_count() == 4, "and the recycled ones are actually gone, not merely forgotten")

	# The leak this prevents is invisible in testing and fatal at minute forty: it grows
	# with the round rather than with the number of players.
	m.config.max_decals = 2
	m.spawn_decal(&"bullet_hole", Transform3D.IDENTITY)
	_check(m.decal_count() == 2, "and lowering the cap takes effect immediately")
	m.config.max_decals = 1
	m.advance(0.016)
	_check(m.decal_count() == 1, "or at the next frame, with no decal spawned")

	# Decals at the instance cap recycle the oldest decal instead of refusing the spawn.
	m.clear()
	m.config.max_decals = 3
	m.config.max_instances = 3
	for _i in range(3):
		m.spawn_decal(&"bullet_hole", Transform3D.IDENTITY)
	_check(
		m.spawn(&"spark", Transform3D.IDENTITY) != null and m.live_count() == 3,
		"with the cap all decals, a new effect recycles the oldest decal instead of being refused"
	)

	m.clear()
	_check(m.live_count() == 0 and m.decal_count() == 0, "clear takes everything, for a map change")

	m.queue_free()


func _test_shake() -> void:
	_section("Shake is a value, and has to be able to be off")

	var s := DotFxShake.new()
	_check(not s.active(), "nothing is shaking to start with")
	_check(s.offset() == Vector3.ZERO, "and the offset is exactly zero")

	s.add(0.5)
	_check(s.active(), "trauma makes it active")
	_check(s.offset() != Vector3.ZERO, "and produces an offset")

	# Squared falloff: a linear one reads as a shake that switches off, because the last
	# few per cent of a linear ramp is still visible motion.
	var big := s.offset().length()
	s.reset()
	s.add(0.25)
	var small := s.offset().length()
	_check(
		small < big * 0.5,
		"halving the trauma takes much more than half the shake away, which is what makes it fade"
	)

	s.reset()
	s.add(2.0)
	_check(s.trauma() <= 1.0, "trauma is clamped, so a hundred explosions is not a hundred shakes")

	s.add(1.0)
	s.advance(1.0)
	_check(s.trauma() < 1.0, "and it decays")
	s.advance(10.0)
	_check(not s.active(), "to nothing")

	# Three offsets into one noise field. Sampling the same point three times gives three
	# identical numbers and a camera that slides along a diagonal.
	s.reset()
	s.add(1.0)
	var o := s.offset()
	_check(
		not (is_equal_approx(o.x, o.y) and is_equal_approx(o.y, o.z)),
		"the three axes are uncorrelated, rather than one number used three times"
	)

	# Continuity: a shake made of a fresh random number per frame is jitter at the frame
	# rate, and reads as a rendering fault rather than as a shaken camera.
	s.reset()
	s.add(1.0)
	var a := s.offset()
	s.advance(1.0 / 240.0)
	var b := s.offset()
	_check(
		a.distance_to(b) < s.max_offset * 0.5,
		"and two consecutive frames are close together, which random-per-frame is not"
	)

	_shake_scale(s)


func _shake_scale(s: DotFxShake) -> void:
	# The accessibility half, and the reason it is read every frame.
	s.scale = 0.0
	_check(not s.active(), "a scale of zero turns it off entirely")
	_check(s.offset() == Vector3.ZERO, "with no residual motion at all")
	_check(is_equal_approx(s.roll(), 0.0), "including the roll")

	# `offset_2d` had no caller. Asserted against `offset()` rather than against a number,
	# because the noise field is what decides the number and a hard-coded one would be
	# asserting the noise implementation rather than the projection.
	s.scale = 1.0
	s.add(1.0)
	s.advance(0.016)
	var three := s.offset()
	var two := s.offset_2d()
	_check(
		is_equal_approx(two.x, three.x) and is_equal_approx(two.y, three.y),
		"the 2D displacement is the same sample as the 3D one, projected"
	)
	s.scale = 0.0
	_check(s.offset_2d() == Vector2.ZERO, "and it goes to zero with everything else")

	var m := _manager()
	m.config.shake_scale = 0.0
	m.spawn(&"grenade_shake", Transform3D.IDENTITY)
	m.advance(0.016)
	_check(
		m.shake.offset() == Vector3.ZERO,
		"and a player's setting reaches it through the manager, on the very next frame"
	)
	m.queue_free()


func _test_flash_limits() -> void:
	_section("A full-screen flash is a hazard before it is a style")

	var m := _manager()
	var events := []
	m.flashed.connect(func(id: StringName, c: Color, peak: float, applied: bool) -> void:
		events.append([id, c, peak, applied])
	)

	_check(m.flash(&"hurt_flash"), "a flash is applied")
	_check(m.flash_colour.a > 0.0, "and shows up as a colour the game draws")
	_check(
		is_equal_approx(m.flash_colour.a, 0.6),
		"capped at the configured maximum rather than the 0.9 the definition asked for"
	)

	# The published guidance is no more than three general flashes in any one second. It
	# is enforced here rather than left to the caller, because the caller that does not
	# honour it is the next feature somebody adds.
	m.flash(&"hurt_flash")
	m.flash(&"hurt_flash")
	var fourth := m.flash(&"hurt_flash")
	_check(not fourth, "the fourth flash in a second is refused")
	_check(events.back()[3] == false, "and says it was refused rather than pretending")

	m.advance(0.5)
	_check(m.flash_colour.a < 0.6, "a flash decays")

	# The off switch. A game that cannot honour a player asking for no flashes has no
	# answer for somebody it could actually harm.
	m.config.allow_flashes = false
	m.flash_colour.a = 0.0
	_check(not m.flash(&"hurt_flash"), "and a player who has asked for none gets none")
	_check(is_equal_approx(m.flash_colour.a, 0.0), "with nothing drawn at all")

	m.config.allow_flashes = true
	m.config.flashes_per_second = 0
	_check(m.flash(&"hurt_flash"), "a rate of zero means unlimited, for a cutscene")

	m.queue_free()


func _test_screen_goo() -> void:
	_section("screen goo: envelope, stacking, status path")
	var goo := DotFxScreenGoo.new()
	add_child(goo)
	_check(goo.amount() == 0.0, "starts clear")
	goo.apply(0.5, 4.0, 1.0, 1.0)
	goo.advance(0.5)
	_check(is_equal_approx(goo.amount(), 0.25), "rises over fade_in")
	goo.advance(1.5)
	_check(is_equal_approx(goo.amount(), 0.5), "holds at its amount")
	goo.apply(0.4, 4.0, 0.0, 0.0)
	goo.advance(0.0)
	_check(is_equal_approx(goo.amount(), 0.9), "two applications stack")
	goo.apply(0.9, 4.0, 0.0, 0.0)
	goo.advance(0.0)
	_check(is_equal_approx(goo.amount(), 1.0), "stacking is capped at max_amount")
	goo.advance(4.1)
	_check(is_equal_approx(goo.amount(), 0.0), "all ended after their duration (%.2f)" % goo.amount())
	_check(goo.applications.is_empty(), "ended applications are dropped")
	goo.max_amount = 0.6
	goo.set_status(2, 5.0)
	goo.advance(1.0)
	_check(is_equal_approx(goo.amount(), 0.6), "status stacks reach per_stack times stacks, capped")
	goo.set_status(2, 0.5)
	goo.advance(1.0)
	_check(is_equal_approx(goo.amount(), 0.3), "status fades over its last second")
	goo.set_status(0, 0.0)
	goo.advance(1.0)
	_check(goo.amount() == 0.0, "no stacks clears")
	goo.apply(1.0, 5.0)
	goo.clear()
	_check(goo.amount() == 0.0, "clear removes at once")
	goo.queue_free()


