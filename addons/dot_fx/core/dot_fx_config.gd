@tool
class_name DotFxConfig
extends DotConfig

## What a player and an operator get to say about effects.
##
## Three of these are accessibility settings rather than performance ones, and they are
## the ones that matter most: [member shake_scale], [member allow_flashes] and
## [member flash_cap]. A game that cannot turn its camera shake off is a game some people
## cannot play, and a full-screen flash at the wrong frequency is a hazard rather than a
## style.

@export_group("Quality")

## 0 lowest, 3 highest. Gates which effects exist at all.
##
## [b]Gating existence rather than detail is deliberate.[/b] Halving the particle count on
## the effect that is killing a frame does not save the frame; not spawning it does. A
## "low" tier should be missing its most expensive effects, not running all of them badly.
@export_range(0, 3, 1) var quality: int = 3

## Effect cost allowed to start in one frame. Zero is unlimited.
##
## What it buys is that a grenade landing in a crowd cannot cost more than a frame has.
## Over budget, the lowest-priority requests are dropped — which is safe for exactly one
## reason, and it is the reason this addon is built the way it is: **an effect never
## changes the simulation**, so a client that skipped one and a client that did not are
## still playing the same game.
@export_range(0, 10000, 1) var frame_budget: int = 60

## How many decals may exist. The oldest is recycled.
##
## Bounded, because an unbounded decal list is the leak every shooter has shipped at least
## once: it grows with the round rather than with the player, so it is invisible in
## testing and fatal at minute forty.
@export_range(0, 4096, 1) var max_decals: int = 256

## How many spawned effects may exist at once, across every id.
@export_range(1, 4096, 1) var max_instances: int = 256

@export_group("Accessibility")

## Multiplies every shake. Zero turns it off entirely.
##
## Camera shake is one of the commonest causes of simulator sickness. This must be able to
## reach zero, must be a player setting rather than a developer one, and is read every
## frame so that turning it off takes effect immediately rather than at the next map.
@export_range(0.0, 2.0, 0.05) var shake_scale: float = 1.0

## Whether full-screen flashes are drawn at all.
##
## [b]A player-facing off switch, and not optional.[/b] The accepted guidance on
## photosensitivity is no more than three general flashes in any one second, and no
## large-area red flashes at all; a game that cannot honour a player asking for none has
## no answer for somebody it could actually harm.
@export var allow_flashes: bool = true

## The hardest a flash may be, whatever a definition asks for.
@export_range(0.0, 1.0, 0.01) var flash_cap: float = 0.6

## The most flashes started in one second, whatever is asked for.
##
## Enforced in the manager. Three is the published guidance and is the default here.
@export_range(0, 60, 1) var flashes_per_second: int = 3

@export_group("Culling")

## Multiplies every definition's cull distance.
@export_range(0.1, 4.0, 0.05) var distance_scale: float = 1.0

## Whether to skip effects behind the listener as well as far from it.
##
## Off by default: the saving is real and the failure is worse than the saving. A player
## who turns round after an explosion behind them should see the smoke.
@export var cull_behind: bool = false


func env_prefix() -> String:
	return "DOT_FX_"


func cli_prefix() -> String:
	return "--fx-"


func validate() -> DotResult:
	if quality < 0 or quality > 3:
		return DotResult.fail(DotError.CODE_INVALID, "quality is a tier from 0 to 3")
	return DotResult.success(null)
