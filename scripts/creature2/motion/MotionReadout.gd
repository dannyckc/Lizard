## The locomotion loop, written down — what `Travel` decided this tick, and what
## it has been deciding for the last few seconds.
##
## The whole of the seam between the mover and anything watching it (the physics
## HUD, `tests/MotionHudProbe.gd`). One object, assembled in one place, for the
## reason every other publication in v2 has one owner: a panel that read a drift
## off `Footwork`, a heel off `Keel`, a margin off `Poise` and a ceiling off
## `Impetus` would be holding four opinions about one body, and the first of them
## to fall a tick behind would look like a bug in the mover rather than in the
## panel. Nothing here decides anything, nothing here smooths anything, and every
## field is a copy of a number its own system had already worked out.
##
## Two halves:
##
##   * **this tick** — the loop's stages as they stand, plus one `Step` per foot
##     carrying what `Footwork` measured and what `Rhythm` granted. A reader
##     draws these directly.
##   * **the last few seconds** — a fixed ring of samples, written on the physics
##     tick, which is the only clock a footfall happens on. The timeline is drawn
##     straight off it and the eight *tells* are reductions of it. It is sized
##     once, when something starts watching, and nothing is allocated per tick.
##
## Geometry is deliberately **not** here. The body's shape is `Armature`'s and a
## reader projects the posed nodes itself (three views are three projections of
## the one armature); copying the chain into this file would be exactly the second
## skeleton the design forbids.
class_name MotionReadout
extends RefCounted

## The timeline's span, seconds — the window a stride pattern reads in.
const WINDOW: float = 4.5
## Samples kept. A shade over the window at 60 Hz, so the oldest sample on screen
## is always a real one rather than the buffer running out.
const TICKS: int = 300

## Landings remembered per foot, for the stride and beat tells. Twelve is three
## or four cycles of anything — enough for a spread to mean something, short
## enough that it is *this* gait rather than the last one.
const LANDINGS: int = 12

## How close to its own limit a joint counts as clamped, radians.
const AT_CAP: float = 0.05

## The bob and sway tells read the last stride or two rather than the whole
## window: a peak-to-peak over five seconds of walking is a fact about the
## terrain, not about the gait.
const TELL_WINDOW: float = 1.2

## Below this the animal is not travelling and the travel tells are mute — a
## standing body must not read as a broken one, px/s.
const TRAVELLING: float = 20.0
## ...and below this it is not turning, so the spine's lead through a turn has
## nothing to be measured, rad/s.
const TURNING: float = 0.25
## Delivery is only a ratio while something is being demanded, px/s².
const DEMANDING: float = 12.0

## What a foot was doing in a sample, in the order a timeline stacks them.
enum { PLANTED, SWINGING, RESCUING, DESPERATE }


## One foot, as the loop last left it — `Footwork`'s measurement and `Rhythm`'s
## answer, copied.
class Step extends RefCounted:
	var name: StringName
	var fore: bool = true
	var swinging: bool = false
	## Where it stands (or last stood), world, and where its body now wants it.
	var anchor: Vector3 = Vector3.ZERO
	var home: Vector2 = Vector2.ZERO
	## Home less anchor — the support the body's own motion has used up.
	var drift: Vector2 = Vector2.ZERO
	## That drift in trigger units: 1.0 is a request to step, `Rhythm.DESPERATE`
	## is a request nothing may deny.
	var urgency: float = 0.0
	var torn: bool = false
	var rescuing: bool = false
	## The swing: where it left, where it is aimed, and how far through it is.
	var lift: Vector3 = Vector3.ZERO
	var land: Vector3 = Vector3.ZERO
	var swing: float = 0.0
	var swing_time: float = 0.2
	var since: float = 0.0
	## The socket it hangs off and the disc it may be placed in.
	var socket: Vector3 = Vector3.ZERO
	var excursion: float = 10.0

	## How far through its arc a swinging foot is, 0..1.
	func through() -> float:
		return clampf(swing / maxf(swing_time, 0.0001), 0.0, 1.0)

	## What this foot is, as a timeline row draws it.
	func mark() -> int:
		if not swinging:
			return DESPERATE if torn or urgency >= Rhythm.DESPERATE else PLANTED
		return RESCUING if rescuing else SWINGING


