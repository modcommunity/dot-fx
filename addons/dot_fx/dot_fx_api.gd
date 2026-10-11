extends RefCounted

## dot-fx's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotFxBeacon, the marker that says where somebody is.
# 3: DotFxBeacon.ping_enabled, for a game that plays the ping through its own catalogue.
const LEVEL := 3
const OLDEST := 1
