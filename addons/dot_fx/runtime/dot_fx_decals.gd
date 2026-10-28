class_name DotFxDecals
extends Node3D

## Pooled blood splatters from hits plus static wall decals placed from data; purely visual.
## At [method DotFxDecalConfig.effective_blood_cap] the oldest node is reused. Time is explicit: call [method advance] each frame.
## Decal nodes where the renderer has them, quads just off the surface otherwise (Compatibility, browser).

const CHANNEL := "fx.decals"

## A static decal was placed (id may be empty).
signal placed(id: StringName)

var config := DotFxDecalConfig.new()

var _rng := RandomNumberGenerator.new()
var _blood_root := Node3D.new()
var _static_root := Node3D.new()
## Live splatters, oldest first: {node, age}.
var _blood: Array[Dictionary] = []
var _free: Array[Node3D] = []
var _static: Dictionary = {}
var _anon_static := 0
var _tint := Color.WHITE


func _init() -> void:
	_blood_root.name = "Blood"
	_static_root.name = "Static"
	add_child(_blood_root)
	add_child(_static_root)
	apply_config(config)


## Whether this renderer has Decal nodes. Compatibility (the web, older GPUs) does not.
static func decal_nodes_supported() -> bool:
	if DotPlatform.is_web():
		return false
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## Takes a config, seeds the generator and applies the tier, gore switch and caps at once.
func apply_config(cfg: DotFxDecalConfig) -> void:
	config = cfg
	_rng.seed = cfg.seed_value if cfg.seed_value != 0 else int(Time.get_ticks_usec())
	_tint = Color.html(cfg.blood_colour) if Color.html_is_valid(cfg.blood_colour) else Color.WHITE
	if not cfg.gore:
		clear_blood()
	_trim()
	_static_root.visible = cfg.quality > 0


## True when Decal nodes (not quads) are in use under the current config.
func uses_decal_nodes() -> bool:
	match config.mode:
		DotFxDecalConfig.Mode.DECAL:
			return true
		DotFxDecalConfig.Mode.MESH:
			return false
	return decal_nodes_supported()


## Spawns one blood splatter at a hit. [param size_scale] multiplies the random width; [param frame]
## picks the texture (negative is random). Returns the node, or null when gore or quality is off.
func splatter(position: Vector3, normal: Vector3, size_scale: float = 1.0, frame: int = -1) -> Node3D:
	var cap := config.effective_blood_cap()
	if not config.gore or cap <= 0:
		return null
	var frames := DotFxDecalSheet.blood_frames()
	if frames.is_empty():
		DotLog.warn(CHANNEL, "blood art missing")
		return null
	_trim()
	var node: Node3D
	if _blood.size() >= cap:
		node = _blood.pop_front()["node"]
	elif not _free.is_empty():
		node = _free.pop_back()
	else:
		node = _make_node()
		_blood_root.add_child(node)
	var f := frame if frame >= 0 else _rng.randi() % frames.size()
	var w := _rng.randf_range(config.blood_size_min, config.blood_size_max) * size_scale
	_configure(node, frames[f % frames.size()], position, normal, Vector2(w, w), _rng.randf() * 360.0, _tint, 1.0)
	node.visible = true
	_blood.append({"node": node, "age": 0.0})
	return node


## Validates and places one static decal from a document, a [DotResult] holding its node.
## Keys: image, position, normal, width, roll, colour, opacity, id.
## Unknown keys are refused so a misspelt "normal" cannot read as the default and paint the floor.
func place(doc: Dictionary) -> DotResult:
	var res := _parse(doc)
	if not res.ok:
		return res
	var p: Dictionary = res.value
	if _static.size() >= config.max_static:
		return DotResult.fail(DotError.CODE_STATE, "static decal cap reached", str(config.max_static))
	var id: StringName = p["id"]
	if id == &"":
		_anon_static += 1
		id = StringName("_anon%d" % _anon_static)
	if _static.has(id):
		return DotResult.fail(DotError.CODE_CONFLICT, "decal id already placed", str(id))
	var node := _make_node()
	_static_root.add_child(node)
	_configure(node, p["tex"], p["position"], p["normal"], p["size"], p["roll"], p["colour"], p["opacity"])
	_static[id] = node
	placed.emit(p["id"])
	return DotResult.success(node)


## Places every document, or none: a bad one is reported with its index and nothing is placed.
## The value is the number placed.
func place_all(docs: Array) -> DotResult:
	for i in range(docs.size()):
		if typeof(docs[i]) != TYPE_DICTIONARY:
			return DotResult.fail(DotError.CODE_INVALID, "decal %d is not a dictionary" % i)
		var r := _parse(docs[i])
		if not r.ok:
			return r.wrap("decal %d" % i)
	if _static.size() + docs.size() > config.max_static:
		return DotResult.fail(DotError.CODE_STATE, "static decal cap reached", str(config.max_static))
	for d in docs:
		var r := place(d)
		if not r.ok:
			return r
	return DotResult.success(docs.size())


## Removes a static decal by id; false when there is none.
func remove(id: StringName) -> bool:
	var node: Node3D = _static.get(id)
	if node == null:
		return false
	_static.erase(id)
	node.queue_free()
	return true


func clear_static() -> void:
	for n in _static.values():
		n.queue_free()
	_static.clear()


func clear_blood() -> void:
	for e in _blood:
		_retire(e["node"])
	_blood.clear()


