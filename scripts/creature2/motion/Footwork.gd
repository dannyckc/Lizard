## The legs supporting and rebalancing the body — the support half of the
## locomotion loop.
##
## Nothing in this file drives the creature forward. The body has already
## moved (Impetus integrated the velocity, the chain followed its head), and
## what is left is the leg's whole job: keep the weight held up from wherever
## the feet actually are, and reorganise the feet when the body's motion has
## used up the support they were giving. So each foot is one of two things:
##
##   * **planted** — a world-fixed anchor. It does not move, whatever the body
##     does over it; that is what a foot on the ground is, and it is why
##     planted feet can never creep. What changes is the *relationship*: the
##     socket travels with the body, the foot's comfortable spot (its "home")
##     travels with the socket, and the drift between home and anchor is the
##     measurement everything else reads.
##   * **swinging** — an arc from where it lifted to a landing predicted from
##     the body's own velocity: where the home will be when the swing ends,
##     plus the stride lead, on whatever surface Outlook says is actually
##     there. The prediction is re-taken every tick, so a turning body lands
##     its feet where it is now going, not where it was going when they lifted.
##
## Steps are *triggered by need* — drift past the step trigger, the ground
## gone from under an anchor, or a balance rescue — and *granted by Rhythm*,
## which owns coordination and nothing else. Which is the design's split:
## need is shared physics, company is the gait.
##
## What the trigger *is* is the flow law, and it is the whole of the rhythm.
## A leg's swing takes what a driven pendulum takes (`Span.span_time` — the
## root of the leg's length, driven by twitch, gear and engine), so at any
## speed there is exactly one stride cycle at which the four swings tile it
## continuously at the occupancy the regime owes (`Rhythm.flow`): cycle =
## the four swing times over the occupancy. The drift a foot may spend
## before it is due is priced from that — the ground the body covers over
## one stance of that cycle — clamped to the anatomy's own wall (the disc a
## stride cannot exceed because the leg ends). So a slow walk takes short,
## frequent, unhurried steps; a cruise strides longer at a quicker beat; and
## the anatomical maximum is reached exactly where the legs run out of cycle
## to spend, which is the flat-out `deliverable` prices. Every term is the
## body's own; the beat is arithmetic, never a clock — a body that stops
## drifting stops stepping wherever it is in the cycle.
##
## The girdle carries are measured here, off the planted anchors: each girdle
## rides at its own feet's ground plus the stance clearance, so a foot set
## down on a ledge raises that end of the body with no ledge-case anywhere.
## And the press the feet have left — `grip` — is measured here and read by
## Impetus, so propulsion and support cannot be two opinions about the feet.
class_name Footwork
extends RefCounted

## Share of a limb's fore-aft excursion a stride may spend at the most — the
## anatomical ceiling on the step trigger, and what is left past it is the
## margin desperate steps and prediction error live in.
##
## This used to be the trigger itself, and that was the beat's whole disease:
## quoted as a fixed share of the *anatomy*, every step was near-maximal
## whatever the pace, so the stride never changed with speed (35 px at a
## stroll and 35 px at a cruise, measured) and every bit of pace adaptation
## was dumped into the wait between steps — a walk of isolated, near-tearing
## strides with the whole body parked four-square between them. The everyday
## trigger is now the *flow's* (see `tick`): the drift a foot may spend is
## priced from the body's own speed and swing tempo so the swings tile the
## cycle, and this share is only the wall it may never be priced past — the
## stride a leg cannot take because the leg ends. `deliverable` still quotes
## it, because flat out is exactly the speed at which the flow arrives here.
const TRIGGER: float = 0.78

## Least press a still-planted foot is quoted as having, whatever its drift —
## the floor under `_press`. A foot on the ground is pressing until it lifts, so
## its share of `grip` may thin as it trails its home but must not vanish while
## it is still bearing weight. Without the floor two feet near their trigger at
## once (an ordinary walk cycle) drove `grip` — and with it the whole engine —
## to zero for a few ticks, the body between feet with nothing to press against.
const PRESS_FLOOR: float = 0.5

## Swing speed, in limb lengths per second at the twitch datum. The muscle's
## ceiling on a swing, not its price: a longer leg swings a longer arc in the
## same time, a fast-twitch body sweeps quicker, and the tendon lever gears it
## (a tendon inserted close to the joint trades press for sweep —
## Carriage.Joint.gear).
##
## The history of this number is the history of the beat looking wrong. At 5.5
## every swing priced under the pendulum floor and the clamp decided
## everything; at 2.4 pricing the swing *by* it still collapsed every gait's
## swing onto whichever bound was nearer — a stroll's short arc swung in a
## flick, a sprint's clamped to the floor (129 ms, measured: the fore's own
## pendulum floor to the digit), and a foot crossing ninety pixels in eight
## frames is a cut, not a step. The lesson, twice learned: arc-over-rate is
## the wrong law for a rhythm, because a leg is a driven pendulum whose swing
## time is nearly a property of the leg (see SWING_SPAN below). So the rate
## now prices only what it honestly can: the ceiling an *emergency* swing may
## be hurried at (a rescue is a flick, and should be), the wall an ordinarily
## priced swing may never need more time than, and the flat-out arithmetic in
## `deliverable`, which is where a leg's sweep genuinely binds.
const SWING_RATE: float = 2.4
const TWITCH_FLOOR: float = 0.6
const TWITCH_SPAN: float = 0.8

## The swing itself, seconds — the reference hind leg's unhurried step at the
## twitch datum, the one pin the whole tempo hangs off. A leg is a driven
## pendulum: its swing time goes with the root of its length (`SWING_MIN_LEG`
## is the datum leg) and with the drive swinging it — fast twitch, the
## tendon's gearing and the census's engine all shorten it, exactly the terms
## that scale the sweep, and every one an exact no-op on the reference build.
## Pace compresses it a little (`SWING_HASTE`): a galloping cat's swing is a
## quarter shorter than its walking one, not a half — the observed near-
## invariance of swing time is *why* animals change duty factor with speed at
## all, and it is the anatomy this whole file's rhythm now derives from.
const SWING_SPAN: float = 0.33
const SWING_HASTE: float = 0.25

## Least of the stance's own annulus a step is worth taking over — the floor
## under the flow's stride budget, so a body creeping at a few px/s takes
## occasional deliberate steps (the stalk) rather than churning its feet over
## drifts too small to matter.
const BUDGET_MIN_SHARE: float = 0.3

## How much of the anatomy's wall the bound's stride budget spends. Under one
## because the wall is the tear-off itself — the gallop strides as long as
## the legs genuinely allow, and this margin is why an ordinary galloping
## stance ends with a lift instead of an anchor torn off its footing.
const BOUND_BUDGET: float = 0.9

