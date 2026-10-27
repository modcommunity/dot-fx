class_name DotFxScreenGoo
extends CanvasLayer

## A full-screen goo, ink or oil overlay that blinds the viewer more as its amount rises.
##
## A server applies it to one survivor through a stacking status (dot-effects'
## `DotEffectDef.screen_impair`); the client mirror feeds the stack count and time left to
## [method set_status], or a game calls [method apply] directly. One procedural canvas shader,
## no textures and no screen read, so it costs the same on a phone and in a browser. It only
## draws; nothing in the simulation depends on it.

const SHADER_CODE := """
shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 goo_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);
uniform float time_s = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - vec2(0.5);
	// Creeps in from the edges, ragged and drifting, then closes over the middle.
	float edge = length(c * vec2(1.0, 1.25)) * 1.4;
	float rag = sin(uv.x * 23.0 + time_s * 0.8) * 0.045 + sin(uv.y * 17.0 - time_s * 0.6 + uv.x * 5.0) * 0.04
		+ sin((uv.x + uv.y) * 41.0 + time_s * 1.3) * 0.02;
	// Drips run down from the top.
	float drip = max(0.0, sin(uv.x * 37.0) * 0.5 + sin(uv.x * 11.0 + 2.0) * 0.5) * (1.0 - uv.y) * 0.25;
	float reach = edge + rag + drip * amount;
	float cover = smoothstep(1.15 - amount * 1.35, 1.25 - amount * 1.35 + 0.18, reach);
	COLOR = vec4(goo_color.rgb, cover * min(1.0, amount * 6.0));
}
"""

## Emitted when the overlay's amount crosses from nothing to something and back.
signal active_changed(active: bool)

## Most that all applications together may reach (1 is a full blackout).
@export_range(0.0, 1.0) var max_amount: float = 1.0
## Amount each status stack adds in [method set_status].
@export_range(0.0, 1.0) var per_stack_amount: float = 0.4
## Seconds the status path takes to reach its amount, and to leave once under [member status_fade_out] left.
@export var status_fade_in: float = 0.25
@export var status_fade_out: float = 1.0
@export var goo_color: Color = Color(0.02, 0.02, 0.03, 1.0):
	set(value):
		goo_color = value
		if _material != null:
			_material.set_shader_parameter("goo_color", value)

## Each application: {amount, start, seconds, fade_in, fade_out}, times on [member clock].
var applications: Array[Dictionary] = []
## Seconds, advanced by [method advance]; a test sets it directly.
var clock: float = 0.0

var _material: ShaderMaterial = null
var _rect: ColorRect = null
var _status_target: float = 0.0
var _status_now: float = 0.0
var _amount: float = 0.0
var _was_active: bool = false


func _init() -> void:
	layer = 90
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	advance(delta)


## One application of goo: rises over [param fade_in], holds, falls over [param fade_out] by [param seconds] after it started.
## Applications add together up to [member max_amount].
func apply(amount: float, seconds: float, fade_in: float = 0.2, fade_out: float = 0.8) -> void:
	applications.append({"amount": clampf(amount, 0.0, 1.0), "start": clock, "seconds": maxf(seconds, 0.01),
		"fade_in": maxf(fade_in, 0.0), "fade_out": maxf(fade_out, 0.0)})


## The status path: [param stacks] applications on the victim and [param seconds_left] on the newest.
func set_status(stacks: int, seconds_left: float) -> void:
	var held := minf(float(maxi(stacks, 0)) * per_stack_amount, max_amount)
	var leaving := clampf(seconds_left / maxf(status_fade_out, 0.001), 0.0, 1.0) if stacks > 0 else 0.0
	_status_target = held * leaving


## Removes everything at once.
func clear() -> void:
	applications.clear()
	_status_target = 0.0
	_status_now = 0.0
	advance(0.0)


## Total amount now, 0 to [member max_amount].
func amount() -> float:
	return _amount


## One application's amount at [param t] seconds in.
static func envelope(amount_peak: float, seconds: float, fade_in: float, fade_out: float, t: float) -> float:
	if t < 0.0 or t >= seconds:
		return 0.0
	var up := clampf(t / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0
	var down := clampf((seconds - t) / fade_out, 0.0, 1.0) if fade_out > 0.0 else 1.0
	return amount_peak * minf(up, down)


func advance(delta: float) -> void:
	clock += delta
	var total := 0.0

	for i in range(applications.size() - 1, -1, -1):
		var a := applications[i]
		var t := clock - float(a["start"])

		if t >= float(a["seconds"]):
			applications.remove_at(i)
			continue

		total += envelope(float(a["amount"]), float(a["seconds"]), float(a["fade_in"]), float(a["fade_out"]), t)

	var rate := 1.0 / maxf(status_fade_in, 0.001)
	_status_now = move_toward(_status_now, _status_target, rate * delta) if delta > 0.0 else _status_target
	total += _status_now
	_amount = minf(total, max_amount)
	var active := _amount > 0.001

	if active != _was_active:
		_was_active = active
		active_changed.emit(active)

	_rect.visible = active
	_material.set_shader_parameter("amount", _amount)
	_material.set_shader_parameter("time_s", clock)


func describe() -> Dictionary:
	return {"amount": _amount, "applications": applications.size(), "status": _status_now}
