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

var _pool: Array[Node3D] = []
var _next := 0
var _built := false


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


func _ensure_built() -> bool:
	if _built:
		return not _pool.is_empty()
	_built = true
	if config == null:
		config = DotMuzzleFlashConfig.new()
	if not available() or config.quality <= 0 or size == Size.NONE:
		return false
	var s: int = mini(int(size), config.max_size)
	var variant := (hash(get_path()) % VARIANTS) + 1
	var scene := load("%s%s%02d.tscn" % [ROOT, FOLDERS[s], variant]) as PackedScene
	if scene == null:
		return false
	var mode := 2 if config.quality == 1 else (1 if config.quality == 2 else 0)
	for i in POOL:
		var node := scene.instantiate()
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
	return true
