# dot-fx

Visual effects as documents: pooled, budgeted, tiered, and safe to drop.

**The distributable is `addons/dot_fx/`.** It requires [dot-core](../dot-core), a separate repository, and nothing else.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

## The invariant, which is the whole design

**An effect never changes the simulation.** Everything else here is a consequence:

- A frame budget may refuse one.
- A quality tier may mean it does not exist.
- A distance cull may skip it.
- A client still downloading its content pack never sees it.

In all four cases two machines still agree about everything that matters, so none of them is a desync and none of them needs to be reported as an error. **That is the property that makes this addon cheap**, and it is why the line is drawn where it is: dot-combat owns damage, dot-effects owns what happens over time, dot-fx owns what it looks like. An effect that is allowed to deal damage takes the property away and every mechanism above becomes a bug.

The suite's budget section says so in its own comment, so that the next person to add a "just this one effect moves the player" feature has to delete the sentence first.

## The two accessibility decisions, which are not preferences

### Camera shake must be able to be zero

`DotFxConfig.shake_scale` reaches 0 and is read **every frame** by `advance()`, so a player turning it off sees it stop immediately rather than at the next map. Camera shake is one of the commonest causes of simulator sickness; a game that cannot turn it off is a game some people cannot play at all.

The suite asserts a scale of zero produces `Vector3.ZERO` exactly — not "small" — because a residual wobble is the failure this setting exists to prevent.

### Flashes are rate limited and can be refused

`allow_flashes` is a player-facing switch. `flashes_per_second` defaults to **3**, which is the published guidance on photosensitivity, and `flash_cap` bounds what any definition can ask for. All three are enforced in `DotFxManager.flash()` rather than left to callers, because a convention that every caller must remember is one the next feature breaks — and the person it harms cannot tell which effect did it.

## Two details that make shake read as shake

- **Trauma is squared.** A linear falloff switches off rather than fading: the last few per cent of a linear ramp is still visible motion. Squared spends most of its life near zero. Asserted by halving the trauma and requiring *much* less than half the shake.
- **The displacement is sampled noise, not a random number per frame.** Random per frame is uncorrelated between frames, so the camera vibrates at the frame rate and reads as a rendering fault — and it looks different at 60 and 144 fps, where a noise path does not. Asserted by checking two consecutive frames at 240 Hz are close together.

And the three axes are three **different offsets into one noise field**. Sampling one field at the same point three times gives three identical numbers and a camera that slides along a diagonal, which is a bug that looks like a badly tuned shake.

## The pieces

| | |
| --- | --- |
| `DotFxDef` | One effect, as a document naming a scene by path. |
| `DotFxCatalogue` | All of them. Validates with no renderer and no files. |
| `DotFxShake` | Trauma in, displacement out. Touches no camera. |
| `DotFxConfig` | Quality, budgets, and the two accessibility settings. A `DotConfig`. |
| `DotFxManager` | Ids in, effects out — or an honest refusal with a reason. |

## Decisions

### A path, not a `PackedScene`

The same reason dot-props names a prop's script by PATH: a **mounted pack's `class_name` globals are not registered in the host**, so a catalogue that preloads cannot describe delivered content — and one holding loaded scenes cannot be validated on a server with none of them.

### `advance()` is explicit, not `_process`

A game that pauses, a replay being scrubbed and a suite stepping one frame at a time all need to decide when the frame happens. `_process` decides for them, and dot-audio found the sharp edge of that on its first run: `_process` does not run while the tree is paused, so a manager that only reaps there comes back from a pause menu permanently stuck.

### The instance pool recycles the *oldest*, and the audio pool does not

Deliberately opposite. An effect's whole value is being seen at the moment it happens, so when the instance cap is reached the oldest is taken back and the newest is drawn. A voice's value is what it is *of*, so dot-audio steals by **priority** and refuses rather than stealing something more important — a gunshot losing to a footstep that started first is that pool's failure mode.

### Refusals carry a reason

`spawned(id, node, why)` names which rule refused: `unknown`, `quality`, `distance`, `behind`, `concurrent`, `instances`, `budget`, `missing`. A profiler wants it, a settings screen wants it, and so does anybody wondering why the smoke did not appear — and without it every one of the seven looks identical from outside.

## Things deliberately not here

- **Any art, any particle, any shader.** dot-ui's rule. A game supplies the scenes; this decides whether, where and how many.
- **A post-processing stack of shipped shaders.** `Kind.SCREEN` produces a colour a game draws. A shipped chromatic-aberration shader would be art with an opinion.
- **Anything that moves a body or deals damage.** See the invariant.
- **Effect networking.** A server names an effect id and a place through whatever transport it already has; there is no wire format here, because there is nothing to agree about — every client may legitimately draw a different subset.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
timeout 120 godot --headless --path . res://examples/fx_selftest.tscn
```

7 sections, 56 checks. What the suite cannot see is whether any of it **looks** right; that wants a screenshot, and this family has found four bugs with a picture that no assertion could reach. After changing anything that draws, render a frame and look at it.
