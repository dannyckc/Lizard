## Species-tunable parameters for one creature's hearing.
##
## Perception values are consumed by HearingSense and are gameplay truth.
## Rendering values are consumed only by HearingRenderer. Keeping both on the
## profile mirrors SightProfile and SmellProfile while keeping detection wholly
## independent from whether the particle layer exists.
class_name HearingProfile
extends Resource

@export_category("Perception")
## Furthest world-space distance this creature can resolve, even if a powerful
## sound wave physically travels farther.
@export_range(40.0, 1800.0, 1.0) var reach: float = 300.0
## Gain applied after distance and occlusion have attenuated a sound.
@export_range(0.05, 4.0, 0.01) var sensitivity: float = 1.0
## Falloff from the source to the edge of a wave's physical reach.
@export_range(0.25, 4.0, 0.05) var distance_falloff: float = 1.15
## Strength below which a sound is not resolved by this creature.
@export_range(0.0, 1.0, 0.005) var min_strength: float = 0.035
## Strength retained for every solid body between source and listener. Sound is
## muffled rather than made binary, leaving room for later AI to reason about
## uncertain events behind cover.
@export_range(0.0, 1.0, 0.01) var occlusion_transmission: float = 0.24
## How long an arrived sound remains in the gameplay-facing read.
@export_range(0.05, 8.0, 0.05) var memory_seconds: float = 2.4
@export_range(1, 64, 1) var max_heard_sounds: int = 16

@export_category("Rendering")
## Near-even dots on the circumference. More amplitude adds resolution to the
## line rather than throwing particles away from it.
@export_range(12, 240, 1) var base_dot_count: int = 54
@export_range(0.0, 160.0, 1.0) var amplitude_dot_gain: float = 86.0
## Fraction of one angular step used as jitter. Kept well below one so adjacent
## particles stay ordered around the ring.
@export_range(0.0, 1.0, 0.01) var angular_jitter: float = 0.45
## Screen-pixel thickness of the particulate wavefront.
@export_range(0.0, 4.0, 0.1) var radial_jitter_px: float = 1.6
@export_range(0.2, 3.0, 0.05) var dot_radius_px: float = 0.5
@export_range(0.0, 2.0, 0.05) var dot_radius_spread_px: float = 0.22
## Earliest fraction of a wave's life at which an individual dot may disappear.
@export_range(0.05, 1.0, 0.01) var survival_floor: float = 0.34
@export_range(0.01, 0.5, 0.01) var fade_in_fraction: float = 0.12
@export_range(0.01, 0.8, 0.01) var dot_fade_fraction: float = 0.22
## Time-fraction over which a dot resting against an obstacle dissolves.
@export_range(0.01, 0.5, 0.01) var obstacle_fade_fraction: float = 0.10
@export_range(0.1, 4.0, 0.05) var dissolve_power: float = 1.1
@export_range(0.0, 1.0, 0.01) var base_opacity: float = 0.24
@export_range(0.0, 1.0, 0.01) var amplitude_opacity_gain: float = 0.26
@export_range(0.0, 1.0, 0.01) var layer_opacity: float = 0.9
@export var ink: Color = Color("14140f")