## How much quicker a fully developed bound carries its swings than the pace
## alone buys — the gathered beat's spine recoil driving the legs. Scaled by
## `Rhythm.bound`, which already carries the spine's own freedom.
const GALLOP_SNAP: float = 0.4

## A swing is never over before or after these, seconds — the floor is the
## fast-twitch law's old truth (limbs stop blurring), the ceiling is a limp
## being a limp rather than a step.
##
## The floor is not one number for every body: a leg is a pendulum, and a
## pendulum's time goes with the root of its length — so the floor is quoted at
## the leg it was tuned on (the reference cat's hind, `SWING_MIN_LEG`) and
## scaled by √(leg/datum) for every limb of every body. A draught animal's
## swing floor is slower because its legs are longer, and nobody authored it;
## the reference hind comes out at the tuned number by construction and the
## shorter fore a shade under it, which is the pendulum being honest.
const SWING_MIN: float = 0.14
const SWING_MIN_LEG: float = 47.0
const SWING_MAX: float = 0.50

## Step clearance at a walk, px, scaled by the stance's own step-height
## leaning and by pace. A climb adds its own rise on top.
const STEP_H: float = 3.0

## How high the gathered beat carries a swinging paw over the walk's own
## clearance, as a share of that limb's length at a fully developed bound.
## Anatomy-scaled, not authored per gait: a galloping cat snaps its forearms
## up toward its chest and its hocks toward its hips, and how much paw that
## lifts is how much leg there is to fold. The fore folds higher — the reach
## phase of a gallop carries the paws up past the elbow — and both fade to
## exactly nothing as `Rhythm.bound` does, so a walk keeps its low, economical
## step.
const BOUND_LIFT_FORE: float = 0.32
const BOUND_LIFT_HIND: float = 0.22

## Share of a limb's plan capacity the striding disc spends — the rest is the
## margin the tear-off, the stretch ramp and a mispredicted landing live in.
## The capacity itself is anatomy (reach at the stops, minus the carry
## height); this is the one policy number between it and the stride.
const STRIDE_SHARE: float = 0.85

## How far ahead of its landing home a foot is set down, as a share of the
## stride it is about to be walked over (spec.foot_lead scales it).
## The landing prediction, not a drive: the body travels over the foot.
const RETARGET: float = 10.0

## Share of the excursion a rescue step spends reaching toward the spill.
const RESCUE_REACH: float = 0.9

## Share of a limb's remaining *plan* capacity — what its true anatomical
## reach (`Rig.reach_share` of its bones) leaves across the ground once the
## socket's own height is spent — past which the leg itself asks to step,
## whatever the drift says. Quoted on the plan and not on the bare span
## because a standing leg is mostly vertical: the fore leg spends nine tenths
## of its reach just standing, and a span-quoted ask would fire from the
## stance itself. The ramp starts early enough that a *standing* body whose
## whole support is creeping toward the edge — every anchor stretching in
## step, because the trunk slides as one piece — can renew its four legs one
## at a time before the anatomy binds: a walk's serial queue takes most of a
## second to turn three legs over, and an ask that fired closer to the tear
## had all three torn off together instead.
const STRETCH_ASK: float = 0.85
## ...and it reaches undeniable *before* the tear-off, not at it. Mapping the
## ramp's top onto the tear itself meant a queued foot only outranked the
## walk's single seat at the exact stretch where its anchor was already gone —
## so a creeping stand drained nothing early, three legs arrived at the cliff
## together, and the body stood on one foot while all of them re-planted. At
## 0.95 a near-torn foot goes desperate with capacity still in hand, the
## queue drains two at a time, and the mass tear never assembles.
const STRETCH_DESPERATE: float = 0.95

## The lateral-sequence seed, per foot in armature order (FL, FR, HL, HR):
## how far behind its own rhythm each anchor starts, as a phase. Only read at
## adoption — the walk keeps its own time from the first stride on.
const SEED_PHASE: Array[float] = [0.25, 0.75, 0.0, 0.5]
const SEED_SHARE: float = 0.35

## How far the surface under a planted anchor may move from what the foot
## stood down on before the foot must re-find its footing — the world changing
## under a foot is an emergency the gait may not deny, because the support the
## body is counting on is no longer the support that is there.
const GROUND_SHIFT: float = 2.0

## The anticipation: how much of a measured rise on the strip a girdle is about
## to cross its carry pre-lifts by, and the most it may pre-lift — the body
## starts carrying itself higher *before* the feet get there, so a step is
## approached on a smooth trajectory rather than hit as a jolt. Capped well
## inside the legs' extension margin: an anticipating body must still reach
## the ground it is actually standing on.
const ANTICIPATE: float = 0.45
const ANTICIPATE_CAP: float = 4.0

## How far a girdle dips between steps, px at full pace — the inverted-pendulum
## bob a walking body has and v2 did not. The carries were a flat measurement of
## the feet plus a constant clearance, so the weight glided at one height and the
## walk read as a hover. This dips the carry below the stance clearance at double
## support and lets it back up to the clearance at single support, off the pair's
## own swing phase (`gather_of`), so the highest point of the bob is the ordinary
## standing height and the leg only ever folds further for it — never reaches
## past its stance, which is what tore the feet off when the bob was a rise.
const VAULT: float = 6.0


## One foot: the world anchor, the swing, and the measurements between.
class Foot extends RefCounted:
	var limb: Armature.Chain
	var index: int = 0
	var fore: bool = true
	## World plan point the foot is standing on; meaningless while swinging.
	var anchor: Vector2 = Vector2.ZERO
	var anchor_z: float = 0.0
	## The surface height the foot stood down onto — what `anchor_z` is checked
	## against so a world moving under a planted foot is noticed.
	var stood_z: float = 0.0
	var swinging: bool = false
	## Seconds into the current swing, against its length.
	var swing: float = 0.0
	var swing_time: float = 0.2
	var lift: Vector3 = Vector3.ZERO
	var land: Vector3 = Vector3.ZERO
	## Seconds since it last landed.
	var since: float = 10.0
	## Drift in trigger units — ≥ 1.0 is a request to step.
	var urgency: float = 0.0
	## The comfortable spot this foot is measured against — where the socket and
	## the body's lean currently put it — and how far the anchor has been left
	## behind it. Readouts of the measurement below, kept because a reader that
	## re-derived either would be holding a second opinion about the same step;
	## `torn` is the honesty rule firing, which is the one state a foot can be in
	## that no drift describes.
	var home: Vector2 = Vector2.ZERO
	var drift: Vector2 = Vector2.ZERO
	var torn: bool = false
	## How much of the limb's remaining plan capacity the anchor is currently
	## spending, 0..1 — 1.0 is the tear-off. A readout of the tear measurement,
	## kept because the urgency reads it.
	var stretch: float = 0.0
	## How much of the *anatomical* room the drift has spent, 0..1 — what the
	## press fades by. Deliberately not the urgency: the flow's trigger moves
	## with speed, but how much push a trailing leg has left is a fact about
	## the leg, and quoting the engine against a rhythm was a grip that
	## weakened whenever the beat quickened.
	var spent: float = 0.0
	## A standing balance demand: where the next step must land, or INF for
	## none. Set by `rescue`, spent by the next lift.
	var rescue_at: Vector2 = Vector2.INF


