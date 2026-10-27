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

const SECTIONS := 12
const CHECKS := 123

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
	_test_placed_before_entering()
	_test_beacon()
	_test_weather()
	_test_beam_and_thruster()
	_test_screen_goo()

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
	m.config.max_decals = 1
	m.advance(0.016)
	_check(m.decal_count() == 1, "or at the next frame, with no decal spawned")

	# Decals at the instance cap used to refuse every spawn: recycling skipped decals.
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


# --- 8 ----------------------------------------------------------------------

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


# --- 9 ----------------------------------------------------------------------

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


# --- 10 ---------------------------------------------------------------------

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
	w.queue_free()
