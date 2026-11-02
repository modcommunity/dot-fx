extends Node3D

## The five break materials in a row, caught shortly after bursting. Needs a display.
## Shot with tools/screenshot.sh /tmp/break.png break [--at seconds].

var _shot := ""
var _t := 0.0
var _fired := false
var _at := 0.25
var _brk: DotFxBreak


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
		if args[i] == "--at" and i + 1 < args.size():
			_at = float(args[i + 1])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(14, 0.2, 5)
	floor_mesh.mesh = bm
	floor_mesh.position = Vector3(0, -0.1, 0)
	add_child(floor_mesh)
	var cfg := DotFxBreakConfig.new()
	cfg.headless = true
	_brk = DotFxBreak.new()
	_brk.config = cfg
	add_child(_brk)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.8, 6.5)
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))


func _process(d: float) -> void:
	_t += d
	if not _fired and _t > 0.3:
		_fired = true
		_t = 0.0
		var i := 0
		for m: String in DotFxBreak.MATERIALS:
			_brk.burst(m, Vector3(-4.8 + i * 2.4, 0.6, 0), Vector3.UP, 1.5)
			i += 1
	elif _fired and _shot != "" and _t > _at:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
