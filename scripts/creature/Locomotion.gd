## What this body can do about moving itself: how hard it accelerates, how far
## each leg reaches under it, how long a foot stays down, and how quickly it can
## be picked up and put somewhere else.
##
## The third of the derived descriptors, and built on exactly the terms of the
## other two. `Physique` reads how much animal there is off the drawn silhouette;
## `Stature` reads how tall it stands off its own legs; this reads how it walks
## off both. Nothing here is a setting and nothing here names a species: an
## Elephant accelerates slowly, swings its legs deliberately and keeps three feet
## on the ground because it is twenty-three times a Lizard standing on legs three
## times as long, not because a preset said 300 where another said 800.
##
## Four laws do the whole of it, and every number below is one of them applied to
## the body that has just been solved:
##
##   * **Force over mass.** Muscle goes as a cross-section and weight goes as a
##     volume, so a creature's push-per-kilo falls as the cube root of its size.
##     That single ratio — `power` — is what makes a heavy animal slow to get
##     going and slow to turn, and it is the same one `Physique` already derives.
##     Fat is in the mass and not in the muscle, so a padded animal is duller for
##     free.
##   * **A leg is a pendulum.** How long a limb takes to swing through goes as the
##     square root of its length, so a long leg is a slow leg however strong the
##     animal wearing it. That, and not a step-duration slider, is why an
##     Elephant's feet move the way they do.
##   * **A foot on a sphere.** A planted foot is a point on a sphere of the leg's
##     own radius about its socket, so how far it can travel fore-and-aft is a
##     question about the leg's length, the angle it is carried at and how far the
##     body is willing to sink while it passes over it. Stride length is that
##     answer. There is no stride parameter any more.
##   * **Feet stay down.** How many of them a posture keeps on the floor is
##     already a posture trait, and it is what a duty factor *is* — so the time a
##     limb is allowed in the air is the rest of its cycle, and never more. This
##     is the one that was missing, and its absence is what let a columnar
##     animal's front legs use the whole of a single-support gait between them
##     and leave the hind pair dragging.
##   * **A body cannot outrun its own legs.** The three above already say how far
##     a foot reaches and how long it takes to come through, and between them
##     that is a speed: stride over cycle, and no faster. It was never asked.
##     `move_speed` was handed straight to the body, the gait divided it by the
##     stride to get a cadence, and whatever came out was what the legs did —
##     eleven steps a second on a cat, twelve on a cheetah, with each swing
##     clipped to a floor of forty-five milliseconds to fit. That is the whole of
##     why the creatures read as sliding: the feet were not carrying the animal,
##     they were being flicked through a blur underneath it to keep up. See
##     `leg_speed`, which is now a ceiling on the body rather than a consequence
##     of it.
##
## Refreshed once per tick from the previous tick's physique, ahead of everything
## that reads it. That one-tick lag is deliberate and harmless: mass and muscle
## are properties of a body that is being eaten over seconds, not of this frame.
class_name Locomotion
extends RefCounted

## Body length of the default build — 14 segments at 15px — so a creature's
## rotational inertia is quoted as a ratio against it. A constant for the same
## reason `Physique.REFERENCE_VOLUME` is: it has to keep meaning the same thing
## after the creation menu has restructured the animal underneath it.
const REFERENCE_LENGTH: float = 195.0

## How far the body will drop over a stride, as a share of the height it stands
## at. This is where an upright animal's stride comes from and it cannot come from
## anywhere else: a leg held near vertical has almost no plan-view reach to swing
## its foot across, so the only way that foot gets out in front of the body is for
## the shoulder to come down as it goes. Which is a walk. A sprawled animal buys
## no stride this way and needs none — its foot is already flung out to the side
## and sweeps a wide arc at no cost in height at all.
##
## Spent out of the joint rather than granted, which is the correction a columnar
## build needed: sinking over a stride is the limb *folding* a little as the body
## passes over it, so an animal whose knee barely closes cannot buy stride that
## way however much it would like to. See `sink`, where the share is taken
## against what the joint actually has between standing and folded — and note
## that this leaves such an animal with the swing of the whole limb and the toe
## at the end of it, which is precisely what a heavy quadruped walks on.
const STRIDE_SINK: float = 0.12
## How much of the travel a limb has, it actually uses. Short of all of it so a
## walking foot is not permanently sitting on its own envelope boundary.
const STRIDE_SHARE: float = 0.80
## Least of the disc a foot may be placed inside that is kept for walking rather
## than for standing wide. The stance and the stride are spent out of one budget —
## the leg reaches so far across the ground and no further, and every pixel of
## that spent holding the foot out to the side is a pixel it cannot travel
## fore-and-aft — so an animal that stands at the full width its posture asks for
## has no stride left, whatever its legs are like. This is where that argument
## stops: past here the stance comes in rather than the stride going to nothing.
const FORE_SHARE: float = 0.55
## How much of the disc the stride is measured across. The rest is headroom — see
## `excursion`.
const TRAVEL_MARGIN: float = 0.94
## Most of that the stance and the sway between them may use up, so there is
## always some stride left. See `excursion`.
const LAT_CEILING: float = 0.88
## Narrowest a stance may be squeezed to by that reservation, as a share of the
## reach. A body thrown about hard enough to want its feet directly underneath it
## is a body that would then be standing on a line, and a creature does not
## balance on one. Well above where any posture puts its feet of its own accord,
## so it is a floor on the *squeeze* rather than on the stance.
const STANCE_FLOOR: float = 0.45
## Largest share of a stride a foot may be aimed ahead by. `foot_lead` is spent
## out of the same travel the stride is measured in, so at 1.0 the two cancel and
## the stride collapses to nothing.
const LEAD_CEILING: float = 0.75

