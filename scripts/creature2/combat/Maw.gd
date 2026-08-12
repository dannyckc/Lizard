## The bite, from the ask to the flesh — v2's strike pipeline.
##
## The v1 pipeline survives structurally (docs/V2_DESIGN.md §9.2): one 3D
## contact point, a preview that commits nothing, a lunge that is the *body*
## moving — a rigid shift capped by the support, because a neck cannot stretch
## — reach measured from the rest pose, and verticals gated before
## horizontals. What changed is the addressing: the contact resolves to a body
## address `(chain, t, θ)` on the target's posed rings (Contour.locate — the
## same rings every view draws, so what is bitten is what is displayed by
## construction), and the damage is §6's depth walk (Corpus.wound), tooth by
## tooth.
##
## The bite is fully 2.5D. The mouth is somewhere — a plan position *and* a
## height, the head node the armature actually carries — and the strike
## connects with what that mouth arrives at. A bite at a carcass on the floor
## carries the head down to it through the armature's own Z channel
## (`head_reach_z`), which moves the drawn head, the jaw frame and the hit
## band together because they are one set of nodes; a contact higher than the
## neck can be carried is refused before any horizontal question is asked; and
## the neck is an arc, so height and distance are one purse — the same gap is
## reachable at the mouth's own level and refused onto the floor.
##
## The hold is possession with the v1 grip's teeth: a latched mouth keeps a
## *body address*, not a world point, so the flesh it follows through every
## pose of the target is the flesh it closed on. The tether tows the lighter
## body, tears free past what flesh holds, and a chew re-closes the same jaws
## on the same wedge — which lands deeper every time, because the census got
## thinner, and nobody wrote "work in".
class_name Maw
extends RefCounted

const IDLE: int = 0
const THROW: int = 1
const RECOVER: int = 2

## The throw and the recovery, seconds. A strike is fast and its recovery is
## not — the same asymmetry as a chew.
const THROW_TIME: float = 0.18
const RECOVER_TIME: float = 0.35

## The feeding cadence: seconds between closings of a latched jaw.
const CHEW_TIME: float = 0.9

## How far past the tooth arc flesh may sit and the closing still find it, as
## a multiple of the muzzle reach. The gape's grab, not a homing radius — and
## sized against the contact solver's own keep: a body pressing on what it
## bites is held about half a muzzle off the flesh by its own chest and legs,
## and a grab that cannot cover that could never bite what it is touching.
const GRAB: float = 1.8

## What a lunge may spend of the ground its legs can still catch it on.
##
## The throw is the body moving out over its own feet, so what pays for it is
## how much ground is left to put a foot down on: `Attitude.plan_reach` is how
## far out from a socket a leg reaches, and `Travel.review` calls the body
## falling once its weight hangs past `Travel.FALL_SHARE` of that. A strike is
## allowed this much of the same ground — under the review's own line, because
## a lunge that spent the whole catch would have nothing left to stop with, and
## the recovery is as much a part of a strike as the throw.
##
## Deliberately a share of a *stance* rather than of `Poise.clearance`, which is
## what this used to read. Clearance is an instant — how far the weight is from
## the edge of the polygon its planted toes make right now — and that polygon
## collapses to a line every time the gait has two feet off the ground, which is
## most of a walk. Read raw it made the throw, and every marker drawn off it,
## swing better than two to one at the stride's own frequency while nothing about
## the animal's ability to lunge had changed at all. What a body can throw is a
## property of the stance it is in; where its weight happens to be inside that
## stance this millisecond is `_hanging` below, and it is only ever a deduction.
const THROW_CATCH: float = 0.75

## Over how long the weight's hanging is worth reading, seconds.
##
## The deduction is real — a body already out past its feet has that much less
## catch left to spend — but it is spent by a strike that takes THROW_TIME to
## throw and RECOVER_TIME to come back, so what it is priced against is the
## ground the legs have been giving up over about that long, not the pixel they
## are short in this frame. A genuinely teetering body stays out for longer than
## the window and throws short; a walking one passes through and does not.
const GATHER: float = 0.45

## The most body a lunge may be, as a share of the trunk.
const THROW_SHARE: float = 0.45

