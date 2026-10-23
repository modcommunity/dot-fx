class_name DotFxBlood
extends Node
## Blood on the surface behind a hit or under a victim, drawn through a [DotFxDecals] pool.
## Visual only: a game calls it from events it already gets, so nothing extra crosses the wire.

## Server splats accepted per second by [method splat_at].
const SPLATS_PER_SECOND := 20

var decals := DotFxDecals.new()
## Physics layers a splatter may land on: the game's rooms and props.
var mask := 0xFFFFFFFF

var _window_start := 0
var _window_count := 0


func _init() -> void:
	name = "Blood"
	decals.name = "Decals"
	add_child(decals)


## Takes the player's `gore` and `fx_quality` from a dot-settings manager (duck-typed: dot-fx does not depend on dot-settings).
func apply_settings(store: Object) -> void:
	var cfg := DotFxDecalConfig.new()
	if store != null:
		cfg.gore = store.get_bool(&"gore", true)
		cfg.quality = store.get_int(&"fx_quality", 3)
	decals.apply_config(cfg)


## Applies the settings now and again whenever `gore` or `fx_quality` changes.
func follow(store: Object) -> void:
	apply_settings(store)
	if store != null and not store.changed.is_connected(_on_changed):
		store.changed.connect(_on_changed.bind(store))


func _on_changed(key: StringName, _value: Variant, _why: StringName, store: Object) -> void:
	if key == &"gore" or key == &"fx_quality":
		apply_settings(store)


## Blood on the first surface behind [param to], seen from [param from], within [param reach] metres. Null: no surface, gore off or no world.
func splat_behind(from: Vector3, to: Vector3, reach: float = 3.0, size: float = 1.0) -> Node3D:
	var along := to - from
	if along.length() < 0.01:
		return null
	return splat_ray(to, along.normalized(), reach, size)


## Blood on the floor under [param feet]; the ray starts [param lift] above so a floor at the feet is found.
func splat_below(feet: Vector3, reach: float = 4.0, lift: float = 0.5, size: float = 1.0) -> Node3D:
	return splat_ray(feet + Vector3(0.0, lift, 0.0), Vector3.DOWN, reach, size)


## Blood on the first surface along a ray from [param origin]. Null when nothing is hit.
func splat_ray(origin: Vector3, direction: Vector3, reach: float, size: float = 1.0) -> Node3D:
	var world := get_viewport().find_world_3d() if get_viewport() != null else null
	if world == null or direction.length() < 0.001:
		return null
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * reach, mask)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return decals.splatter(hit["position"], hit["normal"], size)


## A server's word that blood landed at [param point] facing [param normal]: only near the camera, at most [constant SPLATS_PER_SECOND] a second.
func splat_at(point: Vector3, normal: Vector3, within: float = 60.0) -> Node3D:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null or camera.global_position.distance_to(point) > within:
		return null
	var now := Time.get_ticks_msec()
	if now - _window_start >= 1000:
		_window_start = now
		_window_count = 0
	if _window_count >= SPLATS_PER_SECOND:
		return null
	_window_count += 1
	return decals.splatter(point, normal)


func advance(delta: float) -> void:
	decals.advance(delta)


func clear() -> void:
	decals.clear_blood()
