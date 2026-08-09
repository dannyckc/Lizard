## What one girdle's limbs actually are: how the two bones divide them, what
## angle the joint between them is carried at, and how far that joint may open
## and close.
##
## The fourth of the derived descriptors, and the one the other three were
## quietly assuming. `Physique` reads how much animal there is, `Stature` how
## tall it stands, `Locomotion` how it walks — and all three ask a limb how
## extended it is, which used to be answered by a number typed into a preset.
## A leg is not extended by a number. It is extended by an angle at its elbow or
## its knee, and every other reading of the limb is that angle seen from
## somewhere: how long the chain measures, how high it holds the body, how much
## of itself it has left to fold away, how straight it is drawn.
##
## Two things follow from making the angle the trait, and both were unreachable
## before:
##
##   * **A column is a real pose.** At 173 degrees the two bones are very nearly
##     one bone and the limb stands as a pillar — which is what a graviportal
##     animal does and what the old extension number could not express, because
##     the working envelope was capped a long way below it and the leg came out
##     permanently half-crouched however the preset was tuned.
##   * **The two ends of an animal can differ.** A girdle is the unit, not the
##     creature, so a build may carry a straight strut in front and a folded
##     spring behind — which is a cat, and it is most of what separates one from
##     a scaled lizard. Nothing here knows that; it is two rows of the same table.
##
## What a species actually carries is small: how much more flexed than its stance
## each girdle stands, how far that joint folds, how the bones divide, and how
## wide the socket swings. Everything below is those four read through the stance
## the animal is in — see Posture, which owns the base angles, for the same
## reason it owns the tilt: how upright a limb is held and how straight its joint
## is carried are one fact about a skeleton, and an animal standing on sprawled
## legs with locked elbows does not exist.
class_name Articulation
extends RefCounted

## Least a weight-bearing joint keeps in hand, in degrees. A standing animal's
## joint is never at its own stop: a leg with nothing left to straighten cannot
## push, cannot absorb what the ground does to it, and — the reason this is a
## constraint rather than taste — has no direction left to fold in, so the IK
## seed loses which way the knee bends. Small, because on a columnar build the
## difference between standing and locked is a couple of degrees of a joint that
## is already nearly straight.
const CARRY_MARGIN_DEG: float = 3.0
## Straightest any joint may be quoted at. Not 180: two bones exactly in line
## have no fold plane, and a chain solved there pops between its two mirror
## solutions on whichever side of the axis a rounding error leaves it.
const STRAIGHTEST_DEG: float = 178.0
## Tightest any joint may be quoted at. A limb folded further than this is a limb
## whose foot is inside its own shoulder.
const TIGHTEST_DEG: float = 22.0
## Least of the limb the two bones may leave to one of them. Bones this uneven
## are a chain whose short segment cannot steer the long one, and the fold seed
## degenerates.
const SHARE_MIN: float = 0.34
const SHARE_MAX: float = 0.66