## How much of the room the lift limit leaves a body actually spends. Short of
## all of it, because a gait held at exactly its own ceiling has no free slot at
## any instant: a foot goes up only as another comes down, so which foot goes next
## is whichever has been waiting longest and the footfall pattern never gets to
## choose. The margin is what leaves it a choice.
const SLOT_MARGIN: float = 0.85

## Swing time of a limb one pixel long, in seconds — the constant of
## proportionality on `sqrt(length / gravity)`. Chosen so the default build lands
## on the quarter-second step it was authored with, which is the only thing an
## arbitrary constant in a made-up gravity can honestly be pinned to.
const SWING_PERIOD: float = 1.6
## Fastest any limb may be flicked through a step, whatever the arithmetic asks
## for. A backstop rather than a working floor: what actually holds a swing open
## is `hurried_swing`, which is the limb's own pendulum with as much taken off it
## as muscle can take. This is only here so a degenerate body — a limb of no
## length, a cycle of no duration — cannot ask for a step of zero seconds.
const SWING_FLOOR: float = 0.045
## How far fibre composition can move the swing's drive either way of the mixed
## default — see `swing_time`. Small on purpose: composition is a grade of
## muscle, not a second engine.
const TWITCH_SPAN: float = 0.08
## How much of a limb's free swing muscle may take off it when the animal is
## going flat out.
##
## A leg is thrown as well as dropped, so a running animal does bring its limbs
## through quicker than they would fall — but not by an unbounded amount, and
## this is the bound. Around three fifths, and that figure is a measurement
## rather than a taste: a cat's foreleg makes a free swing of about a quarter of
## a second and its swing phase at a flat gallop is a tenth, so a limb going as
## hard as it can goes at something near two and a half times the rate it would
## fall at. Past that the limb is being driven harder than the same muscle is
## driving the body along, and an animal whose legs outpace its own travel is one
## flailing on the spot.
##
## It used to live inline in `Gait._step_duration` as the target, with the duty
## factor free to cut below it and a flat forty-five millisecond floor under
## that. So it bounded nothing: a cat at full tilt got a forty-five millisecond
## swing out of a two hundred and twenty-seven millisecond leg. Here it is a
## floor as well as a target, and `leg_speed` is what makes the two agree —
## rather than the body going as fast as it likes and the legs blurring to suit.
const SWING_HURRY: float = 0.60

## How much longer a heavy animal keeps its feet down than its posture alone
## says. The posture already sets the base — three feet down on a columnar build,
## two on the others — and this is weight leaning on top of it.
const DUTY_LOAD: float = 0.10
const DUTY_MIN: float = 0.35
const DUTY_MAX: float = 0.86
## How much of its duty factor a body gives up between standing still and going
## flat out, and the least it may fall to.
##
## Every animal keeps fewer feet down the faster it goes — that is what separates
## a walk from a trot and a trot from a gallop, and it is the same fact whichever
## end of the size range it is read at: an elephant at a fast walk has two feet
## down where a standing one has three. Held constant, as it was, a heavy build
## is stuck at its standing duty forever and `leg_speed` then prices its top
## speed off a cycle it only has while it is loitering.
const DUTY_PACE: float = 0.22
const DUTY_SPRINT: float = 0.28

