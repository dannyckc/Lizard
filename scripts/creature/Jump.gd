## One jump, from the pose the animal was already in to the pose it recovers into.
##
## `Leap` says what this body could do; this is the body doing it. It owns two
## things and deliberately nothing else: how much of the store is currently wound,
## and what each girdle's joints are being asked to do about it. Everything a
## jump *looks* like is downstream of that second number, because a girdle's joint
## angle is already what decides how high the body rides, how far its feet reach,
## how wide it stands and how it is drawn — so a crouch, a push-off, a tuck and a
## landing are the same one number moved to four different places, and there is no
## animation anywhere in this file.
##
## The number is signed, and the sign is the whole design. `Articulation` gives
## every girdle three angles — how far it folds, what it stands at, how far it
## locks out — and a joint is somewhere between two of them at all times. Positive
## is toward the fold and negative is toward the lock, so:
##
##   * a gather is a small positive on the driving girdle and a small negative on
##     the other, which is weight moving off the front of the animal and onto the
##     back of it;
##   * a charge is that positive deepening as the store winds;
##   * a push-off is the same number swinging hard negative, which extends the
##     legs, and because the body's height is read off the legs holding it up, the
##     body genuinely rises *before* it leaves the ground;
##   * a flight is the number relaxing, then going negative again as the ground
##     comes up, which is a leg reaching for a landing;
##   * and an impact is it going sharply positive, which is a joint folding under
##     load.
##
## None of those is drawn and none of them is keyed. `Gait._stance_extension`
## reads the number, the limb stands at a different fraction of itself, and the
## stance, the height, the silhouette, the height bands and the picture all follow
## because every one of them was already read off how extended a leg is.
##
## What the phases are for is the *order*, and the order is a real claim about
## animals: nothing pushes before it has gathered, nothing gathers on a foot that
## is in the air, and nothing lands on a leg it has not put out. Each transition
## below is either a measurement coming true or a limb's own swing period
## elapsing, and there is not one number in the file that is a duration somebody
## chose.
class_name Jump
extends RefCounted

## Standing on it, and nothing being asked. The state a creature that cannot jump
## never leaves, however long the key is held.
const STANDING: int = 0
## Weight shifting: the driving feet coming under the body and the load coming off
## the others. Before the crouch, because a body cannot gather onto a leg it has
## not got its weight over yet.
const GATHER: int = 1
## Crouching, and winding whatever this animal has to wind. The only phase that
## accumulates, and it stops accumulating at the top rather than being cut off.
const LOAD: int = 2
## The extension. The feet are still down and the body is being pushed up off
## them; it leaves at the end of this rather than the start.
const THRUST: int = 3
## Off the ground with nothing to do about it.
const FLIGHT: int = 4
## Off the ground with the floor close enough to put the legs out for.
const REACH: int = 5
## On the ground and taking the arrival out through the joints.
const ABSORB: int = 6
## And standing back up out of it.
const RECOVER: int = 7

const PHASE_NAMES: Array[String] = ["standing", "gathering", "charging",
	"pushing off", "leaping", "reaching", "absorbing", "recovering"]

## How far the joints move during the weight shift, as a share of their travel.
## Small — it is a body settling back over its hips, not a crouch — and the two
## girdles get it in opposite directions because that is what shifting weight is.
const GATHER_LOAD: float = 0.22

## How much the girdle that is not driving folds, against the one that is. A
## quadruped's forelimbs bend as it gathers; they do not gather. Derived per
## build from the shares `Leap` measured, so an animal that pushes with both ends
## crouches with both ends and nothing had to know which kind it was.
const CARRIED_FOLD: float = 0.45

## How far the driving joints are thrown open by the push, as a share of their
## travel toward the lock. All of it: a push-off is the one moment a limb is
## genuinely at its own stop, and `Articulation` already keeps that stop a few
## degrees short of straight so the chain never loses which way it folds.
const THRUST_EXTEND: float = 1.0
## And how much of that the other girdle takes. It is not pushing, but it is
## attached to a body that is being pushed, and a limb whose shoulder is
## accelerating upward straightens under it.
const CARRIED_EXTEND: float = 0.35

## How far a body tucks at the top of its own arc, per unit of the charge it left
## with. A hard jump gathers in the air and a weak one hangs, which is the same
## distinction on the way up as it is on the way down.
const AIR_TUCK: float = 0.45

## How far the legs are put out for a landing. Short of the lock, and that is the
## point rather than a margin: a limb arriving at the ground already straight has
## nothing left to fold, and what it does with the impact instead is transmit it.
const REACH_EXTEND: float = 0.55

