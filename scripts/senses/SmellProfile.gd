## Species-tunable parameters for one creature's sense of smell.
##
## Split the same way SightProfile is: perception values describe what the
## creature can resolve and how its read behaves over time, rendering values
## describe only how that read is put on the paper. Both live on a Resource so a
## species preset can swap the whole character of the sense without the creature,
## the scent field or the renderer learning any species names.
class_name SmellProfile
extends Resource

@export_category("Perception")
## World radius the muzzle reaches at all. Nothing beyond it is read.
@export_range(80.0, 1600.0, 1.0) var reach: float = 560.0
## Seconds between reads. The sense works in beats, not continuously, which is
## what lets a read tighten while it holds and dissolve when it lapses.
@export_range(0.05, 2.0, 0.01) var beat_interval: float = 0.58
## How much of the read is owed to facing the thing rather than being near it.
@export_range(0.0, 1.0, 0.01) var muzzle_bias: float = 0.26
## Below this the read is nothing at all and no mark is made for it.
@export_range(0.0, 1.0, 0.01) var min_confidence: float = 0.05
## Strongest reads resolved per beat. A saturated habitat reads its loudest
## news, not all of it at once.
@export_range(1, 48, 1) var reads_per_beat: int = 20
## Marks a fully certain read is worth. Weak reads are sparse by the same curve.
@export_range(0.0, 16.0, 0.5) var marks_per_read: float = 7.0
## Radius the marks of a certain read cluster into.
@export_range(4.0, 120.0, 1.0) var cluster_radius: float = 22.0
## Extra radius an uncertain read scatters over on top of the cluster.
@export_range(0.0, 300.0, 1.0) var scatter_radius: float = 100.0
## Seconds a mark lasts, before its random spread and a bonus for certainty.
@export_range(0.2, 6.0, 0.05) var mark_life: float = 0.8
@export_range(0.0, 6.0, 0.05) var mark_life_spread: float = 1.4
## Speed of the lazy curl every mark drifts on, in world units per second.
@export_range(0.0, 40.0, 0.5) var drift_curl: float = 7.0
## Speed a mark closes on the thing being read, or loses its grip on it.
@export_range(0.0, 60.0, 0.5) var drift_pull: float = 11.0
## Certainty at which a read can occasionally resolve into something legible.
@export_range(0.0, 1.0, 0.01) var legible_confidence: float = 0.6
@export_range(0.0, 1.0, 0.01) var legible_chance: float = 0.45
## Marks of nothing-yet made each beat, so the sense visibly runs whether or not
## it finds anything.
@export_range(0, 12, 1) var ambient_marks: int = 3
@export_range(40, 900, 10) var max_marks: int = 400

@export_category("Rendering")
## Screen lattice the marks are snapped to. They are read off a grid belonging to
## the observer, which is what stops them behaving like objects in the habitat.
@export_range(3.0, 24.0, 1.0) var lattice_cell: float = 9.0
@export_range(3.0, 20.0, 0.1) var glyph_size: float = 6.4
@export_range(0.0, 1.0, 0.01) var mark_opacity: float = 0.74
@export_range(0.0, 1.0, 0.01) var mark_opacity_floor: float = 0.14
@export_range(0.0, 20.0, 0.5) var flicker_rate: float = 6.5
## Opacity is quantised to this many steps, so marks read as a struck impression
## rather than a smooth glow.
@export_range(1, 16, 1) var opacity_steps: int = 6
@export_range(0.0, 1.0, 0.01) var layer_opacity: float = 0.95
## An uncertain read is cool and scattered; certainty warms it toward the hue of
## whatever it is reading. One warm per ScentField.Kind, in that order.
@export var cool_tones: PackedColorArray = PackedColorArray([
	Color("7e98cc"), Color("a896d8"), Color("6fbebe"),
])
@export var warm_tones: PackedColorArray = PackedColorArray([
	Color("eca22c"),  # FORAGE  — seed, starch
	Color("d44a60"),  # QUARRY  — a living animal
	Color("e2609e"),  # CARRION — decay
	Color("c62a36"),  # BLOOD   — iron
	Color("d2743c"),  # SCRAP   — raw meat
])
## Colour of a mark that resolved nothing.
@export var unread_tone: Color = Color("9aa0b0")