## Hardest a body may push against the ground, in gravities.
##
## Traction, and it is the one ceiling on acceleration that is not about muscle.
## A foot pushes a body forward by leaning on friction, and past somewhere near
## its own weight it stops leaning and starts slipping — which is why no animal,
## however strong for its size, gets away from a standstill much quicker than
## this. Without it `drive` and `power` multiply: a Cheetah's posture gain of 1.35
## on a power of 2.28 turned a modest per-species push into 1.64 g, and 1.64 g
## against its own top speed is a creature at full pelt inside a fifth of a
## second. That is not a strong animal, it is a body with no mass.
const PUSH_CEILING: float = 0.55

## Least a forelimb may be, against the hind leg it would have to stand beside,
## and still reach the ground the hips are holding the body over.
##
## This is the whole of what being two-legged is, and it is a measurement rather
## than a category. A shoulder is carried at the height the hind legs set; an arm
## shorter than that cannot be put on the floor without the animal pitching onto
## its face, so it is not put on the floor. Comfortably below any real quadruped —
## the shortest-armed one in the file is at 0.85 of its own leg — and comfortably
## above the vestigial forelimbs of anything that walks on two, so the threshold
## itself never has to be argued about.
const BEARING_RATIO: float = 0.46

## How much of the rise and fall of a vaulting leg the animal takes up in its own
## joints rather than showing in its back. A leg with a foot planted lifts the
## body as it passes underneath and lowers it again as it leaves — that is where
## every bob comes from — but a stance limb is not a strut and flexes under the
## load. How much it can flex is a question about muscle against weight, which is
## `power`: a light, strong animal absorbs nearly all of it and glides, and a
## heavy one has legs it cannot fold and rolls its whole body over each of them.
const ABSORB_BASE: float = 0.75
const ABSORB_MIN: float = 0.30
const ABSORB_MAX: float = 0.70

## How many times per step cycle the body settles onto the height its feet are
## holding it at. Quoted in cycles rather than in seconds so it means the same
## thing on an animal taking four steps a second and one taking one: the body
## follows its feet at the pace its feet are moving, which is what stops a slow
## heavy walk being smoothed into a glide by a response that was tuned for a
## lizard.
const SETTLE_CYCLES: float = 5.0
const SETTLE_MIN: float = 3.0
const SETTLE_MAX: float = 22.0

## How high a foot comes up, as a share of whichever is larger: how high the body
## is being held, or how long the leg is. Both are needed. The first is what makes
## an elephant step over what a lizard walks around; the second is what stops a
## low-slung animal, whose body is barely off the floor, scuffing its feet along
## it — a lizard picks its foot up by a fraction of its own leg even though it has
## almost no clearance to clear.
const LIFT_SHARE: float = 0.22

## Total turn a spine has to be able to make, end to end, to count as a fully
## flexible back — a body that could curl round into a ring. Dimensionless, and
## deliberately so: it is a statement about the animal against itself, so a long
## body of many small bends and a short one of few large ones are compared on the
## terms that matter rather than on their length.
const FLEXIBLE_SPINE: float = TAU
## How much of its own length a fully flexible back adds and removes over a
## stride when the two girdles are working as pairs. This is the other half of a
## gallop's stride and it is not a small term: an animal that folds and extends
## its back covers a good deal more ground per stride than its legs alone reach,
## which is precisely why a bounding gait is fast.
const BUNCH_SHARE: float = 0.16

## Force per unit of weight, against the reference build. Muscle goes as
## mass^(2/3) and weight as mass, so this falls as the cube root of size all on
## its own — and every slow thing about a large animal below is this one number.
var power: float = 1.0
## The fibre composition of that muscle — the params' fast-twitch share. Power
## says how hard the legs can push; this says how quickly the push arrives, so
## it enters the swing's drive term and nowhere else. 0.5 is the mixed default,
## and at 0.5 it changes nothing at all.
var twitch: float = 0.5
## What the muscle behind each girdle can deliver across its sockets, against an
## ordinarily-built animal — see Physique.girdle_drive, which is where it is
## counted and why. Held here because this is the object the gait already reads
## its capabilities off, and because it belongs beside `power`: that is how hard
## the whole animal can push and this is which end of it is pushing.
var girdle_drive: Vector2 = Vector2.ONE
## What each girdle's joints do — how extended its limbs stand, how far they lock
## out and how far they fold. Held rather than derived: it is a description of the
## skeleton, refreshed when the body is rebuilt, and every reading below that used
## to consult a `stance_reach` or a `limb_max_reach` parameter now asks the limb
## it is about. See Articulation.
var articulation: Articulation = Articulation.new()
## Share of its cycle each limb must have a foot on the ground.
var duty: float = 0.5
## Whether the forelimbs reach the ground at all — see BEARING_RATIO. False
## leaves the hind pair walking on their own, which is what two-legged means.
var forelimbs_bear: bool = true
## How many limbs are actually carrying the animal. Two or four, and it is what
## every share of the body's weight and every duty factor is quoted against.
var bearing_limbs: int = 4
## Ground acceleration, in pixels per second squared.
var accel: float = 800.0
## Turn rate, in radians per second, before speed falloff and steering losses.
var turn_rate: float = 0.0
## Share of the vault the joints swallow — see ABSORB_BASE.
var absorbed: float = 0.75
## How freely this back folds along its own length: the total turn the chain can
## make from end to end, against a body that could curl into a half circle, taken
## down by whatever muscle tone is holding it straight. One is a cat, near zero is
## an elephant. Read by everything that asks what the spine contributes to
## walking, so the two consumers cannot disagree about it.
var spine_freedom: float = 1.0