## Ages the blood: holds, then fades, then returns the node to the pool.
func advance(delta: float) -> void:
	if config.blood_hold <= 0.0:
		return
	var i := 0
	while i < _blood.size():
		var e: Dictionary = _blood[i]
		e["age"] = float(e["age"]) + delta
		var over: float = float(e["age"]) - config.blood_hold
		if over >= config.blood_fade:
			_blood.remove_at(i)
			_retire(e["node"])
			continue
		if over > 0.0:
			_set_alpha(e["node"], 1.0 - over / maxf(config.blood_fade, 0.001))
		i += 1


func blood_count() -> int:
	return _blood.size()


func static_count() -> int:
	return _static.size()


## Nodes held in the pool, live and idle.
func pool_size() -> int:
	return _blood.size() + _free.size()


## Alpha (0 to 1) of the n-th oldest live splatter, for tests and tools.
func blood_alpha(n: int) -> float:
	return _alpha_of(_blood[n]["node"])


func describe() -> String:
	return "DotFxDecals: %d blood (cap %d), %d static, %s, gore %s, quality %d" % [
		_blood.size(), config.effective_blood_cap(), _static.size(),
		"Decal nodes" if uses_decal_nodes() else "quads", "on" if config.gore else "off", config.quality]


func _trim() -> void:
	var cap := config.effective_blood_cap()
	while _blood.size() > cap:
		_retire(_blood.pop_front()["node"])


func _retire(node: Node3D) -> void:
	node.visible = false
	_free.append(node)


func _make_node() -> Node3D:
	var node := _new_node()
	node.top_level = true
	return node


func _new_node() -> Node3D:
	if uses_decal_nodes():
		var d := Decal.new()
		d.cull_mask = 0xFFFFF
		d.distance_fade_enabled = config.fade_distance > 0.0
		d.distance_fade_begin = config.fade_distance
		d.distance_fade_length = maxf(config.fade_distance * 0.2, 1.0)
		return d
	var m := MeshInstance3D.new()
	m.mesh = QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 1
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _configure(node: Node3D, tex: Texture2D, pos: Vector3, normal: Vector3, size: Vector2,
		roll: float, colour: Color, opacity: float) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var ref := Vector3.UP if absf(n.y) < 0.99 else Vector3.FORWARD
	var up := (ref - n * ref.dot(n)).normalized().rotated(n, deg_to_rad(roll))
	var right := up.cross(n)
	node.visible = true
	if node is Decal:
		# A Decal projects along its -Y, so Y is the surface normal; the texture's top is -Z.
		node.basis = Basis(right, n, -up)
		node.position = pos
		node.size = Vector3(size.x, config.depth, size.y)
		node.texture_albedo = tex
		node.modulate = Color(colour.r, colour.g, colour.b, colour.a * opacity)
	else:
		node.basis = Basis(right, up, n)
		node.position = pos + n * 0.012
		(node.mesh as QuadMesh).size = size
		var mat := node.material_override as StandardMaterial3D
		mat.albedo_texture = tex
		mat.albedo_color = Color(colour.r, colour.g, colour.b, colour.a * opacity)


func _set_alpha(node: Node3D, a: float) -> void:
	if node is Decal:
		node.modulate.a = a
	else:
		(node.material_override as StandardMaterial3D).albedo_color.a = a


func _alpha_of(node: Node3D) -> float:
	if node is Decal:
		return node.modulate.a
	return (node.material_override as StandardMaterial3D).albedo_color.a


const _KEYS := ["id", "image", "position", "normal", "width", "roll", "colour", "opacity"]


func _parse(doc: Dictionary) -> DotResult:
	for k in doc:
		if not _KEYS.has(String(k)):
			return DotResult.fail(DotError.CODE_INVALID, "unknown decal key", str(k))
	var tex := DotFxDecalSheet.graffiti(StringName(str(doc.get("image", ""))))
	if tex == null:
		return DotResult.fail(DotError.CODE_INVALID, "unknown decal image", str(doc.get("image", "")))
	var pos = _vec3(doc.get("position"))
	if pos == null:
		return DotResult.fail(DotError.CODE_INVALID, "position must be [x, y, z]")
	var normal = _vec3(doc.get("normal", [0, 1, 0]))
	if normal == null or (normal as Vector3).length_squared() < 0.0001:
		return DotResult.fail(DotError.CODE_INVALID, "normal must be a non-zero [x, y, z]")
	var width := float(doc.get("width", 1.0))
	if width <= 0.0 or width > 50.0:
		return DotResult.fail(DotError.CODE_INVALID, "width must be above 0 and at most 50")
	var colour := Color.WHITE
	if doc.has("colour"):
		if not Color.html_is_valid(str(doc["colour"])):
			return DotResult.fail(DotError.CODE_INVALID, "colour is not an html colour")
		colour = Color.html(str(doc["colour"]))
	var aspect := float(tex.get_height()) / float(tex.get_width())
	return DotResult.success({
		"id": StringName(str(doc.get("id", ""))), "tex": tex, "position": pos, "normal": normal,
		"size": Vector2(width, width * aspect), "roll": float(doc.get("roll", 0.0)),
		"colour": colour, "opacity": clampf(float(doc.get("opacity", 1.0)), 0.0, 1.0),
	})


static func _vec3(v: Variant) -> Variant:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() == 3:
		for x in v:
			if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
				return null
		return Vector3(v[0], v[1], v[2])
	return null