## One girdle's joint: the two bones, the three angles, and what each of those
## angles measures as a length.
##
## The angle is the fact and the share is the projection of it, exactly as the
## posture's tilt is the fact and the plan reach is the projection. Every
## consumer wants the length — a chain spans so far, a body is held so high — so
## the conversion is done once here rather than at each of the dozen places that
## ask.
class Joint extends RefCounted:
	## Share of the limb's length in the proximal bone, and in the distal one.
	## Their ratio is the whole of the difference between a graviportal leg, whose
	## weight is carried high and close to the body, and a cursorial one that
	## keeps a long light segment out at the bottom to swing.
	var upper: float = 0.52
	var lower: float = 0.48

	## The included angle at the joint, in radians. Pi is a straight limb.
	var stand_angle: float = 0.0
	var lock_angle: float = 0.0
	var fold_angle: float = 0.0

	## The same three, as a share of the chain's whole length — what the limb
	## measures end to end at each of them. `stand` replaces what used to be a
	## `stance_reach` parameter, `lock` a `limb_max_reach` one, and `fold` a
	## constant floor shared by every animal in the game.
	var stand: float = 0.78
	var lock: float = 0.94
	var fold: float = 0.30

	## Half-angle of the fan the socket swings the whole limb through, in radians.
	## The other joint, and a genuinely separate one: a hip that swings far with a
	## knee that barely bends is a horse, and the reverse is a rabbit.
	var swing: float = 1.08

	## How much of the foot is a toe to push off from, 0 to 1.
	##
	## The last joint in the chain, and the only propulsion a straight-legged
	## animal has. A limb held near vertical cannot lengthen its stride by bending
	## — that is the whole point of standing like a column — so what carries the
	## body over a planted foot at the end of stance is the foot itself rolling
	## forward onto its toe, which raises the ankle and with it everything above
	## it. Small, subtle, and the difference between an elephant walking and an
	## elephant being slid along the ground.
	var push: float = 0.15

	## Sets every angle from a stance's own base angles and one girdle's leanings.
	##
	## `flex` is how much more flexed than its stance this girdle stands, in
	## radians, and negative is straighter. `fold_range` is how far it may close,
	## against what its stance closes to — under one is a joint that cannot be
	## folded away, which is the whole of why a heavy columnar animal can neither
	## crouch nor jump and needed nothing written down to say so.
	func configure(posture: Posture, flex: float, fold_range: float,
			upper_share: float, p_swing: float, p_push: float) -> void:
		upper = clampf(upper_share, SHARE_MIN, SHARE_MAX)
		lower = 1.0 - upper
		var straightest: float = deg_to_rad(STRAIGHTEST_DEG)
		var tightest: float = deg_to_rad(TIGHTEST_DEG)

		stand_angle = clampf(posture.joint - flex, tightest, straightest)
		# It can always straighten past where it stands, and at least as far as its
		# stance does. Both halves are needed: the first is what leaves a standing
		# joint somewhere to go, and the second is what makes a deeply flexed hind
		# leg still able to extend — a cat's knee stands at a hundred and ten
		# degrees and opens to very nearly straight when the animal leaves the
		# ground, and quoting its limit against its resting angle would deny it that.
		lock_angle = clampf(maxf(stand_angle + deg_to_rad(CARRY_MARGIN_DEG),
			posture.joint_lock), stand_angle, straightest)
		fold_angle = clampf(stand_angle - (stand_angle - posture.joint_fold)
			* maxf(fold_range, 0.0), tightest, stand_angle)

		stand = span(stand_angle)
		lock = span(lock_angle)
		fold = span(fold_angle)
		swing = clampf(p_swing, 0.05, PI * 0.5)
		push = clampf(p_push, 0.0, 1.0)

	## What the chain measures end to end at an included angle of `angle`, as a
	## share of its own length. The cosine rule and nothing else: two bones with a
	## known angle between them are a triangle, and this is its third side.
	func span(angle: float) -> float:
		var across: float = upper * upper + lower * lower \
			- 2.0 * upper * lower * cos(angle)
		return clampf(sqrt(maxf(across, 0.0)), 0.0, 1.0)

	## The inverse: what angle a chain measuring `share` of itself is folded to.
	## Used to report what a solved limb is actually doing, never to pose one.
	func angle_at(share: float) -> float:
		var s: float = clampf(share, absf(upper - lower), 1.0)
		var cosine: float = (upper * upper + lower * lower - s * s) \
			/ maxf(2.0 * upper * lower, 0.000001)
		return acos(clampf(cosine, -1.0, 1.0))


var fore: Joint = Joint.new()
var hind: Joint = Joint.new()


## Re-derives both girdles from the stance and the species.
func configure(posture: Posture, p: CreatureParams) -> void:
	if posture == null or p == null:
		return
	fore.configure(posture, deg_to_rad(p.fore_flex_deg), p.fore_fold_range,
		p.fore_upper_share, deg_to_rad(p.fore_swing_deg), p.toe_push)
	hind.configure(posture, deg_to_rad(p.hind_flex_deg), p.hind_fold_range,
		p.hind_upper_share, deg_to_rad(p.hind_swing_deg), p.toe_push)


## The girdle a limb belongs to. `pair` is Limb.FRONT or Limb.REAR.
func of(pair: int) -> Joint:
	return fore if pair == Limb.FRONT else hind
