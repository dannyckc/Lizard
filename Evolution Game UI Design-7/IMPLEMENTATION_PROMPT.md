# Implementation prompt — Locomotion Debug HUD (v2)

*Paste this to Claude working in the game repo. `Physics HUD.dc.html` in this folder is the design spec; open it in a browser to see it live (it runs its own simulation of the loop).*

---

Implement an in-game **locomotion debug HUD** for the v2 creature, specified by `Physics HUD.dc.html` in the attached folder. Open that file in a browser first and watch it run — it is a working mock of the loop, and the layout, signal list, colours and typography are the spec. Its own creature is a *restatement* of the loop, not your solver: **take the layout from the mock, take every number from the live systems** (the same rule §8 of `docs/V2_DESIGN.md` states for the other panels).

## What it is for

I cannot see why the movement reads stiff and unnatural, and I cannot see why a foot steps when it does. This HUD exists to make the locomotion loop visually inspectable in real time: the skeleton, the weight, the feet, and the moment-to-moment decisions of `Rhythm`, `Footwork`, `Poise` and `Keel`. It duplicates whatever the creature is doing — driven by ordinary play, not by a canned animation.

## Hard constraints

1. **The HUD is a pure reader.** It owns no simulation state, no second centre of mass, no re-derived geometry, no smoothing of anything the systems publish. If a number it wants does not exist, the fix is to publish it from its existing owner — never to recompute it in the panel.
2. **One seam.** Extend the `BodyReadout` interface (§8) with a single read-only accessor — `motion_debug() -> Dictionary` (or a typed `MotionReadout`) — assembled by `Travel`, since `Travel` is already the only writer of the published motion seam. Panels depend on `BodyReadout` and nothing else. Do not let the HUD reach into `Footwork`/`Rhythm`/`Poise`/`Keel` internals.
3. **Three views are three projections of the one posed armature.** No parallel skeleton, no separate pose for drawing. Read `Armature`'s node positions (already `Vector3`, XY plan + Z height) once per frame and project:
   - **Sagittal** — x = (p − camera) · forward, y = base − z. Along the heading, so limbs read correctly at any heading.
   - **Plan** — world-aligned XY, the game's own projection.
   - **Frontal** — x = centre − (p − camera) · perp (mirrored so it reads head-on), y = base − z. This is the only view where `Keel`'s roll, the lateral base and the righting demand are legible; it is not decoration.
4. **Debug-flag gated and cheap.** Sample history on the physics tick, draw in one `CanvasItem._draw()` with `draw_polyline` / `draw_circle` / `draw_rect` batches, allocate nothing per frame, and stay under ~0.5 ms. It must be free when off.
5. **Do not change the mover to make the HUD look better.** If a tell reads badly, that is the finding — report it, don't tune it away behind the panel.

## Views — what each element is, and who owns the number

Skeleton, in every view: joints as **beads** (filled circles, ~2.5 px), bones as **sticks** (1.5–2 px hairlines). Near-side limbs at full ink, far-side at ~0.3 alpha. Colour a joint bead red when its bend sits within ~0.05 rad of its cone limit — a clamped joint is where stiffness comes from, so this must be visible per joint, from `Armature`'s joint limits.

| Element | Source |
|---|---|
| Nodes / sticks / joint bends / roll | `Armature` (posed nodes, `socket_of`, joint cone limits, `roll`) |
| Centre of mass, support polygon, margin | `Poise` (posed COM, hull, stability) — the plumb line drops from the COM to the surface under it |
| Planted anchor (world-fixed), its **home**, the signed **drift** between them, the step trigger | `Footwork` — draw the anchor as a red bar/bead, home as a hollow square, drift as a dashed line that turns red when the need crosses its threshold |
| Swinging foot, its **predicted landing** (re-aimed each tick), clearance arc | `Footwork` swing state + landing prediction |
| Torn-off foot, desperate step | `Footwork` honesty rules — mark distinctly (filled red, thicker) |
| Seats: how many feet may swing at this pace, diagonal invitation | `Rhythm` (company, `beat_coupling`) |
| Demand vs. delivered acceleration, push ceiling, grip | `Impetus` — two vectors from the COM in plan (demand dashed, delivered solid red) plus the ceiling as a number |
| Roll, righting demand vs. its girdle-clamped ceiling, lateral base width, lateral margin | `Keel` + `Poise` — the frontal pane and the small KEEL dial |
| `rise_ahead` pre-lift, `headroom` refusal (the balk), `reach_along` pulling a landing short | `Outlook` — a caret ahead of the leading girdle with its value; state reads `BALKED` when headroom kills the ask |
| Rescue / collapse | the review after `Poise` measures — state line reads `RESCUE`, `COLLAPSED`, `FALLING` |

## Timeline (bottom strip, ~4.5 s window, right edge = now)

Ring buffer sampled every physics tick, run-length drawn:

