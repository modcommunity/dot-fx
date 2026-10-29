extends Node3D

## Shots at a wall, a floor, open air, a person and a crate that then moves: only the ones
## that hit the wall, floor and crate stay. Needs a display: tools/screenshot.sh <png> surface.

var _shot := ""
var _frames := 0
var _fx: DotFxManager
var _crate: RigidBody3D


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.4, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_solid(StaticBody3D.new(), Vector3(14, 0.5, 10), Vector3(0, -0.25, 0), Color(0.45, 0.45, 0.42))
	_solid(StaticBody3D.new(), Vector3(14, 5, 0.5), Vector3(0, 2.5, -4.25), Color(0.6, 0.58, 0.55))
	_crate = RigidBody3D.new()
	_crate.freeze = true
	_solid(_crate, Vector3(1.2, 1.2, 1.2), Vector3(3, 0.6, -2), Color(0.7, 0.45, 0.2))
	_solid(CharacterBody3D.new(), Vector3(0.7, 1.8, 0.7), Vector3(-3, 0.9, -2), Color(0.3, 0.6, 0.3))

	var cat := DotFxCatalogue.new()
	var def := DotFxDef.new()
	def.id = &"hole"
	def.kind = DotFxDef.Kind.DECAL
	def.scene_path = "res://fixtures/hole.tscn"
	def.lifetime_ms = 600000
	cat.add(def)
	_fx = DotFxManager.new()
	_fx.catalogue = cat
	_fx.register_as_service = false
	add_child(_fx)
	_fx.setup()

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.5, 9)
	add_child(cam)
	cam.look_at(Vector3(0, 1.2, -2))


func _solid(body: PhysicsBody3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mesh.material_override = mat
	body.add_child(mesh)
	body.position = at
	add_child(body)


func _fire(from: Vector3, dir: Vector3, reach: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit["position"] if not hit.is_empty() else from + dir * reach
	_fx.spawn_decal(&"hole", Transform3D(Basis.looking_at(dir, Vector3.UP), end))


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 3:
		for x in [-2.0, -0.5, 1.0]:
			_fire(Vector3(x, 1.5, 5), Vector3(0, 0, -1), 20.0)
		_fire(Vector3(0, 1.5, 5), Vector3(0, 0.6, -1).normalized(), 4.0)
		_fire(Vector3(-3, 1.5, 5), Vector3(0, 0, -1), 20.0)
		_fire(Vector3(3, 0.9, 5), Vector3(0, 0, -1), 20.0)
	if _frames == 6:
		_crate.global_position += Vector3(0, 1.8, 0)
	if _shot != "" and _frames == 12:
		print("decals kept: ", _fx.decal_count())
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
