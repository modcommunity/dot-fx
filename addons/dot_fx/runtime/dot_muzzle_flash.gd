class_name DotMuzzleFlash
extends Node3D

## A pooled muzzle flash from Binbun's CC0 pack. Parent it to a weapon's muzzle point (view model or world model) and call [method fire] per shot; it builds its instances once and never allocates after.

enum Size { NONE, VERY_SMALL, SMALL, MEDIUM, BIG }

const ROOT := "res://addons/dot_fx/art/binbun_muzzle/BinbunVFX/muzzle_flash/effects/"
const FOLDERS := {
	Size.VERY_SMALL: "wide_flash/wide_flash_",
	Size.SMALL: "short_flash/short_flash_",
	Size.MEDIUM: "muzzle_flash/muzzle_flash_",
	Size.BIG: "big_flash/big_flash_",
}
const VARIANTS := 6
const POOL := 3
## Weapon category to size. A profile's `extra: {muzzle_flash: big}` overrides it.
const CATEGORY_SIZE := {
	"pistol": Size.VERY_SMALL, "revolver": Size.SMALL, "smg": Size.SMALL, "pdw": Size.SMALL,
	"rifle": Size.MEDIUM, "ar": Size.MEDIUM, "carbine": Size.SMALL, "lmg": Size.MEDIUM,
	"shotgun": Size.BIG, "sniper": Size.BIG, "dmr": Size.MEDIUM, "magnum": Size.MEDIUM,
}
const NAMES := {"none": Size.NONE, "very_small": Size.VERY_SMALL, "small": Size.SMALL, "medium": Size.MEDIUM, "big": Size.BIG}

## Shown at the muzzle of the first-person view model: fades near the camera.
@export var first_person: bool = false
@export var size: Size = Size.SMALL
@export var config: DotMuzzleFlashConfig = null

## 1 to 6 picks that variant of the size; 0 picks one from the node path, so neighbouring guns differ.
@export_range(0, 6) var variant: int = 0

## Flash scenes already loaded, kept for the process so a first shot never reads one from disk.
static var _scenes := {}

## The frame an instance was last built in, by any flash.
static var _last_build_frame := -1

var _pool: Array[Node3D] = []
var _next := 0
var _built := false
var _scene_ready := false
var _chosen: PackedScene = null


## The flash size for a weapon: `extra.muzzle_flash` (a size name or "none"), else the category, else small. [param suppressed] gives none.
static func size_for(category: String, extra: Dictionary = {}, suppressed: bool = false) -> Size:
	if suppressed:
		return Size.NONE
	var named := str(extra.get("muzzle_flash", "")).to_lower()
	if NAMES.has(named):
		return NAMES[named]
	return CATEGORY_SIZE.get(category.to_lower(), Size.SMALL)


## Whether flashes can draw here at all: not a headless server.
static func available() -> bool:
	return not DotPlatform.is_headless()


## Play one flash. Returns false when it was skipped (off, headless, size none).
func fire() -> bool:
	if not _ensure_built():
		return false
	var node := _pool[_next]
	_next = (_next + 1) % _pool.size()
	node.call("play")
	return true


## Whether the pool is complete (or can never be), so [method fire] builds nothing.
func is_ready() -> bool:
	return _pool.size() >= POOL or (_scene_ready and _chosen == null) or not available() or size == Size.NONE


func _ready() -> void:
	# Build the pool a node a frame once attached, so the first shot finds it done and no frame pays for all of it.
	if available() and size != Size.NONE:
		set_process(true)
	else:
		set_process(false)


func _process(_delta: float) -> void:
	if _pool.size() >= POOL or not _prepare():
		set_process(false)
		return
	# One instance per frame across all flashes, or eight warming at once would be one big hitch.
	var frame := Engine.get_process_frames()
	if frame == _last_build_frame:
		return
	_last_build_frame = frame
	_add_one()


## Resolves the config, size and scene once; false when this flash can never draw.
func _prepare() -> bool:
	if _scene_ready:
		return _chosen != null
	_scene_ready = true
	if config == null:
		config = DotMuzzleFlashConfig.new()
	if not available() or config.quality <= 0 or size == Size.NONE:
		return false
	var s: int = mini(int(size), config.max_size)
	var pick := variant if variant > 0 else (hash(get_path()) % VARIANTS) + 1
	_chosen = _scene("%s%s%02d.tscn" % [ROOT, FOLDERS[s], pick])
	return _chosen != null


func _add_one() -> void:
	var mode := 2 if config.quality == 1 else (1 if config.quality == 2 else 0)
	var node := _chosen.instantiate()
	node.set("autoplay", false)
	node.set("one_shot", true)
	node.set("alpha_mode", mode)
	var fade := first_person and config.first_person_fade > 0.0
	node.set("proximity_fade", fade)
	if fade:
		node.set("proximity_fade_distance", config.first_person_fade)
	node.set("light_enable", config.quality >= 2 and config.light_scale > 0.0)
	node.set("light_energy", float(node.get("light_energy")) * config.light_scale)
	add_child(node)
	_pool.append(node)
	_built = _pool.size() >= POOL


## Finishes the pool at once (a shot before the frames did); false when nothing can draw.
func _ensure_built() -> bool:
	if not _prepare():
		return false
	while _pool.size() < POOL:
		_add_one()
	return true


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]


## Loads and pins flash scenes until [param budget_ms] is spent; true once all 24 are pinned. Call it once a frame under a loading cover rather than paying every load in one frame.
static func pin_scenes(budget_ms: int) -> bool:
	var until := Time.get_ticks_msec() + budget_ms
	for s: int in FOLDERS:
		for v in range(1, VARIANTS + 1):
			var path := "%s%s%02d.tscn" % [ROOT, FOLDERS[s], v]
			if _scenes.has(path):
				continue
			if Time.get_ticks_msec() >= until:
				return false
			_scene(path)
	return true


## Pins every flash scene (see [method pin_scenes]), then draws one flash of each size once under [param parent] (put it in view, under the loading cover), so the first shot of a match costs no scene load, shader compile or light. Returns the rig; free it a few frames later. Null when flashes cannot draw here.
static func prewarm(parent: Node3D, config: DotMuzzleFlashConfig = null) -> Node3D:
	if parent == null or not available():
		return null
	var rig := Node3D.new()
	rig.name = "MuzzleFlashPrewarm"
	parent.add_child(rig)
	pin_scenes(1 << 30)
	for s: int in FOLDERS:
		var flash := DotMuzzleFlash.new()
		flash.size = s as Size
		flash.variant = 1
		flash.config = config
		rig.add_child(flash)
		flash.fire()
	return rig
