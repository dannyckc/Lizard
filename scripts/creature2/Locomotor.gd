## What this body can do about moving itself — Locomotion's successor, reading
## the one census.
##
## Nothing here is a setting and nothing here names a species. Five laws do the
## whole of it, and every number below is one of them applied to the body Corpus
## has just counted:
##
##   * **Force over mass.** Muscle goes as a cross-section and weight goes as a
##     volume, so push-per-kilo falls as the cube root of size. That ratio —
##     `power` — is what makes a heavy animal slow to get going and slow to turn.
##     Fat is in the mass and not in the muscle, so a padded animal is duller for
##     free. And the force is spent out of the speed: muscle shortening fast has
##     little left to press with, so the push fades as the body works up toward
##     everything it can ask of itself, and the top speed is an arrival rather
##     than an assignment. There is no acceleration parameter — see `push_left`.
##   * **A leg is a pendulum.** Swing time goes as the square root of length, so a
##     long leg is a slow leg however strong the animal wearing it.
##   * **A foot on a sphere.** A planted foot is a point on a sphere of the leg's
##     own radius about its socket, so how far it travels fore-and-aft is a
##     question about length, the angle it is carried at, and how far the body
##     will sink while it passes over it. Stride is that answer, not a parameter.
##   * **Feet stay down.** How many of them a stance keeps on the floor is what a
##     duty factor *is*, so the time a limb has in the air is the rest of its
##     cycle and never more.
##   * **A body cannot outrun its own legs.** The three above are already a speed:
##     stride over cycle, and no faster. See `leg_speed`, which is a ceiling on
##     the body rather than a consequence of it — the difference between feet
##     carrying an animal and feet being flicked through a blur beneath one.
##
## Refreshed once per tick from the census, ahead of everything that reads it.
## The one-tick lag is deliberate and harmless: what an animal weighs and how much
## muscle it has are properties of a body being eaten over seconds.
class_name Locomotor
extends RefCounted

## The default build's mass and locomotor muscle, pinned exactly (the v1 lesson:
## gait behaviour turns on fractions of a per cent of physique drift). `power` is
## a ratio against these, so the reference cat comes out at exactly 1.0 and every
## other body is quoted against the animal the constants below were sized on.
## Re-pin both from CorpusProbe whenever the default knots move.
const REFERENCE_MASS: float = 30523.043797
const REFERENCE_MUSCLE: float = 7902.545570

## Body length of the default build, so rotational inertia is a ratio rather than
## an absolute — see `turn_rate`.
const REFERENCE_LENGTH: float = 164.0

## How far the body drops over a stride, as a share of the height it stands at —
## where an upright animal's stride comes from and it cannot come from anywhere
## else: a leg held near vertical has almost no plan-view reach to swing its foot
## across, so the only way that foot gets out in front is for the shoulder to come
## down as it goes. Spent out of the joint rather than granted: sinking is the limb
## *folding* a little as the body passes over it, so an animal whose knee barely
## closes cannot buy stride that way however much it would like to.
const STRIDE_SINK: float = 0.12
## How much of the travel a limb has it actually uses. Short of all of it, so a
## walking foot is not permanently sitting on its own envelope boundary.
const STRIDE_SHARE: float = 0.80
## Least of the disc that is kept for walking rather than for standing wide. The
## stance and the stride are spent out of one budget — every pixel of the leg's
## reach spent holding the foot out to the side is a pixel it cannot travel fore
## and aft — so past here the stance comes in rather than the stride going to
## nothing.
const FORE_SHARE: float = 0.55
## How much of the disc the stride is measured across; the rest is headroom.
const TRAVEL_MARGIN: float = 0.94
## Most of it the stance and the sway between them may use up.
const LAT_CEILING: float = 0.88
## Narrowest a stance may be squeezed to by that reservation. A body thrown about
## hard enough to want its feet directly underneath it would be standing on a
## line, and a creature does not balance on one.
const STANCE_FLOOR: float = 0.45
## Largest share of a stride a foot may be aimed ahead by: the lead is spent out
## of the same travel the stride is measured in, so at 1.0 the two cancel.
const LEAD_CEILING: float = 0.75

