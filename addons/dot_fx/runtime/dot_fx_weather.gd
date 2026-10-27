class_name DotFxWeather
extends Node3D

## Snow or rain that falls inside boxes the mapper named, and nowhere else, drawn around the
## camera and nothing more.
##
## [b]A shader moves every flake; the CPU moves nothing.[/b] One [MultiMesh] of quads, each placed
## in the vertex shader from its instance id and a clock, wrapped into a box that follows the
## camera. There are no particle nodes, no per-frame transforms and no uniform that changes
## except the camera and the clock, which is what makes it cheap enough for the Compatibility
## renderer in a browser (no compute, no threads, no transform feedback).
##
## [b]Volumes instead of collision.[/b] A flake that is not inside one of the document's boxes is
## collapsed in the vertex shader, so precipitation cannot appear under a roof the mapper left
## outside the volume and no physics query is made. Flakes fade out over the last metre of a
## volume rather than ending in a hard edge. The box around the camera is tested against the
## volumes on the CPU, only the boxes it overlaps (the nearest [constant MAX_ACTIVE]) reach the
## shader, and when it overlaps none the node hides and costs nothing.
##
## [b]Purely visual and client side.[/b] It reads no simulation state and writes none. On a
## dedicated server (no display) [method setup] keeps the document, draws nothing and says so
## in [method describe]; the question is asked of the display server, not the operating system.
##
## [codeblock]
## var w := DotFxWeather.new()
## add_child(w)
## var res := w.apply(map_document["weather"])     # a DotResult; a bad document leaves it off
## w.quality = DotFxWeather.Quality.HIGH           # a settings menu drives this
## w.audible_changed.connect(func(id, inside): ...) # fade the game's own rain sound
## # once a frame
## w.advance(delta, camera.global_position)
## [/codeblock]

const CHANNEL := "fx"

## What a game's settings drive. OFF draws nothing, LOW a third of the flakes, HIGH all of them.
enum Quality { OFF, LOW, HIGH }

## Volumes handed to the shader at once. A uniform array is a fixed size, and thirty-two is more
## than a camera's box ever overlaps on a map that used eighteen in total.
const MAX_ACTIVE := 32

## The most flakes one weather node will ever allocate.
const MAX_FLAKES := 8000

## Emitted when the camera moves into or out of a volume (or at once, for a document with none,
## when it is set up). [param sound] is the document's sound id, which the game maps to its own
## sound; dot-fx ships none.
signal audible_changed(sound: StringName, inside: bool)

## OFF, LOW or HIGH.
@export var quality: Quality = Quality.HIGH:
	set(value):
		quality = value
		_dirty = true

## Multiplies the document's density. A player's slider, 0 to 2.
@export_range(0.0, 2.0, 0.05) var density_scale: float = 1.0:
	set(value):
		density_scale = value
		_dirty = true

## Whether the sound hook says "inside" right now.
var inside: bool = false

var definition: DotFxWeatherDef = null

var _mmi: MultiMeshInstance3D = null
var _material: ShaderMaterial = null
var _render: bool = false
var _dirty: bool = true
var _clock: float = 0.0
var _gust := Vector3.ZERO
var _drift := Vector3.ZERO
var _flakes: int = 0
var _active: int = 0
var _box := Vector3(28, 18, 28)
var _last_viewer := Vector3(INF, INF, INF)

const _SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float clock = 0.0;
uniform vec3 cam = vec3(0.0);
uniform vec3 box_size = vec3(28.0, 18.0, 28.0);
uniform vec3 fall = vec3(0.0, -1.6, 0.0);
uniform vec3 gust = vec3(0.0);
uniform vec3 drift = vec3(0.0);
uniform float flake_size = 0.07;
uniform float streak = 0.0;
uniform float sway = 0.0;
uniform int vol_count = 0;
uniform vec3 vol_min[32];
uniform vec3 vol_max[32];

varying float a;