## Per-girdle geometry re-measured each tick off the active carriage — the
## anatomy the steps are constrained by.
class Span extends RefCounted:
	## Fore-aft excursion radius of the pair's foot, px — the striding disc,
	## quoted at the joint's lock because a stride reaches.
	var excursion: float = 10.0
	## The same radius at the joint's stand — the disc a body at rest is
	## comfortable holding its feet inside. A standing animal's drift is
	## quoted against this: parked feet are held near their stance, not out
	## at the full reach a stride is entitled to, so a shove that skews the
	## stance gets tidied by a step instead of being braced forever.
	var comfort: float = 8.0
	## The disc's *lateral* radius — the bare leg's plan capacity, without
	## the scapula. The blade glides fore and aft only, so a fore disc that
	## spent the glide sideways plotted landings the leg could not span and
	## tore them off the moment they arrived.
	var lateral: float = 10.0
	## What the pair holds its girdle at above its feet, px.
	var clearance: float = 20.0
	## Swing speed, px/s — the muscle's ceiling, for emergencies and walls.
	var sweep: float = 200.0
	## What this pair's swing actually takes, seconds — the driven pendulum,
	## paced (see SWING_SPAN). The tempo the whole beat is derived from.
	var span_time: float = 0.26
	## The pendulum floor under this pair's swing, seconds — see SWING_MIN_LEG.
	var floor_time: float = 0.14
	## The stance's travel budget at this speed, split where the stride spends
	## it: `lead` ahead of the landing home, `threshold` of drift behind it
	## before the foot is due. Re-priced every tick off the flow (see `tick`);
	## `budget_max` is the anatomy's wall on the whole of it.
	var lead: float = 5.0
	var threshold: float = 10.0
	var budget_max: float = 30.0
	## The pair's share of the body's press, per foot.
	var press: float = 0.25


var feet: Array[Foot] = []
## How much press the planted feet have left, 0..1 — Impetus's ground term.
## 1.0 standing square and fresh; 0 airborne or with everything trailing.
var grip: float = 1.0

## How risen the body is, 0..1 — 1 standing, ramped up through a get-up. Scales
## the carries and the press together, because a body pushing itself up off its
## chest has folded legs under it and folded legs have little to press with.
## Written by Travel's recovery; 1 everywhere else, where it is an exact no-op.
var rise: float = 1.0

## Whether a foot came down out of a stride's own flight this tick — the
## gallop's landing, for Travel to spend as the absorb. Cleared every tick.
var stride_landed: bool = false

## What each girdle's own strip of path is about to rise by, px — the
## anticipation `_carry` spends, published because it is the one term of the
## carries that is a prediction rather than a measurement, and the only way to
## see the body starting to climb before a foot has reached the step.
var fore_rise: float = 0.0
var hind_rise: float = 0.0

var _fore: Span = Span.new()
var _hind: Span = Span.new()
## Last ground each girdle's feet were known to stand on — carries hold this
## through moments with the whole pair in the air.
var _fore_ground: float = 0.0
var _hind_ground: float = 0.0

## The standing hip height of the stance the body is *built* in — the Froude
## ladder's ruler. The rest stance deliberately (the v1 lesson: a crouch must
## not inflate the regime), cached at build because it cannot move in life.
var _rest_hip: float = 30.0

## The carriage of the stance the body is built in, for `deliverable` — the
## rest anatomy, deliberately, so the speed the legs quote cannot chase the
## pose the speed produced.
var _rest_carriage: Carriage

var _outlook: Outlook
var _rhythm: Rhythm


## Adopts the armature's limbs, planted exactly where the layout stood them,
## with the lateral-sequence seed staggering their rhythm. `seeded` is the
## spawn's privilege: a body standing back up mid-life adopts its feet exactly
## where its toes actually lie — its limbs were already solved this tick, and
## an anchor seeded away from a placed toe is a toe measurably off its own
## support for the one tick before the next solve. The walk re-finds its
## stagger from drift on its own.
func build(creature: Creature2, outlook: Outlook, rhythm: Rhythm,
		seeded: bool = true) -> void:
	_outlook = outlook
	_rhythm = rhythm
	_rest_hip = creature.body.stance_height(false)
	_rest_carriage = Carriage.new(creature.body, creature.body.posture)
	rise = 1.0
	stride_landed = false
	feet.clear()
	var a: Armature = creature.armature
	var dir: Vector2 = creature.move_dir
	_measure(creature)
	for i in a.limbs.size():
		var limb: Armature.Chain = a.limbs[i]
		var f := Foot.new()
		f.limb = limb
		f.index = i
		f.fore = limb.parent_node != a.pelvis_index()
		var toe: Vector3 = a.pos[limb.nodes[limb.nodes.size() - 1]]
		var reach: Span = _fore if f.fore else _hind
		var phase: float = SEED_PHASE[i] if i < SEED_PHASE.size() else 0.0
		f.anchor = Vector2(toe.x, toe.y)
		if seeded:
			f.anchor += dir * ((phase - 0.5) * SEED_SHARE * reach.excursion)
		f.anchor_z = _outlook.surface(f.anchor)
		f.stood_z = f.anchor_z
		f.home = f.anchor
		f.swinging = false
		f.since = 10.0
		feet.append(f)
	grip = 1.0
	_fore_ground = 0.0
	_hind_ground = 0.0
	_write(creature)
	# The carries are a measurement of the feet from the moment the feet are
	# adopted — a body standing on a table is standing on the table on its
	# first tick, not after one, or the contact stage would find its trunk
	# inside the solid it is standing on and press it off.
	_carry(creature, 0.0, Vector2.ZERO, false)