## How much of the room the lift limit leaves a body actually spends. Short of all
## of it, because a gait held at exactly its ceiling has no free slot at any
## instant — a foot goes up only as another comes down, so which foot goes next is
## whichever has waited longest and the footfall pattern never gets to choose.
const SLOT_MARGIN: float = 0.85

## Swing time of a limb one pixel long, seconds — the constant of proportionality
## on sqrt(length / gravity). Sized so the reference build lands on a quarter-
## second step, which is the only thing an arbitrary constant in a made-up gravity
## can honestly be pinned to.
const SWING_PERIOD: float = 1.6
## Fastest any limb may be flicked through a step, whatever the arithmetic asks
## for. A backstop rather than a working floor — what holds a swing open is
## `hurried_swing`, the limb's own pendulum with as much taken off it as muscle
## can take.
const SWING_FLOOR: float = 0.045
## How far fibre composition moves the swing's drive either way of the mixed
## default. Small on purpose: composition is a grade of muscle, not a second
## engine.
const TWITCH_SPAN: float = 0.08
## How much of a limb's free swing muscle takes off it flat out. A leg is thrown
## as well as dropped, but not by an unbounded amount: a cat's foreleg makes a free
## swing of about a quarter second and its swing phase at a flat gallop is a tenth,
## so a limb going as hard as it can goes at something near two and a half times
## the rate it would fall at. Past that the limb is being driven harder than the
## same muscle drives the body along, which is an animal flailing on the spot.
const SWING_HURRY: float = 0.60

## How much longer a heavy animal keeps its feet down than its stance alone says.
const DUTY_LOAD: float = 0.10
const DUTY_MIN: float = 0.35
const DUTY_MAX: float = 0.86
## How much of its duty factor a body gives up between standing and flat out, and
## the least it may fall to. Every animal keeps fewer feet down the faster it goes
## — that is what separates a walk from a trot and a trot from a gallop.
const DUTY_PACE: float = 0.22
const DUTY_SPRINT: float = 0.28

## Ground push of the reference build while its feet are pressing, in gravities.
## The one constant of proportionality in the propulsion, and it replaces a
## per-species acceleration outright: a number there could not know how much muscle
## stood behind the girdles or what levers it worked through. Sized on the
## reference cat, whose power is 1.0 by construction: it gets away at about a
## third of a gravity, which is what the v1 oracle's cat measures too.
const PUSH_REFERENCE: float = 0.23
## How far fibre composition moves the push. Wider than TWITCH_SPAN, and the
## difference is what is being asked of the muscle: a swing is one limb thrown
## through an arc, acceleration is sustained mechanical power, and power is where
## fast fibre earns its name. Exactly a no-op at 0.5.
const PUSH_TWITCH: float = 0.25
## Hardest a body may push against the ground, in gravities. Traction, and the one
## ceiling on acceleration that is not about muscle: past somewhere near its own
## weight a foot stops leaning on friction and starts slipping. Muscle laid on past
## this is wasted rather than banked — the census still weighs it and the stamina
## still feeds it, but the ground will not take the extra force.
const PUSH_CEILING: float = 0.55

## When a biped's tail reaches the floor with something to spare, and when it is
## thick enough at the root to be stood on. Both are shares — of the hip height the
## drop is measured against, and of the hip girth the root is — and between them
## they are the whole of whether an animal has a fifth limb.
const PROP_REACH_MIN: float = 0.8
const PROP_REACH_FULL: float = 1.1
const PROP_GIRTH_MIN: float = 0.4
const PROP_GIRTH_FULL: float = 0.7

