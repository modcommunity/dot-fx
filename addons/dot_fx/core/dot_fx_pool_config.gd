@tool
class_name DotFxPoolConfig
extends DotConfig

## Pooled effect nodes and the dynamic-light cap (`DOT_FX_POOL_*`, `--pool-*`).

## Most dynamic lights lit at once, across the muzzle flashes and [DotFxLightPool]. -1 picks a platform default, 0 allows none.
@export_range(-1, 64, 1) var max_lights: int = -1

## Lights built and drawn once under a loading cover by [method DotFxLightPool.prewarm], so the first real one pays no shader compile.
@export_range(0, 64, 1) var prewarm_lights: int = 4

## Mesh instances built by [method DotFxMeshPool.prewarm].
@export_range(0, 256, 1) var prewarm_meshes: int = 8


func env_prefix() -> String:
	return "DOT_FX_POOL_"


func cli_prefix() -> String:
	return "--pool-"


func validate() -> DotResult:
	if max_lights < -1:
		return DotResult.fail(DotError.CODE_INVALID, "max_lights cannot be below -1")
	return DotResult.success(null)


## The light cap after the platform: dynamic lights are what web and mobile renderers handle worst.
func effective_max_lights() -> int:
	if max_lights >= 0:
		return max_lights
	if DotPlatform.is_web():
		return 2
	if DotPlatform.is_mobile():
		return 3
	return 8