## Re-derives everything from the body that has just been solved.
##
## `physique` carries the mass and the muscle, and it already has this creature's
## damage folded into both — a limb that is present and not answering contributes
## its weight and none of its pull — so nothing here has to ask about injuries.
func update(posture: Posture, physique: Physique, p: CreatureParams, scale: float,
		joints: Articulation = null) -> void:
	if posture == null or physique == null or p == null:
		return
	power = clampf(physique.strength / maxf(physique.mass, 0.0001), 0.05, 8.0)
	twitch = clampf(p.fast_twitch, 0.0, 1.0)
	girdle_drive = physique.girdle_drive

	# What the joints do. There is no longer a cap here, and its absence is the
	# whole of what let a column stand up: the old one held every limb a fixed
	# distance short of its own limit, which on a build whose standing angle is
	# within three degrees of straight is the difference between a pillar and a
	# permanent half-crouch. What keeps a standing joint off its stop is now the
	# stop's own definition — see Articulation.CARRY_MARGIN_DEG — and what keeps
	# a walking foot off its envelope boundary is the sink and the swing, which is
	# where it always belonged.
	if joints != null:
		articulation = joints

	# Whether there are four legs under this animal or two. Nothing selects it: an
	# arm too short to reach the floor from a shoulder the hind legs are holding up
	# is an arm that is carried, and a body with two of those is walking on two
	# legs. Which is why a T. rex and a Kangaroo need no posture of their own to be
	# bipedal and a Gorilla, whose arms are *longer* than its legs, is emphatically
	# not — its knuckles are on the ground because they reach it.
	forelimbs_bear = bears_on_forelimbs(p)
	bearing_limbs = 4 if forelimbs_bear else 2

	# Ground push, in gravities and then in pixels. Quoted against the world's own
	# pull rather than as a raw rate because that is the only way the number can be
	# argued about: 0.2 g is a figure a real animal can be held to, and 800 px/s²
	# is a figure that happened to be four times a Lizard's top speed. Capped at
	# what a foot can lean on before it slips — see PUSH_CEILING — so the posture
	# gain and the power ratio can no longer multiply into a launch.
	accel = minf(p.acceleration * posture.drive * power, PUSH_CEILING) \
		* Gravity.PULL * scale

	# Torque over rotational inertia. A rod's inertia goes as its mass times the
	# square of its length while the muscle turning it grows with neither, so a
	# long heavy animal comes round slowly for the same reason a short light one
	# snaps about — and the elephant's own body length is doing as much of that
	# here as its weight is.
	var span: float = maxf(p.segment_length * float(p.segment_count - 1) * scale, 1.0)
	turn_rate = deg_to_rad(p.turn_speed_deg) * posture.agility * power \
		* (REFERENCE_LENGTH * scale / span)

	# How much of its cycle a foot spends on the ground. The posture already says
	# how many feet stay down, which is exactly what a duty factor is; weight leans
	# on it, because a heavy animal is unwilling to be caught on fewer legs.
	#
	# Against the legs that are carrying rather than against four, because that is
	# what the fraction means: one foot down out of two is a two-legged walk, and
	# quoted against a girdle the animal is not standing on it would read as a
	# creature permanently in the air.
	# Never all of them: a build has to be able to pick a foot up, and a posture
	# asking for three feet down on an animal standing on two is asking for a
	# statue. The cap is on the posture's caution rather than on the anatomy —
	# whatever the stance would prefer, something has to be free to move.
	var down: int = mini(posture.feet_down, bearing_limbs - 1)
	duty = clampf(float(down) / float(bearing_limbs)
		+ DUTY_LOAD * (1.0 - power), DUTY_MIN, DUTY_MAX)

	absorbed = clampf(ABSORB_BASE * power, ABSORB_MIN, ABSORB_MAX)

	# What the back can do about walking: the total turn it could make from end to
	# end, against a body that could curl right round. Both halves of it are
	# already on the animal — how far one joint bends and how many joints there
	# are — and it is what makes an elephant's back a beam and a cat's a spring
	# without either of them carrying a flexibility number.
	spine_freedom = clampf(deg_to_rad(p.max_bend_deg) * float(p.segment_count - 1)
		/ FLEXIBLE_SPINE, 0.0, 1.0)