- One row per foot (FL FR HL HR): **planted = solid red bar, swinging = hollow outline, desperate step = full-height red tick**. This row set is the answer to "why did that foot step".
- `DOWN` — feet-down count 0–4 as a step line. Compare against MotionProbe's 3.67 strolling / 2.87 cruise / 2.28 sprinting.
- `ACCEL` — demand (dashed) over delivered (filled red area), scaled to the push ceiling. Where the fill is clipped flat, mass is being felt.
- `POISE` — steadiness line with red marks wherever spill exceeds the deficit share.

## The TELLS panel — the part I actually need

Eight measured quantities with a natural band each, value in red when out of band. Computed from the ring buffer only. These are the stiffness diagnostics:

| Tell | Measure | Band | Out-of-band verdict |
|---|---|---|---|
| COM BOB | peak-to-peak COM z over ~1.2 s | 3.5–10 px | `FLAT` = legs are not spending their fold; the body glides |
| LAT SWAY | peak-to-peak lateral COM offset | 2.2–9 px | `RIGID` = weight never shifts over the support |
| SPINE LAG | angle between the pelvis stick and the withers stick, while turning | 3.5–16° | `RIGID` = a rigid pirouette instead of a bend |
| TAIL TRAIL | tail tip vs. pelvis heading | 6–90° | `STIFF` = the tail is welded to the pelvis |
| BEAT SPREAD | CV% of each foot's own stride period | 5–22% | `METRONOME` = the gait is a clock |
| JOINTS AT CAP | joints inside 0.05 rad of a cone limit | 0–1 of 8 | `CLIPPING` = IK is clamping |
| STRIDE/REACH | mean stride length ÷ plan reach | 0.40–0.86 | `MINCING` / `OVERREACH` |
| DELIVERY | delivered ÷ demand while accelerating | 0.30–0.94 | `WEIGHTLESS` = demand is never clamped, the body has no mass to feel |

Gate the travel-dependent tells below ~20 px/s and SPINE LAG below ~0.25 rad/s of turn, so a standing animal does not read as broken. Below the panel, print one plain-language note naming the worst current tell and the mechanism behind it (the mock does this).

## Controls

The mock's nine scenario buttons exist because it has no player. In game, **the player drives**; the HUD needs only:

- **Pause + frame-step** (`Engine.time_scale = 0` plus a one-tick step), so a footfall can be walked through.
- **Slow-motion slider, 0.10×–1.50×** (`Engine.time_scale`), the single most useful control for judging whether motion reads naturally.
- View toggles: hull, trails, and each of the three panes.
- Optionally, keep two scripted probes as buttons for regression watching: the +10 px ledge and the 60 px brink, since both exercise `Outlook` and the carries.

Reuse the existing HUD shell — `HudDock`, drawers, the F3 cycle, `MinimalSlider`, `InkToggle`. Do not build new chrome.

## Visual spec

Background `#F3F1EC`, ink `#14140F`, one accent red `#8E1B12`. Numerals and labels in IBM Plex Mono (or the shell's existing mono) at 8–10 px, uppercase, letter-spaced. Everything is hairlines and beads: 1 px rules, 2/3 dashes for predictions and plumb lines, no gradients, no fills except a ~4.5% hull wash and the ~22% delivery area. Left rail = loop state + tells; right rail = drive/time controls + legend; centre = the three panes; bottom = the timeline.

## Gate (in the repo's own style — behaviours, not constants)

Add `tests/MotionHudProbe.gd`:

1. Every drawn bead sits on an `Armature` node position to 0.000 px — the HUD invents no geometry.
2. The COM the HUD draws is `Poise`'s COM to 1e-6, and the hull it draws has exactly the planted anchors as vertices.
3. Each foot row's plant/swing runs match `Footwork`'s state history tick for tick over 300 walked ticks; each desperate mark coincides with a rule firing.
4. Delivered never exceeds the drawn ceiling; on a standing body the ceiling drops with feet lifted, matching `Impetus`.
5. With the HUD off, the physics trace is bit-identical to the same run with it on.
6. Frame cost under 0.5 ms at 60 fps with all three panes drawn.
7. Walking onto the +10 px ledge, the frontal pane's base and the sagittal carry both rise before any fore foot reaches the step (the anticipation is visible, not just correct).

## Deliverables

- `scripts/creature2/motion/MotionReadout.gd` (or the `BodyReadout` extension) — the seam, assembled by `Travel`.
- `scripts/ui/hud/MotionDebugPanel.gd` (+ scene) — the drawer: three panes, timeline, tells, controls.
- `tests/MotionHudProbe.gd` — the gate above.
- A short note in `docs/V2_DESIGN.md` under Phase 3 recording what the HUD reads and from whom, and any number that had to be newly published.

Start by listing exactly which of the elements above are already reachable through `BodyReadout` and which need publishing, and show me that list before writing the panel.