## One tick of support: measure every drift, ask Rhythm who may step, swing
## what is swinging, and hand the armature its feet and its carries.
##
## `lean` is the body-shift term — the homes are displaced by it, so an
## accelerating body's support genuinely trails its weight and the animal
## leans into its own thrust. `crouch` sinks the carries (a charge, a landing
## absorb). Order matters and is the loop's: the body has already moved this
## tick; the feet are answering it.
func tick(delta: float, creature: Creature2, velocity: Vector2, lean: Vector2,
		crouch: float, pace: float, airborne: bool, bounding: bool = false) -> void:
	var a: Armature = creature.armature
	_measure(creature)
	stride_landed = false

	for f in feet:
		f.since += delta

	if airborne:
		# Two kinds of air. A leap gathers the legs toward the landing
		# (`_float_feet`); a stride's own flight is nothing of the kind — the
		# swings that were already going keep going, aimed where the gait aimed
		# them, and the first to finish catches the body. That is the gallop's
		# suspension ending on a forefoot rather than on all fours.
		if bounding:
			for f in feet:
				if not f.swinging:
					continue
				f.swing += delta
				var fresh: Vector3 = _predict(a, f, velocity, lean,
					maxf(f.swing_time - f.swing, 0.0))
				f.land = f.land.lerp(fresh, 1.0 - exp(-RETARGET * delta))
				if f.swing >= f.swing_time:
					_plant(f)
					stride_landed = true
		else:
			_float_feet(creature, velocity)
		grip = 0.0
		_write(creature)
		_carry(creature, crouch, velocity, true)
		return

	# The beat's price, before any foot is measured against it. The four legs'
	# swing times over the occupancy the regime owes (`Rhythm.flow`) is the one
	# cycle at which the swings tile continuously — the flow — and each pair's
	# stance budget is the ground the body covers over one stance of that
	# cycle. Clamped to the anatomy's wall (`budget_max` — the stride a leg
	# cannot exceed because the leg ends), floored at a step worth taking (a
	# creeping body stalks, it does not churn), and handed back to the wall as
	# the bound develops, because a gallop spends full strides and buys the
	# rest with flight. The budget is then split where the stride spends it:
	# the landing leads its home by the spec's share, and the rest is the
	# drift a planted foot may spend before it is due. Nothing here is a
	# clock — a body that stops drifting stops stepping mid-cycle — but at a
	# steady speed the arithmetic *is* a beat, which is what a rhythm being
	# derived rather than authored means.
	var speed: float = velocity.length()
	var flow_S: float = _rhythm.flow(speed, _rest_hip)
	var cycle: float = 2.0 * (_fore.span_time + _hind.span_time) \
		/ maxf(flow_S, 0.5)
	var lead_share: float = 2.0 * creature.body.foot_lead \
		/ (1.0 + 2.0 * creature.body.foot_lead)
	for g in [_fore, _hind]:
		var pair: Span = g
		var budget: float = clampf(speed * (cycle - pair.span_time),
			BUDGET_MIN_SHARE * TRIGGER * pair.comfort, pair.budget_max)
		# The bound spends full strides — but full stops a step short of the
		# wall itself: a budget priced *at* the tear-off had every galloping
		# stance end torn, and a gait whose every stride is an emergency is
		# the teleporting feet again, wearing physics as an excuse.
		budget = lerpf(budget, pair.budget_max * BOUND_BUDGET,
			clampf(_rhythm.bound, 0.0, 1.0))
		pair.lead = budget * lead_share
		pair.threshold = maxf(budget - pair.lead, 0.001)

	# The measurements: where each planted foot stands against where its body
	# now wants it.
	var urgency := PackedFloat32Array()
	var swinging := PackedByteArray()
	var since := PackedFloat32Array()
	var travel_dir: Vector2 = velocity.normalized() \
		if velocity.length_squared() > 4.0 else Vector2.ZERO
	for f in feet:
		var reach: Span = _fore if f.fore else _hind
		f.home = _home(a, f, lean)
		if not f.swinging:
			f.anchor_z = _outlook.surface(f.anchor)
			# Torn off: a body dragged past what the limb can span from socket
			# to anchor has pulled the foot off its footing — the anchor is no
			# longer support, whatever the foot would prefer, and saying so is
			# what lets the review see a body going over an edge as one losing
			# its feet rather than as one mysteriously still standing. The
			# span that counts is the rig's, not the ruler's: the joints stop
			# a few percent short of geometric straight, and past *that* the
			# leg is no longer delivering the anchor however the bones add up.
			var seat: Vector3 = a.socket_of(f.limb)
			var span: Vector2 = f.anchor - Vector2(seat.x, seat.y)
			var rise: float = seat.z - f.anchor_z
			var held: float = sqrt(span.length_squared() + rise * rise)
			var reach_len: float = creature.body.limb_length(f.fore) \
				* a.rig.reach_share(f.fore)
			if held > reach_len:
				f.torn = true
				f.urgency = Rhythm.DESPERATE
				_lift(a, f, velocity, lean, pace)
			elif f.limb.cramped:
				# The rig ran out of joints holding this anchor last tick —
				# every stop taken and the pose still short (`Rig.cramped`).
				# The same emergency a torn anchor is, told one seam earlier,
				# and it may not wait its turn: the alternative is a paw
				# standing outside its own anatomy.
				f.torn = true
				f.urgency = Rhythm.DESPERATE
				_lift(a, f, velocity, lean, pace)
			else:
				# What the anatomy leaves across the ground from this socket
				# height — the plan room the anchor is spending. The vertical
				# came off the reach first, because it always does.
				var plan_max: float = sqrt(maxf(
					reach_len * reach_len - rise * rise, 1.0))
				f.stretch = span.length() / plan_max
		if f.swinging:
			f.urgency = 0.0
			f.spent = 0.0
			f.drift = Vector2.ZERO
		else:
			var drift: Vector2 = f.home - f.anchor
			f.drift = drift
			# Support is only being used up where the home is leaving the anchor
			# behind — along the travel, or sideways out of the disc. A foot
			# standing *ahead* of its home is support the body is about to walk
			# over, and asking it to step is what turned a walk into a scramble.
			var need: float = drift.length()
			# A travelling body is due at the flow's own trigger — the drift
			# its stance budget prices at this speed, so the steps tile the
			# cycle — and one standing still is only comfortable inside the
			# stance's own annulus (see Span.comfort). `spent` quotes the same
			# drift against the anatomy instead, because how much push the leg
			# has left is a fact about the leg, not about the beat.
			var need_room: float = reach.comfort
			var gate: float = TRIGGER * reach.comfort
			if travel_dir != Vector2.ZERO:
				var along: float = maxf(drift.dot(travel_dir), 0.0)
				var lat: float = drift.dot(Vector2(-travel_dir.y, travel_dir.x))
				need = Vector2(along, lat).length()
				need_room = reach.excursion
				gate = reach.threshold
			f.spent = need / maxf(need_room, 0.001)
			f.urgency = need / maxf(gate, 0.001)
			# ...and the anatomy has its own voice: the drift is measured to the
			# foot's *preferred* spot, and a lean can park the preference right
			# next to the anchor while the leg itself is quietly running out of
			# joint — a standing body being pressed off its feet by nothing but
			# its own sway. So a leg near the edge of its plan capacity asks on
			# that account, ramping to undeniable just before the tear-off
			# would fire, which is what lets the feet reorganise one at a time
			# instead of three of them being torn together the moment the
			# stretch arrives.
			if f.stretch > STRETCH_ASK:
				f.urgency = maxf(f.urgency, 1.0 + (f.stretch - STRETCH_ASK)
					/ maxf(STRETCH_DESPERATE - STRETCH_ASK, 0.001)
					* (Rhythm.DESPERATE - 1.0))
			if absf(f.anchor_z - f.stood_z) > GROUND_SHIFT:
				# The world moved under the anchor — the ground gone from under a
				# foot (or risen through it) is a step nothing may deny.
				f.urgency = maxf(f.urgency, Rhythm.DESPERATE)
			if f.rescue_at.x < INF:
				f.urgency = maxf(f.urgency, Rhythm.DESPERATE)
		urgency.append(f.urgency)
		swinging.append(1 if f.swinging else 0)
		since.append(f.since)

	# The gait: who steps, in what company. The regime is the body's own Froude
	# number off the speed it is actually travelling at — a turning gallop is
	# still a gallop, and quoting only the forward share was what starved a
	# hard-turning sprint of the seats its own legs needed. The couplings the
	# policy weighs are anatomy: the spec's trotting coupling, each girdle's
	# attach hold, the spine's freedom to bound.
	var granted: PackedInt32Array = _rhythm.choose(urgency, swinging, since,
		velocity.length(), _rest_hip, creature.body.beat_coupling,
		Vector2(creature.body.fore_girdle_hold, creature.body.hind_girdle_hold),
		creature.body.spine_freedom)
	for i in granted:
		_lift(a, feet[i], velocity, lean, pace)

	# The swings, each re-aimed at where its landing has moved to.
	for f in feet:
		if not f.swinging:
			continue
		f.swing += delta
		var fresh: Vector3 = _predict(a, f, velocity, lean,
			maxf(f.swing_time - f.swing, 0.0))
		f.land = f.land.lerp(fresh, 1.0 - exp(-RETARGET * delta))
		if f.swing >= f.swing_time:
			_plant(f)

	_press(creature)
	_write(creature)
	_carry(creature, crouch, velocity, false)