## Whether a body of these proportions walks on its forelimbs at all.
##
## The measurement above, put to the parameters alone. Static because how many
## legs an animal has is a question about a *build* rather than about a body that
## has been solved — so the creation menu can ask it of a species nobody has
## grown yet, and get the same answer the simulation will.
static func bears_on_forelimbs(p: CreatureParams) -> bool:
	return p.arm_length >= p.leg_length * BEARING_RATIO


## What one girdle's joints do.
func joint(pair: int) -> Articulation.Joint:
	return articulation.of(pair)


## How extended that girdle's limbs stand.
func extension(pair: int) -> float:
	return articulation.of(pair).stand


## The mean of the two, for the handful of readings that are about the animal
## rather than about one of its ends — how tall it stands before any foot has been
## placed, chiefly. Anything asking about a limb asks the limb.
func mean_extension() -> float:
	return (articulation.fore.stand + articulation.hind.stand) * 0.5


## The span a limb of this bone stands at — the radius of the sphere its foot
## moves on.
func stand(bone: float, pair: int) -> float:
	return bone * extension(pair)


## How far the body may sink over a stride, as a share of the height it is
## standing at.
##
## Not a constant any more, and it could not be one. Sinking is the stance limb
## folding as the body passes over it, so what is available is what the joint has
## between where it stands and where it folds to — nearly all of it on a
## semi-upright build, and next to nothing on a columnar leg whose knee does not
## close. That is why an elephant walks with a level back and a cat's shoulders
## rise and fall over every step, and neither of them was told to.
func sink(pair: int) -> float:
	var j: Articulation.Joint = articulation.of(pair)
	return STRIDE_SINK * clampf((j.stand - j.fold) / maxf(j.stand, 0.0001), 0.0, 1.0)


## How far across the ground a foot may be placed from directly beneath its
## socket, given how high that socket is being carried.
##
## Pythagoras on the limb, and it replaces a flat projection of the leg's length
## that had no idea how high the body was. The difference is the whole of the
## columnar case: a near-vertical leg projects barely a third of itself into the
## ground plane, so measured that way its foot could never be put down far enough
## forward to be a stride — while the actual triangle, with most of the leg spent
## going down and the rest available to lean, gives it half as much again.
func plan_reach(bone: float, socket_height: float, max_reach: float) -> float:
	var span: float = bone * max_reach
	return sqrt(maxf(span * span - socket_height * socket_height, 0.0))


## The same reach, quoted at the bottom of the animal's own bob.
##
## This is the one the foot is *placed* inside, and it has to be this one rather
## than the reach at the height the body happens to be at right now, because the
## two are a loop: the foot goes out because the body is coming down, and the body
## comes down because the foot went out. Quoting the envelope at the instantaneous
## height cuts the foot short of where the stride was measured, and the limb then
## spends the last third of every step skidding along a boundary that opens up
## underneath it. Nothing is over-extended by the difference — `_carry_body` puts
## a hard ceiling on the body at what its legs can actually reach, so the sinking
## always happens.
## `rise` is how far the foot's own toe holds the ankle off the ground over the
## stance — the second way the gap shrinks, and on a build whose joints do not
## fold it is much the larger of the two. A leg spanning less gap reaches further
## across the ground, so this is the push-off spent where a columnar animal
## actually spends it: on stride rather than on height.
func walking_reach(bone: float, socket_height: float, max_reach: float,
		pair: int, rise: float = 0.0) -> float:
	return plan_reach(bone, maxf(socket_height * (1.0 - sink(pair)) - rise, 0.0),
		max_reach)


