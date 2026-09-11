extends Node

## Exercises dot-fx with no renderer, which nearly all of it survives.
##
## What a headless run can genuinely check is the decision-making: which effects exist at
## a quality tier, what the budget refuses, what the distance cull skips, whether the
## decal ring actually recycles, and whether a flash is rate limited. What it cannot check
## is whether any of it looks right — that wants a screenshot, and this family has now
## found four bugs with a picture that no assertion could reach.
##
## [codeblock]
## godot --headless --path . res://examples/fx_selftest.tscn
## [/codeblock]

const SECTIONS := 7
const CHECKS := 62

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-fx self-test")
	_line("")

	_test_definitions()
	_test_catalogue()
	_test_quality_gate()
	_test_budget_and_culling()
	_test_decal_ring()
	_test_shake()
	_test_flash_limits()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _def(id: StringName, kind: DotFxDef.Kind = DotFxDef.Kind.SPAWNED) -> DotFxDef:
	var d := DotFxDef.new()
	d.id = id
	d.kind = kind
	d.scene_path = "res://fixtures/blob.tscn"
	d.lifetime_ms = 100000
	return d


func _catalogue() -> DotFxCatalogue:
	var c := DotFxCatalogue.new()

	var cheap := _def(&"spark")
	cheap.cost = 1
	cheap.priority = 20
	cheap.max_distance = 50.0
	c.add(cheap)

	var dear := _def(&"collapse")
	dear.cost = 40
	dear.priority = 90
	dear.min_quality = 3
	dear.max_distance = 0.0
	c.add(dear)

	var hole := _def(&"bullet_hole", DotFxDef.Kind.DECAL)
	hole.cost = 1
	hole.max_distance = 0.0
	c.add(hole)

	var boom := DotFxDef.new()
	boom.id = &"grenade_shake"
	boom.kind = DotFxDef.Kind.SHAKE
	boom.shake_trauma = 0.6
	c.add(boom)

	var hurt := DotFxDef.new()
	hurt.id = &"hurt_flash"
	hurt.kind = DotFxDef.Kind.SCREEN
	hurt.flash_peak = 0.9
	hurt.flash_colour = Color(1, 0, 0, 1)
	hurt.flash_decay_ms = 200
	c.add(hurt)

	return c


func _manager(cfg: DotFxConfig = null) -> DotFxManager:
	var m := DotFxManager.new()
	m.catalogue = _catalogue()
	m.config = cfg if cfg != null else DotFxConfig.new()
	m.register_as_service = false
	add_child(m)
	m.setup()
	return m


# --- 1 ----------------------------------------------------------------------

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


# --- 2 ----------------------------------------------------------------------

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

	# `missing_scenes` is a different question from `validate`, and had no caller. A
	# catalogue whose documents are all well formed and whose scenes are all absent is
	# exactly what a server validating content it does not have looks like -- and exactly
	# what a client with a broken export looks like. Only one of those is a bug, which is
	# why they are two calls.
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


# --- 3 ----------------------------------------------------------------------

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


# --- 4 ----------------------------------------------------------------------

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

	m.queue_free()
	short.queue_free()


# --- 5 ----------------------------------------------------------------------

func _test_decal_ring() -> void:
	_section("Decals are a ring, because an unbounded list grows with the round")

	var cfg := DotFxConfig.new()
	cfg.quality = 3
	cfg.frame_budget = 0
	cfg.max_decals = 4
	var m := _manager(cfg)

	for _i in range(10):
		m.spawn_decal(&"bullet_hole", Transform3D.IDENTITY)
	_check(m.decal_count() == 4, "the ring holds exactly its capacity")
	_check(m.live_count() == 4, "and the recycled ones are actually gone, not merely forgotten")

	# The leak this prevents is invisible in testing and fatal at minute forty: it grows
	# with the round rather than with the number of players.
	m.config.max_decals = 2
	m.spawn_decal(&"bullet_hole", Transform3D.IDENTITY)
	_check(m.decal_count() == 2, "and lowering the cap takes effect immediately")

	m.clear()
	_check(m.live_count() == 0 and m.decal_count() == 0, "clear takes everything, for a map change")

	m.queue_free()


# --- 6 ----------------------------------------------------------------------

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


# --- 7 ----------------------------------------------------------------------

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


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