## How far up its own arm the neck can be re-carried, as a share of arm
## length above the withers. Down is the floor; up is this.
const RISE_SHARE: float = 0.85

## The tether: slack the hold allows before it tows, and the stretch past
## which the flesh gives out and the mouth comes away with what it holds.
const SLACK_SHARE: float = 0.6
const TEAR_SHARE: float = 2.2
## How much of the tether's overshoot is corrected per tick — meat, not rope.
const TOW: float = 0.35

## The frontal cone a strike must address its target inside, radians off the
## heading. A mouth does not bite what is behind the animal wearing it.
##
## One half of the window (see `window`) and never read on its own: the other
## half is the neck's, and which of the two binds depends on the animal and on
## how far its heading has run ahead of its own back.
const ADDRESS_CONE: float = 1.75


var creature: Creature2
var fangs: Fangs

var state: int = IDLE
var _timer: float = 0.0
## The committed strike: who, and the point the jaws are being taken to —
## re-aimed at the target's actual flesh every tick of the throw, because a
## moving target is met where it is, not where it was when the strike was
## asked for. What is fixed at the commit is the *budget*: `_throw` px of
## body, of which `_thrown` is already spent.
var _target: Creature2 = null
var _at: Vector3 = Vector3.ZERO
var _throw: float = 0.0
var _thrown: float = 0.0
var _latch: bool = false

## The hold: a body address on the target, or empty. The address never moves;
## the target's pose is what carries it about the world.
var holding: Dictionary = {}
var _chew: float = 0.0

## What has gone down the throat, census mass units — the feeding readout.
var belly: float = 0.0

## How far past its own feet this body has been carrying its weight lately, px
## — `Poise.overhang` over `GATHER` rather than in the instant. The only thing
## between the stance's catch and what a strike may spend of it.
var _hanging: float = 0.0


func build(p_creature: Creature2) -> void:
	creature = p_creature
	fangs = Fangs.grow(creature.body)
	release()
	state = IDLE
	_timer = 0.0
	belly = 0.0
	# Seeded, not started from nothing: a body is built square on its feet and
	# has the throw that stance pays for from its first tick, or the first half
	# second of every life would be spent unable to lunge.
	_hanging = _spilling()


# ------------------------------------------------------------------- reach ----

## Where the mouth is: the head node, in all three dimensions. The one point
## the targeting, the movement, the contact test and the damage all quote.
func jaw_point() -> Vector3:
	return creature.armature.pos[creature.armature.head_index()]


## The muzzle's two radii — the tooth arc's forward reach and its width at the
## corners, off the skull the census wrapped.
func muzzle_reach() -> float:
	return creature.body.skull_radius * 1.1


func muzzle_width() -> float:
	return creature.body.skull_radius * 0.8


## Where the purse is centred: the withers, on the plan.
##
## Not the mouth. The neck is an arc rooted at the shoulders, so the shoulders
## are the one point every part of the reach is measured from — the radius
## (`plan_reach`), the bearing (`window`) and the height band all quote it, and
## anchoring any of them at the head instead would make the zone shrink, swell
## and swing as the animal glanced about.
func purse_root() -> Vector2:
	var a: Armature = creature.armature
	return a.plan(a.withers_index())


