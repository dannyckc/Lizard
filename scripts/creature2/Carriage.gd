## How the animal holds its limbs under it — one angle, seen from every side.
##
## Successor of v1's Posture and Articulation, which were one fact split across
## two files: how far the limbs are carried out of the ground plane, and how
## straight the joint between their bones is carried while they stand on them.
## They are not separable in a skeleton — a leg swung out sideways *is* a leg
## folded up under its own shoulder, and an animal standing sprawled with locked
## elbows does not exist — so v2 keeps them in one place and every consumer reads
## the projections rather than re-deriving them.
##
## Two projections do most of the work, and neither is a setting:
##
##   * `plan_reach` — what a limb measures seen from above. The game is drawn
##     looking down, so a limb held at 66° shows barely a third of its length;
##     that, and nothing else, is why an upright animal's feet sit close beneath
##     it and a sprawled one's are flung out to the side.
##   * `stance_clearance` — how high the same limb holds the body once its foot
##     is where the stance and the bias put it. That is the animal's height, and
##     it is the one arithmetic both the census's rest datum and the live gait
##     read, so the two can never be two opinions.
##
## The joint half is the same fact at the other end of the limb. `Joint` carries
## the three angles a girdle works between — where it stands, where it locks out,
## where it folds to — and what each of them measures as a *length*, because
## every consumer wants the length. The tendon's insertion rides here too: it is
## the lever the muscle reaches the ground through, so it gears the push one way
## and the swing the other, and exactly cancels in a jump — a lever trades, it
## never creates.
##
## The table is a table rather than four code paths, and nothing in it names a
## gait, a species or a behaviour. In what order the feet come down is the gait's
## question, not this one; the same erect build walks, trots and gallops. That is
## also why this file survived the locomotion being taken out to be rewritten: it
## is a statement about a skeleton, and the census and the skin both read it.
class_name Carriage
extends RefCounted

## Ordered by the trait itself — how far the limbs are carried out of the ground
## plane — so the index is the stance and everything downstream of it comes out
## monotonic.
const SPRAWLED: int = 0
const SEMI_UPRIGHT: int = 1
const ERECT: int = 2
const COLUMNAR: int = 3
const COUNT: int = 4

const NAMES: Array[String] = ["sprawled", "semi-upright", "erect", "columnar"]

## How far the drawn view is tilted off vertical, as screen pixels down per pixel
## of world height. The whole of the "2.5" in 2.5D, and a presentation constant:
## nothing that decides anything may read it. Held near the v1 datum because how
## upright a build may stand and how far the view is tilted are one decision —
## in a true plan view an animal standing on legs held underneath itself has no
## legs at all, and past this a tall body's feet draw clear of its own silhouette.
const PERSPECTIVE: float = 0.22

## Least a weight-bearing joint keeps in hand, degrees. A standing joint is never
## at its own stop: a leg with nothing left to straighten cannot push, cannot
## absorb what the ground does to it, and has no direction left to fold in — so
## the IK seed would lose which way the knee bends.
const CARRY_MARGIN_DEG: float = 3.0
## Straightest and tightest any joint may be quoted at. Not 180: two bones
## exactly in line have no fold plane, and a chain solved there pops between its
## two mirror solutions on whichever side a rounding error leaves it.
const STRAIGHTEST_DEG: float = 178.0
const TIGHTEST_DEG: float = 22.0
## Least of the limb the two levers may leave to one of them; below this the
## short segment cannot steer the long one and the fold seed degenerates.
const SHARE_MIN: float = 0.34
const SHARE_MAX: float = 0.66

## Where the reference build's muscle inserts past the joint it works, as a share
## of the bone it pulls on. The datum every lever is quoted against, so a body
## that says nothing about its tendons is geared exactly 1:1 and nothing moves.
const INSERTION_REF: float = 0.30
const INSERTION_MIN: float = 0.15
const INSERTION_MAX: float = 0.50

## Closest a foot may come to its own socket, as a share of the limb's length,
## measured through the air. The floor under `fold` rather than the answer to it:
## it is the line below which the chain stops being solvable at any proportion.
const REACH_MIN: float = 0.22

