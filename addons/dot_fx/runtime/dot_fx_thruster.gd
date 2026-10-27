class_name DotFxThruster
extends Node3D

## A jet's exhaust: flame and smoke blown along this node's -Y, scaled by [member throttle],
## with a burst of sparks when it fails. CPU particles, so it runs in a browser build.

## 0 is off, 1 is full burn.
var throttle: float = 0.0:
	set(value):
		throttle = clampf(value, 0.0, 1.0)
		_apply()

## A failed thruster smokes and sparks and never burns.
var broken: bool = false:
	set(value):
		broken = value
		_apply()

var _flame: CPUParticles3D = null
var _smoke: CPUParticles3D = null
var _sparks: CPUParticles3D = null


func _ready() -> void:
	_flame = _emitter(0.35, 24, Color(1.0, 0.75, 0.25), Color(1.0, 0.2, 0.05, 0.0), 0.09, 0.0, 6.0, true)
	_smoke = _emitter(1.1, 14, Color(0.55, 0.55, 0.55, 0.5), Color(0.25, 0.25, 0.25, 0.0), 0.2, 0.3, 2.5, false)
	_sparks = _emitter(0.5, 18, Color(1.0, 0.9, 0.4), Color(1.0, 0.5, 0.1, 0.0), 0.03, 1.0, 5.0, true)
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.spread = 80.0
	_sparks.gravity = Vector3(0.0, -9.0, 0.0)
	_apply()


func _emitter(life: float, count: int, from: Color, to: Color, size: float, grow: float, speed: float,
		glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3.DOWN
	p.spread = 12.0
	p.initial_velocity_min = speed * 0.7
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, 0.5, 0.0)
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, from)
	ramp.set_color(1, to)
	p.color_ramp = ramp
	p.scale_amount_min = size
	p.scale_amount_max = size * (1.0 + grow * 3.0)
	# A soft sprite: the old six-sided sphere read as a hard faceted blob.
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = DotFxSoftSprite.material(Color.WHITE, glow)
	p.mesh = mesh
	add_child(p)
	return p


func _apply() -> void:
	if _flame == null:
		return

	_flame.emitting = throttle > 0.02 and not broken
	_flame.amount = maxi(int(24.0 * throttle), 1)
	_smoke.emitting = throttle > 0.02 or broken
	_smoke.amount = maxi(int(14.0 * maxf(throttle, 0.5 if broken else 0.0)), 1)


## A burst of sparks, once.
func spark() -> void:
	if _sparks != null:
		_sparks.restart()
		_sparks.emitting = true
