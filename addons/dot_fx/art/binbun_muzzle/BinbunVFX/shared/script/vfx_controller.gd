@tool
extends Node3D
class_name DotMuzzleVfxController

## Works only in the editor. By default works like "emitting" on particles. When one_shot is enabled works as a button. 
@export var preview : bool = true:
	set(value):
		if Engine.is_editor_hint():
			if one_shot && value == true:
				play()
			else:
				preview = value
				if value == true:
					play()

@export var one_shot : bool = false:
	set(value):
		one_shot = value
		if Engine.is_editor_hint():
			preview = false

@export var autoplay : bool = true

## Wether to reset particles when animation loops
@export var reset_particles : bool = true

@export_group("General")
@export var local_coords : bool = false:
	set(value):
		local_coords = value
		for p in _get_particles(): if is_instance_valid(p): p.local_coords = value
@export_range(0, 10, 0.01) var speed_scale : float = 1.0:
	set(value):
		speed_scale = value
		_set_shader_params("time_scale", speed_scale)
		_get_anim().speed_scale = value
		for p in _get_particles(): if is_instance_valid(p): p.speed_scale = value

@export_group("Colors")
@export var primary_color : Color:
	set(value):
		primary_color = value
		_set_shader_params("primary_color", primary_color)
@export var secondary_color : Color:
	set(value):
		secondary_color = value
		_set_shader_params("secondary_color", secondary_color)
@export var tertiary_color : Color:
	set(value):
		tertiary_color = value
		_set_shader_params("tertiary_color", tertiary_color)

@export_group("Light")
@export var light_enable : bool = true:
	set(value):
		light_enable = value
		_set_light_prop("visible", value)
@export var light_color : Color:
	set(value):
		light_color = value
		_set_light_prop("light_color", value)
@export var light_energy : float = 4.0:
	set(value):
		light_energy = value
		_set_light_prop("base_energy", value)
@export var light_indirect_energy : float = 1.0:
	set(value):
		light_indirect_energy = value
		_set_light_prop("light_indirect_energy", value)
@export var light_volumetric_fog_energy : float = 1.0:
	set(value):
		light_volumetric_fog_energy = value
		_set_light_prop("light_volumetric_fog_energy", value)

@export_group("Proximity Fade")
@export var proximity_fade : bool = false:
	set(value):
		proximity_fade = value
		_set_shader_params("proximity_fade", proximity_fade)
@export var proximity_fade_distance : float = 1.0:
	set(value):
		proximity_fade_distance = value
		_set_shader_params("proximity_fade_distance", proximity_fade_distance)


@export_group("LODs")
enum Alpha_Mode {
	## Smooth transparency. Most performance intensive
	SMOOTH, 
	## Displays transparency with a dithering pattern. Less performance intensive
	DITHER, 
	## Hard cut alpha. Like "Alpha Scissor" in [b]SpatialMaterial[/b]. Least performance intensive
	CUT,
	## Uses dithering and hard cut to achieve better results
	HYBRID
}
## Specifies how to handle [b]transparency[/b] within shaders.
@export var alpha_mode : Alpha_Mode = Alpha_Mode.SMOOTH:
	set(value):
		alpha_mode = value
		_set_shader_params("alpha_mode", alpha_mode)
@export_range(0.0,1.0,0.01) var alpha_cutoff : float = 0.02:
	set(value):
		alpha_cutoff = value
		_set_shader_params("alpha_cutoff", alpha_cutoff)
@export_range(0.0,1.0,0.01) var dither_cutoff : float = 0.8:
	set(value):
		dither_cutoff = value
		_set_shader_params("dither_cutoff", dither_cutoff)
## Specify resolution of meshes. 
## [br][br]
## [b]SphereMesh:[/b] Sets [code]radial_segments[/code] to the [b]value[/b] and
## [code]rings[/code] to [b]half the value[/b] 
## [br][br]
## [b]CylinderMesh:[/b] Sets [code]radial_segments[/code] to the [b]value[/b]
## [br][br]
## [b]PlaneMesh:[/b] Sets [code]subdivide_width[/code] and [code]subdivide_depth[/code] to the [b]value[/b]
@export var mesh_resolutions : int = 32:
	set(value):
		mesh_resolutions = value
		_set_mesh_resolutions(mesh_resolutions)

var particles : Array[GPUParticles3D] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	if autoplay: play()

func _enter_tree() -> void:
	if autoplay: preview = true

func play():
	var anim : AnimationPlayer = _get_anim()
	
	if !one_shot:
		if reset_particles: _reset_particles()
		anim.play("main")
		anim.seek(0.0)
		await _get_anim().animation_finished
		if Engine.is_editor_hint() && !preview:
			return
		play()
	else:
		_reset_particles()
		if anim.has_animation("oneshot"):
			anim.play("oneshot")
			anim.seek(0.0)
		else:
			anim.play("main")

## Util
func _get_anim() -> AnimationPlayer:
	return get_node("AnimationPlayer")

func _get_particles() -> Array[GPUParticles3D]:
	var result : Array[GPUParticles3D] = []
	for p in get_children():
		if p is GPUParticles3D:
			result.append(p)
	return result

func _get_meshinstances() -> Array[MeshInstance3D]:
	var result : Array[MeshInstance3D] = []
	for m in get_children():
		if m is MeshInstance3D:
			result.append(m)
	return result

func _get_meshes() -> Array[Mesh]:
	var result : Array[Mesh]
	for p in _get_particles(): if is_instance_valid(p):
		result.append(p.draw_pass_1)
	for m in _get_meshinstances(): if is_instance_valid(m):
		result.append(m.mesh)
	return result

func _set_light_prop(pname : String, value) -> void:
	var light = get_node_or_null("Light")
	if light != null:
		light.set(pname, value)

func _reset_particles():
	for p in _get_particles():
		p.restart()

func _set_shader_params(name : String, value) -> void:
	for p in _get_particles():
		if is_instance_valid(p):
			if p.material_override is ShaderMaterial:
				p.material_override.set("shader_parameter/" + name, value)
	for m in _get_meshinstances():
		if is_instance_valid(m):
			if m.material_override is ShaderMaterial:
				m.material_override.set("shader_parameter/" + name, value)

func _set_mesh_resolutions(value : int) -> void:
	for m in _get_meshes(): if is_instance_valid(m):
		if m is SphereMesh:
			m.radial_segments = value
			m.rings = value/2
		if m is CylinderMesh:
			m.radial_segments = value
		if m is PlaneMesh:
			m.subdivide_width = value
			m.subdivide_depth = value