## The armature has just been carried — copy each socket's solved height onto
## its limb, so the leg is solved from where the body actually holds it. The
## socket's own height, not the girdle's: on a heeled body they are not the same
## number, and it is the difference between them that folds one leg up and
## stretches the other off the ground.
func perch(a: Armature) -> void:
	for f in feet:
		f.limb.socket_rise = a.socket_of(f.limb).z


## A balance demand from the review: the weight is going over the edge in
## `overhang`'s direction, and the support has to follow it.
##
## If feet are already in the air, the nearest swing is *steered* toward the
## spill — lifting more support to save the support is how a stumble was
## making its own emergency worse. Only a body with its feet down answers by
## lifting one: the planted foot nearest the spill, marked as a request
## nothing may deny (the step itself still goes through Rhythm).
func rescue(centre: Vector2, overhang: Vector2) -> void:
	if overhang.length_squared() < 0.0001:
		return
	var dir: Vector2 = overhang.normalized()
	var best: Foot = null
	var best_side: float = -INF
	var airborne_feet: int = 0
	for f in feet:
		if f.swinging:
			airborne_feet += 1
	var steer: bool = airborne_feet >= 1
	for f in feet:
		if f.swinging != steer or f.rescue_at.x < INF:
			continue
		var side: float = (f.anchor - centre).dot(dir) if not steer \
			else (Vector2(f.land.x, f.land.y) - centre).dot(dir)
		if side > best_side:
			best_side = side
			best = f
	if best == null:
		return
	var reach: Span = _fore if best.fore else _hind
	best.rescue_at = centre + dir * (overhang.length()
		+ RESCUE_REACH * reach.excursion * 0.5)


## The balance has recovered — standing demands not yet spent are dropped, so
## a stale emergency cannot keep churning feet the body no longer needs moved.
func calm() -> void:
	for f in feet:
		if not f.swinging:
			f.rescue_at = Vector2.INF


## Every swinging foot far enough through its arc comes down where it was
## aimed — what a landing body does with the legs it was holding ready. A leap
## passes 0 (the float gathered every foot toward the landing, and they all
## arrive with the body); a stride's flight passes a share, so the feet still
## early in their swings keep swinging and the gallop's landings stay
## staggered instead of being stamped down four at once.
func touchdown(min_share: float = 0.0) -> void:
	for f in feet:
		if f.swinging and f.swing >= f.swing_time * min_share:
			_plant(f)


func planted() -> int:
	var count: int = 0
	for f in feet:
		if not f.swinging:
			count += 1
	return count


## Seconds until the first swinging foot arrives — how long a stride's flight
## has before something catches the body. INF with nothing in the air.
func first_landing_in() -> float:
	var least: float = INF
	for f in feet:
		if f.swinging:
			least = minf(least, maxf(f.swing_time - f.swing, 0.0))
	return least


## The mean swing phase of a girdle's pair, 0..1 peaking mid-swing — the
## gather, as a measurement: how far under the body the pair is being carried.
## The spine's stride share is driven off this, so the back rounds exactly when
## the hindquarters are coming under and not on any clock of its own.
func gather_of(fore: bool) -> float:
	var sum: float = 0.0
	var count: int = 0
	for f in feet:
		if f.fore != fore:
			continue
		count += 1
		if f.swinging:
			sum += sin(PI * clampf(f.swing / maxf(f.swing_time, 0.001), 0.0, 1.0))
	return sum / maxf(float(count), 1.0)


# ------------------------------------------------------------- the stages ----

## A foot leaves the ground: remember where it was, aim it at where its
## support will be needed, and price the swing off the limb's own tempo.
##
## The tempo is the pair's `span_time` — the driven pendulum — and not the
## arc over the sweep: a leg's swing takes what a leg's swing takes, and
## pricing it by distance was what collapsed every gait's step onto a clamp
## (a short arc flicked, a long one pinned at the floor, and both read as
## cuts). The sweep still has its two honest words: an ordinary swing whose
## arc genuinely outruns the muscle takes the longer time, and a *desperate*
## step — a rescue, a tear-off — is hurried at the muscle's full rate,
## because a stumble recovery is a flick and should be.
func _lift(a: Armature, f: Foot, velocity: Vector2, lean: Vector2,
		pace: float) -> void:
	var reach: Span = _fore if f.fore else _hind
	f.swinging = true
	f.swing = 0.0
	f.lift = Vector3(f.anchor.x, f.anchor.y, f.anchor_z)

	f.land = _predict(a, f, velocity, lean, reach.span_time)
	var arc: float = Vector2(f.land.x - f.lift.x, f.land.y - f.lift.y).length() \
		+ absf(f.land.z - f.lift.z)
	var haste: float = 1.0 + 0.6 * clampf(pace, 0.0, 1.5)
	var sweep_time: float = arc / maxf(reach.sweep * haste, 1.0)
	if f.torn or f.rescue_at.x < INF:
		# A genuine emergency — footing gone, or the balance demanding a print
		# somewhere now. Merely being overdue at pace is not one: hurrying
		# every deep-drifted swing was the sprint's teleporting feet.
		f.swing_time = clampf(sweep_time, reach.floor_time, SWING_MAX)
	else:
		f.swing_time = clampf(maxf(reach.span_time, sweep_time),
			reach.floor_time, SWING_MAX)