# --------------------------------------------------------------- the switch ----

## Whether anything is watching. Nothing is recorded, and nothing is allocated,
## until something sets this — the loop pays for the HUD only while it is open.
var watching: bool = false

# ------------------------------------------------------------- the intent ----

## What was asked of the legs, px/s, and what the body is actually doing.
var ask: float = 0.0
var speed: float = 0.0
var pace: float = 0.0
var ang_vel: float = 0.0

# ------------------------------------------------------------ the delivery ----

## The middle of the loop: what the velocity error demanded, what the feet
## delivered, and what they could have delivered at most — all px/s².
var demand: float = 0.0
var delivered: float = 0.0
var ceiling: float = 0.0
## The same two as directions, because where the body was asked to go and where
## it was actually pushed are not always the same way round — a braking animal
## demands backwards along its own travel.
var demanded: Vector2 = Vector2.ZERO
## The two multipliers under that ceiling: the census's engine and the press the
## planted feet have left.
var power: float = 1.0
var grip: float = 0.0
var lean: Vector2 = Vector2.ZERO
var thrust: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------- the feet ----

var steps: Array[Step] = []
var feet_down: int = 0
## How many feet `Rhythm` will seat at this pace, and how much of a trotter the
## body is.
var seats: int = 1
var coupling: float = 0.0

# --------------------------------------------------------------- the weight ----

## `Poise`, copied: where the weight comes down, how high it hangs, how far
## inside its own support it is (negative is out over the edge), and the support
## itself — the planted prints, in the order the hull walks them.
##
## The plan and the height are two fields rather than one Vector3 for the reason
## `Poise` keeps them apart: a Vector's components are single-precision, and
## rounding the body's own height into one makes the panel's weight disagree with
## the mover's in the seventh decimal. A copy that is not exact is not a copy.
var com: Vector2 = Vector2.ZERO
var com_height: float = 0.0
var com_lateral: float = 0.0
var base: Vector2 = Vector2.ZERO
var margin: float = 0.0
var span: float = 0.0
var pad: float = 0.0
var steadiness: float = 0.0
var overhang: Vector2 = Vector2.ZERO
var hull: PackedVector2Array = PackedVector2Array()

# -------------------------------------------------------------- the attitude ----

## `Keel`, copied: how far over the body is, what the legs are asking for to hold
## it there, and the most they could press if they asked for everything.
var roll: float = 0.0
var roll_rate: float = 0.0
var righting: float = 0.0
var righting_ceiling: float = 0.0
var keel_side: float = 0.0
var keel_spill: float = 0.0
var strained: bool = false

# ---------------------------------------------------------------- the world ----

## `Outlook`, copied: what the strip ahead of each girdle rises by, and how much
## of the ask the path permits (0 is the balk).
var fore_rise: float = 0.0
var hind_rise: float = 0.0
var headroom: float = 1.0
var fore_carry: float = 0.0
var hind_carry: float = 0.0
var height: float = 0.0
var crouch: float = 0.0
var airborne: bool = false
var collapsed: bool = false

## What the loop is doing, in one word — `Travel`'s own precedence.
var state: StringName = &"STANDING"

## Seconds the loop has been watched, and the tick it was last written on.
var clock: float = 0.0

# ------------------------------------------------------------- live tells ----

## Measured every tick because they are angles of the pose rather than histories:
## how far the withers lead the hips through a turn, how far the tail trails the
## pelvis, and how many joints are pressed against their own limits.
var spine_lag: float = 0.0
var tail_trail: float = 0.0
var clamped: int = 0


# ------------------------------------------------------------------ the ring ----
# One sample per physics tick, in flat packed arrays sized once. Oldest-first
# addressing is `sample(k)`; nothing outside this file touches the wrap.

var _t: PackedFloat32Array = PackedFloat32Array()
var _mark: PackedByteArray = PackedByteArray()
var _down: PackedByteArray = PackedByteArray()
var _clamped: PackedByteArray = PackedByteArray()
var _demand: PackedFloat32Array = PackedFloat32Array()
var _delivered: PackedFloat32Array = PackedFloat32Array()
var _ceiling: PackedFloat32Array = PackedFloat32Array()
var _steady: PackedFloat32Array = PackedFloat32Array()
var _spill: PackedFloat32Array = PackedFloat32Array()
var _rise: PackedFloat32Array = PackedFloat32Array()
var _sway: PackedFloat32Array = PackedFloat32Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
## Where the weight has been on the ground plane — the trail a reader draws. Kept
## in the world's own coordinates, because that is where it happened.
var _com_x: PackedFloat32Array = PackedFloat32Array()
var _com_y: PackedFloat32Array = PackedFloat32Array()
var _at: int = 0
var _count: int = 0
var _feet: int = 0