## The angular window a bite can be addressed inside: two absolute bearings, the
## clockwise edge in `x` and the anticlockwise one in `y`, unwrapped so the pair
## draws and clamps without further arithmetic.
##
## The **intersection** of two independent limits, and it has to be an
## intersection because either one alone is a lie about the animal:
##
##   * **the neck's own field.** The jaws are on the end of a neck, and a mouth
##     cannot be brought to bear where the neck cannot carry the head — the
##     cervical joints' own sum, under the look's cap, which is exactly the field
##     `Gaze` gives the cursor (`Gaze.radius`). Centred on the shoulders' own
##     forward, because that is the joint the sweep is measured from; a
##     short-necked animal has a narrow bite window for the same reason it has a
##     narrow field of view, and nobody had to write down that it does.
##   * **the frontal cone.** `ADDRESS_CONE` off the heading. A mouth does not
##     bite what is behind the animal wearing it, however far round the neck has
##     turned.
##
## Which of the two binds is not fixed. On the reference cat the neck is the
## tighter of them by some eighteen degrees a side, so most of what this returns
## is anatomy; but the heading is an integral that can run ahead of the back it
## describes, and when it does the cone swings off-centre and clips one side of
## the field while leaving the other alone. The window is asymmetric then, and
## honestly so — the animal really can reach further round the inside of its own
## turn than the outside of it.
##
## The one authority on the question. `aim` refuses on it, `strike` redirects a
## snap thrown outside it, `Quarry` drops a target that leaves it and `AimMark`
## draws it: a target the player is shown inside the arc is reachable because
## the reach test and the arc are the same two numbers.
func window() -> Vector2:
	var a: Armature = creature.armature
	var datum: float = a.fwd[a.withers_index()].angle()
	var neck: float = creature.gaze.radius() if creature.gaze != null \
		else minf(Gaze.MAX_ANGLE, a.neck_sweep())
	# Both limits carried into the shoulders' frame, where the neck's is centred.
	var off: float = wrapf(creature.heading - datum, -PI, PI)
	var lo: float = maxf(-neck, off - ADDRESS_CONE)
	var hi: float = minf(neck, off + ADDRESS_CONE)
	if lo > hi:
		# The two do not overlap at all — a stiff-necked body whose heading has
		# run right round off its own back. There is no region, and the honest
		# answer is the single bearing nearest both: the animal can bite straight
		# where its neck will let it point, and nowhere else.
		var only: float = clampf(off, -neck, neck)
		lo = only
		hi = only
	return Vector2(datum + lo, datum + hi)


## Whether a bearing — measured from `purse_root`, like everything else about the
## reach — is one these jaws can be brought round onto.
func addressable(bearing: float) -> bool:
	var w: Vector2 = window()
	return absf(wrapf(bearing - (w.x + w.y) * 0.5, -PI, PI)) \
		<= (w.y - w.x) * 0.5 + 0.0001


## Whether a strike from here can meet flesh at `at` on `target`, and what it
## would meet — the preview, free of commitment, re-askable every tick.
##
## Verticals gate before horizontals: a contact the neck cannot be carried to
## is refused before any distance is measured, so a short animal pointed at a
## tall back never chases it. Then the bearing, against `window` — what the neck
## can carry the head round onto, inside the cone a body can face. Then the
## purse: the gap is measured through 3D from the withers, against the arm plus
## the throw the support can deliver plus the grab of the gape — one circle, so
## height spent is distance lost.
##
## Three refusals and one region: `window` gives the arc's two edges and
## `plan_reach` its radius, which between them are the whole of what `AimMark`
## draws. Nothing here is a second opinion about reach.
func aim(target: Creature2, at: Vector2) -> Dictionary:
	var out: Dictionary = {"ok": false, "why": "nothing"}
	if target == null or target == creature or target.contour == null:
		return out
	var jaw: Vector3 = jaw_point()
	var contact: Dictionary = target.contour.locate(Vector3(at.x, at.y, jaw.z))
	if contact.is_empty():
		return out
	var flesh: Vector3 = contact["at"]
	out["contact"] = contact

	# The verticals. The mouth can be carried down to the floor and up a share
	# of its own arm above the withers — outside that band the flesh is simply
	# not addressable, however close it stands on the plan.
	var a: Armature = creature.armature
	var withers: Vector3 = a.pos[a.withers_index()]
	if not carriable(flesh.z):
		out["why"] = "height"
		return out

	# The address: a strike faces what it bites, and it can only face it as far
	# round as the neck goes. Measured from the shoulders the neck is rooted on
	# rather than from the mouth, because that is where the window is centred and
	# where its radius is measured — so the region this refuses on and the region
	# the mark draws are one shape, not two that have to be kept in step. From the
	# mouth it would be neither: the head is already craned somewhere, and the
	# bearing off a swung jaw says nothing about what the neck has left.
	var toward: Vector2 = Vector2(flesh.x - withers.x, flesh.y - withers.y)
	if toward.length() > 0.5 and not addressable(toward.angle()):
		out["why"] = "behind"
		return out

	# The purse: the neck is an arc rooted at the withers, so height and
	# distance are one radius — the same horizontal gap that connects at
	# mouth height is refused onto the floor, because the floor is further
	# through 3D from the shoulder the arm pivots on.
	var gap: float = withers.distance_to(flesh)
	out["gap"] = gap
	out["arm"] = arm()
	if gap > reach():
		out["why"] = "far"
		return out

	out["ok"] = true
	return out