## Half the fore-and-aft travel a foot has, from where it rests.
##
## One triangle, asked at the bottom of the animal's bob rather than the top. A
## planted foot is a point on the sphere of the leg's own reach about its socket;
## how far across the ground that lets it get is how much of the leg is not being
## spent going down, and the animal makes more of it available by coming down —
## which is not a concession, it is the walk. So: drop the socket by what the body
## will sink over a stride, ask how far the leg reaches across the floor from
## there, and take off what the sideways part of the stance is already using. What
## is left is the fore-and-aft half-travel.
##
## Both extremes fall out of the one line, which is why there are no longer two
## branches here. A sprawled animal's socket is a few pixels off the floor, so
## sinking buys it almost nothing — and it needs almost nothing, because its leg
## is already lying along the ground and nearly the whole of it is plan-view
## reach. A columnar animal's socket is a whole leg up, so sinking a tenth of that
## is a long way out for the foot — and it needs every bit, because a near-
## vertical leg has almost no plan reach until it leans.
##
## `lat` is how far out to the side the foot rests and `fan` the joint's own
## limit on the sweep, which is what a stiffened limb loses first.
func excursion(bone: float, socket_height: float, lat: float,
		max_reach: float, fan: float, pair: int, rise: float = 0.0) -> float:
	# Short of the whole disc, for the same reason the stance is short of the whole
	# leg. Size the travel to the exact edge and the design point *is* the
	# boundary: the foot arrives there whenever its stride extreme and the body's
	# sway peak land on the same tick, and a foot on the boundary is a foot the
	# clamp is skidding.
	var across: float = walking_reach(bone, socket_height, max_reach, pair, rise) \
		* TRAVEL_MARGIN
	# However wide the stance and however far the body throws itself, a limb is
	# left something to walk with. Without the floor a body that swayed as far as
	# its own leg reaches would be given a stride of nothing at all — and a stride
	# of nothing is not a small step, it is a foot that can never become overdue
	# and is therefore towed for as long as the creature is on its feet.
	var travel: float = sqrt(maxf(across * across
		- minf(lat, across * LAT_CEILING) * minf(lat, across * LAT_CEILING), 0.0))
	# The joint has the last word. Never binding on a sound limb at any ordinary
	# stance — the reach above runs out first — but it is the whole of what a limb
	# that has lost its range of motion has left, and it is what makes that limb
	# take short steps rather than being quietly dragged.
	return minf(travel, stand(bone, pair) * sin(clampf(fan, 0.0, PI * 0.5)))


## The widest a foot may rest from the line under its own socket.
##
## The posture asks for a stance width and usually gets it — but not at the price
## of the stride. A leg reaches a certain distance across the ground and that disc
## is the whole budget: the sideways offset comes out of it, the body's sway comes
## out of it twice a cycle, and the fore-and-aft travel is whatever is left. Spend
## the first two to the edge and the third is nothing, which is not a wide stance,
## it is an animal standing splay-legged and shuffling — and then dragging its
## feet, because the wave puts them outside the disc from a standing start.
##
## So the fore-and-aft share is reserved first and the stance takes what remains.
## It binds on a sprawled build, whose feet genuinely do belong out at the edge of
## its reach, and on nothing else.
## `sway` is how far the body's own undulation carries this socket sideways, which
## is why it is per-limb and measured rather than quoted — see Limb.sway.
func stance_limit(reach: float, sway: float) -> float:
	return maxf(reach * sqrt(maxf(1.0 - FORE_SHARE * FORE_SHARE, 0.0)) - sway,
		reach * STANCE_FLOOR)


## The distance a foot may drift before it has to be picked up.
##
## Derived rather than authored, and it has to be: a stride longer than the travel
## the limb has is not a long stride but no stride at all, and one shorter than it
## is an animal mincing on legs it is not using. The foot lands `lead` of a stride
## ahead of where it rests and drifts back to the trailing edge of its travel, so
## the whole of the stride is the travel behind it plus the part it was placed
## ahead by — which is one equation with `stride` on both sides, solved here.
func stride(sweep: float, lead: float) -> float:
	return sweep * STRIDE_SHARE / maxf(1.0 - clampf(lead, 0.0, LEAD_CEILING), 0.25)


