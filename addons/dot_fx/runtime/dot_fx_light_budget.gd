class_name DotFxLightBudget
extends RefCounted

## One process-wide count of lit dynamic lights, so muzzle flashes and pooled lights share a cap.

const CHANNEL := "fx.light"

static var config := DotFxPoolConfig.new()

## Expiry tick (msec) of each light currently taking a slot.
static var _until: Array[int] = []
static var _refused := 0


## Takes a slot for [param seconds]; false when the cap is full, and the caller draws without a light.
static func try_take(seconds: float) -> bool:
	var now := Time.get_ticks_msec()
	_until = _until.filter(func(t: int) -> bool: return t > now)
	if _until.size() >= config.effective_max_lights():
		_refused += 1
		if _refused == 1 or _refused % 100 == 0:
			DotLog.debug(CHANNEL, "light cap reached", {"cap": config.effective_max_lights(), "refused": _refused})
		return false
	_until.append(now + maxi(1, roundi(seconds * 1000.0)))
	return true


## Lights holding a slot now.
static func live() -> int:
	var now := Time.get_ticks_msec()
	return _until.filter(func(t: int) -> bool: return t > now).size()


## Frees every slot and the refusal count, for a map change or a suite.
static func reset() -> void:
	_until.clear()
	_refused = 0