## Where this foot should land: its home carried forward by the body's own
## velocity over the rest of the swing, led by the stride share, capped to
## the limb's reach, and placed on the surface that is actually there.
func _predict(a: Armature, f: Foot, velocity: Vector2, lean: Vector2,
		left: float) -> Vector3:
	var reach: Span = _fore if f.fore else _hind
	var socket: Vector2 = _socket(a, f)
	var home_then: Vector2 = _home(a, f, lean) + velocity * left
	var spec: BodySpec = a.spec
	# The landing leads its home by the flow's own share of the coming stance
	# (Span.lead, priced in `tick`): a short quick stride is led a little, a
	# full one more, and the lead can never promise ground the stance budget
	# has not priced.
	var lead: float = reach.lead
	var dir: Vector2 = velocity.normalized() if velocity.length_squared() > 1.0 \
		else Vector2.ZERO
	var plan: Vector2 = home_then + dir * lead
	if f.rescue_at.x < INF:
		plan = f.rescue_at
	# Anatomy last: a foot cannot land past its own excursion — and the disc
	# is an ellipse, because the scapula's share of the fore radius exists
	# fore and aft only (Span.lateral is the bare leg's sideways capacity).
	var socket_then: Vector2 = socket + velocity * left
	var out: Vector2 = plan - socket_then
	var fwd_p: Vector2 = a.fwd[f.limb.parent_node]
	var out_along: float = out.dot(fwd_p)
	var out_lat: float = out.dot(Vector2(-fwd_p.y, fwd_p.x))
	var over: float = sqrt(
		pow(out_along / maxf(reach.excursion, 0.001), 2.0)
		+ pow(out_lat / maxf(reach.lateral, 0.001), 2.0))
	if over > 1.0:
		plan = socket_then + (fwd_p * out_along
			+ Vector2(-fwd_p.y, fwd_p.x) * out_lat) / over
	# ...and the world answers with the surface the landing is actually on.
	var leg: float = spec.limb_length(f.fore)
	return _outlook.reach_along(Vector2(f.lift.x, f.lift.y), plan, f.lift.z, leg)


func _plant(f: Foot) -> void:
	f.swinging = false
	f.anchor = Vector2(f.land.x, f.land.y)
	f.anchor_z = _outlook.surface(f.anchor)
	f.stood_z = f.anchor_z
	f.since = 0.0
	f.torn = false
	f.rescue_at = Vector2.INF


## Airborne, the legs gather toward where the body will need them — swings
## aimed at the landing homes, never planted until the body is down.
func _float_feet(creature: Creature2, velocity: Vector2) -> void:
	var a: Armature = creature.armature
	var t_air: float = maxf(Gravity.fall_time(a.fall.height, a.fall.rate,
		a.fall.floor_height), 0.05)
	for f in feet:
		if not f.swinging:
			f.swinging = true
			f.swing = 0.0
			var from: Vector3 = a.pos[f.limb.nodes[f.limb.nodes.size() - 1]]
			f.lift = from
		f.swing = minf(f.swing, f.swing_time * 0.6)
		var plan: Vector2 = _home(a, f, Vector2.ZERO) + velocity * t_air
		f.land = Vector3(plan.x, plan.y, _outlook.surface(plan))
		f.swing_time = maxf(t_air, 0.15)


# ------------------------------------------------------- the measurements ----

## The pair geometry off the active carriage: what the anatomy currently
## constrains a step to. Re-taken every tick because the stance blends.
func _measure(creature: Creature2) -> void:
	var spec: BodySpec = creature.body
	var carriage: Carriage = creature.attitude.active
	var c: Dictionary = creature.corpus.compartments()
	var fore_pair: float = float(c.get(&"fore_girdle", 1.0)) \
		* carriage.fore.advantage
	var hind_pair: float = float(c.get(&"hind_girdle", 1.0)) \
		* carriage.hind.advantage
	var total: float = maxf(fore_pair + hind_pair, 0.0001)
	# The engine under the swing: locomotor muscle over body mass, against the
	# reference cat's own ratio — the same derived number Impetus pushes with,
	# read at the root because a swing is a force moving a mass and its time
	# goes with the root of the acceleration. Exactly 1.0 on the default build
	# (the power datum), so the reference tempo is untouched; a heavy body with
	# ordinary muscle genuinely swings its legs slower, and a chewed one slows
	# as its compartments shrink.
	var engine: float = sqrt(clampf(creature.travel.impetus.power, 0.05, 4.0))
	for fore in [true, false]:
		var reach: Span = _fore if fore else _hind
		var joint: Carriage.Joint = carriage.of(fore)
		var leg: float = spec.limb_length(fore)
		reach.clearance = carriage.stance_clearance(leg, joint.stand,
			spec.stance_width,
			spec.front_foot_bias if fore else spec.rear_foot_bias)
		# The striding disc is a share of the limb's *plan capacity*: what its
		# true anatomical reach (the joints' own extension stops) leaves
		# across the ground once the carry height is spent — the same quantity
		# the tear-off measures, quoted one seam earlier so a stride and its
		# own honesty rule cannot disagree. Quoting the stand's annulus here
		# was a mincing stride that never used the reach the leg had; quoting
		# the lock's was worse — a disc wider than the leg can span at its
		# own standing height, so landings were plotted outside anatomy and
		# torn off the moment they arrived, over and over. The fore adds the
		# scapula: the glenoid follows the working foot by the rig's glide,
		# the blade acting as the first segment of the limb, and that travel
		# is most of why the strutted fore strides anything like the hind.
		var span_max: float = leg * creature.armature.rig.reach_share(fore)
		var plan_cap: float = sqrt(maxf(span_max * span_max
			- reach.clearance * reach.clearance, 4.0))
		reach.lateral = maxf(STRIDE_SHARE * plan_cap, 2.0)
		if fore:
			plan_cap += minf(Rig.SCAP_FOLLOW * plan_cap,
				Rig.SCAP_TRAVEL * spec.scapula_len)
		reach.excursion = maxf(STRIDE_SHARE * plan_cap, 2.0)
		# At a stand the comfortable disc is the stance's own annulus — never
		# wider than the striding disc, which is a capacity, not a taste.
		reach.comfort = clampf(carriage.fore_aft_reach(leg, joint.stand,
			spec.stance_width), 2.0, reach.excursion)
		var twitch_drive: float = (TWITCH_FLOOR + TWITCH_SPAN * spec.fast_twitch) \
			* joint.gear * engine
		reach.sweep = SWING_RATE * leg * twitch_drive
		reach.floor_time = SWING_MIN * sqrt(maxf(leg, 1.0) / SWING_MIN_LEG)
		# The driven pendulum: what this pair's swing takes. The root-of-length
		# law the floor already states, driven by the same terms the sweep is
		# (twitch, the tendon's gear, the census's engine — each an exact no-op
		# on the reference build), and compressed a little by pace: a swing is
		# nearly a property of the leg, which is exactly why the *cycle* must
		# be derived from it and not the other way round.
		# ...compressed by pace, and snapped up harder by the bound: the
		# gathered beat's spine recoil drives the legs, so a galloping swing
		# is quicker than the pace alone buys — `Rhythm.bound` already
		# carries the spine's own freedom, so a stiff back gets none of it.
		reach.span_time = clampf(
			SWING_SPAN * sqrt(maxf(leg, 1.0) / SWING_MIN_LEG)
				/ maxf(twitch_drive, 0.05)
				/ (1.0 + SWING_HASTE * clampf(creature.speed_norm, 0.0, 1.5))
				/ (1.0 + GALLOP_SNAP * clampf(_rhythm.bound, 0.0, 1.0)),
			reach.floor_time, SWING_MAX)
		# The anatomy's wall on a whole stance's travel — the old fixed stride,
		# kept as the ceiling the flow prices under: trigger's share of the
		# disc behind the home plus the spec's lead ahead of it.
		reach.budget_max = TRIGGER * reach.excursion \
			* (1.0 + 2.0 * spec.foot_lead)
		reach.press = (fore_pair if fore else hind_pair) / total


