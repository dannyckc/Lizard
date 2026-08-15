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
## Teeth go *in*. Every point this file carries the mouth to is a **seat** — the
## flesh's own surface taken back in along its normal by `standoff`, which is
## what is left over once the tooth patches stand where `Fangs` puts them and a
## closing has driven them their own depth past the skin. So the jaws are never
## parked off a silhouette waiting to touch it: a bite from the side buries the
## muzzle in the flank, a bite from above puts the head down onto the back, and
## both are one arithmetic asked at a different `theta`. The head is carried to
## the seat in all three dimensions (`head_reach_z`) and pointed at it (`Gaze`
## reads `bite_point`), so where the head is and which way it faces are both
## consequences of where the teeth went — there is no bite pose anywhere.
##
## Two things outside this file are part of that and would undo it on their own.
## `Clash` takes the biter's neck and head out of the contact for as long as the
## grip lasts — jaws through skin are not an intrusion, and pressing them back
## out is precisely the hovering this used to draw. And `Creature2` puts the
## animal with the mouthful in front, because a mouth painted behind the flesh it
## is holding is a mouth nobody can see.
##
## The hold is possession with the v1 grip's teeth: a latched mouth keeps a
## *body address*, not a world point, so the flesh it follows through every
## pose of the target is the flesh it closed on. It tows the lighter body, tears
## free past what flesh holds, and a chew re-closes the same jaws on the same
## wedge — which lands deeper every time, because the census got thinner, and
## nobody wrote "work in".
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

## The stretch past which the flesh gives out and the mouth comes away with what
## it holds — as a multiple of how deep the teeth went, which is the change.
##
## It used to be quoted against the muzzle, which said nothing about the grip:
## a mouth is not held on by being a certain width. **A mouth holds as much flesh
## as its teeth are buried in**, so what it can be pulled off is that same depth,
## and a little over. Which makes the whole thing derived — a keen deep-fanged
## bite hangs on where a mouthful of blunt cusps slips out, and nobody had to say
## so — and it makes it read as tension rather than as slippage: the grip below
## closes at `GRIP` per second, so a steady haul settles at exactly the gap that
## rate cannot keep up with, and that residual is how hard the mouthful is being
## pulled on. Walking away from a mouthful stays inside it and holds; sprinting
## away opens half again as much and the flesh gives.
const TEAR_SHARE: float = 1.1

## How long the grip may be overstretched before the flesh actually gives,
## seconds.
##
## A moment rather than an instant, and a long enough one to tell a haul from
## everything else that momentarily stretches a grip.
##
## Two things do, and neither is a body pulling away. A chew *retreats its own
## seat* — the mouth has eaten the flesh it was holding, so the next place to hold
## is further in, or round on the wedge beside it — and for the frames it takes
## the grip to follow its own bite the gap is arithmetically identical to being
## hauled on. And an animal with its jaws in another is in contact with it
## everywhere else too: its legs are pressed off the body it is standing over, the
## grip tows the pair back together, and the two argue at a few tenths of a pixel
## a tick for as long as the hold lasts. Both of those come and go inside a third
## of a second. A body actually walking away does not stop, and that is the whole
## of the distinction.
const STRAIN_PATIENCE: float = 0.30

## How quickly a grip closes what is between the mouth and its seat, per second.
##
## There is no slack any more and that is the change: the hold used to allow the
## mouth half a muzzle of play before it corrected anything, which is a mouth
## resting *near* flesh, and at the sizes involved it was most of the gap the
## bite was supposed to have closed. A grip has no play — what it has is a rate,
## and 16 puts the last pixel away over about four frames, quick enough to read
## as jaws shutting and slow enough that nothing snaps.
const GRIP: float = 16.0

