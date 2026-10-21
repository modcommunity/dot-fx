extends Node3D

## Snow in one box and rain in another, with a floor and posts so the edges can be seen. Run it
## under a display; headless it draws nothing, which is the point of [method DotFxWeather.can_render].
##
## [codeblock]
## godot --path . res://examples/weather_demo.tscn
## xvfb-run -a godot --path . res://examples/weather_demo.tscn -- --shot /tmp/weather.png
## [/codeblock]
##
## Keys: Q cycles the quality (off, low, high), W/S move the camera forward and back.

var _snow := DotFxWeather.new()
var _rain := DotFxWeather.new()
var _cam := Camera3D.new()
var _shot_path := ""
var _frames := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--shot":
		_shot_path = args[1]

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.2, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 60)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.33, 0.3)
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	# A post at each volume corner, so the box the weather should stay in can be read.
	for box in [AABB(Vector3(-22, 0, -8), Vector3(16, 10, 16)), AABB(Vector3(6, 0, -8), Vector3(16, 10, 16))]:
		for cx in [box.position.x, box.end.x]:
			for cz in [box.position.z, box.end.z]:
				_post(Vector3(cx, 5, cz), Color(0.9, 0.5, 0.2))
	# A pillar outside both, to see against.
	_post(Vector3(0, 5, -4), Color(0.4, 0.8, 0.9))

	add_child(_snow)
	add_child(_rain)
	var r1 := _snow.apply({"kind": "snow", "density": 1.5, "wind": [0.6, 0, 0], "volumes": [{"min": [-22, 0, -8], "max": [-6, 10, 8]}]})
	var r2 := _rain.apply({"kind": "rain", "colour": [0.75, 0.85, 1.0, 0.6], "volumes": [{"min": [6, 0, -8], "max": [22, 10, 8]}]})
	if not (r1.ok and r2.ok):
		push_error("weather demo: bad document")

	_cam.position = Vector3(0, 3, 7)
	_cam.fov = 85.0
	add_child(_cam)
	_cam.look_at(Vector3(0, 3.5, -8))
	_cam.make_current()
	print(_snow.describe())
	print(_rain.describe())


func _post(at: Vector3, colour: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.3, 10, 0.3)
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	m.material_override = mat
	m.position = at
	add_child(m)


func _process(delta: float) -> void:
	_snow.advance(delta, _cam.global_position)
	_rain.advance(delta, _cam.global_position)
	_frames += 1
	if _shot_path != "" and _frames == 90:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("saved ", _shot_path)
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_Q:
		var q := ((int(_snow.quality) + 2) % 3) as DotFxWeather.Quality
		_snow.quality = q
		_rain.quality = q
	elif k.keycode == KEY_W:
		_cam.position.z -= 2.0
	elif k.keycode == KEY_S:
		_cam.position.z += 2.0
