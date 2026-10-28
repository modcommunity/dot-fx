extends Node
## Shared state, helpers and check counters of the dot-fx self-test.

var _passed := 0
var _failed := 0
var _section_count := 0


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