## The most a grip may reel bodies together at, px/s — the cap on the rate
## above, sized at a slow walk: jaws shut across their last pixels exactly as
## before, and a mouthful that moved (a re-seat, a body pressed back) is
## gathered in over a few tenths rather than in one snatch. The strain clock
## still runs while the gap is open, so a mouthful that keeps outrunning the
## reel is torn free exactly as it should be.
const REEL_MAX: float = 45.0

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
## The committed strike: who, the flesh it was thrown at, and where that flesh
## is right now.
##
## `_aimed` is a body address — band, t, theta — exactly as a hold is, and for
## exactly the same reason: it is re-read through the target's live pose every
## tick, so a target that walks, turns, or is shoved along by the arriving body
## itself is met *at the same place on its body*. Following the nearest flesh
## instead is what this used to do and it was a different thing pretending to be
## the same one — a foreleg sprawled between the jaws and the flank it was aimed
## at is nearer than the flank, so a strike at a haunch quietly became a strike
## at a shin and the player was never told. It is empty for a snap at the air,
## and then `_at` is a place rather than an address, which is all a snap ever had.
##
## What is fixed at the commit is the *budget*: `_throw` px of body, of which
## `_thrown` is already spent.
var _target: Creature2 = null
var _aimed: Dictionary = {}
var _at: Vector3 = Vector3.ZERO
var _throw: float = 0.0
var _thrown: float = 0.0
var _latch: bool = false

## The hold: a body address on the target, or empty. The address never moves;
## the target's pose is what carries it about the world.
var holding: Dictionary = {}
var _chew: float = 0.0
## How long the grip has been stretched past what the flesh bears — see
## `STRAIN_PATIENCE`.
var _strain: float = 0.0

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


## How far short of the flesh the jaw point rides once these teeth are seated in
## it, px — the one number that turns "the mouth touched the surface" into "the
## mouth is in the flesh", and the whole of how deep a bite looks.
##
## Derived from the mouth rather than picked: the contact patches stand
## `Fangs.patch_reach` of the muzzle ahead of the head node — that is where
## `tooth_point` puts them, and where the damage is taken — and a closing drives
## them `close_depth` past whatever surface they met. What is left over is where
## the head has to be for both of those to be true at once, so the picture and
## the wound are two readings of one geometry.
##
## Positive is the head node still outside the surface with its muzzle buried in;
## the reference cat's is a little over a pixel, which puts most of a skull inside
## the silhouette and leaves the eyes out of it. A keen, long-toothed mouth on
## soft flesh comes out negative — the head node itself inside the animal — which
## is what a big cat with its face in a haunch actually looks like. Nothing has to
## be told to clip or not to clip; it is one subtraction, and it is the mouth's.
func standoff() -> float:
	return muzzle_reach() * fangs.patch_reach - fangs.close_depth(creature.corpus)


## How far the mouth may be dragged off its seat before the wedge comes out of
## it, px — how deep the teeth are, and a little over. See `TEAR_SHARE`.
func tear_gap() -> float:
	return fangs.close_depth(creature.corpus) * TEAR_SHARE


## The flesh a bite is about to address, as a live contact on the target.
##
## An address is two questions and they have two different answers here.
##
## **Where along the animal** is the player's, and the picture can carry it: the
## cursor picked a station and that station is followed through the target's own
## pose, so the neck, the flank and the haunch are three things a person can mean
## and get.
##
## **Which way round** is the *approach's*, and it has to be, because the picture
## cannot say. Drawn from almost overhead a back and the belly under it land on
## the same pixels — they are separated by height, and height is the axis this
## view collapsed — so a pointer that tried to choose between them would be
## guessing, and it was: aiming at a back picked the belly about as often as not.
## Where the mouth *is* separates them completely and for free. A head level with
## a flank comes in at the flank; the same head carried over the spine — a cat
## standing over a carcass, or on a step, or landing out of a leap — comes down
## onto the back. The player positions the animal and the bite follows from it,
## which is the only honest way round in a view this flat.
##
## With nothing picked at all this is a bare plan coordinate met at the mouth's
## own height, which is all two numbers can say.
func _contact(target: Creature2, at: Vector2, picked: Dictionary) -> Dictionary:
	if picked.is_empty() or not picked.has("band"):
		return target.contour.locate(Vector3(at.x, at.y, jaw_point().z))
	var band: StringName = picked["band"]
	var t: float = picked["t"]
	var theta: float = target.contour.bearing(band, t, jaw_point())
	return {
		"band": band, "t": t, "theta": theta,
		"station": target.corpus.station_of(band, t),
		"sector": target.corpus.sector_of(band, theta),
		"at": target.contour.place(band, t, theta),
		"centre": target.contour.axis(band, t),
	}


