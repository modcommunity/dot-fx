# dot-fx

Visual effects as documents: pooled, budgeted, tiered, and safe to drop. A game supplies the scenes; dot-fx decides whether, where and how many, and never changes the simulation.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_fx/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/weather.md](docs/weather.md) | touching `DotFxWeather`: why a shader and not particles, how volumes clip, the knobs |
| [docs/design.md](docs/design.md) | changing anything: the invariant, the accessibility settings, how shake is computed, paths not scenes, explicit `advance()`, the pool, refusal reasons, the beacon, what is deliberately not here |

## Layout

| Path | What |
| --- | --- |
| `core/dot_fx_def.gd` | `DotFxDef`: one effect as a document naming a scene by path; `Kind` is SPAWNED, DECAL, SCREEN, SHAKE, BEAM |
| `core/dot_fx_catalogue.gd` | `DotFxCatalogue`: all of them; `validate()` needs no renderer and no files, `missing_scenes()` |
| `core/dot_fx_shake.gd` | `DotFxShake`: trauma in, displacement out; touches no camera |
| `core/dot_fx_config.gd` | `DotFxConfig`: quality, budgets, `shake_scale`, `allow_flashes`, `flash_cap`, `flashes_per_second` (a `DotConfig`) |
| `runtime/dot_fx_manager.gd` | `DotFxManager`: ids in, effects out, or a refusal with a reason; `advance`, `spawn`, `spawn_decal`, `shake_at`, `flash` |
| `runtime/dot_fx_beacon.gd` | `DotFxBeacon`: ring, ripple, through-wall column and ping marking where somebody is |
| `core/dot_fx_weather_def.gd` | `DotFxWeatherDef`: the weather document (`parse()` returns a `DotResult`) |
| `runtime/dot_fx_weather.gd` | `DotFxWeather`: snow or rain in volumes around the camera, one shader-placed MultiMesh |
| `runtime/dot_fx_decals.gd` | `DotFxDecals`: pooled blood splatters (`splatter(pos, normal)`) and static decals from data (`place`, `place_all`); Decal nodes, or quads under Compatibility/web. Config: `core/dot_fx_decal_config.gd` (`DOT_FX_DECAL_*`, `--decal-*`); art sliced by `runtime/dot_fx_decal_sheet.gd` from `art/` |
| `runtime/dot_fx_beam.gd` | `DotFxBeam`: a glowing beam between two points; `zap(parent, from, to)` fades and frees itself, `hold(parent)` stays until `set_ends` stops being called. Used by game-zombie-zone's mutant |
| `runtime/dot_fx_thruster.gd` | `DotFxThruster`: a jetpack exhaust of CPU particles (flame, smoke, sparks); `throttle` 0 to 1, `broken` smokes and never burns, `spark()` is a burst |
| `runtime/dot_fx_blood.gd` | `DotFxBlood`: a `DotFxDecals` plus the rays a game repeats: `splat_behind(from, to)`, `splat_below(feet)`, `splat_ray`, rate-limited `splat_at(point, normal)`, `follow(settings)` for `gore` and `fx_quality`. Used by game-murder-mystery; zombie-zone and playground still carry copies |
| `core/dot_fx_render_config.gd`, `runtime/dot_fx_render_quality.gd` | `DotFxRenderConfig` (`DOT_FX_RENDER_*`, `--render-*`: `anisotropy` -1 = 16x desktop / 4x elsewhere, `aa` auto = MSAA 4x desktop / FXAA elsewhere, `mip_bias`, `sharpness`, `render_scale`) and `DotFxRenderQuality`, the node that puts it on a viewport (`load_layers()`, `follow(settings)` for the keys `aniso`, `aa`, `mip_bias`, `render_scale`, `sharpness`). FSR only under Forward+. Godot's own default is 2x anisotropy, which blurs floors at grazing angles. `examples/render_selftest.tscn` (17 checks). Menu rows for these keys are not in dot-menu yet |
| `runtime/dot_fx_screen_goo.gd` | `DotFxScreenGoo`: a full-screen goo/ink overlay (one procedural canvas shader, no textures, safe on mobile and web). `apply(amount, seconds, fade_in, fade_out)` stacks up to `max_amount`; `set_status(stacks, seconds_left)` is the client mirror of dot-effects' `screen_impair` status. `tools/screenshot.sh <png> goo [amount]` draws it |
| `runtime/dot_muzzle_flash.gd`, `core/dot_muzzle_flash_config.gd` | `DotMuzzleFlash`: pooled muzzle flash from the CC0 Binbun pack in `art/binbun_muzzle/` (see its `LICENSE.txt`); `size_for(category, extra, suppressed)`, `fire()`, `first_person` fades near the camera; off on a headless server. `DotMuzzleFlashConfig` (`DOT_MUZZLE_*`). `tools/screenshot.sh <png> muzzle [fp]` (png path inside the project). Wired by dot-weapon `DotWeaponMuzzle` and zee-dot-weapons `ZeeShotFx`; `tools/screenshot.sh <png> muzzle [--fp] [--near] [--variant N] [--frames N]` (default 2 frames after firing: frame 1 is the startup, where big looks smallest) |
| `dot_fx_api.gd` | the API level (`DotAddonApi` rule) |
| `examples/decals_selftest.tscn` | the decal suite; `decals_demo.tscn` + `tools/screenshot.sh <png> [mesh\|decal]` draw it |
| `examples/fx_selftest.tscn` | the suite; `fixtures/` holds the stand-in scenes it spawns |