## How long a limb of this length takes to swing through, at a standstill.
##
## A leg is a pendulum hanging off a shoulder, so its swing goes as the square
## root of its length and a long leg is a slow leg however strong the animal
## wearing it. Muscle shortens it — a limb is thrown as well as dropped — but only
## as the cube root of the power available, because the same weight that is being
## pushed along is also what has to be swung.
## Never *longer* than the free swing, however weak the animal is, and that bound
## is the correction: a pendulum comes through at its own rate whether or not
## anything is driving it, so muscle is the only term that can move this and it
## can only move it one way. Divided both ways, as it was, an Elephant's legs came
## through a third slower than gravity alone would have brought them — which is
## not a heavy animal walking deliberately, it is a heavy animal wading.
func swing_time(bone: float) -> float:
	# Fibre composition scales the drive, not the pendulum: fast-twitch muscle
	# throws the same limb through sooner, slow-twitch gives that up — and the
	# same bound still holds, because no composition of muscle can slow a limb
	# below the rate gravity alone brings it through at.
	return SWING_PERIOD * sqrt(maxf(bone, 1.0) / Elevation.GRAVITY) \
		/ maxf(pow(clampf(power, 0.05, 8.0), 1.0 / 3.0)
			* lerpf(1.0 - TWITCH_SPAN, 1.0 + TWITCH_SPAN, twitch), 1.0)


## The same swing with as much taken off it as going fast can take.
##
## A limb at a walk falls through; a limb at a gallop is thrown, and arrives
## sooner for it. `pace` is how much of that the animal is doing, and SWING_HURRY
## is how much there is to have. Both halves matter: without the shortening a
## running creature would take the same deliberate step it takes standing, and
## without the bound it takes no time at all — which is the blur this replaced.
func hurried_swing(swing_at_rest: float, pace: float) -> float:
	return swing_at_rest * (1.0 - SWING_HURRY * clampf(pace, 0.0, 1.0))


## How much of its cycle a foot has to be on the ground, at this pace.
##
## `duty` is the standing figure — what the posture asks for with weight leaning
## on it — and this is the same body going faster. It falls rather than holds,
## because keeping fewer feet down is *how* an animal goes faster once its legs
## are already swinging as quick as they can be thrown; a gait that could not do
## it would have to cycle its legs harder instead, which is precisely the failure
## this file now refuses.
func duty_at(pace: float) -> float:
	return maxf(duty - DUTY_PACE * clampf(pace, 0.0, 1.0), minf(duty, DUTY_SPRINT))


## The shortest honest cycle a limb of this swing can be turned over in.
##
## Two facts and nothing else. The swing takes as long as it takes — a thrown
## pendulum, no quicker than `hurried_swing` — and it has to fit inside the part
## of the cycle the foot is off the ground. So the cycle is the one divided by the
## other, and everything about how fast this animal can move follows from it.
##
## How much of the cycle that is has two answers and the smaller wins, which is
## the same pair `swing_budget` already resolves: the duty factor says how much of
## its own cycle *this* foot may spend in the air, and the lift limit says how
## many feet the whole body will have off the ground at once — and four legs each
## aloft for a third of the time is a body permanently on one foot, whatever the
## duty factor thinks. Missing it is what left a Camel's ceiling three times what
## its own gait could deliver, so it was granted a speed it could only meet by
## dragging its feet along behind it.
func cycle_floor(swing_at_rest: float, pace: float, aloft_share: float = 1.0) -> float:
	return maxf(hurried_swing(swing_at_rest, pace)
		/ maxf(minf(1.0 - duty_at(pace), maxf(aloft_share, 0.05) * SLOT_MARGIN), 0.05),
		SWING_FLOOR)


## How fast the legs can actually carry the body, in pixels per second.
##
## Ground covered per cycle over how long a cycle takes, at the only pace worth
## asking it at: flat out, where the swing is as hurried as muscle will make it
## and the duty factor is as low as the animal dares. Which makes it a property of
## the skeleton rather than of what the creature is doing this instant — a
## ceiling, not a reading — and that is deliberate, because a ceiling that moved
## with the speed it bounds would be a feedback loop rather than a limit.
##
## `travel` is the *whole* fore-and-aft excursion the foot has, both halves of it,
## and that is the ground covered because that is what a step is: the foot is put
## down as far forward as its envelope reaches, the body walks over it, and it is
## picked up again as far back as the envelope reaches. Not the stride threshold,
## which is the shorter distance the foot is allowed to drift before it becomes
## due — a foot going the whole way to its trailing edge has been overdue for some
## time by then, which is exactly why the trigger is set inside the envelope.
##
## This is what `move_speed` is now measured against. A species may ask for less
## than its legs can give, and a stately animal is exactly that; it may not ask
## for more, because the alternative is the one it was getting — a body towed
## along at whatever the parameter said with four legs cycling underneath it fast
## enough to look like a wheel.
## `aloft_share` is divided out directly rather than through `cycle_floor`, and
## the difference is SLOT_MARGIN: that margin exists so the footfall pattern has a
## free slot to *choose* with, which is a statement about sequencing rather than
## about how fast a leg can be moved. Spending it here as well would price a
## body's top speed off room it was keeping for a decision.
func leg_speed(travel: float, swing_at_rest: float, aloft_share: float = 1.0) -> float:
	return maxf(travel, 0.0) / maxf(hurried_swing(swing_at_rest, 1.0)
		/ maxf(minf(1.0 - duty_at(1.0), maxf(aloft_share, 0.05)), 0.05), SWING_FLOOR)