## Where a `Contour.locate` answer puts the seat: the surface it found, taken
## back in along the same line the mouth approached it on.
func _seat_found(found: Dictionary) -> Vector3:
	var flesh: Vector3 = found["at"]
	var out: Vector3 = flesh - (found["centre"] as Vector3)
	if out.length_squared() < 0.000001:
		return flesh
	return flesh - out.normalized() * standoff()


## ...and where the standing hold's own address puts it, through the target's
## live pose. The address never moves; the flesh carrying it does.
func _seat_held() -> Vector3:
	var target: Creature2 = holding["target"]
	return target.contour.place(holding["band"], holding["t"], holding["theta"],
		standoff())


## The point the jaws are being taken to, or are shut on — in all three
## dimensions, INF when the mouth is doing neither.
##
## The one thing anything outside this file needs to know about where a bite is:
## `Gaze` points the head at it (which is what makes a side bite face into the
## flank and a top bite face down onto the back), and nothing else reads it.
func bite_point() -> Vector3:
	if not holding.is_empty():
		return _seat_held()
	return _at if state == THROW else Vector3.INF


## Whether these jaws are in `other`, or on their way into it. What `Clash` asks
## before it presses two bodies apart: an animal cannot bite what its own contact
## keeps pushing out of range, and the neck carrying the mouth is inside the other
## body for exactly as long as this is true.
func biting(other: Creature2) -> bool:
	if other == null:
		return false
	if not holding.is_empty():
		return holding["target"] == other
	return state == THROW and _target == other


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
##
## `picked` is the body address the world already resolved the cursor onto, and
## it matters more than it looks. Without one, all a bare plan coordinate can be
## met with is "whatever is at that spot, at the mouth's own height" — which
## throws away the one thing a top bite and a side bite differ by, because from
## overhead a back and the flank beneath it are a couple of pixels apart and both
## answer to the same two numbers. The picture is what separated them
## (`Contour.locate_seen`) and this is the seam that carries the separation
## through to the teeth.
func aim(target: Creature2, at: Vector2, picked: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"ok": false, "why": "nothing"}
	if target == null or target == creature or target.contour == null:
		return out
	var contact: Dictionary = _contact(target, at, picked)
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
func strike(target: Creature2, at: Vector2, latch: bool = false,
		picked: Dictionary = {}) -> bool:
	if state != IDLE or creature.armature.collapsed or not holding.is_empty():
		return false
	var jaw: Vector3 = jaw_point()
	var seen: Dictionary = aim(target, at, picked)
	var cap: float = throw_cap()
	var reached: bool = target != null and bool(seen.get("ok", false))
	if reached:
		var contact: Dictionary = seen["contact"]
		_target = target
		# The flesh, as an address, so the throw goes where it was thrown and
		# nowhere else — see `_aimed`.
		_aimed = {"band": contact["band"], "t": contact["t"],
			"theta": contact["theta"]}
		# Where the mouth is going is the seat, not the surface: the strike is
		# aimed at where the teeth will be once they are in, so the throw has the
		# depth of the bite in it from the first tick rather than stopping at the
		# skin and leaving the last pixels to something else.
		_at = _seat_found(contact)
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
		_aimed = {}
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
	# The strike is re-aimed every tick at where the aimed flesh has got to — a
	# target that walks, turns, or is shoved along by the arriving body itself is
	# met where it is. The commit fixed the *budget* and the *address*, not the
	# spot; see `_aimed`.
	var arrived: bool = false
	if _target != null and _target.contour != null:
		var band: StringName = _aimed.get("band", &"")
		if not _aimed.is_empty():
			# The aimed flesh, followed through the target's own pose — the
			# address is the strike's whole memory of what it is biting.
			_at = _target.contour.place(band, _aimed["t"], _aimed["theta"],
				standoff())
		var fresh: Dictionary = _target.contour.locate(jaw, band)
		if not fresh.is_empty():
			if _aimed.is_empty():
				_at = _seat_found(fresh)
			# The jaws close the moment the mouth reaches its seat — the teeth
			# are in, and that is what a bite connecting is. This used to be a
			# whole muzzle short of the flesh, which parked the head a skull's
			# width off the animal and is the entire reason a bite read as a
			# nose touching a silhouette. Short of the seat the throw runs its
			# course, and the final closing takes whatever stands inside the
			# gape's grab.
			arrived = float(fresh["depth"]) >= -standoff()
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
	var want: Dictionary = _aimed
	var aimed: StringName = want.get("band", &"")
	_target = null
	_aimed = {}
	var jaw: Vector3 = jaw_point()
	var mouth: Dictionary = {}
	if target != null and target.contour != null:
		# Asked of the part that was aimed at, so the mouthful is the flesh the
		# throw went to. Where the jaws did not get there, `aimed` is simply not
		# what they are in and the fall-through below takes whatever is.
		mouth = target.contour.locate(jaw, aimed)
		if mouth.is_empty() or float(mouth["depth"]) < -muzzle_reach() * GRAB:
			target = null
			mouth = {}
		elif not want.is_empty():
			# ...and the mouthful is the flesh the strike was committed to, since
			# the jaws did close on that part of that body. Not whichever bit of
			# it the head has ended up nearest: the throw is capped by what the
			# legs can catch, so a mouth is routinely still short of its seat when
			# it shuts, and a bearing taken from out there says "from the side"
			# about every bite there is — including the one taken standing over a
			# carcass. Which way round the jaws came in was settled when the
			# strike was aimed (`_contact`), by the approach, which is the only
			# thing that can settle it. Only the *depth* stays measured where the
			# teeth actually are, because that is a fact about this closing.
			mouth["t"] = want["t"]
			mouth["theta"] = want["theta"]
			mouth["station"] = target.corpus.station_of(aimed, want["t"])
			mouth["sector"] = target.corpus.sector_of(aimed, want["theta"])
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

