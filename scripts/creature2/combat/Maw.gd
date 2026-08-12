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

## What the support is worth as throw: px of lunge per px of the plumb line's
## clearance inside the feet. A body already out over its edge throws short —
## the lunge is the body moving, and a body that cannot move cannot lunge.
const THROW_SUPPORT: float = 2.5
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


func build(p_creature: Creature2) -> void:
	creature = p_creature
	fangs = Fangs.grow(creature.body)
	release()
	state = IDLE
	_timer = 0.0
	belly = 0.0


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


## Whether a strike from here can meet flesh at `at` on `target`, and what it
## would meet — the preview, free of commitment, re-askable every tick.
##
## Verticals gate before horizontals: a contact the neck cannot be carried to
## is refused before any distance is measured, so a short animal pointed at a
## tall back never chases it. Then the purse: the gap is measured through 3D
## from the resting jaw, against the throw the support can deliver plus the
## grab of the gape — one circle, so height spent is distance lost.
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
	var withers_z: float = a.pos[a.withers_index()].z
	var arm: float = creature.body.neck_length + creature.body.head_offset
	var floor_z: float = a.fall.floor_height
	if flesh.z > withers_z + arm * RISE_SHARE or flesh.z < floor_z - 1.0:
		out["why"] = "height"
		return out

	# The address: a strike faces what it bites.
	var toward: Vector2 = Vector2(flesh.x - jaw.x, flesh.y - jaw.y)
	if toward.length() > 0.5 and absf(wrapf(toward.angle() - creature.heading,
			-PI, PI)) > ADDRESS_CONE:
		out["why"] = "behind"
		return out

	# The purse: the neck is an arc rooted at the withers, so height and
	# distance are one radius — the same horizontal gap that connects at
	# mouth height is refused onto the floor, because the floor is further
	# through 3D from the shoulder the arm pivots on.
	var withers: Vector3 = a.pos[a.withers_index()]
	var gap: float = withers.distance_to(flesh)
	var reach_px: float = arm + throw_cap() + muzzle_reach() * GRAB
	out["gap"] = gap
	out["arm"] = arm
	if gap > reach_px:
		out["why"] = "far"
		return out

	out["ok"] = true
	return out


## The most lunge the body has in it right now: the support's clearance,
## spent as throw. Measured, never authored — a crouched, square body throws
## far and a teetering one hardly at all.
func throw_cap() -> float:
	var p: Poise = creature.poise
	var footing: float = maxf(p.clearance, 0.0) if p.posed and p.feet > 0 else 0.0
	return minf(footing * THROW_SUPPORT, creature.body.trunk_length * THROW_SHARE)


## The same purse read the other way round: how far out *on the plan* this mouth
## can be brought to bear on something standing at height `z`.
##
## One number and one arithmetic, so a marker drawn at this distance is a
## marker the strike then agrees to go to. Height spent is distance lost,
## because the neck is an arc rooted at the withers and this is that arc's
## radius with the vertical taken out of it — which is why the same gap that
## connects at mouth level is refused onto the floor.
func plan_reach(z: float) -> float:
	var a: Armature = creature.armature
	var withers: Vector3 = a.pos[a.withers_index()]
	var arm: float = creature.body.neck_length + creature.body.head_offset
	var radius: float = arm + throw_cap() + muzzle_reach() * GRAB
	var rise: float = z - withers.z
	return sqrt(maxf(radius * radius - rise * rise, 0.0))


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
		_target = null
		_at = Vector3(at.x, at.y, jaw.z)
		_throw = clampf(Vector2(at.x - jaw.x, at.y - jaw.y).length(), cap / 12.0, cap)
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