## How much of the rise and fall of a vaulting leg the animal takes up in its own
## joints rather than showing in its back. A stance limb is not a strut and flexes
## under load; how much is muscle against weight, which is `power` — so a light
## strong animal absorbs nearly all of it and glides, and a heavy one rolls its
## whole body over each of its legs.
const ABSORB_BASE: float = 0.75
const ABSORB_MIN: float = 0.30
const ABSORB_MAX: float = 0.70

## How many times per step cycle the body settles onto the height its feet are
## holding it at. Quoted in cycles rather than seconds so it means the same thing
## on an animal taking four steps a second and one taking one.
const SETTLE_CYCLES: float = 5.0
const SETTLE_MIN: float = 3.0
const SETTLE_MAX: float = 22.0

## How high a foot comes up, as a share of whichever is larger: how high the body
## is held, or how long the leg is. The first is what makes a heavy animal step
## over what a small one walks around; the second is what stops a low-slung animal
## scuffing its feet along the floor it is barely above.
const LIFT_SHARE: float = 0.22

## How much of its own length a fully flexible back adds and removes over a stride
## when the two girdles work as pairs. Not a small term: an animal that folds and
## extends its back covers a good deal more ground per stride than its legs alone
## reach, which is precisely why a bounding gait is fast.
const BUNCH_SHARE: float = 0.16

## Force per unit of weight, against the reference build.
var power: float = 1.0
## The fibre composition of that muscle. Power says how hard the legs push; this
## says how quickly the push arrives, so it enters the swing's drive and the
## ground push and nowhere else.
var twitch: float = 0.5
## How much of each girdle's built muscle is still answering — 1.0 intact, and it
## falls the moment a hip is bitten open, because it is read off the same cells.
var girdle_drive: Vector2 = Vector2.ONE
## The stance this body is in. Held rather than passed at every call: every
## reading below is a projection of it.
var carriage: Carriage
## Share of its cycle each limb must have a foot on the ground.
var duty: float = 0.5
## Whether the forelimbs reach the ground at all.
var forelimbs_bear: bool = true
## How much of a standing prop this build's tail is, 0..1 — the fifth limb, and a
## measurement rather than a mode. Nothing on a quadruped, whatever its tail.
var tail_prop: float = 0.0
var bearing_limbs: int = 4
## Ground acceleration, px/s².
var accel: float = 800.0
## Turn rate, rad/s, before speed falloff and steering losses.
var turn_rate: float = 0.0
var absorbed: float = 0.75
## How freely this back folds along its own length. One is a cat, near zero an
## elephant; read by everything that asks what the spine contributes to walking.
var spine_freedom: float = 1.0
## Where this body's resting feet are actually placed, fore and aft of their own
## sockets: x the fore pair, y the hind. The authored numbers, held to the one
## thing they may not contradict — that the weight ends up over the feet.
var foot_bias: Vector2 = Vector2(0.3, -0.25)
## Least angle a two-legged build has to carry its trunk at to be standing rather
## than toppling, degrees. A floor under the authored lift and never a replacement.
var carriage_deg: float = 0.0

var _spec: BodySpec