## A latched mouth, tick by tick: the mouth is kept on its seat inside the flesh,
## whichever body is lighter gives way, too far parts the hold through the flesh,
## and the chew re-closes on the same wedge — deeper, because the census got
## thinner under it.
func _tick_hold(delta: float) -> void:
	var target: Creature2 = holding["target"]
	if target == null or target.contour == null:
		release()
		return
	var at: Vector3 = _seat_held()
	var a: Armature = creature.armature
	a.head_reach_z = at.z
	var jaw: Vector3 = jaw_point()
	var gap := Vector2(at.x - jaw.x, at.y - jaw.y)

	_strain = _strain + delta if gap.length() > tear_gap() else 0.0
	if _strain >= STRAIN_PATIENCE:
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

	# The grip, and it is a *placement* rather than a pull. The head is the
	# chain's one driven point (`Armature.take_head`), so putting the mouth's
	# anchor on the seat is the whole of holding on: the neck folds to bridge
	# whatever it can reach and the body is towed after whatever it cannot,
	# through the solve that was already there — no second tether, and the
	# anatomy is never violated for a frame, because nothing moves a node behind
	# the solver's back. Split by weight, because which of the two bodies closes
	# the gap is a question about mass and nothing else: an Elephant's flank does
	# not come to a Cat's mouth, and the Cat is dragged instead.
	#
	# Eased rather than set, so a hold taken at the far end of a throw shuts the
	# last of the way over a few frames instead of snapping.
	var mine: float = creature.corpus.mass()
	var theirs: float = target.corpus.mass()
	var share: float = theirs / maxf(mine + theirs, Corpus.MIN_MASS)
	# The rate, and a ceiling on it. The exponential alone closes a share of
	# *any* gap per tick, which on the last pixel is the intended jaws-shutting
	# and on a re-seated mouthful (`_work_in` sliding to standing flesh) was a
	# quarter of the jump in one frame — two bodies yanked at speeds no neck
	# reels at, hard enough to panic the contact seam between them. A neck
	# folds at a finite rate; the reel is capped at one.
	var close: Vector2 = (gap * (1.0 - exp(-GRIP * delta))) \
		.limit_length(REEL_MAX * delta)
	creature.head_pos += close * share
	target.armature.shift(-close * (1.0 - share))
	if not target.armature.collapsed:
		target.head_pos -= close * (1.0 - share)

	_chew += delta
	if _chew >= CHEW_TIME:
		_chew = 0.0
		var was: float = target.corpus.mass()
		target.vitals.absorb(target.corpus.wound(holding["band"],
			target.corpus.station_of(holding["band"], holding["t"]),
			target.corpus.sector_of(holding["band"], holding["theta"]),
			fangs.close_depth(creature.corpus)))
		_swallow_from(target, was)
		# ...and the jaws re-seat on what is left — v1's work-in law: the chew has
		# thinned the wedge, so the next closing goes deeper into the same hole
		# until there is no hole left to go into, and then the mouth slides onto
		# the standing flesh beside it. See `_work_in`.
		holding["theta"] = _work_in(target)


