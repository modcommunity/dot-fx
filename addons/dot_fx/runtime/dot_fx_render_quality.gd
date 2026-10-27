class_name DotFxRenderQuality
extends Node

## Puts a [DotFxRenderConfig] on a viewport: anisotropic filtering, mip bias, anti-aliasing,
## render scale and FSR sharpening. One node per game, not a project setting, so a player's
## menu choice and an operator's cvar both reach a running view.

## Emitted after every apply, with the resolved values (see [method describe]).
signal applied(state: Dictionary)

## The viewport to change; null means the one this node sits in.
var viewport: Viewport

var _cfg := DotFxRenderConfig.new()
var _state := {}


## Applies [param cfg] now (a copy is not taken; change it and call [method apply] again).
func apply_config(cfg: DotFxRenderConfig) -> void:
	_cfg = cfg
	apply()


## Reads the environment (`DOT_FX_RENDER_*`) and command line (`--render-*`) over the defaults and applies them. Returns the result of the layering.
func load_layers(file_path: String = "") -> DotResult:
	var res := _cfg.load_layered(file_path)
	apply()
	return res


## Reads the settings keys `aniso`, `aa`, `mip_bias`, `render_scale` and `sharpness` from a dot-settings manager (duck-typed) and applies them.
func apply_settings(store: Object) -> void:
	if store != null:
		_cfg.anisotropy = store.get_int(&"aniso", _cfg.anisotropy)
		_cfg.aa = store.get_int(&"aa", _cfg.aa)
		_cfg.mip_bias = float(store.get_float(&"mip_bias", _cfg.mip_bias))
		_cfg.render_scale = float(store.get_float(&"render_scale", _cfg.render_scale))
		_cfg.sharpness = float(store.get_float(&"sharpness", _cfg.sharpness))
	apply()


## Applies the settings now and again whenever one of them changes.
func follow(store: Object) -> void:
	apply_settings(store)
	if store != null and not store.changed.is_connected(_on_changed):
		store.changed.connect(_on_changed.bind(store))


func _on_changed(key: StringName, _value: Variant, _why: StringName, store: Object) -> void:
	if key in [&"aniso", &"aa", &"mip_bias", &"render_scale", &"sharpness"]:
		apply_settings(store)


## Writes the config onto the viewport.
func apply() -> void:
	var vp := viewport if viewport != null else get_viewport()
	if vp == null:
		return
	var aa := _cfg.effective_aa()
	var msaa := Viewport.MSAA_DISABLED
	match aa:
		DotFxRenderConfig.Aa.MSAA_2X: msaa = Viewport.MSAA_2X
		DotFxRenderConfig.Aa.MSAA_4X: msaa = Viewport.MSAA_4X
		DotFxRenderConfig.Aa.MSAA_8X: msaa = Viewport.MSAA_8X
	var fxaa := aa == DotFxRenderConfig.Aa.FXAA or aa == DotFxRenderConfig.Aa.TAA_FXAA
	var taa := aa == DotFxRenderConfig.Aa.TAA or aa == DotFxRenderConfig.Aa.TAA_FXAA
	vp.anisotropic_filtering_level = _aniso_enum(_cfg.effective_anisotropy())
	vp.texture_mipmap_bias = _cfg.mip_bias
	vp.msaa_3d = msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = taa
	vp.scaling_3d_scale = _cfg.render_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if _cfg.render_scale < 0.999 and _has_fsr() else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = _cfg.sharpness
	_state = {"anisotropy": _cfg.effective_anisotropy(), "aa": aa, "mip_bias": _cfg.mip_bias, "render_scale": _cfg.render_scale}
	applied.emit(_state)


## FSR needs the Forward+ renderer; Mobile and Compatibility keep bilinear.
static func _has_fsr() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func _aniso_enum(taps: int) -> int:
	match taps:
		2: return Viewport.ANISOTROPY_2X
		4: return Viewport.ANISOTROPY_4X
		8: return Viewport.ANISOTROPY_8X
		16: return Viewport.ANISOTROPY_16X
	return Viewport.ANISOTROPY_DISABLED


## One line of what is applied.
func describe() -> String:
	return "render quality: aniso %dx, aa %d, mip bias %.2f, scale %.2f" % [_state.get("anisotropy", 0), _state.get("aa", 0), _state.get("mip_bias", 0.0), _state.get("render_scale", 1.0)]