## Re-derives everything from the body that has just been counted.
##
## `corpus` carries the mass and the muscle with this creature's damage already
## folded into both, so nothing here has to ask about injuries. `poise` carries
## where that weight is, and is read for exactly two things — where the resting
## feet go and how a two-legged trunk is carried — both constraints rather than
## derivations: a build that already balances is left alone in every particular.
func update(p_carriage: Carriage, corpus: Corpus, poise: Poise,
		spec: BodySpec, attitude: Attitude) -> void:
	if p_carriage == null or corpus == null or spec == null:
		return
	carriage = p_carriage
	_spec = spec
	twitch = clampf(spec.fast_twitch, 0.0, 1.0)
	spine_freedom = clampf(spec.spine_freedom, 0.0, 1.0)

	# Force over mass, both off the census. Strength is the locomotor muscle at the
	# area power — force is cross-section, and cross-section is what a two-thirds
	# power of the tissue's own bulk measures — so fat and bone are in the weight
	# and not in the push, and power-to-weight falls as the cube root of size all on
	# its own.
	var compartments: Dictionary = corpus.compartments()
	var muscle: float = float(compartments.get(&"fore_girdle", 0.0)) \
		+ float(compartments.get(&"hind_girdle", 0.0)) \
		+ float(compartments.get(&"epaxial", 0.0))
	var strength: float = pow(maxf(muscle / REFERENCE_MUSCLE, 0.0), 2.0 / 3.0)
	power = clampf(strength / maxf(corpus.mass() / REFERENCE_MASS, 0.0001), 0.05, 8.0)
	girdle_drive = Vector2(corpus.girdle_soundness(true), corpus.girdle_soundness(false))

	forelimbs_bear = attitude.forelimbs_bear() if attitude != null \
		else Attitude.bears_on_forelimbs(spec)
	bearing_limbs = 4 if forelimbs_bear else 2

	# Where the feet go, and how a trunk with nothing under its shoulders is
	# carried. Settled before the stride, the duty and the tail prop that read them.
	_stand_under_the_weight(poise)

	# Whether the tail is a limb this body can stand on: only a biped has the
	# question, the tail has to reach the floor, and the root has to be a strut
	# rather than a rope.
	tail_prop = 0.0
	if not forelimbs_bear:
		var hip_stand: float = spec.hind_leg_length * carriage.hind.stand * sin(carriage.tilt)
		var drop: float = spec.tail_length * sin(deg_to_rad(carried_deg()))
		tail_prop = smoothstep(PROP_REACH_MIN, PROP_REACH_FULL,
				drop / maxf(hip_stand, 1.0)) \
			* smoothstep(PROP_GIRTH_MIN, PROP_GIRTH_FULL,
				corpus.girth(BodySchema.TAIL, 0) / maxf(spec.girdle_offset, 0.001))

	# Ground push, in gravities and then in pixels. What a foot presses with is the
	# muscle standing behind it: `power` against the weight it has to move, the
	# stance's drive for the posture it is spent from, the tendon's advantage for
	# the lever it reaches the ground through, and the fibre for how quickly the
	# force arrives. Capped at what a foot can lean on before it slips, so the
	# stance gain and the power ratio cannot multiply into a launch.
	var leverage: float = carriage.hind.advantage if not forelimbs_bear \
		else (carriage.fore.advantage + carriage.hind.advantage) * 0.5
	var fibre: float = lerpf(1.0 - PUSH_TWITCH, 1.0 + PUSH_TWITCH, twitch)
	accel = minf(PUSH_REFERENCE * carriage.drive * power * leverage * fibre,
		PUSH_CEILING) * Gravity.PULL

	# Torque over rotational inertia. A rod's inertia goes as its mass times the
	# square of its length while the muscle turning it grows with neither, so a long
	# heavy animal comes round slowly and a short light one snaps about.
	var span: float = maxf(spec.trunk_length + spec.neck_length + spec.tail_length, 1.0)
	turn_rate = deg_to_rad(spec.turn_speed_deg) * carriage.agility * power \
		* (REFERENCE_LENGTH / span)

	# How much of its cycle a foot spends on the ground. The stance says how many
	# feet stay down, which is exactly what a duty factor is; weight leans on it,
	# because a heavy animal is unwilling to be caught on fewer legs. Against the
	# legs that are carrying rather than against four — one foot down out of two is
	# a two-legged walk — and never all of them, because something has to be free
	# to move or the animal is a statue.
	var down: int = mini(carriage.feet_down, bearing_limbs - 1)
	duty = clampf(float(down) / float(bearing_limbs)
		+ DUTY_LOAD * (1.0 - power), DUTY_MIN, DUTY_MAX)

	absorbed = clampf(ABSORB_BASE * power, ABSORB_MIN, ABSORB_MAX)