## Per-foot landing history: how long that foot's own stride took and how far it
## covered, as a share of the disc it was placed in. Both are recorded at the
## moment of a landing, which is the only moment either exists.
var _period: PackedFloat32Array = PackedFloat32Array()
var _stride: PackedFloat32Array = PackedFloat32Array()
var _landings: PackedInt32Array = PackedInt32Array()
var _landed_at: PackedFloat32Array = PackedFloat32Array()
var _was_swinging: PackedByteArray = PackedByteArray()


## Starts or stops the recording. Starting clears whatever was there: a history
## with a hole in it is a lie about a gait, and the hole is exactly as long as
## the panel was closed.
func watch(on: bool) -> void:
	watching = on
	if on:
		clear()


# ------------------------------------------------------------------ writing ----

## One tick of the loop, copied. Called by `Travel.observe` at the end of the
## cycle, when every stage has run and `Poise` has measured the result.
func gather(delta: float, creature: Creature2, travel: Travel,
		state_word: StringName) -> void:
	var a: Armature = creature.armature
	var p: Poise = creature.poise
	var fw: Footwork = travel.footwork
	if steps.size() != fw.feet.size():
		_size(fw.feet.size())
	clock += delta
	state = state_word

	ask = travel.ask_speed
	speed = creature.speed
	pace = creature.speed_norm
	ang_vel = creature.ang_vel
	velocity = travel.impetus.velocity
	thrust = travel.impetus.thrust
	demanded = travel.impetus.demand
	demand = demanded.length()
	delivered = thrust.length()
	power = travel.impetus.power
	grip = fw.grip
	ceiling = travel.impetus.ceiling
	lean = travel.lean

	com = p.centre
	com_height = p.height
	base = p.base
	margin = p.clearance
	span = p.span
	pad = p.pad
	steadiness = p.steadiness()
	overhang = p.overhang
	feet_down = p.feet
	hull = p.support_shape()

	roll = travel.keel.roll
	roll_rate = travel.keel.rate
	righting = travel.keel.righting
	righting_ceiling = travel.keel.ceiling
	keel_side = travel.keel.side
	keel_spill = travel.keel.spill
	strained = travel.keel.strained

	fore_rise = fw.fore_rise
	hind_rise = fw.hind_rise
	headroom = travel.headroom
	fore_carry = a.fore_carry
	hind_carry = a.hind_carry
	height = maxf(a.fall.height - a.fall.floor_height, 0.0)
	crouch = travel.crouch
	airborne = a.fall.is_airborne()
	collapsed = a.collapsed
	seats = travel.rhythm.seats
	coupling = creature.body.beat_coupling

	# Where the weight sits across the body's own axis, rather than across the
	# world's: a sway measured in world coordinates is mostly a fact about which
	# way the animal happens to be walking.
	var lateral := Vector2(-sin(creature.heading), cos(creature.heading))
	com_lateral = (com - a.centre()).dot(lateral)

	_gather_feet(a, fw)
	_gather_angles(a)
	_record()


## Every foot, as `Footwork` left it — the measurement, the grant, and the arc
## in between.
func _gather_feet(a: Armature, fw: Footwork) -> void:
	for i in fw.feet.size():
		var f: Footwork.Foot = fw.feet[i]
		var s: Step = steps[i]
		s.name = f.limb.name
		s.fore = f.fore
		s.swinging = f.swinging
		s.anchor = Vector3(f.anchor.x, f.anchor.y, f.anchor_z)
		s.drift = f.drift
		s.home = f.home
		s.urgency = f.urgency
		s.torn = f.torn
		s.rescuing = f.rescue_at.x < INF
		s.lift = f.lift
		s.land = f.land
		s.swing = f.swing
		s.swing_time = f.swing_time
		s.since = f.since
		s.socket = a.socket_of(f.limb)
		s.excursion = fw.excursion(f.fore)
		# A landing is the moment a swing ends, and it is the only moment a stride
		# and a beat exist to be measured.
		if _was_swinging[i] != 0 and not f.swinging:
			_land(i, s)
		_was_swinging[i] = 1 if f.swinging else 0