## The most lunge the body has in it right now: the ground its legs can still
## catch it on, less what its weight is already hanging out over. Measured,
## never authored — a crouched, square body throws far and a teetering one
## hardly at all.
func throw_cap() -> float:
	return clampf(catch() * THROW_CATCH - _hanging, 0.0,
		creature.body.trunk_length * THROW_SHARE)


## How far out from its sockets this body can put a foot down, px — the stance's
## own plan reach, and the same number `Travel.review` measures a fall against.
## A property of the posture and the leg, so it holds still while the animal
## walks: it is what makes the purse a shape a player can learn.
func catch() -> float:
	return creature.attitude.active.plan_reach(creature.body.hind_leg_length)


## How far the weight is out past the planted feet this instant. Read once a
## tick into `_hanging` and nowhere else, so the budget a marker is drawn from
## and the budget a strike is granted are one number.
##
## A body with nothing planted at all is hanging over everything — there is no
## catch left when there is no leg down to catch with.
func _spilling() -> float:
	var p: Poise = creature.poise
	if p == null or not p.posed or creature.armature.collapsed:
		return 0.0
	return catch() if p.feet <= 0 else p.overhang.length()


## The same purse read the other way round: how far out *on the plan* this mouth
## can be brought to bear on something standing at height `z`.
##
## One number and one arithmetic, so a marker drawn at this distance is a
## marker the strike then agrees to go to. Height spent is distance lost,
## because the neck is an arc rooted at the withers and this is that arc's
## radius with the vertical taken out of it — which is why the same gap that
## connects at mouth level is refused onto the floor.
##
## Zero outside the band the mouth can be carried through at all, so the arc a
## player is shown does not promise ground at a height the jaws are refused for
## being at. The two gates are separate facts about a neck — how far round it
## goes and how far up and down — and a plan view can only draw the one, so the
## other is folded into the radius rather than left silently out of the picture.
func plan_reach(z: float) -> float:
	var a: Armature = creature.armature
	var withers: Vector3 = a.pos[a.withers_index()]
	if not carriable(z):
		return 0.0
	var rise: float = z - withers.z
	var radius: float = reach()
	return sqrt(maxf(radius * radius - rise * rise, 0.0))


## The neck and the head hung off it — how far this mouth reaches with no lunge
## in it at all, and the length the vertical band is a share of.
func arm() -> float:
	return creature.body.neck_length + creature.body.head_offset


## Whether the mouth can be carried to a height at all: down to the floor and up
## a share of its own arm above the withers. The vertical half of the reach, and
## the one part of it a plan view cannot draw.
func carriable(z: float) -> bool:
	var a: Armature = creature.armature
	return z <= a.pos[a.withers_index()].z + arm() * RISE_SHARE \
		and z >= a.fall.floor_height - 1.0


## The purse's radius through 3D, before the height is taken out of it — the
## whole of what a bite can span from the shoulder it pivots on.
##
## Three terms, and each of them is a thing the animal has rather than a number
## somebody picked: the **arm** it already reaches with (the neck and the head
## hung off it), the **lunge** its stance can still pay for (`throw_cap`, the
## ground its legs can catch it on less what its weight is already hanging over),
## and the **gape** — how far past the tooth arc flesh may sit and the closing
## still find it.
func reach() -> float:
	return arm() + throw_cap() + muzzle_reach() * GRAB


## Whether the jaws are shut on anything at all.
func latched() -> bool:
	return not holding.is_empty()


## Whether a strike is playing, at any phase — the lunge in flight or the
## recovery after it.
func lunging() -> bool:
	return state != IDLE


# ------------------------------------------------------------------ commit ----

