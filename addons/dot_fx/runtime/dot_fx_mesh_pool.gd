class_name DotFxMeshPool
extends Node3D

## Reused MeshInstance3D nodes for impact marks and flashes, so none is built or freed mid-match. Place it yourself; no autoload.

var _free: Array[MeshInstance3D] = []
var _all: Array[MeshInstance3D] = []


## Builds [param count] hidden instances (default [member DotFxPoolConfig.prewarm_meshes]) of [param mesh] and draws them for [param frames] frames so the shader compiles under a loading cover.
func prewarm(mesh: Mesh, material: Material = null, count: int = -1, frames: int = 2) -> void:
	var n := DotFxLightBudget.config.prewarm_meshes if count < 0 else count
	for i in n:
		var m := _make()
		m.mesh = mesh
		m.material_override = material
		m.visible = true
		_free.append(m)
	if is_inside_tree():
		for i in frames:
			await get_tree().process_frame
	for m in _free:
		m.visible = false


## A visible instance showing [param mesh] at [param xform], reused when one is idle. Give it back with [method release].
func acquire(mesh: Mesh, xform: Transform3D, material: Material = null) -> MeshInstance3D:
	var m: MeshInstance3D = _free.pop_back() if not _free.is_empty() else _make()
	m.mesh = mesh
	m.material_override = material
	m.transform = xform
	m.visible = true
	return m


## Returns an instance for reuse (hidden, not freed).
func release(m: MeshInstance3D) -> void:
	if not is_instance_valid(m) or _free.has(m):
		return
	m.visible = false
	_free.append(m)


## Instances built so far, in use or idle.
func built() -> int:
	return _all.size()


## Idle instances ready for reuse.
func idle() -> int:
	return _free.size()


func _make() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	_all.append(m)
	return m