## Where the foot's girdle datum is on the plan — the armature's own answer,
## not a second copy of the arithmetic, so a heeled body's shortened plan
## offset is here the moment it is there. The *bare* girdle, deliberately:
## the scapular glide follows the working foot, and measuring homes against a
## socket that chases its own foot would slacken every stride trigger.
func _socket(a: Armature, f: Foot) -> Vector2:
	var seat: Vector3 = a.girdle_of(f.limb)
	return Vector2(seat.x, seat.y)


## The foot's comfortable spot: out from its socket by the rest lead, shifted
## by the body's lean. Everything is measured against this point.
##
## The lean lands girdle by girdle, weighted by each pair's own share of the
## press (the census's muscle through the stance's advantage — `Span.press`,
## ×2 because the two girdles' shares sum to one). An accelerating quadruped
## is not shifted evenly off its feet: the girdle with the engine trails its
## homes further and drives from behind its own weight, the other stays under
## the mass it is about to catch — on the cat, hind drives and fore catches,
## and neither was told to.
func _home(a: Armature, f: Foot, lean: Vector2) -> Vector2:
	var p: int = f.limb.parent_node
	var reach: Span = _fore if f.fore else _hind
	return _socket(a, f) + a.fwd[p] * f.limb.foot_lead \
		+ lean * (2.0 * reach.press)


## How much press the planted feet have left, for Impetus: each foot counts
## its girdle's share, faded by how far it is already trailing its home (a
## leg near full extension behind has nothing left to push with) and by how
## much of its muscle is still answering.
func _press(creature: Creature2) -> void:
	var corpus: Corpus = creature.corpus
	var sum: float = 0.0
	for f in feet:
		if f.swinging:
			continue
		var reach: Span = _fore if f.fore else _hind
		# A planted foot presses less the further it trails its home, but never
		# nothing: it is still flat on the ground until the tick it actually
		# lifts. The fade quotes `spent` — drift against the *anatomy's* room,
		# not against the flow's trigger, because how much push a trailing leg
		# has left is a fact about the leg and the beat quickening must not
		# thin the engine. The floor keeps the traction a still-planted foot
		# genuinely has while leaving the fade that makes a shoved, trailing
		# foot give way (the rescue step) exactly as it was.
		var left: float = clampf(1.0 - maxf(f.spent, 0.0), PRESS_FLOOR, 1.0)
		# Soundness is the muscle still answering; numbness is the nerve still
		# asking. A leg with either gone presses with that much less — a cut
		# sciatic takes its leg out of the engine without touching the flesh.
		sum += reach.press * left * corpus.soundness(f.limb.name) \
			* creature.vitals.numbness(f.limb.name)
	# Standing square and fresh, the four feet sum to two pair-shares — that
	# is the datum grip 1.0 is quoted against. A body still pushing itself up
	# presses with folded legs, which is most of why a get-up is a vulnerable
	# moment rather than a teleport.
	grip = clampf(sum / 2.0, 0.0, 1.0) * lerpf(0.3, 1.0, clampf(rise, 0.0, 1.0))


## Hands the armature its feet: the world points, and whether each is
## bearing. The one writer of the limb seam.
func _write(creature: Creature2) -> void:
	var collapsed: bool = creature.armature.collapsed
	for f in feet:
		var limb: Armature.Chain = f.limb
		if collapsed:
			limb.foot_driven = false
			limb.grounded = false
			continue
		limb.foot_driven = true
		if f.swinging:
			var t: float = clampf(f.swing / maxf(f.swing_time, 0.001), 0.0, 1.0)
			var s: float = smoothstep(0.0, 1.0, t)
			var reach: Span = _fore if f.fore else _hind
			var carriage: Carriage = creature.attitude.active
			var rise: float = STEP_H * carriage.step_height_gain \
				* (0.6 + 0.8 * clampf(creature.speed_norm, 0.0, 1.5)) \
				+ maxf(f.land.z - f.lift.z, 0.0) * 0.35 \
				+ _rhythm.bound * creature.body.limb_length(f.fore) \
				* (BOUND_LIFT_FORE if f.fore else BOUND_LIFT_HIND)
			var plan: Vector2 = Vector2(f.lift.x, f.lift.y).lerp(
				Vector2(f.land.x, f.land.y), s)
			var z: float = lerpf(f.lift.z, f.land.z, s) + sin(t * PI) * rise
			limb.foot_target = Vector3(plan.x, plan.y, z)
			limb.grounded = false
		else:
			limb.foot_target = Vector3(f.anchor.x, f.anchor.y, f.anchor_z)
			limb.grounded = true


