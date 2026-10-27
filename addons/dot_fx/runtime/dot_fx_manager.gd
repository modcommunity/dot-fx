class_name DotFxManager
extends Node

## The node a game holds: an id and a place, and an effect appears — or honestly does not.
##
## [codeblock]
## var fx := DotFxManager.new()
## fx.catalogue = my_catalogue
## add_child(fx)
## fx.setup()
##
## fx.viewer_position = camera.global_position    # once a frame
## fx.spawn(&"muzzle_flash", muzzle.global_transform)
## fx.spawn_decal(&"bullet_hole", hit_transform)
## fx.shake_at(&"grenade", where)
##
## fx.advance(delta)                              # once a frame
## camera.position = base + fx.shake.offset()
## [/codeblock]
##
## **Every refusal here is safe, and that is a property rather than a hope.** An effect
## never changes the simulation, so a client over budget, on a low quality tier, too far
## away, or still downloading its content, is playing the same game as everybody else. The
## moment an effect is allowed to deal damage or move a body, none of this is true — which
## is why dot-combat owns damage and dot-effects owns what happens over time.

const SERVICE := &"dot_fx"
const CHANNEL := "fx"

## Something was spawned, or was refused and why. A settings screen and a profiler both
## want this, and so does anybody wondering where the smoke went.
signal spawned(id: StringName, node: Node, why: StringName)

## A screen flash was asked for. [param applied] is false when it was capped, rate
## limited, or refused by the player's own setting.
signal flashed(id: StringName, colour: Color, peak: float, applied: bool)

@export var catalogue: DotFxCatalogue = null

@export var config: DotFxConfig = null

## Where spawned effects are parented. Resolved per instance, in the inspector.
##
## A [DotNodeRef] rather than a path, for the family's rule and for a practical reason: an
## effect parented into the world is destroyed with the world on a map change, and one
## parented to the manager is not. Which of those a game wants is a decision the game
## makes, not this addon.
@export var world_ref: DotNodeRef = null

@export var register_as_service: bool = true

## Where the camera is, for culling. A game sets this once a frame.
var viewer_position: Vector3 = Vector3.ZERO

## Which way it is looking, for [member DotFxConfig.cull_behind].
var viewer_forward: Vector3 = Vector3.FORWARD

## The shake, which computes a value and touches no camera.
var shake: DotFxShake = null

## The current screen flash colour and strength. A game draws it; this does not.
##
## Same rule as the shake and as dot-spectate's camera: one implementation serves a 3D
## game, a 2D one and a headless suite because it produces a number rather than a
## [ColorRect].
var flash_colour: Color = Color(0, 0, 0, 0)

var _world: Node = null
var _live: Array[Dictionary] = []
var _decals: Array[Dictionary] = []
var _concurrent: Dictionary = {}
var _budget_left := 0
## What started since the last [method advance]: the only effects a higher-priority request
## may displace, because nobody has seen a frame of them yet.
var _this_frame: Array[Dictionary] = []
var _flash_times: Array[int] = []
var _flash_decay_ms := 250
var _scene_cache: Dictionary = {}


func _init() -> void:
	shake = DotFxShake.new()
	if config == null:
		config = DotFxConfig.new()


func setup() -> DotResult:
	if catalogue == null:
		catalogue = DotFxCatalogue.new()
	var res := catalogue.validate()
	if not res.ok:
		return res.wrap("fx catalogue")
	if config == null:
		config = DotFxConfig.new()
	var cres := config.validate()
	if not cres.ok:
		return cres.wrap("fx config")

	if world_ref != null:
		var wres := world_ref.resolve(self)
		if wres.ok:
			_world = wres.value
	if _world == null:
		_world = self

	_budget_left = config.frame_budget
	if register_as_service:
		DotRegistry.register(SERVICE, self)
	return DotResult.success(null)


func _exit_tree() -> void:
	clear()
	if register_as_service:
		DotRegistry.unregister_instance(SERVICE, self)


