extends RefCounted

## dot-fx's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotFxBeacon, the marker that says where somebody is.
# 3: DotFxBeacon.ping_enabled, for a game that plays the ping through its own catalogue.
# 4: DotFxBeacon.resize(), ring radius and column height applied to a beacon that exists.
# 5: DotFxWeather and DotFxWeatherDef, snow and rain inside volumes; DotFxConfig.weather_quality and weather_density.
# 6: DotFxDecals, DotFxDecalConfig and DotFxDecalSheet: pooled blood splatters and data-placed static decals.
# 7: DotFxBlood, splatter behind a hit or under a victim (rays, settings, server splat rate limit).
const LEVEL := 7
const OLDEST := 1