float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 seed = vec3(h(id + 1.0), h(id + 2.0), h(id + 3.0));
	vec3 vel = fall * (0.85 + 0.3 * h(id + 4.0));
	vec3 local = mod(seed * box_size + vel * clock + drift - cam + box_size * 0.5, box_size);
	vec3 w = cam - box_size * 0.5 + local;
	w.x += sin(clock * 1.3 + id) * sway;
	w.z += cos(clock * 1.1 + id * 1.7) * sway;

	// How far inside the nearest volume this flake is; a flake outside all of them is gone.
	float margin = 1.0e4;
	if (vol_count > 0) {
		margin = -1.0;
		for (int i = 0; i < 32; i++) {
			if (i >= vol_count) { break; }
			vec3 lo = w - vol_min[i];
			vec3 hi = vol_max[i] - w;
			margin = max(margin, min(min(min(lo.x, lo.y), min(lo.z, hi.x)), min(hi.y, hi.z)));
		}
	}
	vec2 c2 = (local.xz / box_size.xz - 0.5) * 2.0;
	float ring = 1.0 - smoothstep(0.7, 1.0, max(abs(c2.x), abs(c2.y)));
	float vert = clamp(min(local.y, box_size.y - local.y) / (box_size.y * 0.15), 0.0, 1.0);
	a = tint.a * clamp(margin, 0.0, 1.0) * ring * vert;

	vec3 c = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	if (streak > 0.0) {
		vec3 dir = normalize((VIEW_MATRIX * vec4(normalize(fall + gust), 0.0)).xyz);
		vec3 side = normalize(cross(dir, normalize(c)));
		c += side * VERTEX.x * flake_size + dir * VERTEX.y * streak;
	} else {
		c += vec3(VERTEX.xy * flake_size, 0.0);
	}
	VERTEX = a > 0.0 ? c : vec3(0.0);
}