## Puts the feet under the weight, and rears the trunk far enough that there is
## weight to put them under. Both are floors and neither is a derivation, which is
## the difference between constraining a build and retuning one.
func _stand_under_the_weight(poise: Poise) -> void:
	foot_bias = Vector2(_spec.front_foot_bias, _spec.rear_foot_bias)
	carriage_deg = 0.0
	if poise == null or poise.built_com < 0.0:
		return
	var hind_reach: float = carriage.fore_aft_reach(_spec.hind_leg_length,
		carriage.hind.stand, _spec.stance_width)
	if not forelimbs_bear:
		# One girdle, one beam, everything on both sides of it hanging off the hip.
		# The feet go under the weight, and where the feet cannot reach, the trunk
		# rears until the weight comes back to them.
		carriage_deg = poise.carriage_deg(hind_reach)
		foot_bias.y = poise.stand_under(hind_reach, deg_to_rad(carried_deg()))
		return
	var fore_reach: float = carriage.fore_aft_reach(_spec.fore_leg_length,
		carriage.fore.stand, _spec.stance_width)
	foot_bias.x = maxf(_spec.front_foot_bias, poise.bias_floor(fore_reach, true))
	foot_bias.y = minf(_spec.rear_foot_bias, -poise.bias_floor(hind_reach, false))
	foot_bias = foot_bias.clampf(-1.0, 1.0)


## The angle this build's trunk is carried at when nothing is under its shoulders:
## what it asks for, or what its balance demands, whichever is steeper. A build is
## free to stand more upright than its balance requires; it is not free to stand
## with its whole mass hanging off the front of its hips and call it a posture.
func carried_deg() -> float:
	return maxf(_spec.trunk_lift_deg if _spec != null else 0.0, carriage_deg)


## What one girdle's joints do.
func joint(fore: bool) -> Carriage.Joint:
	return carriage.of(fore)


## The span a limb of this bone stands at — the radius of the sphere its foot
## moves on.
func stand(bone: float, fore: bool) -> float:
	return bone * carriage.of(fore).stand


## How far the body may sink over a stride, as a share of the height it stands at.
## Not a constant and it could not be one: sinking is the stance limb folding as
## the body passes over it, so what is available is what the joint has between
## where it stands and where it folds to.
func sink(fore: bool) -> float:
	var j: Carriage.Joint = carriage.of(fore)
	return STRIDE_SINK * clampf((j.stand - j.fold) / maxf(j.stand, 0.0001), 0.0, 1.0)


## How far across the ground a foot may be placed from directly beneath its
## socket, given how high that socket is carried. Pythagoras on the limb, and the
## difference from a flat projection is the whole of the columnar case: a near-
## vertical leg projects barely a third of itself into the ground plane.
func plan_reach(bone: float, socket_height: float, max_reach: float) -> float:
	var span: float = bone * max_reach
	return sqrt(maxf(span * span - socket_height * socket_height, 0.0))


## The same reach quoted at the bottom of the animal's own bob — the one a foot is
## *placed* inside. It has to be this one rather than the reach at the height the
## body happens to be at, because the two are a loop: the foot goes out because the
## body is coming down, and the body comes down because the foot went out.
## `rise` is how far the foot's own toe holds the ankle off the ground over the
## stance, which on a build whose joints do not fold is much the larger of the two.
func walking_reach(bone: float, socket_height: float, max_reach: float,
		fore: bool, rise: float = 0.0) -> float:
	return plan_reach(bone, maxf(socket_height * (1.0 - sink(fore)) - rise, 0.0),
		max_reach)


