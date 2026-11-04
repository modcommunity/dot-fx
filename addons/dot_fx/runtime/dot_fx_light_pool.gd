class_name DotFxLightPool
extends Node3D

## Reused OmniLight3D nodes for impact flashes, so none is built or freed mid-match. Place it yourself; no autoload.

const CHANNEL := "fx.light"

var _free: Array[OmniLight3D] = []
var _all: Array[OmniLight3D] = []


## Builds [param count] lights (default [member DotFxPoolConfig.prewarm_lights]) and shows each for [param frames] frames so the renderer compiles them now.
func prewarm(count: int = -1, frames: int = 2) -> void:
	var n := DotFxLightBudget.config.prewarm_lights if count < 0 else count
	for i in n:
		var light := _make()
		light.light_energy = 0.001
		light.visible = true
		_free.append(light)
	if is_inside_tree():
		for i in frames:
			await get_tree().process_frame
	for light in _free:
		light.visible = false
		light.light_energy = 0.0


## Lights a pooled light at [param at] for [param seconds]; null when the cap is full (the caller still draws the effect, just unlit).
func flash(at: Vector3, colour: Color, energy: float, light_range: float, seconds: float) -> OmniLight3D:
	if not DotFxLightBudget.try_take(seconds):
		return null
	var light: OmniLight3D = _free.pop_back() if not _free.is_empty() else _make()
	light.position = at
	light.light_color = colour
	light.light_energy = energy
	light.omni_range = light_range
	light.visible = true
	if is_inside_tree():
		get_tree().create_timer(seconds).timeout.connect(_release.bind(light))
	return light


## Lights built so far, in use or idle.
func built() -> int:
	return _all.size()


## Idle lights ready for reuse.
func idle() -> int:
	return _free.size()


func _release(light: OmniLight3D) -> void:
	if not is_instance_valid(light) or _free.has(light):
		return
	light.visible = false
	light.light_energy = 0.0
	_free.append(light)


func _make() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	_all.append(light)
	return light