## Commits a strike: the aim's answer, taken. Returns whether the body goes.
##
## Never refused for being out of reach, and that is v1's deliberate reversal.
## The body used to decline the strike outright when the target was above it,
## below it or too far — the correct *fact* delivered as the wrong *behaviour*,
## because a click that does nothing at all is indistinguishable from a click
## the game did not receive, and an animal that has misjudged a lunge is a thing
## that happens. So the strike is always thrown, and what it then meets is
## decided where it has always been decided: in the world, by the jaws arriving
## somewhere and there being something in them or not.
##
## `target` may be null, and then this is a snap at whatever is at `at` — the
## floor, the air, or a body that walks into it before the jaws shut. The
## refusals `aim` gives are not wasted for that: they are what the mark draws
## hollow and what the readout says, so "you cannot get to that" is said before
## the button rather than by swallowing it.
func strike(target: Creature2, at: Vector2, latch: bool = false) -> bool:
	if state != IDLE or creature.armature.collapsed or not holding.is_empty():
		return false
	var jaw: Vector3 = jaw_point()
	var seen: Dictionary = aim(target, at)
	var cap: float = throw_cap()
	var reached: bool = target != null and bool(seen.get("ok", false))
	if reached:
		var contact: Dictionary = seen["contact"]
		_target = target
		_at = contact["at"]
		# The body covers what the arm cannot: gap from the withers, less the
		# neck-and-head already reaching along it. A contact inside the arm asks
		# for almost no body at all — the carry alone takes the mouth there — but
		# never for none: floored at a twelfth of what this animal could throw,
		# so even a bite taken point-blank reads as a strike rather than as the
		# jaws opening and shutting where they already were.
		_throw = clampf(float(seen["gap"]) - float(seen["arm"]), cap / 12.0, cap)
	else:
		# At air, the whole of what this body can throw itself, aimed at the
		# point rather than past it — and floored at a twelfth of it, so even a
		# point-blank snap reads as a strike rather than as a twitch.
		#
		# Unless the point is somewhere these jaws could never have been brought
		# round onto, and then the lunge goes where the head is already pointing
		# instead. A click outside the window is not a refusal — a body that has
		# committed to a strike goes — but neither is it an instruction the neck
		# can carry out, and throwing the animal sideways at something it is not
		# facing would land the jaws somewhere the head never went. Where the mouth
		# points is where the bite goes, which is also the one place the player can
		# see it is going, because the head is drawn.
		_target = null
		var toward := Vector2(at.x - jaw.x, at.y - jaw.y)
		if toward.length() > 0.5 \
				and not addressable((at - purse_root()).angle()):
			toward = creature.armature.fwd[creature.armature.head_index()] \
				* toward.length()
		_at = Vector3(jaw.x + toward.x, jaw.y + toward.y, jaw.z)
		_throw = clampf(toward.length(), cap / 12.0, cap)
	_latch = latch
	_thrown = 0.0
	state = THROW
	_timer = 0.0
	return true


## One tick of whatever the mouth is doing. Runs inside the loop, after the
## world's solids and before the feet answer — a lunge is a positional change
## exactly as a wall's push is, and the support drift it opens is how the legs
## learn the body moved.
func tick(delta: float) -> void:
	# The footing first, and unconditionally: what the body can throw is a
	# property of how it has been standing, not of what its jaws happen to be
	# doing, and a mouth that only re-read it between strikes would price the
	# next one off the last one's stance.
	_hanging = lerpf(_hanging, _spilling(), 1.0 - exp(-delta / GATHER))
	if creature.armature.collapsed:
		release()
		state = IDLE
		creature.armature.head_reach_z = NAN
		return
	match state:
		THROW:
			_tick_throw(delta)
		RECOVER:
			_timer += delta
			creature.armature.head_reach_z = NAN
			if _timer >= RECOVER_TIME:
				state = IDLE
		_:
			if not holding.is_empty():
				_tick_hold(delta)


# ---------------------------------------------------------------- the throw ----