Paths except `examples/` and `fixtures/` are in `addons/dot_fx/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/fx_selftest.tscn`. The suite cannot see whether anything looks right: after changing anything that draws, render a frame and look at it.

## Rules that bite

- An effect never changes the simulation: no damage, no moving a body. Dropping one is never a desync or an error. [design](docs/design.md#the-invariant-which-is-the-whole-design)
- `shake_scale` must reach exactly zero and is read every frame. [design](docs/design.md#camera-shake-must-be-able-to-be-zero)
- Flash limits (`allow_flashes`, `flashes_per_second` = 3, `flash_cap`) are enforced in `DotFxManager.flash()`, never left to callers. [design](docs/design.md#flashes-are-rate-limited-and-can-be-refused)
- Shake is trauma squared, sampled from noise, with three different offsets into one field for the three axes. [design](docs/design.md#two-details-that-make-shake-read-as-shake)
- A definition names its scene by path, never a `PackedScene`. [design](docs/design.md#a-path-not-a-packedscene)
- Call `advance()` yourself; nothing runs in `_process`. [design](docs/design.md#advance-is-explicit-not-_process)
- At the instance cap the oldest non-decal is recycled (else the oldest decal), the opposite of dot-audio's pool; the budget is checked first, and a higher `priority` displaces only this frame's lower ones. [design](docs/design.md#the-instance-pool-recycles-the-oldest-and-the-audio-pool-does-not)
- `spawn_decal` ray-checks for a surface (`decal_surface_mask`, 0 skips): none gives `no_surface`, a character or ragdoll bone is refused, a RigidBody3D or AnimatableBody3D hit adopts the decal so it moves and dies with it.
- Every refusal emits `spawned(id, null, why)` with its reason; a new rule gets a new reason. [design](docs/design.md#refusals-carry-a-reason)
- `DotFxBeacon.local_view` for the marked player's own view, or the camera stands inside the column. [design](docs/design.md#the-beacon-is-the-one-thing-here-that-draws)

Deliberately not here: art, particle effects (weather is the one exception and is a shader), shaders, a post-processing stack, effect networking. [design](docs/design.md#things-deliberately-not-here)

## Open items

- `DotFxBeacon` is used by mg-prop-hunt, game-hide-n-seek and game-zombie-zone. game-arena, game-g2gfast, game-playground, mg-buses-from-hell, mg-deathrun, mg-smash-copter and mg-wipeout still carry their own `*_beacon.gd`: not yet converted; reason unknown.
