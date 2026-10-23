@tool
class_name DotFxDecalConfig
extends DotConfig

## What a player and an operator get to say about [DotFxDecals]: the gore toggle, a quality
## tier, how many marks exist, how long blood lasts. Layered like every [DotConfig]
## (defaults < JSON < environment `DOT_FX_DECAL_*` < command line `--decal-*`).

## Mode of drawing. Auto uses Decal nodes where the renderer has them and quads where it does not.
enum Mode { AUTO, DECAL, MESH }

@export_group("Switches")

## Whether blood is drawn at all. The player-facing gore toggle; static decals are unaffected.
@export var gore: bool = true

## 0 draws no decals at all, 1 a quarter of the blood cap, 2 half, 3 all of it.
@export_range(0, 3, 1) var quality: int = 3

## Auto picks Decal nodes or quads from the renderer; the others force one.
@export_range(0, 2, 1) var mode: int = Mode.AUTO

@export_group("Blood")

## Most blood splatters alive at once, before the quality tier scales it. The oldest is recycled.
@export_range(0, 1024, 1) var max_blood: int = 96

## Seconds a splatter stays fully visible. Zero or less: it never fades, only recycles.
@export_range(0.0, 3600.0, 0.5) var blood_hold: float = 20.0

## Seconds spent fading out after the hold.
@export_range(0.0, 600.0, 0.5) var blood_fade: float = 8.0

## Smallest and largest splatter width in metres, picked at random per splatter.
@export_range(0.05, 10.0, 0.05) var blood_size_min: float = 0.8
@export_range(0.05, 10.0, 0.05) var blood_size_max: float = 1.6

## Html colour multiplied into the blood; a game with green blood sets it here.
@export var blood_colour: String = "#ffffff"

@export_group("Placement")

## How far a Decal projects into the surface, in metres. Too deep paints the far side of thin walls.
@export_range(0.05, 5.0, 0.05) var depth: float = 0.5

## Distance beyond which a Decal node fades out, in metres. Zero turns that off.
@export_range(0.0, 1000.0, 1.0) var fade_distance: float = 60.0

## Most static decals (graffiti and the like) that [method DotFxDecals.place] accepts.
@export_range(0, 4096, 1) var max_static: int = 512

## Seed for the random choice of frame, size and roll; zero seeds from the clock.
@export var seed_value: int = 0


func env_prefix() -> String:
	return "DOT_FX_DECAL_"


func cli_prefix() -> String:
	return "--decal-"


func validate() -> DotResult:
	if blood_size_min > blood_size_max:
		return DotResult.fail(DotError.CODE_INVALID, "blood_size_min is above blood_size_max")
	if not Color.html_is_valid(blood_colour):
		return DotResult.fail(DotError.CODE_INVALID, "blood_colour is not an html colour")
	return DotResult.success(null)


## Blood cap after the quality tier.
func effective_blood_cap() -> int:
	if quality <= 0:
		return 0
	return int(ceil(max_blood * [0.0, 0.25, 0.5, 1.0][clampi(quality, 0, 3)]))