## The body moves. A rigid shift of the whole armature toward the flesh, at
## the throw's own tempo, with the head carried to the contact's height — and
## nothing else: no velocity is written, so what the lunge costs the balance
## is real and the review sees it.
func _tick_throw(delta: float) -> void:
	var a: Armature = creature.armature
	var jaw: Vector3 = jaw_point()
	# The strike is re-aimed every tick at where the flesh actually is — a
	# target that walks, turns, or is shoved along by the arriving body
	# itself is met where it is. The commit fixed the *budget*, not the spot.
	var arrived: bool = false
	if _target != null and _target.contour != null:
		var fresh: Dictionary = _target.contour.locate(jaw)
		if not fresh.is_empty():
			_at = fresh["at"]
			# The jaws close early the moment the teeth are genuinely on the
			# flesh — a bite is over when it connects. Short of that the
			# throw runs its course, and the final closing takes whatever
			# stands inside the gape's grab.
			arrived = float(fresh["depth"]) >= -muzzle_reach()
	var toward := Vector2(_at.x - jaw.x, _at.y - jaw.y)
	var step: float = minf(_throw * delta / THROW_TIME,
		minf(_throw - _thrown, toward.length()))
	if not arrived and step > 0.001 and toward.length() > 0.001:
		var push: Vector2 = toward.normalized() * step
		a.shift(push)
		creature.head_pos += push
		_thrown += step
	a.head_reach_z = _at.z
	_timer += delta
	if arrived or _timer >= THROW_TIME:
		_close()
		_timer = 0.0
		if holding.is_empty():
			state = RECOVER
		else:
			state = IDLE


## The jaws close — on wherever the target's flesh actually is now, not where
## it was when the strike was asked for. Each tooth is its own 3D contact:
## placed on the arc at the jaw's height, located on the target's posed rings,
## and driven its own depth into whatever column it landed on, less whatever
## air stood between its patch and the surface. Teeth that arrive over nothing
## bite nothing.
func _close() -> void:
	var target: Creature2 = _target
	_target = null
	var jaw: Vector3 = jaw_point()
	var mouth: Dictionary = {}
	if target != null and target.contour != null:
		mouth = target.contour.locate(jaw)
		if mouth.is_empty() or float(mouth["depth"]) < -muzzle_reach() * GRAB:
			target = null
			mouth = {}
	if target == null:
		# Nothing was committed to, or the strike arrived somewhere other than
		# where it was thrown. Either way the jaws take what is in them — the
		# world decides a bite, not the aim that started it, which is how a snap
		# at the air catches the animal that walked into it and how a lunge that
		# overshot a leg closes on the belly behind it.
		var caught: Dictionary = _in_the_jaws(jaw)
		if caught.is_empty():
			return
		target = caught["who"]
		mouth = caught["mouth"]
	var a: Armature = creature.armature
	var fwd: Vector2 = a.fwd[a.head_index()]
	var depth: float = fangs.close_depth(creature.corpus)
	var was: float = target.corpus.mass()

	for tooth in fangs.teeth:
		var point: Vector3 = fangs.tooth_point(tooth, jaw, fwd,
			muzzle_reach(), muzzle_width())
		var found: Dictionary = target.contour.locate(point)
		if found.is_empty():
			continue
		# A patch short of the surface loses the gap; one already pressed into
		# the flesh spends everything it has.
		var bite: float = fangs.tooth_depth(tooth, depth) \
			+ minf(float(found["depth"]), 0.0)
		if bite <= 0.05:
			continue
		target.vitals.absorb(target.corpus.wound(found["band"],
			found["station"], found["sector"], bite))

	# ...and the jaw bearing down behind the points, over the mouthful itself.
	var crush: float = fangs.crush_depth(depth) + minf(float(mouth["depth"]), 0.0)
	if crush > 0.05:
		target.vitals.absorb(target.corpus.wound(mouth["band"],
			mouth["station"], mouth["sector"], crush))

	_swallow_from(target, was)

	# The latch: the mouth keeps the address it closed on. An address, so the
	# hold follows the flesh through the target's every pose.
	if _latch:
		holding = {
			"target": target, "band": mouth["band"],
			"t": mouth["t"], "theta": mouth["theta"],
		}
		_chew = 0.0


# ----------------------------------------------------------------- the hold ----