# --- The frame --------------------------------------------------------------

## Ages everything and refills the budget. Called once a frame by the game.
##
## Explicit rather than [method Node._process] for the reason every tickable thing in this
## family is explicit: a game that pauses, a replay being scrubbed and a suite stepping one
## frame at a time all need to decide when this happens, and `_process` decides for them.
func advance(delta: float) -> void:
	shake.scale = config.shake_scale
	shake.advance(delta)

	if flash_colour.a > 0.0:
		var fade := delta * 1000.0 / maxf(float(_flash_decay_ms), 1.0)
		flash_colour.a = maxf(0.0, flash_colour.a - fade)

	var now := Time.get_ticks_msec()
	for i in range(_live.size() - 1, -1, -1):
		var entry := _live[i]
		if now >= int(entry["expires"]):
			_retire(i)

	# A lowered cap applies from the next frame, not only at the next decal.
	_trim_decals()
	_this_frame.clear()
	_budget_left = config.frame_budget if config.frame_budget > 0 else 1 << 30


# --- Spawning ---------------------------------------------------------------

## Spawns an effect at a transform. Returns the node, or null when it was refused.
func spawn(id: StringName, at: Transform3D, scale_hint: float = 1.0) -> Node:
	var def := catalogue.find(id) if catalogue != null else null
	if def == null:
		spawned.emit(id, null, &"unknown")
		return null

	match def.kind:
		DotFxDef.Kind.SHAKE:
			shake.add(def.shake_trauma * scale_hint)
			spawned.emit(id, null, &"ok")
			return null
		DotFxDef.Kind.SCREEN:
			flash(id)
			return null
		_:
			pass

	var why := _may_spawn(def, at.origin)
	if why != &"ok":
		spawned.emit(id, null, why)
		return null

	var node := _instance(def, at)
	if node == null:
		spawned.emit(id, null, &"missing")
		return null

	_budget_left -= def.cost
	_concurrent[id] = int(_concurrent.get(id, 0)) + 1
	var entry := {
		"id": id,
		"node": node,
		"expires": Time.get_ticks_msec() + def.lifetime_ms,
		"decal": def.kind == DotFxDef.Kind.DECAL,
		"cost": def.cost,
		"priority": def.priority,
	}
	_this_frame.append(entry)
	if def.kind == DotFxDef.Kind.DECAL:
		_decals.append(entry)
		_trim_decals()
	_live.append(entry)
	spawned.emit(id, node, &"ok")
	return node


## Spawns each of [param ids] once at [param at] (put it in view, under the loading cover) so the first real one costs no scene load or shader compile. Returns the nodes; they retire by their own lifetime.
func warm(ids: Array, at: Transform3D) -> Array[Node]:
	var out: Array[Node] = []
	for id: Variant in ids:
		var node := spawn(StringName(id), at)
		if node != null:
			out.append(node)
	return out


## Spawns at a 2D position, on the XZ plane.
##
## Two entry points rather than one widened signature, which is the choice dot-props and
## dot-npc made when they grew a second dimension: a caller holding a [Vector2] is a
## different caller, and widening the existing signature changes every call site in the
## family for the benefit of the new one.
func spawn_2d(id: StringName, at: Vector2, rotation: float = 0.0) -> Node:
	var t := Transform3D.IDENTITY
	t.origin = Vector3(at.x, 0.0, at.y)
	t.basis = Basis(Vector3.UP, rotation)
	return spawn(id, t)


## Spawns a decal, which is a spawn with a ring behind it.
func spawn_decal(id: StringName, at: Transform3D) -> Node:
	return spawn(id, at)


## Adds this effect's shake, scaled by how far away it was.
func shake_at(id: StringName, position: Vector3, falloff: float = 30.0) -> void:
	var def := catalogue.find(id) if catalogue != null else null
	if def == null or def.shake_trauma <= 0.0:
		return
	shake.add_at(def.shake_trauma, viewer_position.distance_to(position), falloff)


