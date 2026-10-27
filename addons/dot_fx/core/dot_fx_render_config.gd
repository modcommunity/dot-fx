@tool
class_name DotFxRenderConfig
extends DotConfig

## Texture and edge quality of the 3D view: anisotropic filtering, anti-aliasing, mip bias and
## sharpening. Layered like every [DotConfig] (defaults < JSON < environment `DOT_FX_RENDER_*`
## < command line `--render-*`). Applied by [DotFxRenderQuality].

## Anti-aliasing choices. TAA and FXAA are shader passes (cheap, soft); MSAA is geometry edges only.
enum Aa { AUTO, OFF, FXAA, MSAA_2X, MSAA_4X, MSAA_8X, TAA, TAA_FXAA }

@export_group("Textures")

## Anisotropic filtering: 0 (off), 2, 4, 8 or 16 taps. -1 picks the platform: 16 on desktop, 4 on mobile and the web.
## Grazing-angle floors and walls stay sharp with it; Godot's own default is 2x.
@export_range(-1, 16, 1) var anisotropy: int = -1

## Added to the mip level chosen per pixel, in levels: negative is sharper (and shimmers), positive blurrier. Zero is neutral.
@export_range(-2.0, 2.0, 0.05) var mip_bias: float = 0.0

@export_group("Edges")

## Which anti-aliasing runs. AUTO is MSAA 4x on desktop, FXAA on mobile and the web.
@export_range(0, 7, 1) var aa: int = Aa.AUTO

## FSR sharpening, 0 (sharpest) to 2 (softest); only acts when [member render_scale] is under 1.
@export_range(0.0, 2.0, 0.05) var sharpness: float = 0.2

## 3D resolution scale; the menu's `render_scale`. Below 1 uses FSR so the image is rebuilt rather than smeared.
@export_range(0.25, 2.0, 0.05) var render_scale: float = 1.0


func env_prefix() -> String:
	return "DOT_FX_RENDER_"


func cli_prefix() -> String:
	return "--render-"


## The anisotropy that will be applied: the platform's pick for -1, else the value snapped down to 0, 2, 4, 8 or 16.
func effective_anisotropy() -> int:
	if anisotropy < 0:
		return 16 if DotPlatform.is_desktop() else 4
	for tap in [16, 8, 4, 2]:
		if anisotropy >= tap:
			return tap
	return 0


## The anti-aliasing that will be applied, with AUTO resolved.
func effective_aa() -> int:
	if aa != Aa.AUTO:
		return aa
	return Aa.MSAA_4X if DotPlatform.is_desktop() else Aa.FXAA