## How much of the fold a landing may spend, at most. Never the whole of it — a
## joint driven to its own stop by an arrival is a joint that has run out of
## suspension, and what happens after that is not absorption.
const ABSORB_DEPTH: float = 0.85

## Phase lengths that are not a limb's own swing, in multiples of one that is.
const ABSORB_SWINGS: float = 0.9
const RECOVER_SWINGS: float = 1.8

## Least of the driving girdle that has to be on the ground for a push to be worth
## anything. A jump is a push against the floor, so a body caught mid-stride with
## its driving feet in the air has very little to push with — and it is a share
## rather than a refusal, because a creature that must have both hind feet exactly
## down would be one that could never jump while walking.
const CONTACT_FLOOR: float = 0.35


# --- what the body is doing about it -----------------------------------------

var phase: int = STANDING
## How much of the store is wound, 0..1. The charge, and it is a real fraction of
## a real quantity rather than a power meter: `Leap.peak` reads it as how far the
## joints were folded before the push, which is how much travel there is to push
## through and how much elastic there is to give back.
var charge: float = 0.0
## What each girdle's joint is being asked for, eased. Positive folds toward the
## joint's own fold stop, negative extends toward its lock. x is the fore girdle
## and y the hind, matching every other pair of girdle readings in the simulation.
var load: Vector2 = Vector2.ZERO
## True for the one tick the body leaves the ground, with the apex it leaves for.
## Read by the creature, which owns the vertical axis; nothing here touches it.
var took_off: bool = false
var launch_peak: float = 0.0
## How hard the animal was pointed somewhere when it let go, 0..1. What makes a
## running jump carry and a standing one go straight up.
var launch_lean: float = 0.0

## How fast the joints are being moved this tick, in response per second.
##
## Published rather than kept private because the body has to know: a girdle whose
## joint is being driven open changes length on this timescale rather than on the
## walk's, and a body that followed it at walking pace would extend its legs fully
## and only then begin, slowly, to rise on them. See Gait.update, which takes it
## alongside the demand itself.
var drive: float = 0.0

var _timer: float = 0.0
var _want: Vector2 = Vector2.ZERO
var _swing: float = 0.25
## How much of the fold the landing asked for, held across the absorb so the
## recovery has something to come back from.
var _impact_fold: float = 0.0


func reset() -> void:
	phase = STANDING
	charge = 0.0
	load = Vector2.ZERO
	_want = Vector2.ZERO
	_timer = 0.0
	_impact_fold = 0.0
	drive = 0.0
	took_off = false
	launch_peak = 0.0
	launch_lean = 0.0


