## How an animal holds its legs under it, and everything that follows from that.
##
## One number is the trait: the angle the limbs are carried out of the ground
## plane. Everything else here is read off it or off the same fact about the
## animal, because in a real skeleton they are not separable — a leg swung out
## sideways is a low body, a wide track and a short plan-view reach, and a leg
## stacked under the shoulder is a high body, a narrow track and a long one. They
## are the same posture seen from three directions.
##
## Two consequences do the most work, and both are projections rather than
## settings:
##
##   * `plan_reach` — what a limb measures *seen from above*. The game is drawn
##     looking down, so a limb held at 72 degrees shows barely a third of its
##     length in the picture. That, and nothing else, is why a columnar animal's
##     feet sit close beneath it while a sprawled one's are flung out to the
##     side; there is no stance-width dial doing it.
##   * `clearance` — how far off the ground the same projection leaves the body.
##     That is the animal's height, and it is what the whole 2.5D layer is
##     measured in. A creature does not carry a "how tall am I" number; it stands
##     on its legs and the answer falls out.
##
## A third projection decides how the limb *travels*, and it is the one that
## makes an upright animal walk differently rather than merely stand differently:
##
##   * `track` — how far out to the side the foot is carried, which is the same
##     cosine applied a second time. Coming up out of the ground plane and
##     swinging round underneath the body are one movement in a real shoulder: a
##     sprawled limb rows in the frontal plane, so its foot is flung wide and the
##     arc it sweeps is carried out there with it, while an erect one pendulums
##     parasagittally, directly beneath its own shoulder. That is why a cat's and
##     an elephant's feet fall in two lines under the body and a lizard's in two
##     lines outside it, and it is the whole of the difference — the stride, the
##     envelope and the fold plane are all read off it below.
##
## The rest of the table is per-posture tuning, and it is deliberately a table
## rather than three code paths. Nothing below names a gait, a species or a
## behaviour: they are multipliers on numbers the existing systems already read,
## so a posture is a set of leanings — this build accelerates hard and turns
## flat, that one carries weight and turns wide — rather than a mode anything
## switches into.
class_name Posture
extends RefCounted

const SPRAWLED: int = 0
const SEMI_UPRIGHT: int = 1
const COLUMNAR: int = 2
const COUNT: int = 3

const NAMES: Array[String] = ["sprawled", "semi-upright", "columnar"]

## How far the drawn view is tilted off vertical, as screen pixels down per pixel
## of world height. Zero would be a true plan view; one would be a side-on
## platformer. This is the whole of the "2.5" in 2.5D, and it is a presentation
## constant rather than a simulation one — nothing gameplay-facing reads it.
##
## How upright a build may stand and how far the view is tilted are one decision
## made twice, and this is the second half of it. In a true plan view an animal
## standing on legs held underneath itself has no legs at all: the feet are
## directly beneath the shoulders, so every part of every limb lands inside the
## silhouette and the creature draws as a slug. A sprawled animal is indifferent —
## its feet are flung out beside it and legible from any angle — which is why the
## number could stay tiny for as long as everything was sprawled, and why bringing
## the legs in under the body is what forced it up.
##
## It is bounded at the other end by the one thing the whole picture is registered
## to: a body is drawn where the simulation puts it, and its legs are drawn
## hanging below that. Push the tilt far enough and a tall animal's feet are drawn
## clear of its own silhouette — all four of them below it rather than two either
## side — and there is no longer anything to walk between. So it is held under
## what a wide, tall body is half as wide as, which is a real ceiling on this
## projection rather than a taste one: lifting it means registering every body to
## the ground rather than to itself, and that is a different picture.
const PERSPECTIVE: float = 0.22

## Per-posture tuning. Each row is a complete description; nothing falls back.
##
## `tilt_deg` is the trait. The rest are leanings, quoted as multipliers on
## parameters the species already sets, so a Cat's own acceleration is still the
## Cat's — the posture only says that a semi-upright build gets more out of it.
const TABLE: Array[Dictionary] = [
	{
		# Legs out to the sides, belly close to the floor, body flattened
		# top-to-bottom. The spine does much of the walking: a sprawled stride is
		# lengthened by the lateral wave, which is why undulation is left at full
		# strength here and taken away from the two upright builds.
		"tilt_deg": 12.0,
		"socket_inset": 0.0,
		"depth_ratio": 0.60,
		"wave_gain": 1.0,
		"feet_down": 2,
		"coupling_gain": 1.0,
		"step_height_gain": 1.0,
		"stride_gain": 1.0,
		"agility": 1.0,
		"drive": 1.0,
		"neck_reach": 0.10,
	},
	{
		# Feet drawn in under the body, elbow and knee working fore-and-aft. The
		# socket moves inboard with them, and because the limbs are drawn beneath
		# the torso that alone hides the upper bone — the occlusion is the body
		# standing over its own shoulder, not a decision to stop drawing part of
		# a leg.
		"tilt_deg": 50.0,
		"socket_inset": 0.42,
		"depth_ratio": 0.92,
		"wave_gain": 0.30,
		"feet_down": 2,
		"coupling_gain": 1.15,
		"step_height_gain": 1.35,
		"stride_gain": 1.15,
		"agility": 1.30,
		"drive": 1.45,
		"neck_reach": 0.16,
	},
	{
		# Legs as pillars directly beneath the body, which is held a whole leg
		# clear of the ground. Weight is the point: three feet stay down at all
		# times, the diagonal beat is nearly gone — a heavy animal ambles, it does
		# not trot — and what it gives up for that is the ability to turn or
		# accelerate quickly.
		"tilt_deg": 72.0,
		# Less inset than the semi-upright stance, not more, and the reason is the
		# view rather than the anatomy: a columnar body is drawn high enough that
		# the tilt alone already hides the top of every leg, and the far pair then
		# has to clear the *top* edge of a very deep silhouette to be seen at all.
		# Pulled any further in they disappear under the animal entirely and it
		# reads as a two-legged one.
		"socket_inset": 0.18,
		"depth_ratio": 1.05,
		"wave_gain": 0.08,
		"feet_down": 3,
		"coupling_gain": 0.45,
		"step_height_gain": 0.55,
		"stride_gain": 0.95,
		"agility": 0.55,
		"drive": 0.55,
		"neck_reach": 0.20,
	},
]

