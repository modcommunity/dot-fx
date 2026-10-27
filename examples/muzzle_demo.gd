extends Node3D

## The four muzzle flash sizes on four dummy guns, caught a moment after firing. Needs a display.
##
## [codeblock]
## tools/screenshot.sh /tmp/muzzle.png muzzle [fp]
## [/codeblock]

var _shot := ""
var _t := 0.0
var _fired := false
var _flashes: Array[DotMuzzleFlash] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := OS.get_cmdline_user_args()
	var fp := false
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
		if args[i] == "--fp":
			fp = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	add_child(_box(Vector3(2.5, -0.1, 0), Vector3(14, 0.2, 4), Color(0.3, 0.3, 0.28)))
	var sizes := [DotMuzzleFlash.Size.VERY_SMALL, DotMuzzleFlash.Size.SMALL, DotMuzzleFlash.Size.MEDIUM, DotMuzzleFlash.Size.BIG]
	for i in sizes.size():
		var y := 3.6 - i * 1.0
		add_child(_box(Vector3(-0.3, y, 0), Vector3(1.0, 0.25, 0.25), Color(0.2, 0.2, 0.22)))
		var f := DotMuzzleFlash.new()
		f.size = sizes[i]
		f.first_person = fp
		f.position = Vector3(0.25, y, 0)
		add_child(f)
		_flashes.append(f)
	var cam := Camera3D.new()
	cam.position = Vector3(1.2, 2.0, 5.2)
	add_child(cam)
	cam.look_at(Vector3(1.2, 2.0, 0))


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


func _process(d: float) -> void:
	_t += d
	if not _fired and _t > 0.3:
		_fired = true
		_t = 0.0
		for f in _flashes:
			f.fire()
	elif _fired and _shot != "" and _t > 0.06:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
