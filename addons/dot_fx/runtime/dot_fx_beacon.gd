class_name DotFxBeacon
extends Node3D

## A marker that says WHERE somebody is: a ring at their feet that sends out a ripple once a
## period, a thin column above them drawn through everything, and a positional ping.
##
## [b]Seven games had their own copy of this[/b], three of them byte for byte, and every one
## for the same two jobs: an administrator's `beacon`, and a game rule that gives the last few
## players of a side away (the hiding games' "last one standing"). It is one node now, and a
## game sets the colour, the period and the column's height and moves it.
##
## [b]Drawn from one replicated flag on every client; nothing about the picture travels.[/b]
## The server decides who is marked and each client draws its own ripple, because two screens
## a quarter of a second apart in a ripple is not something anybody can see, and a phase on
## the wire would be a message a second per marked player for nothing.
##
## [b]The column is the half that matters.[/b] A ring alone says where somebody is only to
## somebody who can already see their feet; a column with no depth test says it from anywhere,
## through walls and floors. The ring keeps its depth test: a ring showing through a floor
## would put the player on top of it when they are under it.
##
## [b]No column on your own marker.[/b] Set [member local_view] for the marked player's own
## view: a first-person camera stands inside the column, and a no-depth-test cylinder seen from
## inside is a translucent smear over the whole screen. They still see the ring and hear the
## ping, which is how they know.
##
## [b]The ping is synthesised unless a stream is given[/b], so a game that ships no sound
## still has one. A tenth of a second of a falling sine on an [AudioStreamPlayer3D], so it
## comes from where the player is: the whole of a beacon's job is to say where, and a flat
## ping says only that somebody somewhere is marked.
##
## [b]Top level[/b], so it is placed where the player is DRAWN rather than inheriting the
## body's per-tick transform: a ring that stepped at the tick rate under a smoothly moving
## camera reads as the ring juddering. The game calls [method advance] once a frame and sets
## [code]global_position[/code] to where it drew the player.

## Seconds between ripples, and between pings.
@export_range(0.1, 10.0, 0.05) var period: float = 1.0

## How far a ripple spreads before it has faded, as a multiple of the ring.
@export_range(1.0, 10.0, 0.1) var ripple_scale: float = 3.5

## The marker's colour. Magenta by default: the one colour least likely to be any game's sky,
## floor or team.
@export var colour: Color = Color(0.98, 0.22, 0.86)

## The column's length, in metres. Tall enough to clear what stands between the marked player
## and the furthest place anybody watches from.
@export_range(0.0, 500.0, 0.5) var column_height: float = 30.0

## Where the column starts above the feet, so it marks the player rather than hiding them.
@export_range(0.0, 10.0, 0.05) var column_base: float = 2.2

## The ring's outer radius, in metres.
@export_range(0.1, 10.0, 0.05) var ring_radius: float = 0.8

## Metres the ping carries. Past this a ping is noise from nowhere.
@export_range(0.0, 2000.0, 1.0) var ping_range: float = 180.0

## The ping, or null to synthesise one.
@export var ping_stream: AudioStream = null

## Volume of the ping, in decibels.
@export_range(-60.0, 12.0, 0.5) var ping_volume_db: float = 0.0

## The bus the ping plays on.
@export var ping_bus: StringName = &"Master"

const PING_HZ := 880.0
const PING_SEC := 0.12
const PING_MIX_RATE := 22050

## Whether this is the marked player's own view. Hides the column; see the class notes.
var local_view: bool = false:
	set(value):
		local_view = value
		if _column != null:
			_column.visible = not value

## Pings played since this marker was built. For a check: the rate is the promise.
var pings: int = 0

var _ring: MeshInstance3D = null
var _ripple: MeshInstance3D = null
var _column: MeshInstance3D = null
var _ripple_material: StandardMaterial3D = null
var _ring_material: StandardMaterial3D = null
var _column_material: StandardMaterial3D = null
var _voice: AudioStreamPlayer3D = null
var _built: bool = false

## Seconds into the current period. Starts at the end of one, so the first advance pings:
## somebody turning a beacon on should hear it start, not a second later.
var _phase: float = -1.0


