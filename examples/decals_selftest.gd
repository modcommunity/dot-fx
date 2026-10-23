extends Node

## Headless checks for [DotFxDecals]: counts, the pool cap, fade, the gore and quality switches,
## placed documents and config layering. Looks are checked with decals_demo.tscn.
##
## [codeblock]
## godot --headless --path . res://examples/decals_selftest.tscn
## [/codeblock]

const SECTIONS := 6
const CHECKS := 54

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_art()
	_blood()
	_fade()
	_switches()
	_placed()
	_config()
	print("")
	print("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		print("ERROR: %d sections and %d checks ran, %d and %d expected" % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _make(cfg: DotFxDecalConfig = null) -> DotFxDecals:
	var d := DotFxDecals.new()
	add_child(d)
	var c := cfg if cfg != null else DotFxDecalConfig.new()
	c.seed_value = 7
	d.apply_config(c)
	return d


func _art() -> void:
	_section("The vendored art slices into textures")
	var frames := DotFxDecalSheet.blood_frames()
	_check(frames.size() == DotFxDecalSheet.BLOOD_FRAMES, "six blood frames")
	_check(frames[0].get_width() == frames[0].get_height() and frames[0].get_width() == 256, "frames are 256 square")
	var names := DotFxDecalSheet.graffiti_names()
	_check(names.size() == 7, "seven graffiti images")
	var all := true
	for n in names:
		var t := DotFxDecalSheet.graffiti(n)
		all = all and t != null and t.get_width() == DotFxDecalSheet.GRAFFITI[n].size.x
	_check(all, "each graffiti texture has its rectangle's width")
	_check(DotFxDecalSheet.graffiti(&"nope") == null, "an unknown name is null")


func _blood() -> void:
	_section("Blood is pooled and capped, the oldest recycled")
	var cfg := DotFxDecalConfig.new()
	cfg.max_blood = 5
	var d := _make(cfg)
	var first := d.splatter(Vector3(0, 0, 0), Vector3.UP)
	_check(first != null and d.blood_count() == 1, "a splatter is spawned")
	_check(first.top_level and first.position.length() < 0.05, "it is placed in world space")
	for i in range(1, 12):
		d.splatter(Vector3(i, 0, 0), Vector3.UP)
	_check(d.blood_count() == 5, "never more than the cap: 12 spawned, 5 live")
	_check(d.pool_size() == 5, "no node was allocated past the cap")
	_check(d.get_child(0).get_child_count() == 5, "the scene holds exactly 5 nodes")
	var again := d.splatter(Vector3(99, 0, 0), Vector3.UP)
	_check(again == first or d.pool_size() == 5, "at the cap a node is reused")
	_check(again.position.distance_to(Vector3(99, 0, 0)) < 0.05, "the recycled node moved to the new hit")
	var wall := d.splatter(Vector3(0, 1, 0), Vector3(0, 0, 1))
	if wall is Decal:
		_check(wall.basis.y.is_equal_approx(Vector3(0, 0, 1)), "a Decal's projection axis is the surface normal")
		_check(wall.basis.is_orthonormal(), "the basis is a rotation")
	else:
		_check(wall.basis.z.is_equal_approx(Vector3(0, 0, 1)), "a quad faces along the normal")
		_check(wall.basis.is_orthonormal(), "the basis is a rotation")
	_check(d.describe().contains("5 blood"), "describe reports the count")
	d.queue_free()


func _fade() -> void:
	_section("Blood holds, fades, then returns to the pool")
	var cfg := DotFxDecalConfig.new()
	cfg.blood_hold = 10.0
	cfg.blood_fade = 4.0
	var d := _make(cfg)
	d.splatter(Vector3.ZERO, Vector3.UP)
	d.advance(9.0)
	_check(d.blood_count() == 1 and is_equal_approx(d.blood_alpha(0), 1.0), "fully visible during the hold")
	d.advance(3.0)
	_check(d.blood_count() == 1 and is_equal_approx(d.blood_alpha(0), 0.5), "half faded two seconds into a four-second fade")
	d.advance(2.0)
	_check(d.blood_count() == 0 and d.pool_size() == 1, "gone after the fade; the node is kept for reuse")
	var n := d.splatter(Vector3(1, 0, 0), Vector3.UP)
	_check(d.pool_size() == 1 and is_equal_approx(d.blood_alpha(0), 1.0) and n.visible, "the reused node is opaque again")
	cfg.blood_hold = 0.0
	d.advance(1000.0)
	_check(d.blood_count() == 1, "a hold of zero never fades")
	d.queue_free()


func _switches() -> void:
	_section("Gore, quality and mode switches")
	var cfg := DotFxDecalConfig.new()
	cfg.max_blood = 40
	var d := _make(cfg)
	for i in range(30):
		d.splatter(Vector3(i, 0, 0), Vector3.UP)
	_check(d.blood_count() == 30, "30 splatters under the full cap")
	cfg.quality = 1
	d.apply_config(cfg)
	_check(d.blood_count() == 10, "quality 1 trims to a quarter of the cap at once")
	cfg.quality = 0
	d.apply_config(cfg)
	_check(d.blood_count() == 0 and d.splatter(Vector3.ZERO, Vector3.UP) == null, "quality 0 draws no blood")
	cfg.quality = 3
	cfg.gore = false
	d.apply_config(cfg)
	_check(d.splatter(Vector3.ZERO, Vector3.UP) == null and d.blood_count() == 0, "gore off spawns nothing")
	cfg.gore = true
	d.apply_config(cfg)
	_check(d.splatter(Vector3.ZERO, Vector3.UP) != null, "gore on again spawns")
	cfg.mode = DotFxDecalConfig.Mode.MESH
	var m := _make(cfg)
	_check(not m.uses_decal_nodes() and m.splatter(Vector3.ZERO, Vector3.UP) is MeshInstance3D, "mesh mode builds quads")
	cfg.mode = DotFxDecalConfig.Mode.DECAL
	var dd := _make(cfg)
	_check(dd.uses_decal_nodes() and dd.splatter(Vector3.ZERO, Vector3.UP) is Decal, "decal mode builds Decal nodes")
	var q := _make(DotFxDecalConfig.new())
	q.config.quality = 0
	q.apply_config(q.config)
	var r := q.place({"image": "alien", "position": [0, 0, 0]})
	_check(r.ok and not q.get_child(1).visible, "quality 0 hides static decals too")
	for x in [d, m, dd, q]:
		x.queue_free()


func _placed() -> void:
	_section("Static decals come from data")
	var cfg := DotFxDecalConfig.new()
	cfg.max_static = 3
	var d := _make(cfg)
	var r := d.place({"id": "a", "image": "alien", "position": [1, 2, 3], "normal": [0, 0, 1], "width": 2.0})
	_check(r.ok and d.static_count() == 1, "a good document places one")
	var node: Node3D = r.value
	_check(node.position.distance_to(Vector3(1, 2, 3)) < 0.05, "at its position")
	var tex := DotFxDecalSheet.graffiti(&"alien")
	var expect_h := 2.0 * tex.get_height() / tex.get_width()
	var h: float = (node as Decal).size.z if node is Decal else ((node as MeshInstance3D).mesh as QuadMesh).size.y
	_check(is_equal_approx(h, expect_h), "height follows the image's aspect")
	_check(d.place({"id": "a", "image": "beast", "position": [0, 0, 0]}).code() == DotError.CODE_CONFLICT, "a duplicate id is refused")
	_check(d.place({"image": "zzz", "position": [0, 0, 0]}).code() == DotError.CODE_INVALID, "an unknown image is refused")
	_check(d.place({"image": "alien", "position": [0, 0]}).code() == DotError.CODE_INVALID, "a short position is refused")
	_check(d.place({"image": "alien", "position": [0, 0, 0], "normals": [0, 0, 1]}).code() == DotError.CODE_INVALID, "a misspelt key is refused")
	_check(d.place({"image": "alien", "position": [0, 0, 0], "width": 0}).code() == DotError.CODE_INVALID, "a zero width is refused")
	_check(d.static_count() == 1, "none of the bad ones was placed")
	var batch := d.place_all([{"image": "spider", "position": [0, 0, 0]}, {"image": "robot", "position": [1, 0, 0]}])
	_check(batch.ok and batch.value == 2 and d.static_count() == 3, "place_all places a list")
	_check(d.place({"image": "beast", "position": [0, 0, 0]}).code() == DotError.CODE_STATE, "past max_static is refused")
	_check(d.remove(&"a") and not d.remove(&"a") and d.static_count() == 2, "remove frees a slot, once")
	var before := d.static_count()
	var bad := d.place_all([{"image": "robot", "position": [0, 0, 0]}, {"image": "nope", "position": [0, 0, 0]}])
	_check(not bad.ok and bad.error.message.contains("decal 1") and d.static_count() == before, "a bad document in a list places none")
	d.clear_static()
	_check(d.static_count() == 0, "clear_static empties")
	d.queue_free()


func _config() -> void:
	_section("The config layers like every DotConfig")
	var cfg := DotFxDecalConfig.new()
	_check(cfg.gore and cfg.quality == 3 and cfg.max_blood == 96, "defaults")
	var unknown := cfg.apply_dictionary({"max_blood": 12, "gore": "false", "blood_hold": 3, "blood_colour": "#40ff40"}, "test")
	_check(cfg.max_blood == 12 and not cfg.gore and is_equal_approx(cfg.blood_hold, 3.0), "a dictionary overrides the defaults")
	_check(cfg.validate().ok, "the result validates")
	cfg.blood_colour = "banana"
	_check(not cfg.validate().ok, "a bad colour fails validation")
	cfg.blood_colour = "#40ff40"
	cfg.blood_size_min = 3.0
	_check(not cfg.validate().ok, "min above max fails validation")
	_check(cfg.env_prefix() == "DOT_FX_DECAL_" and cfg.cli_prefix() == "--decal-", "environment and command-line prefixes")
	OS.set_environment("DOT_FX_DECAL_MAX_BLOOD", "33")
	var envd := DotFxDecalConfig.new()
	envd.apply_env()
	OS.unset_environment("DOT_FX_DECAL_MAX_BLOOD")
	_check(envd.max_blood == 33, "the environment overrides")
	var file := "user://decal_cfg_test.json"
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string('{"quality": 1, "max_blood": 40}')
	f.close()
	var fd := DotFxDecalConfig.new()
	_check(fd.apply_json_file(file).ok and fd.quality == 1 and fd.max_blood == 40, "a JSON file overrides")
	_check(fd.effective_blood_cap() == 10, "the effective cap is a quarter of 40 at quality 1")
	var d := _make(fd)
	for i in range(30):
		d.splatter(Vector3.ZERO, Vector3.UP)
	_check(d.blood_count() == 10, "the layered config governs the pool")
	_check(cfg.unknown_keys.is_empty() and unknown.size() == 4, "four keys applied, none unknown")
	var tint := _make(envd)
	envd.blood_colour = "#40ff40"
	tint.apply_config(envd)
	var n := tint.splatter(Vector3.ZERO, Vector3.UP)
	var col: Color = n.modulate if n is Decal else (n.material_override as StandardMaterial3D).albedo_color
	_check(col.g > col.r, "the blood colour tints the splatter")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	d.queue_free()
	tint.queue_free()


func _section(title: String) -> void:
	_section_count += 1
	print("")
	print("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)