## Half the fore-and-aft travel a foot has, from where it rests.
##
## One triangle asked at the bottom of the bob rather than the top: drop the socket
## by what the body will sink over a stride, ask how far the leg reaches across the
## floor from there, and take off what the sideways part of the stance is already
## using. Both extremes fall out of the one line — a sprawled animal's leg is
## already lying along the ground and nearly all of it is plan reach; a columnar
## one's socket is a whole leg up, so sinking a tenth of that is a long way out.
func excursion(bone: float, socket_height: float, lat: float, max_reach: float,
		fan: float, fore: bool, rise: float = 0.0) -> float:
	var across: float = walking_reach(bone, socket_height, max_reach, fore, rise) \
		* TRAVEL_MARGIN
	# However wide the stance and however far the body throws itself, a limb is left
	# something to walk with. A stride of nothing is not a small step — it is a foot
	# that can never become overdue and is therefore towed.
	var spent: float = minf(lat, across * LAT_CEILING)
	var travel: float = sqrt(maxf(across * across - spent * spent, 0.0))
	# The joint has the last word. Never binding on a sound limb at any ordinary
	# stance, and the whole of what a limb that has lost its range of motion has.
	return minf(travel, stand(bone, fore) * sin(clampf(fan, 0.0, PI * 0.5)))


## The widest a foot may rest from the line under its own socket. The stance asks
## for a width and usually gets it, but not at the price of the stride: the
## fore-and-aft share is reserved first and the stance takes what remains.
func stance_limit(reach: float, sway: float) -> float:
	return maxf(reach * sqrt(maxf(1.0 - FORE_SHARE * FORE_SHARE, 0.0)) - sway,
		reach * STANCE_FLOOR)


## The distance a foot may drift before it has to be picked up. Derived rather
## than authored, and it has to be: the foot lands `lead` of a stride ahead of
## where it rests and drifts back to the trailing edge of its travel, which is one
## equation with `stride` on both sides.
func stride(sweep: float, lead: float) -> float:
	return sweep * STRIDE_SHARE / maxf(1.0 - clampf(lead, 0.0, LEAD_CEILING), 0.25)


## How long a limb of this length takes to swing through, at a standstill.
##
## A leg is a pendulum hanging off a shoulder, so its swing goes as the square root
## of its length. Muscle shortens it — a limb is thrown as well as dropped — but
## only as the cube root of the power available, because the same weight being
## pushed along is what has to be swung. Never *longer* than the free swing however
## weak the animal: a pendulum comes through at its own rate whether or not
## anything drives it. `gear` is the girdle's lever, which scales the throw and
## never the pendulum underneath it.
func swing_time(bone: float, gear: float = 1.0) -> float:
	return SWING_PERIOD * sqrt(maxf(bone, 1.0) / Gravity.PULL) \
		/ maxf(pow(clampf(power, 0.05, 8.0), 1.0 / 3.0)
			* lerpf(1.0 - TWITCH_SPAN, 1.0 + TWITCH_SPAN, twitch)
			* maxf(gear, 0.05), 1.0)


## The same swing with as much taken off it as going fast can take. Without the
## shortening a running creature takes the deliberate step it takes standing;
## without the bound it takes no time at all, which is the blur this replaced.
func hurried_swing(swing_at_rest: float, pace: float) -> float:
	return swing_at_rest * (1.0 - SWING_HURRY * clampf(pace, 0.0, 1.0))


## How much of its cycle a foot has to be on the ground at this pace. It falls
## rather than holds, because keeping fewer feet down is *how* an animal goes
## faster once its legs are already swinging as quick as they can be thrown.
func duty_at(pace: float) -> float:
	return maxf(duty - DUTY_PACE * clampf(pace, 0.0, 1.0), minf(duty, DUTY_SPRINT))


## The most of a cycle a foot may spend in the air, given how long that cycle is —
## the duty factor stated as a deadline. `aloft_share` is the other half of the
## same arithmetic: over one cycle every leg spends the same share of it in the
## air, so the mean number of feet off the ground is that share times the number of
## legs, and no more than the lift limit of them may be off at once.
func swing_budget(cycle: float, aloft_share: float = 1.0, pace: float = 0.0) -> float:
	return maxf(cycle * minf(1.0 - duty_at(pace), maxf(aloft_share, 0.05) * SLOT_MARGIN),
		SWING_FLOOR)


