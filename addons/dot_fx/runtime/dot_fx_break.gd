class_name DotFxBreak
extends Node

## Splinters, shards, sparks or chunks, and a crack, where a prop breaks, keyed by its material. A game adds one node and calls [method burst] from its break signal; nothing here touches the simulation.
## CPUParticles3D everywhere: bursts are a few dozen one-shot particles, and GPU particles would cost a browser a shader compile.

const CHANNEL := "fx.break"
const MATERIALS: PackedStringArray = ["glass", "wood", "metal", "stone", "plastic"]
const SOUND_VARIANTS := 3

## Source material names (and a few common ones) onto the five this draws.
const ALIASES := {
	"unbreakable_glass": "glass", "glass_frosted": "glass", "window": "glass",
	"plank": "wood", "crate": "wood", "cardboard": "wood", "paper": "wood",
	"concrete": "stone", "rock": "stone", "tile": "stone", "brick": "stone", "ceramic": "stone",
	"tin": "metal", "plate": "metal", "computer": "metal",
	"flesh": "plastic", "web": "plastic", "rubber": "plastic",
}

var config := DotFxBreakConfig.new()
## Why the last [method burst] returned null, empty after one that spawned.
var last_refusal := ""
## Bursts drawn since this node entered the tree.
var spawned := 0

var _live: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _materials := {}
var _streams := {}


func _ready() -> void:
	apply_config(config)


func apply_config(cfg: DotFxBreakConfig) -> void:
	config = cfg
	if cfg.seed_value != 0:
		_rng.seed = cfg.seed_value
	else:
		_rng.randomize()


## Takes `fx_quality` (0 off) from a dot-settings manager, duck-typed: dot-fx does not depend on it.
func follow(store: Object) -> void:
	if store == null:
		return
	config.enabled = store.get_int(&"fx_quality", 3) > 0
	if not store.changed.is_connected(_on_changed):
		store.changed.connect(_on_changed.bind(store))


func _on_changed(key: StringName, _value: Variant, _why: StringName, store: Object) -> void:
	if key == &"fx_quality":
		config.enabled = store.get_int(&"fx_quality", 3) > 0


## The material this draws for [param name]: one of [constant MATERIALS], else glass for anything unknown.
static func canonical(name: String) -> StringName:
	var n := name.to_lower()
	if MATERIALS.has(n):
		return StringName(n)
	return StringName(String(ALIASES.get(n, "glass")))


func live_count() -> int:
	_prune()
	return _live.size()


## A burst of [param material] at [param at], thrown along [param normal] (the broken face's outward
## direction), [param size] about the prop's width in metres. Returns its root, which frees itself, or
## null with [member last_refusal] set.
func burst(material: String, at: Vector3, normal: Vector3 = Vector3.UP, size: float = 1.0) -> Node3D:
	last_refusal = ""
	if not is_inside_tree():
		last_refusal = "not in the tree"
		return null
	if not config.enabled:
		last_refusal = "disabled"
		return null
	if DotPlatform.is_headless() and not config.headless:
		last_refusal = "headless"
		return null
	_prune()
	if _live.size() >= config.max_live:
		last_refusal = "too many live"
		return null
	var kind := canonical(material)
	var root := Node3D.new()
	root.name = "Break_%s" % kind
	add_child(root)
	root.global_position = at
	var up := normal.normalized() if normal.length() > 0.001 else Vector3.UP
	var width := clampf(size, 0.1, 6.0)
	var count := mini(int(round(_base_count(kind) * (0.5 + width * 0.5) * config.effective_scale())), config.max_particles)
	var lifetime := 0.0
	if count > 0:
		lifetime = _particles(root, kind, count, up, width)
	if config.sounds:
		lifetime = maxf(lifetime, _sound(root, kind))
	_live.append(root)
	spawned += 1
	get_tree().create_timer(maxf(lifetime, 0.1) + 0.3).timeout.connect(root.queue_free)
	DotLog.trace(CHANNEL, "break", {"material": String(kind), "particles": count})
	return root


static func _base_count(kind: StringName) -> int:
	match kind:
		&"glass":
			return 28
		&"wood":
			return 22
		&"metal":
			return 18
		&"stone":
			return 16
	return 14