## One tick of it.
##
## `held` is the vertical command being asked for — the key down, or whatever an
## AI is doing in its place. `contact` is the share of each girdle's limbs
## actually standing on something, measured off the gait rather than assumed, and
## `lean` is how hard the animal is being driven forward at the moment it lets go.
##
## Everything else is read: the elevation says whether there is ground underfoot
## and how hard the body arrived, and `Leap` says what this particular anatomy can
## do about any of it.
func advance(delta: float, held: bool, leap: Leap, elevation: Elevation,
		loco: Locomotion, contact: Vector2, lean: float) -> void:
	took_off = false
	if leap == null or elevation == null or loco == null:
		return
	_timer += delta
	_swing = maxf(leap.charge_time, 0.05)

	# Off the ground without having pushed — walked off a ledge, or thrown by
	# something. It is still a body in the air with a landing coming, so it joins
	# the arc at the point it is actually at rather than needing a phase of its
	# own. This is also what makes the whole machine safe to run on a creature that
	# never jumps: everything below is either a consequence of the ground being
	# there or of it not being.
	if elevation.is_airborne() and phase < FLIGHT:
		_enter(FLIGHT)

	match phase:
		STANDING:
			_want = Vector2.ZERO
			charge = 0.0
			if held and elevation.is_grounded():
				_enter(GATHER)
		GATHER:
			# Weight off the girdle that is not pushing and onto the one that is.
			# Opposite signs, because that is the whole of what shifting weight is:
			# the loaded end settles into its joints and the unloaded end comes up.
			_want = Vector2(
				-GATHER_LOAD * leap.share.y * 0.5 + GATHER_LOAD * leap.share.x,
				-GATHER_LOAD * leap.share.x * 0.5 + GATHER_LOAD * leap.share.y)
			if not held:
				_enter(THRUST)
			elif _timer >= leap.gather_time:
				_enter(LOAD)
		LOAD:
			# The one accumulating phase, and it saturates rather than stopping.
			# Held past the top the animal simply stays in the crouch it has reached:
			# the store is full, the joints are as folded as they are going to get,
			# and there is nothing further for the muscle to wind.
			charge = clampf(charge + delta / maxf(leap.charge_time, 0.001), 0.0, 1.0)
			_want = _crouch(leap, charge)
			if not held:
				_enter(THRUST)
		THRUST:
			# Legs open. The body rises on its own legs while this runs, because the
			# height it is carried at is read off how extended they are — so the push
			# is visible before there is any elevation at all, which is what makes it
			# read as a push rather than a launch.
			_want = _extend(leap)
			if _timer >= leap.thrust_time:
				_release(leap, elevation, contact, lean)
		FLIGHT:
			# Gathered at the top by however hard it left, and letting that go as it
			# falls. Nothing is holding these legs out — see Gait, which draws a limb
			# with no ground under it in toward the body — so what this decides is
			# only how tightly.
			_want = Vector2(AIR_TUCK, AIR_TUCK) * charge \
				* clampf(elevation.rate / maxf(_takeoff_rate(), 1.0), 0.0, 1.0)
			if elevation.landed:
				_land(leap, elevation, loco)
			elif _fall_time(elevation) <= leap.gather_time + leap.thrust_time:
				_enter(REACH)
		REACH:
			# Legs down, and short of locked. A limb that arrives straight has
			# nothing left to fold and passes the whole arrival into the body.
			_want = _reach(leap, loco)
			if elevation.landed:
				_land(leap, elevation, loco)
			elif elevation.is_grounded():
				_enter(RECOVER)
		ABSORB:
			_want = _absorb(leap, loco)
			if _timer >= _swing * ABSORB_SWINGS:
				_enter(RECOVER)
		RECOVER:
			_want = Vector2.ZERO
			charge = 0.0
			if _timer >= _swing * RECOVER_SWINGS or (held and elevation.is_grounded()):
				_enter(STANDING)
				# A key still down at the bottom of a landing is the next jump, and
				# a body that has just absorbed one is already half gathered for it.
				if held:
					_enter(GATHER)

	# Eased rather than set, and this is the whole of "no snapping". Joints move at
	# a rate, and the rate is the limb's own: a heavy leg with a long pendulum
	# gathers slowly and pushes slowly, a light one snaps through both, and neither
	# of them was given a speed. What the phase decides is where the joint is
	# going; how fast it gets there is anatomy.
	drive = _response(leap) if active() else 0.0
	load = load.lerp(_want, 1.0 - exp(-maxf(drive, 0.0001) * delta))


## Where the joints go while the store winds.
##
## Each girdle folds by its own share of the drive, so a build that pushes with
## its hind pair crouches behind and merely bends in front, and one that pushes
## with both crouches with both. The shares are `Leap`'s measurement of which end
## of this animal has the muscle, the travel and the spring, so nothing here knows
## what a quadruped is.
func _crouch(leap: Leap, amount: float) -> Vector2:
	var lead: float = maxf(leap.share.x, leap.share.y)
	if lead <= 0.0:
		return Vector2.ZERO
	return Vector2(
		amount * lerpf(CARRIED_FOLD, 1.0, leap.share.x / lead),
		amount * lerpf(CARRIED_FOLD, 1.0, leap.share.y / lead))


## And where they go to push. The same shares read the other way: the girdle that
## is driving throws itself open, and the one that is not straightens under a body
## that is accelerating away from it.
func _extend(leap: Leap) -> Vector2:
	var lead: float = maxf(leap.share.x, leap.share.y)
	if lead <= 0.0:
		return Vector2.ZERO
	return -Vector2(
		lerpf(CARRIED_EXTEND, THRUST_EXTEND, leap.share.x / lead),
		lerpf(CARRIED_EXTEND, THRUST_EXTEND, leap.share.y / lead))


## Putting the legs out for the ground.
##
## The bracing girdle leads, and which one that is falls out of where it is on the
## animal rather than out of a rule — see `Leap.brace`. A quadruped comes down
## nose-first out of a ballistic arc, so its forelimbs meet the floor first and
## reach furthest for it; a two-legged animal has only the pair it left with, and
## they do both jobs.
func _reach(leap: Leap, loco: Locomotion) -> Vector2:
	var brace: int = leap.brace(loco.forelimbs_bear)
	var out := Vector2(-REACH_EXTEND, -REACH_EXTEND)
	# The girdle that is not meeting the ground first reaches less far, so it
	# arrives with more of its own fold still in hand — which is what it will need,
	# because it lands second and onto a body that is already folding.
	out[1 if brace == Limb.FRONT else 0] = -REACH_EXTEND * 0.7
	return out