## How fast the legs can actually carry the body, px/s.
##
## Ground covered per cycle over how long a cycle takes, at the only pace worth
## asking it at: flat out, where the swing is as hurried as muscle will make it and
## the duty factor is as low as the animal dares. A property of the skeleton rather
## than of what the creature is doing this instant — a ceiling that moved with the
## speed it bounds would be a feedback loop rather than a limit.
##
## `travel` is the *whole* fore-and-aft excursion, both halves of it, because that
## is what a step covers: the foot is put down as far forward as the envelope
## reaches, the body walks over it, and it is picked up as far back as the envelope
## reaches. `aloft_share` is divided out directly rather than through the swing
## budget — SLOT_MARGIN exists so the pattern has a slot to *choose* with, and
## pricing a top speed off room kept for a decision would be double-counting.
func leg_speed(travel: float, swing_at_rest: float, aloft_share: float = 1.0) -> float:
	return maxf(travel, 0.0) / maxf(hurried_swing(swing_at_rest, 1.0)
		/ maxf(minf(1.0 - duty_at(1.0), maxf(aloft_share, 0.05)), 0.05), SWING_FLOOR)


## How much of its standing push the muscle has left at this speed, 0..1.
##
## Muscle trades force for the speed it is already shortening at — the
## force–velocity relation, and the whole of why nothing accelerates at its own top
## speed. A leg drives the body by pushing the ground backward past it, so the
## faster the body travels the faster the same muscle is contracting just to keep
## the foot planted. Linear between the ends, which is what whole-animal thrust
## actually measures as: the per-fibre curve is hyperbolic, but a gait recruits
## across joints and gears and what reaches the ground falls off close to straight.
##
## `top` is what the animal will ever ask of itself — the same denominator exertion
## is quoted against — and deliberately not the measured leg ceiling: the gait's
## reading rides on the solved feet, and the solved feet know where the head is
## looking, so a fade priced off it would let the aim perturb a straight run.
## Braking never reads this: muscle resisting stretch is stronger than muscle
## shortening, which is why an animal stops harder than it starts.
func push_left(speed: float, top: float) -> float:
	if top <= 0.0:
		return 1.0
	return clampf(1.0 - absf(speed) / top, 0.0, 1.0)


## How fast the feet can walk a standing body around, rad/s. A creature turning on
## the spot is not spinning; it is stepping its feet round a circle, so the rate is
## the speed a foot can be placed at over the radius of the socket with furthest to
## go. The furthest rather than the average, because a gait is only as quick as the
## limb that cannot keep up.
func walked_turn(carry_speed: float, radius: float) -> float:
	return maxf(carry_speed, 0.0) / maxf(radius, 1.0)


## How quickly the body settles onto the height its feet are holding it at, given
## how long one limb's cycle is.
func settle(cycle: float) -> float:
	return clampf(SETTLE_CYCLES / maxf(cycle, 0.001), SETTLE_MIN, SETTLE_MAX)


## How high a foot comes up at the top of a step, before the stance's own leaning.
func lift(socket_height: float, bone: float) -> float:
	return maxf(socket_height, bone) * LIFT_SHARE


## How much shorter the body is drawn, given how far its two ends have converged.
## Positive is a back folded up with the hind feet forward under the shoulders,
## negative one stretched out at full extension. The whole of the spine's
## contribution to a stride, and it needs no second term anywhere: a body shorter
## this tick than last has carried its own shoulders backward relative to its hips,
## the sockets ride on the chain, and the stride and the step timing follow from
## measuring where the socket actually went. `gathering` is how much of the
## asymmetric regime the animal is in, so the answer is *exactly* nothing under any
## alternating gait rather than merely nearly nothing.
func bunch(gather: float, gathering: float) -> float:
	return clampf(gather, -1.0, 1.0) * clampf(gathering, 0.0, 1.0) \
		* BUNCH_SHARE * spine_freedom