## Per-posture tuning. Each row is a complete description; nothing falls back.
## `tilt_deg` is the trait; the rest are leanings quoted as multipliers on what
## the body already derives, so a cat's push is still the cat's muscle through
## the cat's levers — the stance only says that a semi-upright build gets more
## out of it, because a limb out to the side has ground to press against that a
## pillar stacked under a shoulder has not.
const TABLE: Array[Dictionary] = [
	{
		# Legs out to the sides, belly near the floor. The spine does much of the
		# walking, which is why undulation is left at full strength here and
		# taken away from the two upright builds. A sprawled elbow is folded to a
		# right angle and a little over, and has the least to give either way.
		"tilt_deg": 12.0,
		"joint_deg": 102.0,
		"joint_lock_deg": 140.0,
		"joint_fold_deg": 35.0,
		"depth_ratio": 0.60,
		"wave_gain": 1.0,
		"feet_down": 2,
		"coupling_gain": 1.0,
		"step_height_gain": 1.0,
		"agility": 1.0,
		"drive": 1.0,
	},
	{
		# Feet drawn in under the body, elbow and knee working fore-and-aft. The
		# joint comes up out of its crouch with the limb, but only halfway: this
		# is the stance that keeps a bend in reserve everywhere, which is where
		# its leap comes from and why it is the springiest row in the table.
		#
		# The undulation is nearly gone here and that is the point of the row: an
		# animal whose limbs swing fore-and-aft under its body walks with its legs,
		# and a back that went on wagging behind them would be a lizard's mechanism
		# left running under a cat. What is left is the little the trunk really does
		# sway when the weight crosses from one diagonal to the other.
		"tilt_deg": 50.0,
		"joint_deg": 132.0,
		"joint_lock_deg": 158.0,
		"joint_fold_deg": 38.0,
		"depth_ratio": 0.92,
		"wave_gain": 0.12,
		"feet_down": 2,
		"coupling_gain": 1.15,
		"step_height_gain": 1.35,
		"agility": 1.30,
		"drive": 1.45,
	},
	{
		# Limbs under the body and swinging in the sagittal plane alone — the
		# stance a long-striding runner stands in, and the one an animal walking
		# on two legs has to be in. Emphatically not a *bipedal* posture: nothing
		# here says how many legs are on the ground. `feet_down` of one is what
		# lets an erect animal have two feet — or on the run, all four — off the
		# ground at once, which is what a springing gait is made of.
		"tilt_deg": 66.0,
		"joint_deg": 150.0,
		"joint_lock_deg": 168.0,
		"joint_fold_deg": 40.0,
		"depth_ratio": 0.88,
		"wave_gain": 0.10,
		"feet_down": 1,
		"coupling_gain": 1.25,
		"step_height_gain": 1.15,
		"agility": 1.15,
		"drive": 1.35,
	},
	{
		# Legs as pillars directly beneath the body. Weight is the point: three
		# feet down at all times, so what comes out is a four-beat amble. Two
		# bones very nearly in line and a joint that barely opens or closes —
		# which is what a column *is*, and where every other consequence of the
		# row comes from: it cannot bend to crouch, cannot fold to spring, and
		# does not lose height walking over its own feet, so what it has instead
		# of a stride bought by sinking is one bought by swinging and a push off
		# the toe at the end of it.
		"tilt_deg": 72.0,
		"joint_deg": 170.0,
		"joint_lock_deg": 177.0,
		"joint_fold_deg": 58.0,
		"depth_ratio": 1.05,
		"wave_gain": 0.08,
		"feet_down": 3,
		"coupling_gain": 0.45,
		"step_height_gain": 0.55,
		"agility": 0.55,
		"drive": 0.55,
	},
]


