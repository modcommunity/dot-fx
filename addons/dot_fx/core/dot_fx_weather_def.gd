class_name DotFxWeatherDef
extends RefCounted

## Falling weather as a document: what falls, where, how thick, how windy, what colour.
##
## [b]A document so a map can carry it.[/b] A map's author writes the precipitation volumes where
## the weather falls (a brush volume in a map source becomes one box here), the game hands the
## dictionary to [method parse], and the result is either a definition or a [DotResult] that
## says which key was wrong. Nothing here touches a renderer, so the same call validates a
## document on a server that will never draw it.
##
## [codeblock]
## {
##   "kind": "snow",                      # "snow" or "rain"
##   "volumes": [                         # axis-aligned boxes in world space; none = everywhere
##     {"min": [-10, 0, -10], "max": [10, 12, 10]},
##     {"center": [40, 5, 0], "size": [8, 10, 8]}
##   ],
##   "density": 1.0,                      # 0 to 4, 1 is the default thickness
##   "wind": [1.5, 0, 0],                 # metres per second added to the fall (optional)
##   "colour": "#ffffff",                 # html string or [r, g, b(, a)] (optional)
##   "sound": "amb_rain"                  # an id the game maps to its own sound (optional)
## }
## [/codeblock]
##
## [b]Unknown keys are refused[/b]: a misspelt "volumes" would otherwise read as "everywhere",
## and the weather would fall through a roof the mapper had covered.

const SNOW := &"snow"
const RAIN := &"rain"

## The most volumes one document may carry. Generous: a large map used about eighteen.
const MAX_VOLUMES := 256

const _KEYS := ["kind", "volumes", "density", "wind", "colour", "sound"]

## [constant SNOW] or [constant RAIN].
var kind: StringName = SNOW

## World-space boxes. Empty means everywhere around the camera.
var volumes: Array[AABB] = []

## Thickness multiplier, 0 to 4.
var density: float = 1.0

## Metres per second added to the fall.
var wind: Vector3 = Vector3.ZERO

## The particle colour; alpha is the peak opacity.
var colour: Color = Color(1, 1, 1, 1)

## An id the consumer maps to a sound. Empty for none; dot-fx ships no sounds.
var sound: StringName = &""


## A definition from a dictionary, or a failure naming the key. Succeeds with a
## [DotFxWeatherDef] as its value.
static func parse(doc: Dictionary) -> DotResult:
	for key in doc:
		if not (key is String) or not _KEYS.has(key):
			return DotResult.fail(DotError.CODE_INVALID, "weather: unknown key '%s'" % str(key))

	var d := DotFxWeatherDef.new()

	var k := str(doc.get("kind", ""))
	if k != "snow" and k != "rain":
		return DotResult.fail(DotError.CODE_INVALID, "weather: 'kind' must be \"snow\" or \"rain\", not '%s'" % k)
	d.kind = StringName(k)

	var dens: Variant = doc.get("density", 1.0)
	if not (dens is float or dens is int) or not is_finite(float(dens)) or float(dens) < 0.0 or float(dens) > 4.0:
		return DotResult.fail(DotError.CODE_INVALID, "weather: 'density' must be a number from 0 to 4")
	d.density = float(dens)

	if doc.has("wind"):
		var w := _vec3(doc["wind"])
		if w == null:
			return DotResult.fail(DotError.CODE_INVALID, "weather: 'wind' must be [x, y, z]")
		d.wind = w

	if doc.has("colour"):
		var c: Variant = _colour(doc["colour"])
		if c == null:
			return DotResult.fail(DotError.CODE_INVALID, "weather: 'colour' must be an html colour or [r, g, b(, a)]")
		d.colour = c

	if doc.has("sound"):
		if not (doc["sound"] is String or doc["sound"] is StringName):
			return DotResult.fail(DotError.CODE_INVALID, "weather: 'sound' must be a string")
		d.sound = StringName(str(doc["sound"]))

	if doc.has("volumes"):
		var vs: Variant = doc["volumes"]
		if not (vs is Array):
			return DotResult.fail(DotError.CODE_INVALID, "weather: 'volumes' must be an array")
		if vs.size() > MAX_VOLUMES:
			return DotResult.fail(DotError.CODE_INVALID, "weather: %d volumes, at most %d" % [vs.size(), MAX_VOLUMES])
		for i in range(vs.size()):
			var box: Variant = _box(vs[i])
			if box == null:
				return DotResult.fail(DotError.CODE_INVALID, "weather: volume %d needs min+max or center+size, finite and not inside out" % i)
			d.volumes.append(box)

	return DotResult.success(d)


## The document this was parsed from, so a definition built in code can be saved with a map.
func to_dict() -> Dictionary:
	var vs: Array = []
	for b in volumes:
		vs.append({"min": [b.position.x, b.position.y, b.position.z], "max": [b.end.x, b.end.y, b.end.z]})
	return {
		"kind": String(kind),
		"volumes": vs,
		"density": density,
		"wind": [wind.x, wind.y, wind.z],
		"colour": "#" + colour.to_html(colour.a < 1.0),
		"sound": String(sound),
	}


func describe() -> String:
	return "%s density %.2f, %s, wind %s%s" % [
		kind, density,
		"%d volumes" % volumes.size() if not volumes.is_empty() else "everywhere",
		wind, ", sound '%s'" % sound if sound != &"" else "",
	]


static func _vec3(v: Variant) -> Variant:
	if not (v is Array) or v.size() != 3:
		return null
	for n in v:
		if not (n is float or n is int) or not is_finite(float(n)):
			return null
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _colour(v: Variant) -> Variant:
	if v is String:
		if not Color.html_is_valid(v):
			return null
		return Color.html(v)
	if v is Array and (v.size() == 3 or v.size() == 4):
		for n in v:
			if not (n is float or n is int) or not is_finite(float(n)):
				return null
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() == 4 else 1.0)
	return null


static func _box(v: Variant) -> Variant:
	if not (v is Dictionary):
		return null
	var lo: Variant = null
	var hi: Variant = null
	if v.has("min") and v.has("max"):
		lo = _vec3(v["min"])
		hi = _vec3(v["max"])
	elif v.has("center") and v.has("size"):
		var c: Variant = _vec3(v["center"])
		var s: Variant = _vec3(v["size"])
		if c != null and s != null:
			lo = c - s * 0.5
			hi = c + s * 0.5
	if lo == null or hi == null:
		return null
	if hi.x <= lo.x or hi.y <= lo.y or hi.z <= lo.z:
		return null
	return AABB(lo, hi - lo)