var kind: int = SPRAWLED
## The trait, in radians.
var tilt: float = 0.0
## Fraction of the body's half-width the limb socket is drawn inboard by.
var socket_inset: float = 0.0
## The body's vertical thickness as a multiple of its drawn width. Sprawled
## animals are flattened and upright ones are deep-chested, which is why this
## belongs to the posture and not to the silhouette.
var depth_ratio: float = 0.6
var wave_gain: float = 1.0
var feet_down: int = 2
var coupling_gain: float = 1.0
var step_height_gain: float = 1.0
var stride_gain: float = 1.0
var agility: float = 1.0
var drive: float = 1.0
## How far the jaws can be carried from their resting height, as a fraction of
## the animal's own body length. A neck is a real length, so it reaches both ways
## off the same number.
var neck_reach: float = 0.1


func _init(p_kind: int = SPRAWLED) -> void:
	configure(p_kind)


func configure(p_kind: int) -> void:
	kind = clampi(p_kind, 0, COUNT - 1)
	var row: Dictionary = TABLE[kind]
	tilt = deg_to_rad(float(row["tilt_deg"]))
	socket_inset = float(row["socket_inset"])
	depth_ratio = float(row["depth_ratio"])
	wave_gain = float(row["wave_gain"])
	feet_down = int(row["feet_down"])
	coupling_gain = float(row["coupling_gain"])
	step_height_gain = float(row["step_height_gain"])
	stride_gain = float(row["stride_gain"])
	agility = float(row["agility"])
	drive = float(row["drive"])
	neck_reach = float(row["neck_reach"])


## What a limb of this length measures seen from above — the radius of the disc
## its foot may be set down anywhere inside.
func plan_reach(limb_length: float) -> float:
	return limb_length * cos(tilt)


## How far off the ground a limb of this length holds the body.
func clearance(limb_length: float) -> float:
	return limb_length * sin(tilt)


## How far out to the side the same limb carries its foot: the plan reach with
## the same cosine taken out of it again, because the plane the limb swings in
## has rotated by the same angle the limb itself has.
##
## What is left of the plan reach after this is the fore-and-aft excursion — the
## stride — so the two together say that an upright animal spends its reach
## walking and a sprawled one spends it standing wide.
func track(limb_length: float) -> float:
	return plan_reach(limb_length) * cos(tilt)


## How far inboard of its own socket a foot may be set down, as a fraction of
## the socket's own offset from the spine. Zero on a sprawled limb, which cannot
## bring its foot in under the shoulder at all; most of the way to the midline on
## a columnar one, whose entire stance is standing underneath itself.
func adduction() -> float:
	return 1.0 - cos(tilt)


## How much of itself the same limb measures *on the screen*, which is neither of
## the two above: the picture shows the plan reach across, plus whatever the
## perspective makes of the height it is holding the body at. Used only to
## normalise — how far a drawn leg is extended, how thick to draw it — never to
## decide where a foot goes.
func drawn_reach(limb_length: float) -> float:
	var flat: float = cos(tilt)
	var up: float = sin(tilt) * PERSPECTIVE
	return limb_length * sqrt(flat * flat + up * up)


## Most feet this posture will lift at once. A body that has to stay held up
## picks fewer of them up.
func airborne_limit() -> int:
	return maxi(4 - feet_down, 1)


func name() -> String:
	return NAMES[kind]


## Screen offset for something standing at world height `h`, drawn against a
## reference plane at `reference`. Positive y is down the screen, so anything
## below the reference is pushed down and anything above it is lifted — which is
## the whole of how height reads in a top-down picture.
static func drop(h: float, reference: float) -> Vector2:
	return Vector2(0.0, (reference - h) * PERSPECTIVE)
