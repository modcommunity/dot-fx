extends Node

## Headless checks for [DotFxRenderQuality]: platform picks, snapping, and what lands on a viewport.

const SECTIONS := 3
const CHECKS := 17

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_config()
	_viewport()
	_store()
	print("")
	print("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		print("ERROR: %d sections and %d checks ran, %d and %d expected" % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _config() -> void:
	_section("Config picks and snaps")
	var c := DotFxRenderConfig.new()
	_check(c.effective_anisotropy() == (16 if DotPlatform.is_desktop() else 4), "auto anisotropy follows the platform")
	_check(c.effective_aa() == (DotFxRenderConfig.Aa.MSAA_4X if DotPlatform.is_desktop() else DotFxRenderConfig.Aa.FXAA), "auto aa follows the platform")
	c.anisotropy = 7
	_check(c.effective_anisotropy() == 4, "7 snaps down to 4")
	c.anisotropy = 16
	_check(c.effective_anisotropy() == 16, "16 stays")
	c.anisotropy = 1
	_check(c.effective_anisotropy() == 0, "1 is off")
	c.anisotropy = 0
	_check(c.effective_anisotropy() == 0, "0 is off")
	c.aa = DotFxRenderConfig.Aa.TAA
	_check(c.effective_aa() == DotFxRenderConfig.Aa.TAA, "an explicit aa is kept")


func _viewport() -> void:
	_section("It lands on the viewport")
	var q := DotFxRenderQuality.new()
	add_child(q)
	var c := DotFxRenderConfig.new()
	c.anisotropy = 8
	c.aa = DotFxRenderConfig.Aa.MSAA_2X
	c.mip_bias = -0.5
	q.apply_config(c)
	var vp := get_viewport()
	_check(vp.anisotropic_filtering_level == Viewport.ANISOTROPY_8X, "8x")
	_check(vp.msaa_3d == Viewport.MSAA_2X, "msaa 2x")
	_check(is_equal_approx(vp.texture_mipmap_bias, -0.5), "mip bias")
	c.aa = DotFxRenderConfig.Aa.TAA_FXAA
	q.apply()
	_check(vp.use_taa and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and vp.msaa_3d == Viewport.MSAA_DISABLED, "taa+fxaa clears msaa")
	c.render_scale = 0.7
	q.apply()
	_check(vp.scaling_3d_mode == (Viewport.SCALING_3D_MODE_FSR if DotFxRenderQuality._has_fsr() else Viewport.SCALING_3D_MODE_BILINEAR), "scale under 1 uses FSR where the renderer has it")
	c.render_scale = 1.0
	q.apply()
	_check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "scale 1 is native")
	_check(q.describe().contains("aniso 8x"), "describe")


func _store() -> void:
	_section("A settings store drives it")
	var s := _Store.new()
	s.values = {&"aniso": 2, &"aa": DotFxRenderConfig.Aa.FXAA}
	var q := DotFxRenderQuality.new()
	add_child(q)
	q.follow(s)
	_check(get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_2X, "read at follow")
	s.values[&"aniso"] = 16
	s.changed.emit(&"aniso", 16, &"user")
	_check(get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_16X, "follows a change")
	s.values[&"aniso"] = 0
	s.changed.emit(&"gore", true, &"user")
	_check(get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_16X, "ignores other keys")


class _Store extends RefCounted:
	signal changed(key: StringName, value: Variant, why: StringName)
	var values := {}

	func get_int(key: StringName, d: int) -> int:
		return int(values.get(key, d))

	func get_float(key: StringName, d: float) -> float:
		return float(values.get(key, d))


func _section(title: String) -> void:
	_section_count += 1
	print("-- %s" % title)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: %s" % what)