## What one girdle's limbs actually are: the two levers, the three angles, and
## what each of those angles measures as a length.
class Joint extends RefCounted:
	## Share of the limb's length above the joint, and below it.
	var upper: float = 0.52
	var lower: float = 0.48

	## The included angle at the joint, radians. Pi is a straight limb.
	var stand_angle: float = 0.0
	var lock_angle: float = 0.0
	var fold_angle: float = 0.0

	## The same three as a share of the chain's whole length — what the limb
	## measures end to end at each of them.
	var stand: float = 0.78
	var lock: float = 0.94
	var fold: float = 0.30

	## Half-angle of the fan the socket swings the whole limb through, radians.
	## A genuinely separate joint: a hip that swings far with a knee that barely
	## bends is a horse, and the reverse is a rabbit.
	var swing: float = 1.08
	## How much of the foot is a toe to push off from — the last joint in the
	## chain, and the only propulsion a straight-legged animal has.
	var push: float = 0.15

	## The lever the muscle works this girdle through: the effort arm over the
	## load arm. Close to the joint the same shortening sweeps the foot far and
	## fast and presses lightly; further out it sweeps slowly and presses hard.
	var insertion: float = INSERTION_REF
	var advantage: float = 1.0
	var gear: float = 1.0

	func configure(row: Dictionary, flex: float, fold_range: float,
			share: float, p_swing: float, p_push: float,
			p_insertion: float) -> void:
		upper = clampf(share, SHARE_MIN, SHARE_MAX)
		lower = 1.0 - upper
		# The lever first, because it is a property of where the tendon meets the
		# bone rather than of anything the joint is doing. Both readings are one
		# ratio seen from the two ends and they multiply to one.
		insertion = clampf(p_insertion, INSERTION_MIN, INSERTION_MAX)
		advantage = insertion / INSERTION_REF
		gear = INSERTION_REF / insertion

		var straightest: float = deg_to_rad(STRAIGHTEST_DEG)
		var tightest: float = deg_to_rad(TIGHTEST_DEG)
		stand_angle = clampf(deg_to_rad(float(row["joint_deg"])) - flex,
			tightest, straightest)
		# It can always straighten past where it stands, and at least as far as
		# its stance does. The first leaves a standing joint somewhere to go; the
		# second is what lets a deeply flexed hind leg still extend — a cat's
		# knee stands well bent and opens to nearly straight leaving the ground.
		lock_angle = clampf(maxf(stand_angle + deg_to_rad(CARRY_MARGIN_DEG),
			deg_to_rad(float(row["joint_lock_deg"]))), stand_angle, straightest)
		fold_angle = clampf(stand_angle
			- (stand_angle - deg_to_rad(float(row["joint_fold_deg"])))
			* maxf(fold_range, 0.0), tightest, stand_angle)

		stand = span(stand_angle)
		lock = span(lock_angle)
		fold = maxf(span(fold_angle), REACH_MIN)
		swing = clampf(p_swing, 0.05, PI * 0.5)
		push = clampf(p_push, 0.0, 1.0)

	## What the chain measures end to end at an included angle, as a share of its
	## own length. The cosine rule and nothing else.
	func span(angle: float) -> float:
		var across: float = upper * upper + lower * lower \
			- 2.0 * upper * lower * cos(angle)
		return clampf(sqrt(maxf(across, 0.0)), 0.0, 1.0)

	## The inverse: what angle a chain measuring `share` of itself is folded to.
	## A reading of a solved limb, never an input to one.
	func angle_at(share: float) -> float:
		var s: float = clampf(share, absf(upper - lower), 1.0)
		return acos(clampf((upper * upper + lower * lower - s * s)
			/ maxf(2.0 * upper * lower, 0.000001), -1.0, 1.0))


var spec: BodySpec
var kind: int = SEMI_UPRIGHT
## The trait, radians.
var tilt: float = 0.0
## The same trait at the other end of the limb — the standing angle and its two
## stops, before either girdle's own leaning is applied.
var joint: float = 0.0
var joint_lock: float = 0.0
var joint_fold: float = 0.0
## The body's vertical thickness as a multiple of its drawn width.
var depth_ratio: float = 0.92
var wave_gain: float = 0.30
## How many feet this stance prefers to keep on the floor. A leaning and not a
## limit — how many may be off the ground is the gait's answer — but it is what
## sets the base of the duty factor, which is where weight leans on it.
var feet_down: int = 2
var coupling_gain: float = 1.0
var step_height_gain: float = 1.0
var agility: float = 1.0
var drive: float = 1.0

