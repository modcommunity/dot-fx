class_name DotFxShake
extends RefCounted

## Camera shake as a value. It computes an offset and never touches a camera.
##
## Same rule as dot-spectate's "computes a transform and touches no camera", and for the
## same payoff: one implementation serves a 3D rig, a 2D one, a spectator's camera and a
## headless suite, with no second code path and nothing to keep in step.
##
## [codeblock]
## shake.add(0.4)                       # a grenade nearby
## shake.advance(delta)                 # once a frame
## camera.position = base + shake.offset()
## camera.rotation.z = base_roll + shake.roll()
## [/codeblock]
##
## [b]Trauma, not offset.[/b] Callers add trauma in 0..1 and the shake is trauma squared
## (or cubed), which is the standard trick and is worth the explanation: a linear falloff
## reads as a shake that stops abruptly, because the last few per cent of a linear ramp is
## still visible motion. A squared falloff spends most of its time near zero, so the shake
## fades out rather than switching off — and two small shakes together stay small while
## one big one is unmistakable.
##
## The displacement comes from sampled noise rather than from a random number per frame.
## [b]Random per frame is not shake, it is jitter[/b]: consecutive frames are unrelated,
## so the camera vibrates at the frame rate and reads as a rendering fault. Noise sampled
## along a moving t gives a continuous path, which is what a shaken camera actually does —
## and it means the shake looks the same at 60 and at 144 frames per second, which random
## per frame does not.

## How fast the trauma decays, per second.
var decay_per_second: float = 1.4

## How far the camera moves at full trauma, in metres.
var max_offset: float = 0.35

## How far it rolls at full trauma, in radians.
var max_roll: float = 0.08

## How quickly the noise is traversed. Higher is a sharper, faster shake.
var frequency: float = 22.0

## The exponent trauma is raised to. 2 or 3; see the class description.
var exponent: float = 2.0

## A multiplier a player controls, and which must be able to reach zero.
##
## [b]Not a nicety.[/b] Camera shake is one of the two or three commonest causes of
## simulator sickness, and a game with no way to turn it off is a game some people cannot
## play at all. It is a settings entry in [DotFxConfig] for that reason and the manager
## reads it on every frame rather than at start-up, so turning it off takes effect
## immediately rather than at the next map.
var scale: float = 1.0

var _trauma: float = 0.0
var _t: float = 0.0
var _noise: FastNoiseLite = null


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	# A fixed seed: two clients shaking identically is not required by anything, but a
	# shake that differs between a recording and its playback is a bug report nobody can
	# reproduce.
	_noise.seed = 0x5EED


## Adds trauma. Clamped at 1, so a hundred explosions is not a hundred times the shake.
func add(amount: float) -> void:
	_trauma = clampf(_trauma + maxf(0.0, amount), 0.0, 1.0)


## Adds trauma scaled by distance, which is what an explosion actually wants.
func add_at(amount: float, distance: float, falloff_distance: float) -> void:
	if falloff_distance <= 0.0:
		add(amount)
		return
	var near := clampf(1.0 - distance / falloff_distance, 0.0, 1.0)
	add(amount * near * near)


func advance(delta: float) -> void:
	_t += delta * frequency
	_trauma = maxf(0.0, _trauma - decay_per_second * delta)


func trauma() -> float:
	return _trauma


func active() -> bool:
	return _trauma > 0.0001 and scale > 0.0


## The displacement to add to a camera's position this frame.
func offset() -> Vector3:
	if not active():
		return Vector3.ZERO
	var s := pow(_trauma, exponent) * max_offset * scale
	# Three different offsets into the same noise field, so the axes are uncorrelated.
	# Sampling one field three times at the same point gives three identical numbers and a
	# camera that slides along a diagonal.
	return Vector3(
		_noise.get_noise_2d(_t, 0.0) * s,
		_noise.get_noise_2d(_t, 137.0) * s,
		_noise.get_noise_2d(_t, 911.0) * s
	)


## The 2D displacement, for a game on the XZ plane or a [Camera2D].
func offset_2d() -> Vector2:
	var o := offset()
	return Vector2(o.x, o.y)


## The roll to add, in radians.
func roll() -> float:
	if not active():
		return 0.0
	return _noise.get_noise_2d(_t, 555.0) * pow(_trauma, exponent) * max_roll * scale


func reset() -> void:
	_trauma = 0.0


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"shake: trauma %.3f, scale %.2f%s" % [
			_trauma, scale, "  (off)" if scale <= 0.0 else ""
		],
	])