func _may_spawn(def: DotFxDef, where: Vector3) -> StringName:
	if config.quality < def.min_quality:
		return &"quality"

	if def.max_distance > 0.0:
		var limit := def.max_distance * config.distance_scale
		var to := where - viewer_position
		if to.length() > limit:
			return &"distance"
		if config.cull_behind and to.length() > 1.0 and viewer_forward.dot(to.normalized()) < -0.2:
			return &"behind"

	if def.max_concurrent > 0 and int(_concurrent.get(def.id, 0)) >= def.max_concurrent:
		return &"concurrent"

	# The budget before the instance cap, so a request the budget refuses has not already
	# retired a live effect to make room for itself.
	if config.frame_budget > 0 and def.cost > _budget_left and not _make_room(def):
		return &"budget"

	if _live.size() >= config.max_instances:
		# Recycling the oldest rather than refusing. An effect's whole value is
		# being seen at the moment it happens, so the newest is always worth more than the
		# oldest -- the opposite of the audio pool, where stealing by age is what makes a
		# gunshot lose to a footstep.
		if not _retire_oldest():
			return &"instances"

	return &"ok"


## Places [param node] at [param at] BEFORE it enters the tree.
##
## [b]Before, because a particle emitter fires on entering.[/b] This used to add the
## scene and then set its transform, so an emitter in world coordinates -- the default
## for [CPUParticles3D] and [GPUParticles3D] -- spent its first burst at the world's
## origin and only the later particles came from where the effect was asked for. The
## node itself ended up in the right place, which is all a check of `global_position`
## could see; game-g2gfast's gate effects found it only by being rendered (96b2be2).
## A 2D node takes the transform's X and Z as its position and its yaw as its rotation,
## which is how [method spawn_2d] encodes them.
func _place(node: Node, at: Transform3D) -> void:
	if node is Node3D:
		var parent := _world as Node3D
		(node as Node3D).transform = (
			parent.global_transform.affine_inverse() * at
			if parent != null and parent.is_inside_tree() else at
		)
	elif node is Node2D:
		var flat := Transform2D(at.basis.get_euler().y, Vector2(at.origin.x, at.origin.z))
		var parent_2d := _world as Node2D
		(node as Node2D).transform = (
			parent_2d.get_global_transform().affine_inverse() * flat
			if parent_2d != null and parent_2d.is_inside_tree() else flat
		)


func _instance(def: DotFxDef, at: Transform3D = Transform3D.IDENTITY) -> Node:
	if def.scene_path.is_empty():
		return null
	var packed: PackedScene = _scene_cache.get(def.scene_path)
	if packed == null:
		if not ResourceLoader.exists(def.scene_path):
			# Not an error. A client whose content pack is still arriving asks for scenes
			# it does not have, and skipping one is safe by this addon's central property.
			DotLog.debug(CHANNEL, "no such scene", {"path": def.scene_path})
			return null
		packed = load(def.scene_path) as PackedScene
		if packed == null:
			return null
		_scene_cache[def.scene_path] = packed
	var node := packed.instantiate()
	_place(node, at)
	_world.add_child(node)
	return node


## Frees this frame's budget for [param def] by retiring effects of lower priority that
## started this frame, lowest priority first and the newest of a tie first. All or nothing:
## when even all of them would not make room, nothing is retired.
##
## [b]Only this frame's.[/b] The budget is what may START in a frame; an effect from an earlier
## frame has been seen and costs nothing more, so displacing it would refund nothing real.
## [member DotFxDef.priority] used to be documented as "higher survives when the budget is
## spent" and read by nothing: the budget went first come, first served.
func _make_room(def: DotFxDef) -> bool:
	var lower: Array[Dictionary] = []
	var freed := 0
	for entry: Dictionary in _this_frame:
		if int(entry["priority"]) < def.priority:
			lower.append(entry)
			freed += int(entry["cost"])
	if _budget_left + freed < def.cost:
		return false
	lower.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"]) \
			or (int(a["priority"]) == int(b["priority"]) and _this_frame.find(a) > _this_frame.find(b)))
	for entry: Dictionary in lower:
		if def.cost <= _budget_left:
			break
		var at := _live.find(entry)
		if at >= 0:
			_retire(at)
		_budget_left += int(entry["cost"])
	return def.cost <= _budget_left