## The pose's own angles: the lead the back is holding through a turn, the trail
## in the tail, and how many joints have run out of room.
func _gather_angles(a: Armature) -> void:
	spine_lag = rad_to_deg(absf(wrapf(
		a.fwd[a.withers_index()].angle() - a.fwd[a.pelvis_index()].angle(), -PI, PI)))
	var tail: Armature.Chain = a.chain(BodySchema.TAIL)
	var tip: int = tail.nodes[tail.nodes.size() - 1]
	var run: Vector2 = a.plan(tip) - a.plan(a.pelvis_index())
	tail_trail = 0.0
	if run.length_squared() > 0.01:
		# Against where the tail would lie if it were welded on straight behind
		# the hips, which is what "the tail is stiff" means.
		tail_trail = rad_to_deg(absf(wrapf(
			run.angle() - (-a.fwd[a.pelvis_index()]).angle(), -PI, PI)))
	clamped = a.joints_at_cap(AT_CAP)


## A landing: the ground that step covered, and how long it was since this foot
## last put itself down.
##
## The stride is quoted against the *disc the foot may be placed in* — twice the
## pair's fore-aft excursion, which is the plan reach the anatomy allows at this
## stance — because a length on its own says nothing: a long leg taking a short
## step and a short leg taking a long one are the same number of pixels and
## opposite findings.
func _land(i: int, s: Step) -> void:
	var k: int = _landings[i] % LANDINGS
	var slot: int = i * LANDINGS + k
	_period[slot] = (clock - _landed_at[i]) if _landings[i] > 0 else NAN
	_stride[slot] = Vector2(s.land.x - s.lift.x, s.land.y - s.lift.y).length() \
		/ maxf(s.excursion * 2.0, 0.001)
	_landed_at[i] = clock
	_landings[i] += 1


func _record() -> void:
	var i: int = _at
	_t[i] = clock
	for j in _feet:
		_mark[i * _feet + j] = steps[j].mark()
	_down[i] = feet_down
	_clamped[i] = mini(clamped, 255)
	_demand[i] = demand
	_delivered[i] = delivered
	_ceiling[i] = ceiling
	_steady[i] = steadiness
	_spill[i] = maxf(-margin, 0.0) / maxf(span, 0.001)
	_rise[i] = com_height
	_sway[i] = com_lateral
	_speed[i] = speed
	_com_x[i] = com.x
	_com_y[i] = com.y
	_at = (_at + 1) % TICKS
	_count = mini(_count + 1, TICKS)


# ------------------------------------------------------------------ reading ----

## How many samples are on the ring, oldest at 0.
func samples() -> int:
	return _count


func sample_time(k: int) -> float:
	return _t[_ring(k)]


func sample_mark(k: int, foot: int) -> int:
	return _mark[_ring(k) * _feet + foot]


func sample_down(k: int) -> int:
	return _down[_ring(k)]


func sample_demand(k: int) -> float:
	return _demand[_ring(k)]


func sample_delivered(k: int) -> float:
	return _delivered[_ring(k)]


func sample_ceiling(k: int) -> float:
	return _ceiling[_ring(k)]


func sample_steadiness(k: int) -> float:
	return _steady[_ring(k)]


func sample_spill(k: int) -> float:
	return _spill[_ring(k)]


## Where the weight was, world plan, and how high it hung — the trail.
func sample_com(k: int) -> Vector3:
	var i: int = _ring(k)
	return Vector3(_com_x[i], _com_y[i], _rise[i])


func _ring(k: int) -> int:
	return (_at - _count + k + TICKS * 2) % TICKS


# -------------------------------------------------------------------- tells ----
# The eight diagnostics, each a reduction of the ring and each NAN where it
# cannot honestly be measured — a standing animal has no gait to be stiff, and a
# body going straight has no turn for its back to be rigid through. Nothing here
# is a verdict: a reader owns the bands, because what is a *natural* number is a
# judgement about an animal and these are only measurements of one.