var fore: Joint = Joint.new()
var hind: Joint = Joint.new()


func _init(p_spec: BodySpec = null, p_kind: int = SEMI_UPRIGHT) -> void:
	spec = p_spec
	configure(p_kind)


func configure(p_kind: int) -> void:
	kind = clampi(p_kind, 0, COUNT - 1)
	_read(TABLE[kind], TABLE[kind], 0.0)


## Carries this carriage part of the way from one stance to another.
##
## A stance change is a movement rather than a swap — a crocodile rising into its
## high walk rotates its limbs under its body over several strides — so the trait
## is interpolated and everything that is a projection of it comes out consistent
## for free: at `t` of the way up, the clearance is the sine of an angle the limbs
## are genuinely at. At either end this is exactly `configure`, to the digit.
##
## One number is deliberately not blended: `depth_ratio` describes how the trunk
## is built, and an animal re-carrying its limbs does not grow a deeper chest.
## Whoever owns the blend owns pinning it back to the build — see Attitude.
func mix(from_kind: int, to_kind: int, t: float) -> void:
	if t <= 0.0 or from_kind == to_kind:
		configure(from_kind)
		return
	if t >= 1.0:
		configure(to_kind)
		return
	var a: Dictionary = TABLE[clampi(from_kind, 0, COUNT - 1)]
	var b: Dictionary = TABLE[clampi(to_kind, 0, COUNT - 1)]
	kind = clampi(from_kind if t < 0.5 else to_kind, 0, COUNT - 1)
	_read(a, b, t)


## Reads one row — or the point `t` of the way between two — into the fields, and
## re-derives both girdles' joints from it. The discrete entries go with
## whichever end is nearer, which is the only way a discrete fact can be read
## mid-movement.
func _read(a: Dictionary, b: Dictionary, t: float) -> void:
	tilt = deg_to_rad(lerpf(float(a["tilt_deg"]), float(b["tilt_deg"]), t))
	joint = deg_to_rad(lerpf(float(a["joint_deg"]), float(b["joint_deg"]), t))
	joint_lock = deg_to_rad(lerpf(float(a["joint_lock_deg"]),
		float(b["joint_lock_deg"]), t))
	joint_fold = deg_to_rad(lerpf(float(a["joint_fold_deg"]),
		float(b["joint_fold_deg"]), t))
	depth_ratio = lerpf(float(a["depth_ratio"]), float(b["depth_ratio"]), t)
	wave_gain = lerpf(float(a["wave_gain"]), float(b["wave_gain"]), t)
	feet_down = int(a["feet_down"]) if t < 0.5 else int(b["feet_down"])
	coupling_gain = lerpf(float(a["coupling_gain"]), float(b["coupling_gain"]), t)
	step_height_gain = lerpf(float(a["step_height_gain"]),
		float(b["step_height_gain"]), t)
	agility = lerpf(float(a["agility"]), float(b["agility"]), t)
	drive = lerpf(float(a["drive"]), float(b["drive"]), t)
	var row := {
		"joint_deg": rad_to_deg(joint),
		"joint_lock_deg": rad_to_deg(joint_lock),
		"joint_fold_deg": rad_to_deg(joint_fold),
	}
	if spec == null:
		fore.configure(row, 0.0, 1.0, 0.52, 1.08, 0.15, INSERTION_REF)
		hind.configure(row, 0.0, 1.0, 0.52, 1.08, 0.15, INSERTION_REF)
		return
	fore.configure(row, deg_to_rad(spec.fore_flex_deg), spec.fore_fold_range,
		spec.upper_share(true), deg_to_rad(spec.fore_swing_deg), spec.toe_push,
		spec.fore_insertion)
	hind.configure(row, deg_to_rad(spec.hind_flex_deg), spec.hind_fold_range,
		spec.upper_share(false), deg_to_rad(spec.hind_swing_deg), spec.toe_push,
		spec.hind_insertion)


func of(p_fore: bool) -> Joint:
	return fore if p_fore else hind