func _retire(index: int) -> void:
	var entry := _live[index]
	_live.remove_at(index)
	_this_frame.erase(entry)
	var id: StringName = entry["id"]
	_concurrent[id] = maxi(0, int(_concurrent.get(id, 1)) - 1)
	_decals.erase(entry)
	var node: Node = entry["node"]
	if node != null and is_instance_valid(node):
		node.queue_free()


## The oldest effect that is not a decal, else the oldest decal. Decals used to be skipped
## outright, so with [member DotFxConfig.max_instances] of long-lived decals alive (both
## default to 256) every spawn was refused, a decal's own ring included.
func _retire_oldest() -> bool:
	for i in range(_live.size()):
		if not bool(_live[i]["decal"]):
			_retire(i)
			return true
	if _live.is_empty():
		return false
	_retire(0)
	return true


func _trim_decals() -> void:
	while _decals.size() > config.max_decals and _decals.size() > 0:
		var oldest: Dictionary = _decals[0]
		var idx := _live.find(oldest)
		if idx >= 0:
			_retire(idx)
		else:
			_decals.remove_at(0)


# --- Screen flashes ---------------------------------------------------------

## Asks for a full-screen flash, subject to the player's settings and a rate limit.
##
## [b]Both limits are enforced here rather than left to the caller.[/b] A caller that
## honours them is one caller; the next feature added by the next person is the one that
## does not, and the person it harms has no way to know which effect did it.
func flash(id: StringName) -> bool:
	var def := catalogue.find(id) if catalogue != null else null
	if def == null:
		return false

	if not config.allow_flashes:
		flashed.emit(id, def.flash_colour, 0.0, false)
		return false

	var now := Time.get_ticks_msec()
	# The published photosensitivity guidance is no more than three general flashes in any
	# one second. The window is a second and the cap is a setting, defaulting to three.
	for i in range(_flash_times.size() - 1, -1, -1):
		if now - _flash_times[i] > 1000:
			_flash_times.remove_at(i)
	if config.flashes_per_second > 0 and _flash_times.size() >= config.flashes_per_second:
		flashed.emit(id, def.flash_colour, 0.0, false)
		return false

	_flash_times.append(now)
	var peak := minf(def.flash_peak, config.flash_cap)
	flash_colour = def.flash_colour
	flash_colour.a = peak
	_flash_decay_ms = def.flash_decay_ms
	flashed.emit(id, def.flash_colour, peak, true)
	return true


# --- Housekeeping -----------------------------------------------------------

## Frees everything. Called on a map change, and by [method Node._exit_tree].
func clear() -> void:
	for i in range(_live.size() - 1, -1, -1):
		_retire(i)
	_live.clear()
	_decals.clear()
	_concurrent.clear()
	shake.reset()
	flash_colour.a = 0.0


func live_count() -> int:
	return _live.size()


func decal_count() -> int:
	return _decals.size()


func budget_left() -> int:
	return _budget_left


func describe() -> Dictionary:
	return {
		"quality": config.quality,
		"live": _live.size(),
		"decals": _decals.size(),
		"budget": _budget_left,
		"shake": shake.trauma(),
		"flashes_allowed": config.allow_flashes,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("dot-fx  quality %d" % config.quality)
	out.append("  %d live, %d decals (max %d)" % [_live.size(), _decals.size(), config.max_decals])
	out.append("  budget  %d of %d left this frame" % [_budget_left, config.frame_budget])
	out.append_array(shake.describe_lines())
	if not config.allow_flashes:
		out.append("  flashes off, by request")
	return out