func _init() -> void:
	top_level = true


func _ready() -> void:
	build()


## Builds the meshes and the voice from the current settings. Called on entering the tree;
## call it again after changing [member colour], [member column_height] or [member ring_radius].
func build() -> void:
	for child in [_ring, _ripple, _column, _voice]:
		if child != null:
			(child as Node).queue_free()

	var inner := ring_radius * 0.775
	_ring_material = _material(0.95, false)
	_ring = _torus(inner, ring_radius, _ring_material)
	_ring.name = "Ring"
	add_child(_ring)

	_ripple_material = _material(0.8, false)
	_ripple = _torus(ring_radius * 0.825, ring_radius * 0.95, _ripple_material)
	_ripple.name = "Ripple"
	add_child(_ripple)

	_column_material = _material(0.5, true)
	_column = MeshInstance3D.new()
	_column.name = "Column"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.09
	cylinder.bottom_radius = 0.09
	cylinder.height = maxf(column_height, 0.01)
	cylinder.radial_segments = 8
	cylinder.rings = 1
	_column.mesh = cylinder
	_column.material_override = _column_material
	_column.position = Vector3(0.0, column_height * 0.5 + column_base, 0.0)
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = not local_view and column_height > 0.0
	add_child(_column)

	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Ping"
	_voice.stream = ping_stream if ping_stream != null else synth_ping()
	_voice.unit_size = 20.0
	_voice.max_distance = ping_range
	_voice.volume_db = ping_volume_db
	_voice.bus = ping_bus
	_voice.position = Vector3(0.0, 1.0, 0.0)
	add_child(_voice)

	if _phase < 0.0:
		_phase = period

	_built = true


## Moves the time on by [param delta], redraws, and pings when a new ripple starts. Returns
## whether it pinged.
func advance(delta: float) -> bool:
	if not _built:
		build()

	_phase += maxf(delta, 0.0)
	var pinged := false

	if _phase >= period:
		_phase = fmod(_phase, period)
		pinged = true
		pings += 1

		if _voice.is_inside_tree():
			_voice.play()

	var t := _phase / period
	var spread := lerpf(1.0, ripple_scale, t)
	_ripple.scale = Vector3(spread, 0.25, spread)
	_ripple_material.albedo_color.a = 0.8 * (1.0 - t) * (1.0 - t)

	# The ring breathes with the ripple rather than holding still, so a marker seen from far
	# away — a few pixels of ring — still reads as something alive.
	_ring_material.albedo_color.a = lerpf(0.95, 0.55, t)

	return pinged


## Whether the column is being drawn. For a check.
func column_shown() -> bool:
	return _column != null and _column.visible


func _torus(inner: float, outer: float, material: StandardMaterial3D) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flattened to a band. A torus's tube is round, and a round tube at a player's feet reads
	# as a lifebuoy rather than a mark.
	mesh.scale = Vector3(1.0, 0.25, 1.0)
	mesh.position = Vector3(0.0, 0.06, 0.0)
	return mesh


func _material(alpha: float, through_walls: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	material.no_depth_test = through_walls
	return material


## A short falling sine, as sixteen-bit PCM.
##
## Falling rather than flat, and an octave under the tone a hit marker would use, so it is
## heard as "there" rather than as "I hit something" when both happen at once.
static func synth_ping() -> AudioStreamWAV:
	var frames := int(PING_SEC * PING_MIX_RATE)
	var data := PackedByteArray()
	var _sized := data.resize(frames * 2)
	var angle := 0.0

	for i in range(frames):
		var t := float(i) / float(frames)
		angle += TAU * PING_HZ * lerpf(1.0, 0.7, t) / float(PING_MIX_RATE)
		# A few milliseconds of attack so it does not click, then a quadratic decay.
		var envelope := minf(1.0, t * 30.0) * (1.0 - t) * (1.0 - t)
		data.encode_s16(i * 2, int(sin(angle) * envelope * 0.6 * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = PING_MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func describe() -> Dictionary:
	return {
		"period": period,
		"colour": colour.to_html(false),
		"column": column_shown(),
		"pings": pings,
	}
