This is the **fx** asset for TMC's **Dot** collection. It adds visual effects as documents rather than as scattered `instantiate()` calls: pooled, budgeted, quality-tiered, distance-culled, and safe to drop.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

## One invariant, and everything follows from it

**An effect never changes the simulation.** It is a picture of something that already happened.

That single property is what makes every mechanism here safe. A frame budget may drop one, a quality tier may refuse one, a distance cull may skip one, and a client whose content pack is still downloading simply does not see it. In none of those cases do two machines disagree about anything that matters. The moment an effect is allowed to deal damage, move a body or decide a hit, the property is gone and every one of those becomes a desync.

So: dot-combat owns damage, dot-effects owns what happens over time, and this owns what it looks like.

## A low quality tier is missing effects, not running all of them badly

`min_quality` gates whether an effect **exists**, not how detailed it is. Halving the particle count on the effect that is killing the frame does not save the frame; not spawning it does. A "low" tier built the other way is one where everything looks worse and the frame rate is the same.

`frame_budget` is the same idea per frame: a grenade landing in a crowd cannot cost more than one frame has, and what goes is the lowest-priority request: one of higher `priority` takes the room of lower ones started in the same frame (never of an effect already on screen), and a request the budget refuses retires nothing.

## Camera shake is a value, and has to be able to be off

```gdscript
fx.advance(delta)
camera.position = base + fx.shake.offset()
camera.rotation.z = base_roll + fx.shake.roll()
```

It computes a displacement and touches no camera, which is why one implementation serves a 3D rig, a 2D one, a spectator camera and a headless suite.

Two details that make it read as shake rather than as a fault:

- **Trauma, squared.** A linear falloff stops abruptly, because the last few per cent of a linear ramp is still visible motion. Squared spends most of its time near zero, so it fades.
- **Sampled noise, not a random number per frame.** Random per frame is jitter at the frame rate, and it looks like a rendering fault, and it looks different at 60 and at 144 fps, where a noise path does not.

And `shake_scale` must be able to reach **zero**. Camera shake is one of the commonest causes of simulator sickness, and a game with no way to turn it off is a game some people cannot play. It is read every frame, so turning it off takes effect immediately rather than at the next map.

## A full-screen flash is a hazard before it is a style

`allow_flashes` is a player-facing off switch and `flashes_per_second` defaults to **three**, which is the published photosensitivity guidance. Both are enforced in the manager rather than left to the caller, because the caller that does not honour them is the next feature somebody adds, and the person it harms has no way to know which effect did it.

## Decals are a ring

An unbounded decal list grows with the **round** rather than with the number of players, which makes it invisible in testing and fatal at minute forty. `max_decals` recycles the oldest, and lowering it takes effect at the next decal or the next `advance`, whichever comes first.

## Using it

```gdscript
var fx := DotFxManager.new()
fx.catalogue = my_catalogue
fx.world_ref = DotNodeRef.of_path(world.get_path())   # or leave it on the manager
add_child(fx)
fx.setup()

fx.viewer_position = camera.global_position     # once a frame; culling needs it
fx.spawn(&"muzzle_flash", muzzle.global_transform)
fx.spawn_decal(&"bullet_hole", hit)
fx.shake_at(&"grenade", where)                  # scaled by distance
fx.flash(&"hurt")                               # capped and rate limited
fx.advance(delta)
```

`spawn_2d` is beside `spawn` rather than a widened signature, which is the choice the props and NPC assets made when they grew a second dimension: a caller holding a `Vector2` is a different caller.

## A beacon, for saying where somebody is

`DotFxBeacon` is a ring at a player's feet that sends out a ripple once a period, a column above them that shows through walls, and a ping that comes from where they are. Games use it for an admin's `beacon` and for rules that give the last players of a side away. It is built from shapes in code and makes its own ping, so it needs no art or sound files.

```gdscript
var marker := DotFxBeacon.new()
marker.colour = Color(1.0, 0.6, 0.1)
marker.period = 1.0
marker.local_view = is_my_player        # no column in your own eyes
add_child(marker)

marker.global_position = drawn_position # once a frame, where the player is drawn
marker.advance(delta)                   # true on the frame it pings
```

A game that plays the ping through its own sound catalogue sets `marker.ping_enabled = false` (API level 3, before `add_child` or followed by `build()`): no voice is built, and `advance()` still returns true on each pulse so the game plays its own sound from that. Without it the ping would be heard twice.

To change the size of a marker that is already running, call `marker.resize(radius, height, base)` (API level 4); it edits the meshes in place and keeps the phase, where `build()` frees and rebuilds them.

## Weather: snow and rain inside volumes

