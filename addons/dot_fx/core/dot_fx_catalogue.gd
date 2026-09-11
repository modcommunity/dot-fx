@tool
class_name DotFxCatalogue
extends Resource

## Every effect a game has, as a document a server can check with no renderer.

@export var defs: Array[DotFxDef] = []

var _by_id: Dictionary = {}


func add(def: DotFxDef) -> DotFxCatalogue:
	defs.append(def)
	_by_id.clear()
	return self


func find(id: StringName) -> DotFxDef:
	_ensure_index()
	return _by_id.get(id)


func has(id: StringName) -> bool:
	_ensure_index()
	return _by_id.has(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in defs:
		out.append(d.id)
	return out


func with_tag(tag: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in defs:
		if d.tags.has(tag):
			out.append(d.id)
	return out


func _ensure_index() -> void:
	if _by_id.size() == defs.size():
		return
	_by_id.clear()
	for d in defs:
		if d != null:
			_by_id[d.id] = d


func validate() -> DotResult:
	var seen := {}
	for d in defs:
		if d == null:
			return DotResult.fail(DotError.CODE_INVALID, "a null entry in the catalogue")
		var res := d.validate()
		if not res.ok:
			return res
		if seen.has(d.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"effect id '%s' appears twice" % d.id,
				"the second one is unreachable and nothing would ever say so"
			)
		seen[d.id] = true
	return DotResult.success(null)


## Which scenes named here are not present. A separate question from validity.
func missing_scenes() -> PackedStringArray:
	var out := PackedStringArray()
	for d in defs:
		if d.scene_path != "" and not ResourceLoader.exists(d.scene_path):
			out.append(d.scene_path)
	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("catalogue: %d effects" % defs.size())
	for d in defs:
		out.append("  %s" % d.describe_line())
	return out
