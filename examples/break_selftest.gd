extends Node

## Headless checks for [DotFxBreak]: one burst per material with particles and a sound, aliases, frees
## itself, off spawns none, the caps, a headless refusal, config layering. Looks: break_demo.tscn.

const SECTIONS := 6
const CHECKS := 38

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_materials()
	_aliases()
	_switches()
	_caps()
	await _frees()
	_config()
	print("")
	print("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		print("ERROR: %d sections and %d checks ran, %d and %d expected" % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _make(cfg: DotFxBreakConfig = null) -> DotFxBreak:
	var b := DotFxBreak.new()
	var c := cfg if cfg != null else DotFxBreakConfig.new()
	c.headless = true
	c.seed_value = 5
	b.config = c
	add_child(b)
	return b


func _materials() -> void:
	_section("each material spawns particles and a sound")
	var b := _make()
	for m: String in DotFxBreak.MATERIALS:
		var n := b.burst(m, Vector3(1, 2, 3), Vector3.UP, 1.0)
		_check(n != null, "%s spawns" % m)
		if n == null:
			_check(false, "%s has particles" % m)
			_check(false, "%s has a sound" % m)
			continue
		var p := n.get_node_or_null("Pieces") as CPUParticles3D
		_check(p != null and p.amount > 0 and p.emitting, "%s has emitting particles" % m)
		_check(n.get_node_or_null("Crack") is AudioStreamPlayer3D and (n.get_node("Crack") as AudioStreamPlayer3D).stream != null,
			"%s has a sound with a stream" % m)
	_check(b.spawned == 5, "five bursts counted")
	b.queue_free()


func _aliases() -> void:
	_section("source material names map onto the five")
	_check(DotFxBreak.canonical("concrete") == &"stone", "concrete is stone")
	_check(DotFxBreak.canonical("unbreakable_glass") == &"glass", "unbreakable_glass is glass")
	_check(DotFxBreak.canonical("computer") == &"metal", "computer is metal")
	_check(DotFxBreak.canonical("Wood") == &"wood", "case is ignored")
	_check(DotFxBreak.canonical("nonsense") == &"glass", "unknown falls back to glass")


func _switches() -> void:
	_section("off, no sound, scale 0, headless")
	var cfg := DotFxBreakConfig.new()
	cfg.enabled = false
	var b := _make(cfg)
	_check(b.burst("wood", Vector3.ZERO) == null and b.last_refusal == "disabled", "disabled spawns none")
	b.config.enabled = true
	b.config.sounds = false
	var n := b.burst("wood", Vector3.ZERO)
	_check(n != null and n.get_node_or_null("Crack") == null, "sounds off: particles only")
	b.config.sounds = true
	b.config.scale = 0.0
	n = b.burst("glass", Vector3.ZERO)
	_check(n != null and n.get_node_or_null("Pieces") == null and n.get_node_or_null("Crack") != null, "scale 0: sound only")
	b.config.scale = 1.0
	b.config.headless = false
	_check(b.burst("wood", Vector3.ZERO) == null and b.last_refusal == "headless", "a headless process draws nothing unless told to")
	b.queue_free()


func _caps() -> void:
	_section("particle and live caps")
	var cfg := DotFxBreakConfig.new()
	cfg.max_particles = 10
	cfg.max_live = 3
	var b := _make(cfg)
	var n := b.burst("glass", Vector3.ZERO, Vector3.UP, 6.0)
	_check((n.get_node("Pieces") as CPUParticles3D).amount <= 10, "a big prop is held to max_particles")
	b.burst("wood", Vector3.ZERO)
	b.burst("wood", Vector3.ZERO)
	_check(b.live_count() == 3, "three live")
	_check(b.burst("wood", Vector3.ZERO) == null and b.last_refusal == "too many live", "the fourth is refused")
	b.queue_free()


func _frees() -> void:
	_section("a burst frees itself")
	var b := _make()
	var n := b.burst("wood", Vector3.ZERO)
	var ref: WeakRef = weakref(n)
	_check(n.get_parent() == b, "under the node")
	await get_tree().create_timer(4.0).timeout
	_check(ref.get_ref() == null, "gone after its lifetime")
	_check(b.get_child_count() == 0, "the node is empty again")
	_check(b.burst("wood", Vector3.ZERO) != null, "and room for more")
	b.queue_free()


func _config() -> void:
	_section("config layering")
	var cfg := DotFxBreakConfig.new()
	var rep: Variant = cfg.apply_dictionary({"enabled": false, "scale": 2.0, "max_live": 4})
	_check(not cfg.enabled and cfg.scale == 2.0 and cfg.max_live == 4, "a dictionary sets keys")
	_check(cfg.effective_scale() == 0.0, "disabled has no effective scale")
	cfg.enabled = true
	_check(cfg.env_prefix() == "DOT_FX_BREAK_" and cfg.cli_prefix() == "--break-", "env and cli prefixes")
	_check(cfg.validate().ok, "valid")
	cfg.max_live = -1
	_check(not cfg.validate().ok, "negative caps are refused")
	_check(rep != null, "apply_dictionary reports")


func _section(title: String) -> void:
	_section_count += 1
	print("")
	print("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)
