@tool
class_name DotFxDef
extends Resource

## One visual effect, as a document that names a scene and never loads one.
##
## [b]The invariant this whole addon rests on: an effect never changes the
## simulation.[/b] It is a picture of something that already happened. That single
## property is what makes every other decision here safe — a budget may drop one, a
## quality tier may refuse one, a distance cull may skip one, and a client that has not
## downloaded the content yet simply does not see it, and in none of those cases do two
## machines disagree about anything that matters.
##
## The moment an effect is allowed to deal damage, move a body or decide a hit, that
## property is gone and every one of those mechanisms becomes a desync. dot-combat owns
## damage; dot-effects owns what happens over time; this owns what it looks like.

enum Kind {
	## A scene instanced at a transform and freed when it is done. Particles, a muzzle
	## flash, a shatter.
	SPAWNED,
	## A mark left on the world. Bounded by a ring; see [DotFxManager].
	DECAL,
	## A full-screen tint or flash. See [member flash_peak] before raising it.
	SCREEN,
	## Camera shake. Computed as a value the game applies.
	SHAKE,
	## A trail or beam between two points.
	BEAM,
}

## The id a game asks for. Unique in a catalogue.
@export var id: StringName = &""

## The scene's path, as a string.
##
## A string rather than a [PackedScene] for the reason dot-props names a prop's script by
## PATH: a game delivered as a content pack is mounted at runtime and **a mounted pack's
## `class_name` globals are not registered in the host**, so a catalogue that preloads
## cannot describe delivered content — and a catalogue holding loaded scenes cannot be
## validated on a server that has none of them.
@export var scene_path: String = ""

@export var kind: Kind = Kind.SPAWNED

## Milliseconds before it is taken back, whatever it thinks it is doing.
##
## [b]A hard ceiling, not a hint.[/b] One effect that forgets to free itself is a leak
## that looks like a slow memory problem in the game rather than a bug in one particle
## system, and the thing that finds it is the ceiling firing rather than anybody noticing.
@export_range(1, 600000, 1) var lifetime_ms: int = 2000

## What it costs against the per-frame budget. Arbitrary units; be consistent.
##
## A muzzle flash is 1 and a building collapsing is 50. What the numbers mean matters far
## less than that they are comparable, because the budget is a ranking under pressure.
@export_range(0, 1000, 1) var cost: int = 1

## Higher survives when the budget is spent.
@export_range(0, 100, 1) var priority: int = 50

## The lowest quality tier at which this effect appears at all.
##
## [b]Gating existence rather than only detail is the point.[/b] Halving a particle count
## on the effect that is killing the frame does not save the frame; not spawning it does.
## A game's "low" tier should be missing its most expensive effects, not running all of
## them badly.
@export_range(0, 3, 1) var min_quality: int = 0

## Metres past which it is not spawned. Zero is never culled.
@export_range(0.0, 100000.0, 1.0, "or_greater") var max_distance: float = 120.0

## How many of this id may exist at once. Zero is no limit.
@export_range(0, 256, 1) var max_concurrent: int = 0

@export var tags: Array[StringName] = []

@export_group("Shake")

## Trauma added, 0..1. Squared before it is applied; see [DotFxShake].
@export_range(0.0, 1.0, 0.01) var shake_trauma: float = 0.0

@export_group("Screen")

## Peak opacity of a full-screen flash, 0..1.
##
## [b]Read [member DotFxConfig.allow_flashes] before raising this.[/b] A full-screen
## flash at high frequency is a photosensitivity hazard, not a style choice: the accepted
## guidance is no more than three general flashes a second and no large-area red flashes
## at all. The manager enforces a rate limit and a player-facing off switch, and both of
## those are more important than any number set here.
@export_range(0.0, 1.0, 0.01) var flash_peak: float = 0.3

@export var flash_colour: Color = Color(1, 1, 1, 1)

## Milliseconds the flash takes to fall back to nothing.
@export_range(1, 10000, 1) var flash_decay_ms: int = 250


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "an effect with no id")
	if kind == Kind.SPAWNED or kind == Kind.DECAL or kind == Kind.BEAM:
		if scene_path.is_empty():
			return DotResult.fail(
				DotError.CODE_INVALID, "'%s' is a scene effect that names no scene" % id
			)
	if kind == Kind.SHAKE and shake_trauma <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' is a shake with no trauma in it" % id,
			"which is an effect that is guaranteed to do nothing"
		)
	if kind == Kind.SCREEN and flash_peak <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID, "'%s' is a screen effect with no opacity" % id
		)
	return DotResult.success(null)


func describe_line() -> String:
	return "%-24s %-8s cost %-3d prio %-3d q>=%d  %s" % [
		String(id),
		["spawned", "decal", "screen", "shake", "beam"][kind],
		cost,
		priority,
		min_quality,
		scene_path,
	]
