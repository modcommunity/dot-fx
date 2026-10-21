# Weather

`DotFxWeather` is the one thing in dot-fx that is a continuous effect rather than a spawned one. It takes a document ([`DotFxWeatherDef`](../addons/dot_fx/core/dot_fx_weather_def.gd)), the camera's position once a frame, and draws snow or rain around the camera inside the document's volumes.

## Why a shader and not particles

A browser build runs the Compatibility renderer, single threaded. GPU particles there work but cost a node and a process material each, and clipping them to a set of boxes needs either collision or a sub-emitter per box. A map converted from a source with eighteen precipitation volumes would be eighteen emitters.

Instead there is one `MultiMeshInstance3D` of quads that never changes. The vertex shader derives each flake's place from its instance id (a hash), a clock and the camera: `mod(seed * box + velocity * clock - camera + box / 2, box)` wraps the flake into a box that follows the camera without the flake ever being moved by the CPU. The only uniforms that change per frame are the clock and the camera.

## How volumes clip

The shader receives up to `MAX_ACTIVE` (32) volumes as two uniform arrays. A flake whose centre is outside all of them gets zero alpha and a collapsed vertex. Near a volume's boundary alpha ramps over the last metre, so snow thins out at a mapper's edge rather than stopping on a line. There is no collision and no ray: the volume is the truth, which is what the mapper drew.

The CPU tests the camera's box against the document's volumes whenever the camera moves (`select_volumes`, pure, tested headless) and sends only the overlapping ones, the nearest 32 if more. When none overlaps the instance is hidden and nothing is submitted. A document with no volumes is "everywhere around the camera".

A flake is only drawn inside the camera box (28 by 18 by 28 m for snow, 24 by 20 by 24 for rain), so a volume is seen filled out to that distance and thins at its edge; a very large volume does not cost more.

## Knobs

| What | Where |
| --- | --- |
| Off, low, high | `DotFxWeather.quality`, or `DotFxConfig.weather_quality` through `apply_config()`. Low draws 30% of the flakes. |
| Player density slider | `density_scale`, `DotFxConfig.weather_density`, multiplies the document's density |
| Colour, wind, density | the document |
| Flake cap | `MAX_FLAKES` (8000) |

## Sound

dot-fx ships none. The document's `sound` is an id the game maps to its own sound (a catalogue entry, a stream). `audible_changed(sound, inside)` is emitted when the camera enters or leaves a volume; for a document with no volumes it is emitted once as inside.

## No display

`DotFxWeather.can_render()` is `not DotPlatform.is_headless()`. Without a display, `setup()` keeps the definition and the sound hook still works, but nothing is built, so a dedicated server may load a map document carrying weather at no cost.

## Known limits

- The clock wraps at 600 s; the weather reshuffles once there, which is not visible in falling snow.
- Flakes pass through anything between volume and camera visually only as far as the depth buffer allows: a roof inside a volume hides the flakes below it from outside, but flakes above it fall through it (no collision, by design). Draw the volume so its floor is the roof.
- It does not splash, accumulate or wet anything.