## And folding under the arrival.
##
## How deep is how much of what the girdle could have caught the impact actually
## used — see `Leap.absorb`, which is the same work-over-distance the push was,
## run backwards. A landing well inside what the legs can take barely bends them;
## one at the limit folds them as far as the joint goes. The bracing girdle takes
## the larger share because it arrives first.
func _absorb(leap: Leap, loco: Locomotion) -> Vector2:
	var brace: int = leap.brace(loco.forelimbs_bear)
	var deep: float = _impact_fold
	var out := Vector2(deep, deep)
	out[1 if brace == Limb.FRONT else 0] = deep * 0.6
	return out


## How quickly the joints move toward what the phase is asking for.
##
## Four time constants over the length of the phase itself, so each one actually
## arrives at what it was going for rather than being interrupted part way. Which
## makes the push quick and the recovery slow without either being told to: the
## phase lengths are the limb's own pendulum, and this is only spreading the
## movement across whichever one is running.
func _response(leap: Leap) -> float:
	var window: float = _swing
	match phase:
		GATHER:
			window = leap.gather_time
		LOAD:
			window = leap.charge_time
		THRUST:
			window = leap.thrust_time
		FLIGHT, REACH:
			window = leap.gather_time + leap.thrust_time
		ABSORB:
			window = _swing * ABSORB_SWINGS * 0.4
		RECOVER:
			window = _swing * RECOVER_SWINGS * 0.5
	return 4.0 / maxf(window, 0.02)


## The push completing.
##
## Everything that decides how far this animal goes has already been decided by
## the time this runs: what its anatomy is worth is `Leap`, and how much of the
## store it wound is `charge`. What is left here is the one thing that is about
## this instant rather than about the body — whether the feet that were supposed
## to be pushing were actually on anything.
func _release(leap: Leap, elevation: Elevation, contact: Vector2, lean: float) -> void:
	var footing: float = leap.share.x * contact.x + leap.share.y * contact.y
	launch_lean = clampf(lean, 0.0, 1.0)
	launch_peak = leap.peak(charge) * lerpf(CONTACT_FLOOR, 1.0, clampf(footing, 0.0, 1.0))
	# A body that has not got a jump does not get one for having held the key. The
	# gather and the crouch were real — it shifted its weight and bent what it
	# could bend — and this is where it finds out that is all there was.
	took_off = leap.capable and launch_peak > 0.0 and elevation.is_grounded()
	if not took_off:
		launch_peak = 0.0
		_enter(RECOVER)
		return
	_enter(FLIGHT)


## And the arrival.
##
## How much fold it costs is measured rather than chosen: the speed the body came
## in at, against the speed that girdle could have caught — see `Leap.absorb`.
## An animal stepping off a kerb barely flexes and one that has fallen a long way
## folds to its stops, and the same line does both.
func _land(leap: Leap, elevation: Elevation, loco: Locomotion) -> void:
	var brace: int = leap.brace(loco.forelimbs_bear)
	var caught: float = leap.absorb.x if brace == Limb.FRONT else leap.absorb.y
	_impact_fold = clampf(elevation.impact / maxf(caught, 1.0), 0.0, 1.0) * ABSORB_DEPTH
	charge = 0.0
	_enter(ABSORB)


## How long until this body reaches the ground, in seconds. The ballistic
## solution and nothing else — height, the rate it is going, and gravity.
func _fall_time(elevation: Elevation) -> float:
	var v: float = elevation.rate
	var h: float = maxf(elevation.height, 0.0)
	var g: float = Elevation.GRAVITY
	return (v + sqrt(maxf(v * v + 2.0 * g * h, 0.0))) / g


## How fast the body left, for scaling the tuck. Read off what it was launched
## for rather than kept, so a jump interrupted mid-arc still normalises against
## something real.
func _takeoff_rate() -> float:
	return sqrt(2.0 * Elevation.GRAVITY * maxf(launch_peak, 1.0))


func _enter(next: int) -> void:
	phase = next
	_timer = 0.0


## Whether the body is in the middle of one, which is every phase except standing
## still. Read by the creature to decide whether the jump has anything to say
## about the pose at all.
func active() -> bool:
	return phase != STANDING


## Whether the animal is winding one up right now — the half of it a player can
## still change their mind about.
func charging() -> bool:
	return phase == GATHER or phase == LOAD


func phase_name() -> String:
	return PHASE_NAMES[phase]