`DotFxWeather` draws snow or rain around the camera, only inside boxes the document names (or everywhere around the camera when it names none). One `MultiMesh` of quads is placed entirely in a vertex shader, so there are no particle nodes, no per-frame transforms and no collision: a flake outside every volume is collapsed in the shader, which is how nothing falls through a roof. It runs under the Compatibility renderer in the browser.

```gdscript
var w := DotFxWeather.new()
add_child(w)
var res := w.apply(map_document["weather"])        # DotResult; a bad document keeps the old weather
w.quality = DotFxWeather.Quality.HIGH              # OFF, LOW (a third of the flakes), HIGH
w.density_scale = 1.0                              # a player's slider, 0 to 2
w.audible_changed.connect(_on_weather_sound)       # (sound id, inside): the game plays its own sound
w.advance(delta, camera.global_position)           # once a frame
```

The document, validated by `DotFxWeatherDef.parse()`:

```json
{
  "kind": "snow",
  "volumes": [{"min": [-10, 0, -10], "max": [10, 12, 10]}, {"center": [40, 5, 0], "size": [8, 10, 8]}],
  "density": 1.0,
  "wind": [1.5, 0, 0],
  "colour": "#ffffff",
  "sound": "amb_wind"
}
```

`kind` is `snow` or `rain` and is the only required key. `volumes` are axis-aligned world-space boxes, as `min`/`max` or `center`/`size`; none means everywhere. Unknown keys are refused so a misspelt `volumes` cannot read as "everywhere". `DotFxConfig.weather_quality` (0, 1, 2) and `weather_density` carry the settings; `apply_config()` reads them. Weather is skipped without a display (`DotFxWeather.can_render()`, false on a dedicated server). More in [docs/weather.md](docs/weather.md); run `examples/weather_demo.tscn`.

## Decals

`DotFxDecals` spawns pooled, capped, fading blood splatters from a hit position and normal, and places static wall decals (graffiti) from data. It uses `Decal` nodes where the renderer has them and textured quads just off the surface under Compatibility and the web. `DotFxDecalConfig` carries the gore toggle, quality tier, caps, hold and fade times and blood colour, layered like every `DotConfig` (`DOT_FX_DECAL_*`, `--decal-*`).

```gdscript
var decals := DotFxDecals.new()
add_child(decals)
decals.apply_config(cfg)                                  # DotFxDecalConfig
decals.splatter(hit_position, hit_normal)                 # null when gore is off
decals.place({"image": "alien", "position": [1, 2, 3], "normal": [0, 0, 1], "width": 1.5})
decals.advance(delta)                                     # once a frame
```

`DotFxBlood` wraps a `DotFxDecals` with what every game that draws blood repeats: `splat_behind(from, to)` (the surface behind a hit), `splat_below(feet)` (the floor under a victim), `splat_ray`, `splat_at(point, normal)` (a server's splat, near the camera and rate-limited), `mask` for the layers it may land on, and `follow(settings)` to track the player's `gore` and `fx_quality`.

Images: `alien`, `warning`, `drip`, `beast`, `spider`, `tentacle`, `robot`. Run `examples/decals_selftest.tscn` (headless) and `examples/decals_demo.tscn`.

Art, both CC0:

- Blood splatter by ExileGL, https://opengameart.org/content/blood-splatter (CC0), downscaled to six 256 px frames in `art/blood_splatter.png`.
- Graffiti Decals 64x by Mumu, https://opengameart.org/content/graffiti-decals-64x (CC0), `art/graffiti.png`.

## Muzzle flashes

`DotMuzzleFlash` is a pooled muzzle flash node: parent it to a weapon's muzzle point (view model or world model) and call `fire()` per shot. Three instances are built on the first shot and reused, so nothing is allocated per shot, and nothing is built at all on a headless server (`DotMuzzleFlash.available()`). `DotMuzzleFlash.size_for(category, extra, suppressed)` picks a size: pistol very small, revolver, SMG and carbine small, rifle, LMG and DMR medium, shotgun and sniper big, suppressed none; a weapon profile overrides it with `extra: {muzzle_flash: big}` (`very_small`, `small`, `medium`, `big`, `none`). Set `first_person = true` on the view model's node: it fades the mesh out within `first_person_fade` metres of the camera so it never fills the view. `DotMuzzleFlashConfig` (`DOT_MUZZLE_*`, `--muzzle-*`) has `quality` (0 off, 1 hard-edged no light, 2 dithered with light, 3 smooth with light), `light_scale`, `max_size`. Run `tools/screenshot.sh shots/m.png muzzle`.

Art, CC0: Muzzle Flash VFX - Godot 3D by Binbun, https://binbun3d.itch.io/muzzle-flash-vfx (CC0), vendored in `art/binbun_muzzle/` with the licence statement in `LICENSE.txt`.

## Installing

Copy `addons/dot_fx/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-fx in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## Licence

MIT. See [LICENSE](LICENSE).
