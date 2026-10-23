extends Node3D

## A floor and a wall with blood splattered on both and graffiti on the wall. Needs a display.
##
## [codeblock]
## godot --path . res://examples/decals_demo.tscn
## tools/screenshot.sh /tmp/decals.png [mesh|decal]
## [/codeblock]

var _shot := ""
var _frames := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := OS.get_cmdline_user_args()
	var cfg := DotFxDecalConfig.new()
	cfg.seed_value = 3
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
		if args[i] == "--mode=mesh":
			cfg.mode = DotFxDecalConfig.Mode.MESH
		if args[i] == "--mode=decal":
			cfg.mode = DotFxDecalConfig.Mode.DECAL

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.25, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	add_child(_box(Vector3(0, -0.25, 0), Vector3(14, 0.5, 10), Color(0.45, 0.45, 0.42)))
	add_child(_box(Vector3(0, 2.5, -4.25), Vector3(14, 5, 0.5), Color(0.6, 0.58, 0.55)))

	var decals := DotFxDecals.new()
	add_child(decals)
	decals.apply_config(cfg)
	var docs: Array = [
		{"image": "alien", "position": [-4.5, 2.2, -4.0], "normal": [0, 0, 1], "width": 2.0},
		{"image": "beast", "position": [-0.5, 2.4, -4.0], "normal": [0, 0, 1], "width": 3.2},
		{"image": "tentacle", "position": [4.0, 1.2, -4.0], "normal": [0, 0, 1], "width": 2.6, "id": "t"},
		{"image": "warning", "position": [2.6, 3.4, -4.0], "normal": [0, 0, 1], "width": 1.2},
		{"image": "spider", "position": [-3.0, 0.05, 3.0], "normal": [0, 1, 0], "width": 1.4},
	]
	var res := decals.place_all(docs)
	if not res.ok:
		push_error("demo: " + res.error.message)
	for p in [Vector3(-2, 0, -1), Vector3(0.5, 0, 0.5), Vector3(2.5, 0, -0.5), Vector3(-1, 0, 1.5)]:
		decals.splatter(p, Vector3.UP, 1.6)
	for p in [Vector3(-3, 1.0, -4.0), Vector3(1.5, 1.8, -4.0)]:
		decals.splatter(p, Vector3(0, 0, 1), 1.4)
	print(decals.describe())

	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.2, 8.5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, -1.5))


func _box(pos: Vector3, size: Vector3, colour: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	m.material_override = mat
	m.position = pos
	return m


func _process(_d: float) -> void:
	_frames += 1
	if _shot != "" and _frames == 8:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
