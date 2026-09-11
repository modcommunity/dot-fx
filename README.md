This is the **fx** asset for TMC's **Dot** collection. It adds visual effects as documents rather than as scattered `instantiate()` calls: pooled, budgeted, quality-tiered, distance-culled, and safe to drop.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

## One invariant, and everything follows from it

**An effect never changes the simulation.** It is a picture of something that already happened.

That single property is what makes every mechanism here safe. A frame budget may drop one, a quality tier may refuse one, a distance cull may skip one, and a client whose content pack is still downloading simply does not see it — and in none of those cases do two machines disagree about anything that matters. The moment an effect is allowed to deal damage, move a body or decide a hit, the property is gone and every one of those becomes a desync.

So: dot-combat owns damage, dot-effects owns what happens over time, and this owns what it looks like.

## A low quality tier is missing effects, not running all of them badly

`min_quality` gates whether an effect **exists**, not how detailed it is. Halving the particle count on the effect that is killing the frame does not save the frame; not spawning it does. A "low" tier built the other way is one where everything looks worse and the frame rate is the same.

`frame_budget` is the same idea per frame: a grenade landing in a crowd cannot cost more than one frame has, and what goes is the lowest-priority request.

## Camera shake is a value, and has to be able to be off

```gdscript
fx.advance(delta)
camera.position = base + fx.shake.offset()
camera.rotation.z = base_roll + fx.shake.roll()
```

It computes a displacement and touches no camera, which is why one implementation serves a 3D rig, a 2D one, a spectator camera and a headless suite.

Two details that make it read as shake rather than as a fault:

- **Trauma, squared.** A linear falloff stops abruptly, because the last few per cent of a linear ramp is still visible motion. Squared spends most of its time near zero, so it fades.
- **Sampled noise, not a random number per frame.** Random per frame is jitter at the frame rate, and it looks like a rendering fault — and it looks different at 60 and at 144 fps, where a noise path does not.

And `shake_scale` must be able to reach **zero**. Camera shake is one of the commonest causes of simulator sickness, and a game with no way to turn it off is a game some people cannot play. It is read every frame, so turning it off takes effect immediately rather than at the next map.

## A full-screen flash is a hazard before it is a style

`allow_flashes` is a player-facing off switch and `flashes_per_second` defaults to **three**, which is the published photosensitivity guidance. Both are enforced in the manager rather than left to the caller, because the caller that does not honour them is the next feature somebody adds — and the person it harms has no way to know which effect did it.

## Decals are a ring

An unbounded decal list grows with the **round** rather than with the number of players, which makes it invisible in testing and fatal at minute forty. `max_decals` recycles the oldest, and lowering it takes effect immediately.

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

## Installing

Copy `addons/dot_fx/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-fx in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## License

MIT.