## How fast the feet can walk a standing body around, in radians per second.
##
## A creature turning on the spot is not spinning; it is stepping its feet round
## a circle, and every term of that is already measured. A socket at `radius` from
## the point the body turns about is carried sideways at `radius` times the turn
## rate, and the foot underneath it has to be picked up and put down at least that
## fast or it is simply dragged round — so the rate is the speed a foot can be
## placed at, over the radius of the socket that has furthest to go.
##
## The furthest rather than the average, because a gait is only as quick as the
## limb that cannot keep up, and it is the *socket* radius rather than anything
## about where the mass is: how hard a body is to swing is torque over inertia and
## is already `turn_rate`, which a species leans on and which still applies. This
## is a second ceiling beside it and it is the one that was missing — with only
## the first, a light strong animal on a short body was handed nine radians a
## second and span like a top with its feet planted, because nothing in the
## arithmetic had to be walked.
func walked_turn(carry_speed: float, radius: float) -> float:
	return maxf(carry_speed, 0.0) / maxf(radius, 1.0)


## The most of a cycle a foot may spend in the air, given how long that cycle is.
## This is the duty factor stated as a deadline, and it is what keeps three feet
## under a columnar animal instead of letting two legs use the whole of a
## single-support gait between them.
##
## `aloft_share` is the second half of the same arithmetic and it was missing.
## Over one cycle every leg spends the same share of it in the air, so the mean
## number of feet off the ground is that share times the number of legs — and no
## more than `Footfall.lift_limit` of them may be off at once. A duty factor that
## asks for more than the lift limit allows is not a fast gait; it is a body
## permanently saturated at its own ceiling, where a foot goes up whenever a slot
## falls free rather than when the pattern says. What comes out is four legs
## taking turns in the order they happened to become overdue in, which is the one
## thing the footfall pattern exists to replace — and it is invisible until a
## build has enough interference to want something other than the even four-beat
## that order produces.
func swing_budget(cycle: float, aloft_share: float = 1.0, pace: float = 0.0) -> float:
	return maxf(cycle * minf(1.0 - duty_at(pace), maxf(aloft_share, 0.05) * SLOT_MARGIN),
		SWING_FLOOR)


## How quickly the body settles onto the height its feet are holding it at, given
## how long one limb's cycle is.
func settle(cycle: float) -> float:
	return clampf(SETTLE_CYCLES / maxf(cycle, 0.001), SETTLE_MIN, SETTLE_MAX)


## How high a foot comes up at the top of a step, before the posture's own leaning
## is applied. See LIFT_SHARE for why it is the larger of the two.
func lift(socket_height: float, bone: float) -> float:
	return maxf(socket_height, bone) * LIFT_SHARE


## How much shorter the body is drawn, given how far the two ends of it have
## converged. Signed: positive is a back folded up with the hind feet forward
## under the shoulders, negative is one stretched out at full extension.
##
## This is the whole of the spine's contribution to a stride and it needs no
## second term anywhere else. A body that is shorter this tick than it was last
## tick has carried its own shoulders backward relative to its hips; the limb
## sockets ride on the spine, so `Limb.track_socket` measures that as socket
## travel and the stride, the step timing and the landing prediction all follow
## from it exactly as they follow from the animal walking. Writing the back's
## share into the limb's own reach as well would be the same ground counted twice
## — and would hand the foot a stride longer than the envelope it is clamped
## into, which is a leg that can never become overdue and is towed instead.
## `gathering` is how much of the asymmetric regime the animal is actually in —
## see Footfall.aerial — and it is here so that the answer is *exactly* nothing
## under any alternating gait rather than merely nearly nothing. The measurement
## `gather` comes from very nearly cancels on its own when the limbs of a pair are
## half a cycle apart, but "very nearly" is not a rest length: a body whose spine
## is a thousandth of a pixel short every tick is a body the invariants can no
## longer be stated about, and a back that folds only when the girdles work as
## pairs is the truthful claim anyway.
func bunch(gather: float, gathering: float) -> float:
	return clampf(gather, -1.0, 1.0) * clampf(gathering, 0.0, 1.0) \
		* BUNCH_SHARE * spine_freedom