func tells() -> Dictionary:
	return {
		&"bob": _peak_to_peak(_rise),
		&"sway": _peak_to_peak(_sway),
		&"lag": spine_lag if absf(ang_vel) > TURNING else NAN,
		# The tail is a follow-through, so it is only a reading while there is
		# something to follow: a standing animal's tail lying straight behind it is
		# not stiff, it is at rest.
		&"tail": tail_trail if speed >= TRAVELLING else NAN,
		&"spread": _beat_spread(),
		&"clip": float(clamped),
		&"stride": _mean_stride(),
		&"delivery": _delivery_share(),
	}


## Peak-to-peak of a recorded channel over the tell window — NAN while the body
## is not travelling, because the answer would be a fact about standing still.
func _peak_to_peak(channel: PackedFloat32Array) -> float:
	if _count < 8 or speed < TRAVELLING:
		return NAN
	var low: float = INF
	var high: float = -INF
	var seen: int = 0
	for k in range(_count - 1, -1, -1):
		var i: int = _ring(k)
		if clock - _t[i] > TELL_WINDOW:
			break
		if _speed[i] < TRAVELLING:
			return NAN
		low = minf(low, channel[i])
		high = maxf(high, channel[i])
		seen += 1
	return (high - low) if seen >= 8 else NAN


## How irregular the beat is: the spread of each foot's own stride period,
## as a percentage of the mean. A clock reads near zero.
func _beat_spread() -> float:
	if speed < TRAVELLING:
		return NAN
	var sum: float = 0.0
	var n: int = 0
	for slot in _period.size():
		if is_finite(_period[slot]) and _period[slot] > 0.0:
			sum += _period[slot]
			n += 1
	if n < 5:
		return NAN
	var mean: float = sum / float(n)
	var variance: float = 0.0
	for slot in _period.size():
		if is_finite(_period[slot]) and _period[slot] > 0.0:
			variance += (_period[slot] - mean) * (_period[slot] - mean)
	return sqrt(variance / float(n)) / maxf(mean, 0.0001) * 100.0


## Mean stride as a share of the ground the leg was placed over — a length on its
## own says nothing, because a long leg's short step and a short leg's long one
## are the same number.
func _mean_stride() -> float:
	if speed < TRAVELLING:
		return NAN
	var sum: float = 0.0
	var n: int = 0
	for slot in _stride.size():
		if _stride[slot] > 0.0:
			sum += _stride[slot]
			n += 1
	return sum / float(n) if n >= 4 else NAN


## What share of the demand the feet actually delivered, over the samples where
## anything was being demanded. One is a body with no mass to feel.
func _delivery_share() -> float:
	var sum: float = 0.0
	var n: int = 0
	for k in _count:
		var i: int = _ring(k)
		if _demand[i] <= DEMANDING:
			continue
		sum += _delivered[i] / _demand[i]
		n += 1
	return sum / float(n) if n >= 8 else NAN


# ------------------------------------------------------------------- sizing ----

func _size(count: int) -> void:
	_feet = count
	steps.clear()
	for _i in count:
		steps.append(Step.new())
	_mark.resize(TICKS * maxi(count, 1))
	_period.resize(count * LANDINGS)
	_stride.resize(count * LANDINGS)
	_landings.resize(count)
	_landed_at.resize(count)
	_was_swinging.resize(count)
	# One at a time, because a packed array put in a list is a copy of itself and
	# resizing that copy resizes nothing.
	_t.resize(TICKS)
	_demand.resize(TICKS)
	_delivered.resize(TICKS)
	_ceiling.resize(TICKS)
	_steady.resize(TICKS)
	_spill.resize(TICKS)
	_rise.resize(TICKS)
	_sway.resize(TICKS)
	_speed.resize(TICKS)
	_com_x.resize(TICKS)
	_com_y.resize(TICKS)
	_down.resize(TICKS)
	_clamped.resize(TICKS)
	clear()


## Forgets the history. Whatever comes next is a different run of the body — a
## reset, a revival, a panel just opened — and a timeline that ran across the
## join would be drawing a stride that never happened.
func clear() -> void:
	_at = 0
	_count = 0
	clock = 0.0
	_period.fill(NAN)
	_stride.fill(0.0)
	_landings.fill(0)
	_landed_at.fill(0.0)
	_was_swinging.fill(0)
