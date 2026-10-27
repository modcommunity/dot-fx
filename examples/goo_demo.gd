extends Node3D

## A street corner under the screen goo at three amounts, side by side. Needs a display.
##
## [codeblock]
## tools/screenshot.sh /tmp/goo.png goo
## [/codeblock]

var _shot := ""
var _frames := 0
var _goo: DotFxScreenGoo = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := OS.get_cmdline_user_args()
	var amount := 0.6
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
		if args[i].begins_with("--amount="):
			amount = float(args[i].substr(9))

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.55, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	add_child(_box(Vector3(0, -0.25, 0), Vector3(30, 0.5, 30), Color(0.4, 0.4, 0.38)))
	for i in range(5):
		add_child(_box(Vector3(-6 + i * 3, 1.5, -6), Vector3(2, 3, 2), Color.from_hsv(0.08 * i, 0.5, 0.8)))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.7, 5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.5, -6))
	_goo = DotFxScreenGoo.new()
	add_child(_goo)
	_goo.apply(amount, 60.0, 0.0, 0.0)


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