## The carries: each girdle rides at its own feet's ground plus the stance
## clearance, sunk by the crouch and pre-lifted toward whatever rise its own
## strip of path is about to cross — the body's trajectory anticipates the
## step instead of being jolted by it, and the feet then land on ground the
## body is already carrying itself toward. A pair entirely in the air keeps
## the last ground it stood on — the body does not guess at a floor its feet
## have not touched.
func _carry(creature: Creature2, crouch: float, velocity: Vector2,
		airborne: bool) -> void:
	var a: Armature = creature.armature
	for fore in [true, false]:
		var reach: Span = _fore if fore else _hind
		var ground: float = 0.0
		var down: int = 0
		for f in feet:
			if f.fore != fore or f.swinging:
				continue
			ground += f.anchor_z
			down += 1
		if down > 0:
			ground /= float(down)
			if fore:
				_fore_ground = ground
			else:
				_hind_ground = ground
		else:
			ground = _fore_ground if fore else _hind_ground
		# The clearance the pair delivers, sunk by the crouch — and by how far
		# through a get-up the body is: a rising animal's girdles travel from
		# chest height to stance height because its legs are unfolding under
		# it, and `rise` is that unfolding. 1 everywhere outside a get-up.
		var carry: float = ground + reach.clearance \
			* (1.0 - 0.4 * clampf(crouch, 0.0, 1.0)) \
			* lerpf(0.15, 1.0, clampf(rise, 0.0, 1.0))
		var coming: float = 0.0
		if not airborne:
			# The anticipation, measured from the girdle itself: what rises on
			# the strip *this* end of the body is about to cross, so the fore
			# quarters lift for a step the hind quarters have not reached yet.
			var girdle: Vector2 = a.plan(a.withers_index() if fore else a.pelvis_index())
			coming = _outlook.rise_ahead(girdle, velocity * Outlook.HORIZON, ground)
			carry += clampf(coming * ANTICIPATE, 0.0, ANTICIPATE_CAP)
			# ...and the vault: a walking body rides highest as it passes over its
			# own standing leg and settles between steps, so the weight breathes
			# vertically instead of gliding. Written as a dip from the stance
			# clearance at double support (this girdle's pair both down, nothing
			# mid-swing) back up to it at single support (one foot swinging, its
			# partner bearing the body) — downward only, so the leg folds into the
			# bob and never has to reach past its own stance height for it, which
			# is what tore the feet off when the vault was written as a rise.
			# Scaled by pace, so a standing body does not bob and a brisk walk
			# breathes most, and handed to the gallop's ballistic suspension as
			# the bound develops, so the two never stack.
			# Suppressed under the crouch: a body gathering for a jump or sinking
			# into a landing has its feet planted, which reads as double support
			# and would spend the full dip on a body that is deliberately low for
			# a different reason — the crouch owns the vertical there, not the
			# walk's bob, and without this the extra sink dropped a charged leap
			# low enough to clip the lip of what it was jumping onto.
			var support_phase: float = clampf(gather_of(fore) * 2.0, 0.0, 1.0)
			carry -= VAULT * clampf(creature.speed_norm, 0.0, 1.0) \
				* (1.0 - support_phase) * (1.0 - clampf(_rhythm.bound, 0.0, 1.0)) \
				* (1.0 - clampf(crouch, 0.0, 1.0))
		if fore:
			fore_rise = coming
			a.fore_carry = carry
		else:
			hind_rise = coming
			a.hind_carry = carry


## The ground frame the carries are quoting: what the planted (or last
## planted) feet are standing on, averaged over the girdles. The fall's floor
## is measured against this while the body is airborne — the difference
## between the ground now under the body and the ground it took off from.
func frame_ground() -> float:
	return (_fore_ground + _hind_ground) * 0.5


## What a pair's anatomy currently allows a step: the fore-aft disc a foot may
## be placed in, what the pair holds its girdle at above its feet, and how fast
## it sweeps. Re-measured every tick off the active carriage (`_measure`) — the
## constraints a stride is quoted against, and the reason a stride length on its
## own says nothing about whether a walk is mincing.
func excursion(fore: bool) -> float:
	return (_fore if fore else _hind).excursion


func clearance(fore: bool) -> float:
	return (_fore if fore else _hind).clearance


func sweep(fore: bool) -> float:
	return (_fore if fore else _hind).sweep


## The speed these legs can actually deliver flat out, px/s — the anatomical
## ceiling every ask is ultimately spent against, derived and never authored.
##
## The arithmetic is the stride cycle read backwards. A swinging foot must
## regain, against the ground, the stride it just spent: its own excursion plus
## the trigger's share of drift, minus what the scapula's glide hands the fore
## pair for free. It regains it at the margin between how fast the leg can
## sweep (the same tempo law `_measure` prices swings with, at the haste the
## gait tops out at) and how fast the body is carrying its socket away — and it
## has at most `SWING_MAX` to do it in, because past that a swing is a limp.
## Solve that for the body's speed and each girdle quotes a ceiling; the animal
## travels at the slower girdle, which for the cat is the short-strutted fore —
## exactly the anatomy that binds a real gallop.
##
## Every term is the body's own: leg length, twitch, tendon gearing, the rest
## stance's reach, the census's power (wounds genuinely slow the sprint). The
## rest carriage deliberately — quoting the live pose would let the speed chase
## the crouch the speed produced. Nothing here reads the solved gait.
func deliverable(creature: Creature2) -> float:
	var spec: BodySpec = creature.body
	if _rest_carriage == null:
		_rest_carriage = Carriage.new(spec, spec.posture)
	var engine: float = sqrt(clampf(creature.travel.impetus.power, 0.05, 4.0))
	# The quickest beat the gait ever asks for — `_lift`'s haste at its own
	# pace cap.
	var haste: float = 1.0 + 0.6 * 1.5
	var least: float = INF
	for fore in [true, false]:
		var joint: Carriage.Joint = _rest_carriage.of(fore)
		var leg: float = spec.limb_length(fore)
		# The same striding disc `_measure` quotes, off the rest carriage.
		var span_max: float = leg * creature.armature.rig.reach_share(fore)
		var clear_h: float = _rest_carriage.stance_clearance(leg, joint.stand,
			spec.stance_width,
			spec.front_foot_bias if fore else spec.rear_foot_bias)
		var plan_cap: float = sqrt(maxf(span_max * span_max
			- clear_h * clear_h, 4.0))
		var glide: float = 0.0
		if fore:
			glide = minf(Rig.SCAP_FOLLOW * plan_cap,
				Rig.SCAP_TRAVEL * spec.scapula_len)
			plan_cap += glide
		var exc: float = maxf(STRIDE_SHARE * plan_cap, 2.0)
		var sweep_rate: float = SWING_RATE * leg \
			* (TWITCH_FLOOR + TWITCH_SPAN * spec.fast_twitch) * joint.gear \
			* engine
		# What the foot must regain against the ground each cycle — the blade's
		# travel is regained for free, the glenoid moving with the foot.
		var stride: float = maxf((1.0 + TRIGGER) * exc - 2.0 * glide, 0.0)
		least = minf(least, sweep_rate * haste - stride / SWING_MAX)
	return maxf(least, 1.0)
