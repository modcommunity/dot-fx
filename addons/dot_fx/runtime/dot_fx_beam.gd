class_name DotFxBeam
extends Node3D

## A straight energy beam between two points: a thin glowing cylinder that shimmers and fades.
## One-shot ([method zap]) frees itself; a held beam ([method hold]) is kept alive by calling
## [method set_ends] every frame and fades once the caller stops.

## Seconds a held beam lasts after its last [method set_ends].
const HOLD_GRACE := 0.15

var colour: Color = Color(0.45, 0.8, 1.0)
var width: float = 0.08
var lifetime: float = 0.25

var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _age: float = 0.0
var _held: bool = false
var _seed: float = 0.0


## One short flash from [param from] to [param to], added under [param parent].
static func zap(parent: Node, from: Vector3, to: Vector3, p_colour: Color = Color(0.45, 0.8, 1.0),
		seconds: float = 0.25, p_width: float = 0.08) -> DotFxBeam:
	var beam := DotFxBeam.new()
	beam.colour = p_colour
	beam.lifetime = seconds
	beam.width = p_width
	parent.add_child(beam)
	beam.set_ends(from, to)
	return beam


## A beam to keep alive by calling [method set_ends] each frame.
static func hold(parent: Node, p_colour: Color = Color(0.45, 0.8, 1.0), p_width: float = 0.1) -> DotFxBeam:
	var beam := DotFxBeam.new()
	beam.colour = p_colour
	beam.width = p_width
	beam._held = true
	parent.add_child(beam)
	return beam


func _ready() -> void:
	top_level = true
	_seed = randf() * 10.0
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = colour
	_material.no_depth_test = false
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cylinder
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## Places the beam; a zero-length one hides it.
func set_ends(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()

	if length < 0.01:
		visible = false
		return

	visible = true
	_age = 0.0 if _held else _age
	var up := d / length
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	global_transform = Transform3D(Basis(side, up, side.cross(up)), (from + to) * 0.5)
	_mesh.scale = Vector3(width, length, width)


func _process(delta: float) -> void:
	_age += delta

	if _held:
		if _age > HOLD_GRACE:
			visible = false
		return

	var left := 1.0 - _age / maxf(lifetime, 0.01)

	if left <= 0.0:
		queue_free()
		return

	var flicker := 0.75 + 0.25 * sin((_age + _seed) * 90.0)
	_material.albedo_color = Color(colour.r, colour.g, colour.b, left * flicker)