## The chew's re-seat — v1's work-in law, said in the one currency that can say
## it: the census.
##
## A closing thins the wedge under the teeth and the next one goes deeper into the
## same hole, which is what makes a long piece get eaten end-first with nobody
## deciding to. That holds right up to the moment the wedge is *gone* — chewed
## down to its bone core, with nothing left for a tooth to take — and then the
## mouth has to move or it spends the rest of the meal closing on a hollow. It
## slides to the proudest flesh still standing within its own gape, which is the
## neighbouring wedge, and starts again there.
##
## Asked of the cells rather than of the geometry, because it is a question about
## what is *left* and only the census knows that. `Contour.locate` cannot answer
## it at all — it reports the surface in whatever direction you ask from, so a
## mouth sitting in the hollow it ate is told, quite correctly, that the nearest
## surface is the hollow.
func _work_in(target: Creature2) -> float:
	var band: StringName = holding["band"]
	var here: float = holding["theta"]
	var b: Contour.Band = target.contour.band(band)
	if b == null:
		return here
	var corpus: Corpus = target.corpus
	var station: int = corpus.station_of(band, holding["t"])
	var at: int = corpus.sector_of(band, here)
	# Still something to bite: stay, and work in.
	if corpus.surface_radius(band, station, at) \
			> corpus.layer_radius(band, station, at, 1) + 0.01:
		return here
	# Spent: the standing flesh within the gape, proudest first.
	var span: int = maxi(int(round(fangs.span / TAU * float(b.sectors))), 1)
	var best: int = at
	var proudest: float = -INF
	for step in range(-span, span + 1):
		var s: int = posmod(at + step, b.sectors)
		var r: float = corpus.surface_radius(band, station, s) \
			- corpus.layer_radius(band, station, s, 1)
		if r > proudest:
			proudest = r
			best = s
	return wrapf(atan2(b.sines[best], b.cosines[best]), 0.0, TAU)


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
	_aimed = {}
	_latch = false
	_chew = 0.0
	_strain = 0.0


## What a closing took, weighed: the census before against the census after,
## because the census is the one scale. Only a stopped heart is meat — flesh
## torn from a living animal is a wound, not a meal.
func _swallow_from(target: Creature2, mass_before: float) -> void:
	if target.vitals.arrested:
		belly += maxf(mass_before - target.corpus.mass(), 0.0)