func name() -> String:
	return NAMES[kind]


# ------------------------------------------------------------- projections ----

## What a limb of this length measures seen from above — the radius of the disc
## its foot may be set down anywhere inside.
func plan_reach(limb_length: float) -> float:
	return limb_length * cos(tilt)


## How far off the ground the same limb holds the body at full plan reach.
func clearance(limb_length: float) -> float:
	return limb_length * sin(tilt)


## How far out to the side it carries its foot: the plan reach with the same
## cosine taken out again, because the plane the limb swings in has rotated by
## the angle the limb itself has. What is left of the plan reach after this is
## the fore-and-aft excursion — so an upright animal spends its reach walking and
## a sprawled one spends it standing wide.
func track(limb_length: float) -> float:
	return plan_reach(limb_length) * cos(tilt)


## How far inboard of its own socket a foot may be set down, as a share of the
## socket's offset from the spine. Nothing on a sprawled limb, which cannot bring
## its foot under the shoulder at all; most of the way to the midline on a
## columnar one, whose whole stance is standing underneath itself.
func adduction() -> float:
	return 1.0 - cos(tilt)


## How much of itself the limb measures on the screen — the plan reach across,
## plus whatever the perspective makes of the height. Used only to normalise,
## never to decide where a foot goes.
func drawn_reach(limb_length: float) -> float:
	var flat: float = cos(tilt)
	var up: float = sin(tilt) * PERSPECTIVE
	return limb_length * sqrt(flat * flat + up * up)


## How high a limb of `bone`, standing at `extension` of itself, holds the body
## with its foot where the stance puts it.
##
## The one closed form both the census's rest datum and the live gait read, and
## it is Pythagoras on a stance rather than `clearance` of the same leg: a real
## rest stance is not out at the limb's full plan reach. The lateral offset takes
## as much of the plan disc as the swing plane has not rotated away, the bias
## spends a fraction of what is left fore or aft, and the height is the third
## side. Asking `clearance` instead is what left a columnar build solved twenty
## degrees more bent than it stands.
func stance_clearance(bone: float, extension: float, width: float,
		bias: float) -> float:
	var reach: float = bone * extension
	var stance: float = plan_reach(reach)
	var lat: float = stance * cos(tilt) * width
	var fore_aft: float = sqrt(maxf(stance * stance - lat * lat, 0.0)) * bias
	var out: float = sqrt(minf(lat * lat + fore_aft * fore_aft, reach * reach))
	return sqrt(maxf(reach * reach - out * out, 0.0))


## The fore-and-aft radius one pair's resting foot is placed out of — the same
## split `stance_clearance` makes, asked of the half that is left over. What a
## stance being *considered* is measured with, before any body is solved into it.
func fore_aft_reach(bone: float, extension: float, width: float) -> float:
	var stance: float = plan_reach(bone * extension)
	var lat: float = stance * cos(tilt) * width
	return sqrt(maxf(stance * stance - lat * lat, 0.0))


# --------------------------------------------------------------- the view ----

## Screen offset for something standing at world height `h`, drawn against a
## reference plane. Positive y is down the screen, so anything below the
## reference is pushed down and anything above it lifted — the whole of how
## height reads in a top-down picture.
static func drop(h: float, reference: float) -> Vector2:
	return Vector2(0.0, (reference - h) * PERSPECTIVE)


## The same projection for a body that is not level. `pitch` and `roll` are
## gradients in world height per world pixel along and across the animal, and a
## gradient through this projection is a shear — the same transform as `drop`
## with two terms that vary over the body instead of being constant across it.
## So there is still no second renderer and no lean drawn over the top of one.
static func tip(centre: Vector2, fwd: Vector2, pitch: float, roll: float,
		base: Vector2) -> Transform2D:
	var perp := Vector2(-fwd.y, fwd.x)
	var gradient: Vector2 = (fwd * pitch + perp * roll) * -PERSPECTIVE
	return Transform2D(
		Vector2(1.0, gradient.x),
		Vector2(0.0, 1.0 + gradient.y),
		base - Vector2(0.0, gradient.dot(centre)))
