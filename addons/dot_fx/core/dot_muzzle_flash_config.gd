@tool
class_name DotMuzzleFlashConfig
extends DotConfig

## Muzzle flash settings, layered like every [DotConfig] (`DOT_MUZZLE_*`, `--muzzle-*`).

## 0 off, 1 hard-edged and no light (cheapest, web and mobile), 2 dithered with a light, 3 smooth with a light.
@export_range(0, 3, 1) var quality: int = 3

## Light energy multiplier; 0 drops the flash light on every tier.
@export_range(0.0, 2.0, 0.05) var light_scale: float = 1.0

## Fade a first-person flash out within this many metres of the camera, so a mesh never fills the view.
@export_range(0.0, 3.0, 0.05) var first_person_fade: float = 0.6

## Seconds a flash shows, however long the art runs: a muzzle flash is a frame or three, and the art's own 0.2 s read as stuck on automatic fire.
@export_range(0.02, 0.2, 0.005) var lifetime: float = 0.05

## Largest flash allowed: 1 very small, 2 small, 3 medium, 4 big.
@export_range(1, 4, 1) var max_size: int = 4


func env_prefix() -> String:
	return "DOT_MUZZLE_"


func cli_prefix() -> String:
	return "--muzzle-"