void fragment() {
	float m;
	if (streak > 0.0) {
		m = (1.0 - abs(UV.x * 2.0 - 1.0)) * sin(UV.y * 3.14159);
	} else {
		m = 1.0 - smoothstep(0.25, 0.5, length(UV - 0.5));
	}
	ALBEDO = tint.rgb;
	ALPHA = a * m;
}
"""


## Whether this process can draw at all. False on a dedicated server or any headless run.
## Asked of the display server, so it is a capability and not an operating-system name.
static func can_render() -> bool:
	return not DotPlatform.is_headless()


## The volumes of [param volumes] that touch [param region], the nearest [param cap] of them to
## [param viewer] when more than that do. Pure, so it is tested without a renderer.
static func select_volumes(volumes: Array[AABB], region: AABB, viewer: Vector3, cap: int = MAX_ACTIVE) -> Array[AABB]:
	var hit: Array[AABB] = []
	for v in volumes:
		if v.intersects(region):
			hit.append(v)
	if hit.size() > cap:
		hit.sort_custom(func(x: AABB, y: AABB) -> bool: return _distance_to(x, viewer) < _distance_to(y, viewer))
		hit.resize(cap)
	return hit


## Whether [param point] is inside any of [param volumes].
static func inside_any(volumes: Array[AABB], point: Vector3) -> bool:
	for v in volumes:
		if v.has_point(point):
			return true
	return false


## How many flakes a document of [param kind] and [param density] draws at [param q].
static func flakes_for(kind: StringName, density: float, q: Quality) -> int:
	if q == Quality.OFF or density <= 0.0:
		return 0
	var base := 3000.0 if kind == DotFxWeatherDef.RAIN else 2500.0
	var n := base * density * (0.3 if q == Quality.LOW else 1.0)
	return mini(int(n), MAX_FLAKES)


## Reads a game's [DotFxConfig]: its weather tier and density slider.
func apply_config(config: DotFxConfig) -> void:
	quality = config.weather_quality as Quality
	density_scale = config.weather_density


## Validates [param doc] and sets up from it. A bad document leaves the previous weather alone.
func apply(doc: Dictionary) -> DotResult:
	var res := DotFxWeatherDef.parse(doc)
	if not res.ok:
		DotLog.warn(CHANNEL, "weather document refused", {"why": res.error.message})
		return res
	setup(res.value)
	return DotResult.success(res.value)


## Uses [param def]. Builds the drawing only where there is a display.
func setup(def: DotFxWeatherDef) -> void:
	definition = def
	_render = can_render()
	_dirty = true
	_last_viewer = Vector3(INF, INF, INF)
	inside = false
	if not _render:
		DotLog.debug(CHANNEL, "weather kept, not drawn: no display", {"kind": def.kind})
		return
	if _mmi == null:
		_build()
	var rain := def.kind == DotFxWeatherDef.RAIN
	_box = Vector3(24, 20, 24) if rain else Vector3(28, 18, 28)
	var fall := Vector3(0, -14.0 if rain else -1.6, 0) + def.wind
	_material.set_shader_parameter("tint", def.colour)
	_material.set_shader_parameter("box_size", _box)
	_material.set_shader_parameter("fall", fall)
	# A streak is as long as the drop falls in about a tenth of a second and wide enough to
	# survive a chase camera 8 m away; 0.04 by 0.9 m was a hairline nobody saw in a play test.
	_material.set_shader_parameter("flake_size", 0.055 if rain else 0.11)
	_material.set_shader_parameter("streak", 1.6 if rain else 0.0)
	_material.set_shader_parameter("sway", 0.0 if rain else 0.3)
	_mmi.custom_aabb = AABB(-_box * 0.5 - Vector3.ONE, _box + Vector3.ONE * 2.0)


## Leans the fall by [param wind] (metres per second, horizontal) on top of the document's steady wind, so gusts reach the drawing. Zero removes it.
func set_gust(wind: Vector3) -> void:
	_gust = Vector3(wind.x, 0.0, wind.z)
	if _material != null:
		_material.set_shader_parameter("gust", _gust)


## The gust lean set by [method set_gust].
func gust() -> Vector3:
	return _gust


## Once a frame, with where the camera is. Moves nothing but the clock and the follow.
func advance(delta: float, viewer: Vector3) -> void:
	if definition == null:
		return
	_update_inside(viewer)
	if not _render:
		return
	if _dirty:
		_apply_quality()
	if _flakes == 0:
		_mmi.visible = false
		return
	_clock = fmod(_clock + delta, 600.0)
	if _gust != Vector3.ZERO or _drift != Vector3.ZERO:
		# Integrated, not multiplied by the clock: a changing gust must not teleport every flake.
		_drift = Vector3(fposmod(_drift.x + _gust.x * delta, _box.x), 0.0, fposmod(_drift.z + _gust.z * delta, _box.z))
		_material.set_shader_parameter("drift", _drift)
	if viewer != _last_viewer:
		_last_viewer = viewer
		var region := AABB(viewer - _box * 0.5, _box)
		var picked: Array[AABB] = []
		if not definition.volumes.is_empty():
			picked = select_volumes(definition.volumes, region, viewer)
			_active = picked.size()
			var lo := PackedVector3Array()
			var hi := PackedVector3Array()
			lo.resize(MAX_ACTIVE)
			hi.resize(MAX_ACTIVE)
			for i in range(picked.size()):
				lo[i] = picked[i].position
				hi[i] = picked[i].end
			_material.set_shader_parameter("vol_count", picked.size())
			_material.set_shader_parameter("vol_min", lo)
			_material.set_shader_parameter("vol_max", hi)
		else:
			_active = -1
			_material.set_shader_parameter("vol_count", 0)
		_mmi.global_position = viewer
		_material.set_shader_parameter("cam", viewer)
	# Hidden when the camera's surroundings overlap no volume: nothing is submitted at all.
	_mmi.visible = _active != 0
	_material.set_shader_parameter("clock", _clock)


## One line for a console or a debug overlay.
func describe() -> String:
	if definition == null:
		return "weather: none"
	return "weather: %s, %s, quality %s, %d flakes, %s" % [
		definition.describe(),
		"drawn" if _render else "not drawn (no display)",
		Quality.keys()[quality], _flakes,
		"%d volumes near" % _active if _active >= 0 else "everywhere",
	]


func _update_inside(viewer: Vector3) -> void:
	var now := definition.volumes.is_empty() or inside_any(definition.volumes, viewer)
	if now != inside:
		inside = now
		audible_changed.emit(definition.sound, inside)


func _apply_quality() -> void:
	_dirty = false
	_flakes = flakes_for(definition.kind, definition.density * density_scale, quality)
	_mmi.multimesh.instance_count = _flakes
	_mmi.visible = _flakes > 0
	_last_viewer = Vector3(INF, INF, INF)


func _build() -> void:
	var shader := Shader.new()
	shader.code = _SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.top_level = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## Metres from [param p] to the nearest point of [param box]; zero inside it.
static func _distance_to(box: AABB, p: Vector3) -> float:
	var nearest := p.clamp(box.position, box.end)
	return nearest.distance_to(p)