## A latched mouth, tick by tick: the head is carried at the flesh, the tether
## tows whichever body is lighter, too far parts the hold through the flesh,
## and the chew re-closes on the same wedge — deeper, because the census got
## thinner under it.
func _tick_hold(delta: float) -> void:
	var target: Creature2 = holding["target"]
	if target == null or target.contour == null:
		release()
		return
	var at: Vector3 = target.contour.place(holding["band"],
		holding["t"], holding["theta"])
	var a: Armature = creature.armature
	a.head_reach_z = at.z
	var jaw: Vector3 = jaw_point()
	var gap := Vector2(at.x - jaw.x, at.y - jaw.y)
	var slack: float = muzzle_reach() * SLACK_SHARE

	if gap.length() > muzzle_reach() * TEAR_SHARE:
		# Torn free: the parting takes flesh, the way leaving with a mouthful
		# does — one more closing's worth, spent on the way out.
		var was: float = target.corpus.mass()
		target.vitals.absorb(target.corpus.wound(holding["band"],
			target.corpus.station_of(holding["band"], holding["t"]),
			target.corpus.sector_of(holding["band"], holding["theta"]),
			fangs.close_depth(creature.corpus) * 0.5))
		_swallow_from(target, was)
		release()
		return

	if gap.length() > slack:
		# The tether: positional, split by weight — an Elephant's head does not
		# follow a Cat's mouthful anywhere, and both of those are this share.
		var over: Vector2 = gap.normalized() * (gap.length() - slack) * TOW
		var mine: float = creature.corpus.mass()
		var theirs: float = target.corpus.mass()
		var share: float = theirs / maxf(mine + theirs, Corpus.MIN_MASS)
		a.shift(over * share)
		creature.head_pos += over * share
		target.armature.shift(-over * (1.0 - share))
		if not target.armature.collapsed:
			target.head_pos -= over * (1.0 - share)

	_chew += delta
	if _chew >= CHEW_TIME:
		_chew = 0.0
		var was: float = target.corpus.mass()
		target.vitals.absorb(target.corpus.wound(holding["band"],
			target.corpus.station_of(holding["band"], holding["t"]),
			target.corpus.sector_of(holding["band"], holding["theta"]),
			fangs.close_depth(creature.corpus)))
		_swallow_from(target, was)
		# The jaws re-seat on what is left — v1's work-in law: the chew has
		# thinned the wedge and its surface has retreated, so the hold walks
		# onto the nearest standing flesh rather than hanging in the hole the
		# last mouthful left. This is also how a long piece is eaten
		# end-first, with nobody deciding to.
		var seat: Dictionary = target.contour.locate(jaw_point())
		if not seat.is_empty():
			holding["band"] = seat["band"]
			holding["t"] = seat["t"]
			holding["theta"] = seat["theta"]


## Whichever body these jaws are deepest into, and where — or nothing at all.
## Scored in the one currency the whole hit test is scored in, so a mouth
## covering two animals closes on the one it is further inside.
func _in_the_jaws(jaw: Vector3) -> Dictionary:
	if creature == null or not creature.is_inside_tree():
		return {}
	var floor_depth: float = -muzzle_reach() * GRAB
	var best: Dictionary = {}
	var deepest: float = floor_depth
	for node in creature.get_tree().get_nodes_in_group("creatures2"):
		var other := node as Creature2
		if other == null or other == creature or other.contour == null:
			continue
		var found: Dictionary = other.contour.locate(jaw)
		if found.is_empty():
			continue
		var depth: float = float(found["depth"])
		if depth < deepest:
			continue
		deepest = depth
		best = {"who": other, "mouth": found}
	return best


## The button, tracked. Held is a grip — jaws that close while it is down keep
## what they closed on — and letting go is letting go, immediately, whether the
## mouth is on flesh or still on its way to it.
## A strike already in flight is left to land: the button coming up costs it its
## latch, never its throw, because a lunge is a movement the animal has already
## committed its weight to and stopping one in mid-air is not something a body
## can do.
func hold(held: bool) -> void:
	_latch = held
	if not held and not holding.is_empty():
		release()


func release() -> void:
	holding.clear()
	_target = null
	_latch = false
	_chew = 0.0


## What a closing took, weighed: the census before against the census after,
## because the census is the one scale. Only a stopped heart is meat — flesh
## torn from a living animal is a wound, not a meal.
func _swallow_from(target: Creature2, mass_before: float) -> void:
	if target.vitals.arrested:
		belly += maxf(mass_before - target.corpus.mass(), 0.0)