func _particles(root: Node3D, kind: StringName, count: int, up: Vector3, width: float) -> float:
	var p := CPUParticles3D.new()
	p.name = "Pieces"
	p.amount = maxi(count, 1)
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = up
	p.spread = 70.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15 * width
	p.lifetime = 1.3
	p.mesh = _mesh(kind)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	if kind == &"metal":
		p.initial_velocity_max = 5.0
	root.add_child(p)
	p.emitting = true
	var life := p.lifetime
	# A dim, low-alpha puff: unshaded sprites stack to white if bright, and hide the pieces.
	if kind == &"wood" or kind == &"stone":
		var dust := CPUParticles3D.new()
		dust.name = "Dust"
		dust.amount = maxi(count / 4, 2)
		dust.one_shot = true
		dust.explosiveness = 1.0
		dust.local_coords = false
		dust.direction = up
		dust.spread = 90.0
		dust.initial_velocity_min = 0.3
		dust.initial_velocity_max = 1.2
		dust.gravity = Vector3(0.0, 0.2, 0.0)
		dust.lifetime = 0.9
		dust.scale_amount_min = 0.3 * width
		dust.scale_amount_max = 0.6 * width
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.3, 0.24, 0.17, 0.2) if kind == &"wood" else Color(0.28, 0.28, 0.26, 0.2))
		ramp.set_color(1, Color(0.22, 0.19, 0.15, 0.0))
		dust.color_ramp = ramp
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = DotFxSoftSprite.material(Color.WHITE, false)
		dust.mesh = quad
		root.add_child(dust)
		dust.emitting = true
	return life


func _mesh(kind: StringName) -> Mesh:
	var key := String(kind)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: Mesh
	match kind:
		&"glass":
			mat.albedo_color = Color(0.75, 0.92, 1.0, 0.55)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var shard := PrismMesh.new()
			shard.size = Vector3(0.07, 0.11, 0.01)
			mesh = shard
		&"wood":
			mat.albedo_color = Color(0.62, 0.43, 0.24)
			var splinter := BoxMesh.new()
			splinter.size = Vector3(0.035, 0.035, 0.26)
			mesh = splinter
		&"metal":
			mat.albedo_color = Color(1.0, 0.82, 0.4)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.6, 0.2)
			var spark := BoxMesh.new()
			spark.size = Vector3(0.015, 0.015, 0.07)
			mesh = spark
		&"stone":
			mat.albedo_color = Color(0.5, 0.5, 0.48)
			var chunk := BoxMesh.new()
			chunk.size = Vector3(0.08, 0.06, 0.07)
			mesh = chunk
		_:
			mat.albedo_color = Color(0.85, 0.25, 0.2)
			var piece := BoxMesh.new()
			piece.size = Vector3(0.07, 0.04, 0.06)
			mesh = piece
	mesh.material = mat
	_materials[key] = mesh
	return mesh


func _sound(root: Node3D, kind: StringName) -> float:
	var stream := _stream(kind, _rng.randi() % SOUND_VARIANTS)
	if stream == null:
		return 0.0
	var a := AudioStreamPlayer3D.new()
	a.name = "Crack"
	a.stream = stream
	a.volume_db = config.volume_db
	a.pitch_scale = _rng.randf_range(0.9, 1.1)
	a.unit_size = 8.0
	a.max_distance = 60.0
	root.add_child(a)
	a.play()
	return stream.get_length()


func _stream(kind: StringName, variant: int) -> AudioStream:
	var path := "%s/art/break_sounds/%s_%d.ogg" % [(DotFxBreak as Script).resource_path.get_base_dir().get_base_dir(), kind, variant]
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		DotLog.warn(CHANNEL, "break sound missing", {"path": path})
	_streams[path] = s
	return s


func describe() -> Dictionary:
	return {"enabled": config.enabled, "scale": config.effective_scale(), "live": _live.size(), "spawned": spawned}


func _prune() -> void:
	var alive: Array[Node3D] = []
	for n in _live:
		if is_instance_valid(n):
			alive.append(n)
	_live = alive
