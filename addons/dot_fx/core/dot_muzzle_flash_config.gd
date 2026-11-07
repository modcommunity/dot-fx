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

## Instances kept per flash that is not on the first-person gun (a bot's or another player's). One is enough: a shot restarts the flash, and 32 bots at 3 each was 96 particle nodes. The first-person gun keeps 3.
@export_range(1, 3, 1) var world_pool: int = 1

## A flash on someone else's gun is not drawn when the camera is farther than this many metres; 0 never culls.
@export_range(0.0, 500.0, 1.0) var max_distance: float = 120.0

## A flash on someone else's gun carries no light when the camera is farther than this many metres (it still draws); 0 never drops the light.
@export_range(0.0, 200.0, 1.0) var light_distance: float = 30.0
