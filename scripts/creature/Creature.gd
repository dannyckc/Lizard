## Owns the creature's motion state and drives the four subsystems in order.
##
## Per physics tick:
##   1. integrate the head's position/heading from the movement command;
##   2. correct that position against other bodies — pushed out of the ones it is
##      inside, pulled back onto anything its jaws have hold of;
##   3. drag the spine after it (constraint solve);
##   4. rebuild the body shape from the solved spine;
##   5. run the gait, which reads the new body and solves the limb IK.
##
## The dependency chain is strictly one-way — input -> head -> contacts -> spine
## -> body -> limbs — which is why the whole thing is stable without any global
## solver. All state is in world space and this node stays at the origin, so the
## view can draw the raw coordinates.
##
## Step 2 is the only place two creatures affect each other, and both halves of
## it work the same way: each creature measures the error itself, corrects its
## own share of it, and never writes into the other's state. The share is its
## mass — see `_contact_share` — which is the whole of what weight does here.
class_name Creature
extends Node2D

signal ate_food(total: int)
## Emitted at the apex of the lunge, not on the click — see _physics_process.
signal bite_started(center: Vector2, radius: float)
signal tissue_damaged(integrity: float)
## Chunks of skin and muscle a bite tore off, for the world to scatter.
signal tissue_shed(chunks: Array, origin: Vector2)

@export var params: CreatureParams
## Simulation-space spawn because this node intentionally remains at the world
## origin while its procedural points are stored directly in world space.
@export var spawn_position: Vector2 = Vector2.ZERO
@export var spawn_heading: float = 0.0

## Whether anything is driving this body. Until there is an AI, everything placed
## in the habitat is a carcass — see the dead tick below.
##
## It is a property of the body rather than of who happens to be steering it, so
## the day something does drive one the only change here is that this becomes
## true; nothing else in the class is conditional on the player specifically.
@export var alive: bool = true
## Deterministic shape of a carcass's slump. Left at 0 one is derived from where
## the body was placed, so a given body lies the same way every run while two of
## them never lie identically.
@export var rest_seed: int = 0

var spine: Spine
var body: BodyShape
var gait: Gait
## Owns the limbs while `alive` is false, exactly where Gait owns them while it is
## true. Null on a living creature.
var ragdoll: Ragdoll = null
var anatomy: AnatomyState = AnatomyState.new()
## Mass, strength and bite force, read off the solved body and the lattice each
## tick. Not settings — see Physique. Refreshed at the end of the tick with the
## rest of the derived state, so the contact and grip passes read the physique of
## the pose they are correcting, exactly as they already read its bounds.
var physique: Physique = Physique.new()

# --- motion state -----------------------------------------------------------
var head_pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var ang_vel: float = 0.0
var move_dir: Vector2 = Vector2.RIGHT
## Speed as a 0..1 fraction of top speed. Drives stride, step timing and sway.
var speed_norm: float = 0.0

## The cursor articulates only the head around the solved neck. This angle is
## deliberately separate from `heading`, which remains the WASD-owned body
## direction used by locomotion, gait and collision braking.
const HEAD_LOOK_MAX_ANGLE: float = deg_to_rad(82.0)
const HEAD_LOOK_RESPONSE: float = 14.0
const HEAD_LOOK_DEADZONE_SQ: float = 36.0
var head_look_angle: float = 0.0
var head_look_dir: Vector2 = Vector2.RIGHT

var food_eaten: int = 0
## Uniform scale on the whole creature — body, limbs, stride, reach and bite all
## read off it. Growth has been taken out for now, so it is pinned at 1.0 and
## nothing writes to it; it is left in place as the single value a growth system
## will drive when one lands, rather than as a multiplier to be re-threaded
## through forty call sites later.
var size_scale: float = 1.0

# --- collision --------------------------------------------------------------
## Fraction of a contact each creature resolves on its own when the two weigh the
## same. Both parties run the same pass against each other, so together they
## provide one full correction without either creature writing into the other's
## simulation state. Mass then splits that correction unevenly — see
## `_contact_share` — but the two halves still sum to exactly one.
const CONTACT_SHARE: float = 0.5
## Floor and ceiling on a mass-weighted share. An extreme ratio would otherwise
## leave the heavy party contributing nothing at all to a separation, so a pair
## spawned inside each other could stay interlocked; and the light party would be
## teleported by the whole of it.
const MIN_CONTACT_SHARE: float = 0.08
## Ceiling on how far one tick may translate a complete creature. A deep overlap —
## two creatures spawned inside each other, or a segment count change that
## lengthens a body through its neighbour — then unwinds over a few ticks
## instead of teleporting it. Applied before the mass share, so the lighter body
## of a badly mismatched pair takes at most eleven pixels of it per tick and an
## evenly matched one six. The grip's tether is capped by the same number, for
## the same reason: neither correction may become a jump.
const MAX_CONTACT_PUSH: float = 12.0
const CONTACT_EPSILON: float = 0.0001

## Bounding circle around the whole body, refreshed with the pose. Only used to
## reject creature pairs before the capsule-pair contact walk.
var bounds_center: Vector2 = Vector2.ZERO
var bounds_radius: float = 0.0
## Spine coordinate of the most recent body contact returned by the narrow
## phase. A living body resolves that contact as a rigid correction; a free dead
## spine can accept it where it actually landed and bend around the impact.
var _contact_spine_t: float = 0.0

# --- bite state -------------------------------------------------------------
## The strike is an animation with a hit frame, not an instant event. A click
## starts a wind-up, the head is then thrown forward, and the bite resolves at
## full extension — so what gets bitten is whatever the jaws actually reached,
## and the lunge reads as the cause of the damage rather than as a flourish
## played after it.
const LUNGE_WINDUP: float = 0.07
const LUNGE_STRIKE: float = 0.08
const LUNGE_RECOVER: float = 0.18
const LUNGE_TOTAL: float = LUNGE_WINDUP + LUNGE_STRIKE + LUNGE_RECOVER
## How far the head rocks back during the wind-up, as a fraction of the throw.
const LUNGE_SETBACK: float = -0.22

# --- grip -------------------------------------------------------------------
## Play in the jaws, in pixels. The tether takes up nothing inside this, which is
## what stops the biter's own spine settling under a clamped head from quietly
## towing it into its victim, and what keeps a fresh grip from fighting the
## contact pass that is holding the two bodies apart at the same point.
const GRIP_SLACK: float = 3.0
## Separation speed, in px/s, at which one unit of purchase puts one unit of
## force on the jaws. This is what `jaw_power` is measured against.
const GRIP_LOAD_REFERENCE: float = 150.0
## How quickly measured load follows the instantaneous pull. A grip has to be
## broken by a sustained heave rather than by one coarse tick.
const GRIP_LOAD_RESPONSE: float = 6.0
## What one unit of towed mass costs the hauler, against its own strength.
const HAUL_COST: float = 1.0
## However overmatched, a creature can still shuffle. Zero here would be a
## creature frozen by a grip, which is the static hold this replaced.
const HAUL_FLOOR: float = 0.05
## How much of the jaws' penetration is spent holding on, per unit of strain.
const CHEW_STRAIN_COST: float = 0.75
## Floor under that, so jaws at the edge of losing their grip still do damage.
const CHEW_MIN_DEPTH: float = 0.30
## How much wider than the footprint it crushes a set of jaws can find a new hold
## in. `bite_radius` is the volume a bite destroys; the gape is the span the jaws
## can close on, and it has to be the larger of the two or a bite that eats a
## clean hole would then be unable to reach the flesh around the hole it made.
const GRIP_GAPE: float = 1.75
## Resolution of the search for somewhere new to hold. Only ever runs on the tick
## a mouthful comes away, so it is priced like the bite it follows rather than
## like anything per-frame.
const REGRIP_STATIONS: int = 32
const REGRIP_LATERALS: Array[float] = [0.0, 0.5, -0.5, 0.9, -0.9]

# --- tearing ------------------------------------------------------------------
# The other way a hold ends, and the one the jaws win. Flesh has a tensile
# strength of its own — see `Grip.tissue_strength` — and a pull past its yield
# point draws it out of the body instead of moving the creature. Held long
# enough, it parts, and the mouthful comes away in the jaws.
#
# Both this and the jaws coming off are measured against the same `load`, so
# which of them happens is never chosen anywhere: it is whichever gives out
# first. Jaws weaker than the flesh they are on are pulled off a body that stayed
# in one piece; jaws stronger than it take a piece of it with them. That is the
# whole of why a Crocodile strips meat off prey a Gecko can only be shaken from,
# and no rule was written for either case.

## Fraction of its strength at which flesh starts to give rather than merely take
## up. Below this a pull is held indefinitely, however long it lasts.
const TEAR_YIELD: float = 0.5
## Seconds of pulling at one full strength over the yield point needed to part
## the fibres. Larger is tougher meat everywhere.
const TEAR_WORK: float = 1.1
## How fast stretched tissue recovers once the pull comes off it, per second. A
## victim that stops struggling before the tear stops being torn.
const TEAR_RELAX: float = 0.45
## How deep the mouthful a tear takes comes out, in the lattice's hit points.
## Enough to clear skin and muscle at the centre of the jaws, so what comes away
## is meat rather than a graze — bone still yields at its own reduced rate and
## stops the tear at the skeleton, which is why a limb can be stripped but a
## ribcage only bared. The margin over the flesh stack is what makes the cell it
## was bound to genuinely empty afterwards rather than left with a sliver, which
## the hold would otherwise go on pulling against at almost no strength at all.
const TEAR_DEPTH: float = (TissueGrid.SKIN_HP + TissueGrid.MUSCLE_HP) * 1.15

# --- chewing ------------------------------------------------------------------
## How long the jaws stay shut on their bind after the button comes up. A press
## inside this window is the same jaws closing again on the same flesh — a chew —
## rather than a fresh strike. Chewing is therefore a repeated action, as biting
## is, without costing a second control: holding still holds, and working the
## button works the jaws.
const GRIP_REGRASP_WINDOW: float = 0.25

# ------------------------------------------------------------------ dead ----
## Inertia a carcass keeps between ticks. Well under `spine_damping`, which is
## the give of a body holding itself together; this is ground friction under one
## that is not, and its whole job is to bring the body to rest and keep it there.
const DEAD_DAMPING: float = 0.42
## Share of a dead body's contact correction carried by its centre of mass. The
## rest lands at the actual spine station and bends it. A purely local correction
## can be absorbed as shape change, making a corpse fold in place instead of
## yielding to a shove; a purely rigid one is the plank-like response the
## ragdoll path exists to avoid.
const DEAD_CONTACT_TRANSLATION: float = 0.55
## How sharply a pull on a carcass falls off along the spine, per station away
## from where the pull acts. See `_drag_at`.
const DRAG_FALLOFF: float = 0.55

var bite_cooldown_remaining: float = 0.0
var bite_connected: bool = false
## True from a world-space left-button press until its matching release. A
## connected strike that reaches its hit frame during that interval clamps at
## full extension and takes hold of what it bit; holding a miss never creates a
## latch.
var bite_held: bool = false
var bite_latched: bool = false
## The jaws' hold on another creature, or null. Owned and written only here; the
## victim finds it by looking, so neither party touches the other's state.
var grip: Grip = null
## The grip currently holding *this* creature, refreshed once at the top of the
## tick so the three consumers below do not each walk the creature group.
var _held_by: Grip = null
## Set when a grip ends by itself — torn off, or the flesh under it eaten away.
## Cleared on button release, so jaws that lost their hold cannot silently take
## it again while the button is still down.
var _grip_lockout: bool = false
## Seconds the jaws will stay shut on their bind with the button already up. Non
## zero only between a release and the moment the hold actually ends, which is
## the window a chew is taken in.
var _regrasp_remaining: float = 0.0
## Seconds until jaws that are already holding something will close again.
var _chew_cooldown: float = 0.0
## A chew taken this tick, queued for the solved pose exactly as a strike is.
var _chew_requested: bool = false
## Set only for the synchronous emit a tear resolves through, so the world's one
## bite path prices the mouthful being pulled out rather than a closing of jaws.
var _tearing: bool = false
## Seconds into the current strike, or -1 while not striking.
var bite_time: float = -1.0
## How far ahead of its resting position the lunge is currently holding the
## head, in world pixels. Applied to the spine, never to `head_pos`.
var lunge_offset: float = 0.0
var _bite_requested: bool = false
var _impact_done: bool = false

## Set by whoever is driving this creature, before the physics tick.
var command: MovementInput.Command = MovementInput.Command.new()


func _ready() -> void:
	if params == null:
		params = CreatureParams.new()
	head_pos = spawn_position
	heading = spawn_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	head_look_angle = heading
	head_look_dir = move_dir
	add_to_group("creatures")
	rebuild()


## Rebuilds the structures that depend on segment count. Cheap enough to call
## from a slider callback.
func rebuild() -> void:
	# One generator across both halves of a carcass, so the slump of its spine and
	# the sprawl of its limbs are different draws describing one body rather than
	# the same few numbers used twice.
	var rng: RandomNumberGenerator = null if alive else _rest_rng()
	spine = Spine.new()
	var seg_len: float = params.segment_length * size_scale
	if alive:
		spine.rebuild(params.segment_count, seg_len, head_pos, heading)
	else:
		spine.rebuild_slumped(params.segment_count, seg_len, head_pos, heading,
			deg_to_rad(params.max_bend_deg), rng)
	body = BodyShape.new()
	gait = Gait.new()
	gait.setup()
	body.build(spine, params, size_scale)
	if alive:
		ragdoll = null
		gait.update(0.0, body, move_dir, 0.0, params, size_scale)
	else:
		ragdoll = Ragdoll.new()
		ragdoll.settle(body, gait.limbs, params, size_scale, rng)
	# Existing damage is kept — it lives in body space precisely so a structural
	# rebuild cannot wash it off — but its world geometry is now stale.
	anatomy.update(self)
	physique.update(body, spine, anatomy.tissue, params)
	_update_bounds()


## The generator a carcass's resting shape is drawn from.
##
## Seeded off where the body actually is rather than off the clock, so it lies
## the same way every run — a body that rearranged itself on reload would not read
## as something that had come to rest at all — while two bodies lying anywhere
## apart lie differently without anyone having to author either pose.
##
## Where it *is*, not `spawn_position`, and the difference is not academic: the
## authored placement is a property of the scene file that `reset` never touches,
## so a body moved anywhere at runtime would go on wearing the pose it was built
## with at its old address.
func _rest_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rest_seed if rest_seed != 0 \
		else hash(Vector3(head_pos.x, head_pos.y, heading))
	return rng


func reset(at: Vector2 = Vector2.ZERO, facing: float = 0.0) -> void:
	head_pos = at
	heading = facing
	speed = 0.0
	ang_vel = 0.0
	move_dir = Vector2.RIGHT.rotated(heading)
	head_look_angle = heading
	head_look_dir = move_dir
	food_eaten = 0
	command = MovementInput.Command.new()
	anatomy.reset()
	bite_cooldown_remaining = 0.0
	bite_connected = false
	bite_held = false
	bite_latched = false
	bite_time = -1.0
	lunge_offset = 0.0
	_bite_requested = false
	_impact_done = false
	_grip_lockout = false
	_regrasp_remaining = 0.0
	_chew_cooldown = 0.0
	_chew_requested = false
	_tearing = false
	grip = null
	_held_by = null
	# Reset is an authority from outside the simulation, not a move inside it, so
	# it is the one place a creature reaches into another's state: a body teleported
	# back to its spawn is no longer the body anybody had hold of, and leaving the
	# tether attached would yank the biter across the world after it.
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("creatures"):
			var other := node as Creature
			if other != null and other != self and other.grip != null and other.grip.victim == self:
				other.grip = null
				other.bite_latched = false
				other._regrasp_remaining = 0.0
	rebuild()


func _physics_process(delta: float) -> void:
	# Segment count is the only structural parameter; everything else is read live
	# each tick, so tuning sliders take effect immediately. Checked before the
	# branch because it is the one thing both kinds of body need.
	if spine == null or spine.size() != params.segment_count:
		rebuild()
	if not alive:
		_dead_process(delta)
		return

	bite_cooldown_remaining = maxf(bite_cooldown_remaining - delta, 0.0)
	_chew_cooldown = maxf(_chew_cooldown - delta, 0.0)
	# Jaws let go by running out of the window they were given, not by the button
	# coming up — see GRIP_REGRASP_WINDOW. Held down, the window is never running.
	if _regrasp_remaining > 0.0 and not bite_held:
		_regrasp_remaining = maxf(_regrasp_remaining - delta, 0.0)
		if _regrasp_remaining <= 0.0:
			_release_grip()

	_held_by = _find_grip_on_self()

	if _bite_requested:
		_bite_requested = false
		bite_time = 0.0
		bite_connected = false
		bite_latched = false
		_impact_done = false
		bite_cooldown_remaining = params.bite_cooldown
	_advance_lunge(delta)

	_integrate_motion(delta)
	# Between "where input put the head" and "where the body follows it to", so
	# the silhouette, the limbs and the tissue lattice are all built from the
	# corrected pose within this same tick rather than a tick behind it.
	_resolve_contacts()
	# Immediately after, because the two are the same kind of correction pointing
	# opposite ways: contacts push bodies out of each other, a grip pulls jaws back
	# onto flesh. Running them in one phase lets a pair that is both held and
	# overlapping settle within a tick instead of alternating.
	_resolve_grip()

	# The lunge is fed to the spine rather than to `head_pos`, which stays the
	# creature's honest position: the throw has to be something the body follows
	# through the constraint solve — that is what makes it whip — and it must
	# not accumulate into the motion integrator or a strike would teleport the
	# creature forward by its own reach.
	var seg_len: float = params.segment_length * size_scale
	spine.step(delta, head_pos + head_look_dir * lunge_offset, params, speed_norm, seg_len)
	_update_head_look(delta)
	# Mouse look is posed after the body solve, so it can move and turn point 0
	# without changing point 1 or anything downstream of it.
	spine.pose_head(head_look_dir, seg_len)
	body.build(spine, params, size_scale)
	gait.update(delta, body, move_dir, speed_norm, params, size_scale,
		Callable(self, "_limb_contact_push"))
	anatomy.update(self)
	physique.update(body, spine, anatomy.tissue, params)
	_update_bounds()

	# Resolve at full extension, once the pose above is the lunged one, so the
	# bite is tested against where the jaws have genuinely arrived. The clock is
	# clamped to the end of the animation rather than run past it, so this can
	# never be stepped over — one click is always exactly one hit frame, however
	# coarse the tick that carries it.
	if bite_time >= 0.0 and not _impact_done and bite_time >= LUNGE_WINDUP + LUNGE_STRIKE:
		_impact_done = true
		_strike()
	if bite_time >= LUNGE_TOTAL:
		bite_time = -1.0
		lunge_offset = 0.0

	# Last, because everything it does is a consequence of the pose that has just
	# been solved: what the jaws are now pulling against, whether they can still
	# hold it, and whether they have come round to close again.
	_advance_grip(delta)


## One tick of a body nobody is driving.
##
## The live chain runs input -> head -> contacts -> spine -> body -> limbs. A
## carcass has no input and no head to place, so the very same chain simply
## starts further down it: what moves this body is other bodies pushing it and
## whatever has hold of it, its spine is a free chain rather than one pinned to a
## driven head, and its limbs hang off the sockets instead of walking. Nothing is
## reordered and nothing is skipped that anything downstream depends on — the
## silhouette, the tissue lattice, the physique and the bounds are all rebuilt
## from this tick's pose exactly as they are for a living creature, which is why
## a carcass can still be collided with, bitten, held and eaten.
##
## Weight needs no code of its own here. `physique` is read off the drawn body and
## the surviving tissue whether or not anything is driving it, and the contact and
## grip passes below already split every correction by mass — so a heavy carcass
## is shouldered aside less and towed more slowly for exactly the reason a heavy
## creature is, through exactly the same line.
func _dead_process(delta: float) -> void:
	if spine == null or body == null or ragdoll == null:
		return
	_held_by = _find_grip_on_self()
	_resolve_contacts()
	_resolve_grip()

	spine.step_free(params, params.segment_length * size_scale, DEAD_DAMPING)
	# The head is no longer placed, so `head_pos` follows the body instead of
	# leading it. Everything that reads it — the first capsule of the contact
	# walk, the broad phase, the jaws — then describes where this body actually
	# is rather than where nothing is steering it to.
	head_pos = spine.points[0]
	head_look_dir = spine.forwards[0]
	head_look_angle = head_look_dir.angle()
	move_dir = head_look_dir

	body.build(spine, params, size_scale)
	ragdoll.step(delta, body, gait.limbs, params, size_scale,
		Callable(self, "_limb_contact_push"))
	anatomy.update(self)
	physique.update(body, spine, anatomy.tissue, params)
	_update_bounds()


## Advances the strike clock and resolves it to a forward displacement.
##
## Three phases, shaped so the silhouette itself carries the timing: a soft
## rock backwards to load, a hard ease-out throw (all the distance covered in
## the first half of it, which is what makes it read as a snap rather than a
## lean), and a slow settle back. Nothing is fed back into the motion state, so
## a creature that never bites is bit-for-bit unaffected by any of this.
func _advance_lunge(delta: float) -> void:
	if bite_time < 0.0:
		lunge_offset = 0.0
		return
	# A held bite clamps only after the synchronous world resolver confirmed that
	# the jaws connected. Keeping the clock on the hit frame holds the visible
	# head at full extension without restarting the cooldown; what the jaws then
	# do to the flesh in them is the grip's business, not the animation's.
	if is_bite_latched():
		bite_time = LUNGE_WINDUP + LUNGE_STRIKE
		lunge_offset = params.bite_reach * size_scale * 0.85
		return
	# The clock never advances past the hit frame in a single step. A tick large
	# enough to span the whole animation would otherwise leave the head already
	# recovered on the frame the bite resolves, and it would strike from resting
	# reach — so "the bite is tested at full extension" would hold only at a
	# well-behaved tick rate. Stopping on the apex makes it unconditional; the
	# strike then releases the clamp and recovery runs on the following tick.
	var limit: float = LUNGE_TOTAL if _impact_done else LUNGE_WINDUP + LUNGE_STRIKE
	bite_time = minf(bite_time + delta, limit)

	var throw_distance: float = params.bite_reach * size_scale * 0.85
	var e: float
	if bite_time < LUNGE_WINDUP:
		e = LUNGE_SETBACK * smoothstep(0.0, 1.0, bite_time / LUNGE_WINDUP)
	elif bite_time < LUNGE_WINDUP + LUNGE_STRIKE:
		var x: float = (bite_time - LUNGE_WINDUP) / LUNGE_STRIKE
		e = lerpf(LUNGE_SETBACK, 1.0, 1.0 - (1.0 - x) * (1.0 - x))
	else:
		var x2: float = (bite_time - LUNGE_WINDUP - LUNGE_STRIKE) / LUNGE_RECOVER
		e = 1.0 - smoothstep(0.0, 1.0, x2)
	lunge_offset = e * throw_distance


## True while a strike is playing, at any phase.
func is_lunging() -> bool:
	return bite_time >= 0.0


## Smooth, anatomically bounded cursor look. Only this derived head direction
## reads `aim_world`; body heading and motion remain exclusively command-driven.
func _update_head_look(delta: float) -> void:
	# The solved neck is the truthful centre of the head's range. It can lag the
	# logical movement heading during a turn, and clamping against `heading`
	# instead would let the first joint exceed the spine's bend invariant.
	var neck_angle: float = spine.forwards[1].angle() if spine != null and spine.size() > 2 else heading
	var max_look: float = minf(HEAD_LOOK_MAX_ANGLE, deg_to_rad(params.max_bend_deg))
	var desired: float = neck_angle
	# A latched head is aimed by what it is holding, not by the cursor. The pose
	# is not frozen — the two bodies move relative to each other while the grip
	# lasts — so the head has to keep tracking the flesh in its jaws or the
	# drawn head would drift off the place the tether is anchored to.
	var aim_active: bool = command.aim_active
	var aim_world: Vector2 = command.aim_world
	if is_bite_latched() and grip != null and grip.is_alive():
		aim_active = true
		aim_world = grip.anchor()
	if aim_active:
		var look_origin: Vector2 = head_pos
		if spine != null and spine.size() > 1:
			look_origin = spine.points[1]
		var to_aim: Vector2 = aim_world - look_origin
		if to_aim.length_squared() > HEAD_LOOK_DEADZONE_SQ:
			var local: float = clampf(
				wrapf(to_aim.angle() - neck_angle, -PI, PI),
				-max_look,
				max_look)
			desired = neck_angle + local

	var response: float = 1.0 - exp(-HEAD_LOOK_RESPONSE * delta)
	head_look_angle = lerp_angle(head_look_angle, desired, response)
	# Clamp again after interpolation because the neck may itself have swung
	# sharply this tick while the head angle was easing from its previous pose.
	var relative: float = clampf(
		wrapf(head_look_angle - neck_angle, -PI, PI),
		-max_look,
		max_look)
	head_look_angle = wrapf(neck_angle + relative, -PI, PI)
	head_look_dir = Vector2.RIGHT.rotated(head_look_angle)


func _integrate_motion(delta: float) -> void:
	var p: CreatureParams = params
	# A grip is a load on whichever end of it this creature is, and the only thing
	# it changes about locomotion is how much of it survives that load. Turning is
	# deliberately left alone, for the same reason a body contact never touches
	# heading: however overmatched a creature is, thrashing has to remain
	# available — and thrashing is exactly what loads a set of jaws.
	var haul: float = _haul_factor()

	# Turn rate falls off with speed so the arc stays wider than the body. At a
	# standstill the full rate is available, which is what lets the creature
	# pivot on the spot (together with the pivot offset below).
	var turn_rate: float = deg_to_rad(p.turn_speed_deg) * (1.0 - p.turn_speed_falloff * speed_norm)
	# Angular velocity eases toward the commanded rate rather than snapping, so
	# the body has something to lag behind during a turn.
	var desired_ang_vel: float = command.turn * turn_rate
	ang_vel = lerpf(ang_vel, desired_ang_vel, 1.0 - exp(-p.turn_responsiveness * delta))

	# Turning swings the head around a pivot behind it instead of just spinning
	# it in place. Without this a stationary creature could rotate its heading
	# without the head ever moving, so the spine would never bend and the feet
	# would never trip their stride threshold — it would turn without walking.
	# The pivot shortens at speed so fast turns are wide arcs, not handbrakes.
	var pivot_dist: float = p.turn_pivot * size_scale * (1.0 - 0.6 * speed_norm)
	var pivot: Vector2 = head_pos - Vector2.RIGHT.rotated(heading) * pivot_dist
	heading = wrapf(heading + ang_vel * delta, -PI, PI)
	head_pos = pivot + Vector2.RIGHT.rotated(heading) * pivot_dist

	# Forward speed: accelerate toward the commanded speed, coast down faster
	# than we spin up so releasing the key feels responsive.
	var top_speed: float = p.move_speed * size_scale \
		* (p.sprint_multiplier if command.sprint else 1.0) * haul
	var desired_speed: float = command.throttle * top_speed
	var rate: float = p.acceleration * size_scale * haul
	if absf(desired_speed) < absf(speed):
		rate *= 1.6
	speed = move_toward(speed, desired_speed, rate * delta)

	move_dir = Vector2.RIGHT.rotated(heading)
	head_pos += move_dir * (speed * delta)
	speed_norm = clampf(absf(speed) / maxf(p.move_speed * size_scale, 1.0), 0.0, 1.0)


# ------------------------------------------------------------- collision ----

## Pushes this creature out of any other creature it is standing inside.
##
## Each creature resolves its own half of every contact and never touches
## another's state. A contact translates the complete creature: pushing the
## penetrated spine particles separately makes the distance/angle solver pull
## them back on the very next line, creating a slow separation and feeding the
## disagreement into the flexible body as exaggerated flailing.
##
## Detection compares every pair of variable-radius spine capsules rather than
## probing only their endpoints. Endpoint probes miss a thin body crossing the
## middle of a long segment, which is exactly how creatures can become deeply
## interlocked before the old solver notices them.
##
## This pass is body-vs-body only. Limb contacts run later inside the gait solve:
## they bend or slide the limb around the obstacle without pushing either body
## apart at arm's length.
func _resolve_contacts() -> void:
	if spine == null or body == null or not is_inside_tree():
		return
	# The single deepest contact anywhere on the body, kept unclamped so the
	# brake below can read how squarely it opposes travel, along with the share of
	# it this creature's mass makes it responsible for.
	var deepest: Vector2 = Vector2.ZERO
	var deepest_share: float = CONTACT_SHARE
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.body == null or other.spine == null:
			continue
		# Two creatures joined at the jaws are governed by the tether, not by
		# separation. A grip holds the biter's mouth *on* — meaning inside —
		# flesh the contact pass would spend every tick pushing it back out of,
		# and the two constraints act on the same pair at the same point in
		# opposite directions: the pair buzzes, and the stretch the grip's load is
		# measured from runs away with it. So while a hold is in force this pair
		# has exactly one rule between them, and it is the one the jaws impose.
		# Both parties reach the same conclusion from the same grip, so neither
		# collides with the other while the other does not. Everything else in the
		# world still collides with both, and the limbs still route around both.
		if _is_joined_to(other):
			continue
		# The body's bound is from its last solved pose, while the authoritative
		# head has already integrated this tick. Inflate by that small sweep so a
		# fast nose cannot cross the broad-phase boundary unnoticed.
		var head_sweep: float = head_pos.distance_to(spine.points[0])
		if bounds_center.distance_to(other.bounds_center) \
				> bounds_radius + other.bounds_radius + head_sweep:
			continue
		var push: Vector2 = _push_out_of_creature(other)
		if push == Vector2.ZERO:
			continue
		var share: float = _contact_share(other)
		if push.length_squared() > deepest.length_squared():
			deepest = push
			deepest_share = share
		var correction: Vector2 = push.limit_length(MAX_CONTACT_PUSH) * share
		if alive:
			_translate_contact(correction)
		else:
			var local: Vector2 = correction * (1.0 - DEAD_CONTACT_TRANSLATION)
			_translate_contact(correction * DEAD_CONTACT_TRANSLATION)
			_drag_at(spine.sample(_contact_spine_t).pos, local)
	_brake_into(deepest, deepest_share)


## How much of a contact with `other` this creature does the moving for.
##
## Mass, and nothing else. The share is the *other* body's fraction of the pair's
## total, so a light creature does nearly all of the moving and a heavy one barely
## notices. Both parties compute it from the same two numbers, so the two shares
## sum to exactly one and the separation is still complete without either creature
## writing into the other's state. Equal masses give 0.5 each — the constant this
## replaced — so two creatures of the same build behave exactly as they did.
##
## This is the whole of what weight does to a contact. There is still no shove
## force and no momentum transfer: what changed is only *who yields*, which is
## what the pass was already deciding and previously always split down the middle.
func _contact_share(other: Creature) -> float:
	if other == null or other.physique == null:
		return CONTACT_SHARE
	var total: float = physique.mass + other.physique.mass
	if total <= 0.0:
		return CONTACT_SHARE
	return clampf(other.physique.mass / total, MIN_CONTACT_SHARE, 1.0 - MIN_CONTACT_SHARE)


## Deepest capsule-pair penetration from `other` into this creature. The return
## vector points in the direction this whole creature must move to get clear.
func _push_out_of_creature(other: Creature) -> Vector2:
	var self_last: int = mini(body.last_index, spine.size() - 1)
	var other_last: int = mini(other.body.last_index, other.spine.size() - 1)
	if self_last < 1 or other_last < 1:
		return Vector2.ZERO

	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	for i in range(self_last):
		var a0: Vector2 = head_pos if i == 0 else spine.points[i]
		var a1: Vector2 = spine.points[i + 1]
		for j in range(other_last):
			var b0: Vector2 = other.spine.points[j]
			var b1: Vector2 = other.spine.points[j + 1]
			var uv: Vector2 = _closest_segment_parameters(a0, a1, b0, b1)
			var axis_a: Vector2 = a0.lerp(a1, uv.x)
			var axis_b: Vector2 = b0.lerp(b1, uv.y)
			var delta: Vector2 = axis_a - axis_b
			var distance: float = delta.length()
			var normal: Vector2 = delta / distance if distance > CONTACT_EPSILON \
				else _coincident_contact_normal(other, a0, a1, b0, b1)

			# Each radius is narrowed on the side actually facing the contact, so
			# a bitten-open flank remains a real opening in both halves of the test.
			var self_side: float = (-normal).dot(spine.perps[i])
			var other_side: float = normal.dot(other.spine.perps[j])
			var self_solid: float = _contact_solid(i, uv.x, self_side, self_last)
			var other_solid: float = other._contact_solid(j, uv.y, other_side, other_last)
			if self_solid <= 0.0 or other_solid <= 0.0:
				continue
			var self_radius: float = lerpf(body.widths[i], body.widths[i + 1], uv.x) * self_solid
			var other_radius: float = lerpf(
				other.body.widths[j], other.body.widths[j + 1], uv.y) * other_solid
			var overlap: float = self_radius + other_radius - distance
			if overlap <= deepest:
				continue
			deepest = overlap
			out = normal * overlap
			_contact_spine_t = (float(i) + uv.x) / float(maxi(spine.size() - 1, 1))
	return out


## Translates the pose as one piece and cancels the same shift out of the gait's
## socket-velocity history. Feet may remain planted and naturally take a step,
## but collision correction must not masquerade as a huge burst of locomotion.
func _translate_contact(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	head_pos += offset
	spine.translate(offset)
	bounds_center += offset
	if gait != null:
		for limb in gait.limbs:
			if limb.socket_tracked:
				limb.prev_anchor += offset
	# A carcass's limbs are particles rather than IK targets, so they have to be
	# carried by the same shift. Left behind by one, the length constraints would
	# snap them back into place on the following tick.
	if ragdoll != null and gait != null:
		ragdoll.translate(gait.limbs, offset)


## Tissue reach for one point along a contact capsule. The explicit head cap
## owns the front half of the first interval; the remaining chain uses the
## side-specific torso lattice.
func _contact_solid(segment: int, u: float, side: float, last: int) -> float:
	if segment == 0 and u <= 0.5:
		return anatomy.tissue.head_solid()
	var t: float = (float(segment) + u) / float(maxi(last, 1))
	# At an end cap the contact direction can be parallel to the spine, with no
	# meaningful flank sign. The circular cap reaches as far as its wider side.
	if absf(side) <= CONTACT_EPSILON:
		return maxf(anatomy.tissue.body_solid(t, -1.0),
			anatomy.tissue.body_solid(t, 1.0))
	return anatomy.tissue.body_solid(t, side)


## Closest parameters on two finite line segments, returned as (u, v). This is
## the narrow-phase axis query for the two capsules.
static func _closest_segment_parameters(a0: Vector2, a1: Vector2,
		b0: Vector2, b1: Vector2) -> Vector2:
	var da: Vector2 = a1 - a0
	var db: Vector2 = b1 - b0
	var r: Vector2 = a0 - b0
	var aa: float = da.dot(da)
	var bb: float = db.dot(db)
	var ab: float = da.dot(db)
	var ar: float = da.dot(r)
	var br: float = db.dot(r)
	var u: float = 0.0
	var v: float = 0.0

	if aa <= CONTACT_EPSILON and bb <= CONTACT_EPSILON:
		return Vector2.ZERO
	if aa <= CONTACT_EPSILON:
		return Vector2(0.0, clampf(br / bb, 0.0, 1.0))
	if bb <= CONTACT_EPSILON:
		return Vector2(clampf(-ar / aa, 0.0, 1.0), 0.0)

	var denominator: float = aa * bb - ab * ab
	if denominator > CONTACT_EPSILON:
		u = clampf((ab * br - ar * bb) / denominator, 0.0, 1.0)
	v = (ab * u + br) / bb
	if v < 0.0:
		v = 0.0
		u = clampf(-ar / aa, 0.0, 1.0)
	elif v > 1.0:
		v = 1.0
		u = clampf((ab - ar) / aa, 0.0, 1.0)
	return Vector2(u, v)


## Intersecting/collinear axes have no geometric separation direction. Pick a
## stable normal from the lower-instance-id participant, then orient it away
## from the other centre (or by id when the centres also coincide). Both sides
## consequently choose exact opposites even when their headings are reversed.
func _coincident_contact_normal(other: Creature, a0: Vector2, a1: Vector2,
		b0: Vector2, b1: Vector2) -> Vector2:
	var self_first: bool = get_instance_id() < other.get_instance_id()
	var tangent: Vector2 = (a1 - a0) if self_first else (b1 - b0)
	if tangent.length_squared() <= CONTACT_EPSILON:
		tangent = Vector2.RIGHT
	tangent = tangent.normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	# Canonicalise an unoriented axis so reversed creature headings agree.
	if normal.x < -CONTACT_EPSILON \
			or (absf(normal.x) <= CONTACT_EPSILON and normal.y < 0.0):
		normal = -normal
	var centre_delta: Vector2 = bounds_center - other.bounds_center
	var side: float = centre_delta.dot(normal)
	if absf(side) > CONTACT_EPSILON:
		return normal * signf(side)
	return normal if self_first else -normal


## Collision callback consumed by Gait while it solves a limb. Limbs only react
## to other creatures' bodies: their own torso is already excluded by the gait's
## anatomical swing envelope, and limb-vs-limb contacts would make four light,
## kinematic chains snag one another without a useful notion of mass.
func _limb_contact_push(limb_key: String, limb_segment: int,
		a: Vector2, b: Vector2, radius: float) -> Vector2:
	if not is_inside_tree() or radius <= 0.0:
		return Vector2.ZERO
	var solid: float = anatomy.tissue.limb_solid(limb_key, limb_segment)
	if solid <= 0.0:
		return Vector2.ZERO
	var collision_radius: float = radius * solid
	var midpoint: Vector2 = (a + b) * 0.5
	var capsule_bound: float = a.distance_to(b) * 0.5 + collision_radius
	var deepest: Vector2 = Vector2.ZERO
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.body == null or other.spine == null:
			continue
		if midpoint.distance_to(other.bounds_center) \
				> capsule_bound + other.bounds_radius:
			continue
		var push: Vector2 = other.push_capsule_out_of_body(
			a, b, collision_radius, bounds_center - other.bounds_center)
		if push.length_squared() > deepest.length_squared():
			deepest = push
	return deepest


## Pushes an arbitrary capsule out of this creature's tissue-aware body. Used
## for limb bones and feet, including the mid-segment crossings that a point
## query cannot see. `preferred` resolves the otherwise ambiguous direction
## when the two capsule axes intersect exactly.
func push_capsule_out_of_body(a: Vector2, b: Vector2, radius: float,
		preferred: Vector2 = Vector2.ZERO) -> Vector2:
	if body == null or spine == null or radius <= 0.0:
		return Vector2.ZERO
	var last: int = mini(body.last_index, spine.size() - 1)
	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	for i in range(last):
		var body_a: Vector2 = spine.points[i]
		var body_b: Vector2 = spine.points[i + 1]
		var uv: Vector2 = _closest_segment_parameters(a, b, body_a, body_b)
		var limb_axis: Vector2 = a.lerp(b, uv.x)
		var body_axis: Vector2 = body_a.lerp(body_b, uv.y)
		var delta: Vector2 = limb_axis - body_axis
		var distance: float = delta.length()
		var normal: Vector2
		if distance > CONTACT_EPSILON:
			normal = delta / distance
		else:
			# Prefer the side containing the limb root/owning creature. Projecting
			# onto the body's normal chooses the shortest route out rather than
			# sliding an intersecting bone all the way along the torso.
			var body_normal: Vector2 = spine.perps[i]
			var root_side: float = (a - body_axis).dot(body_normal)
			if absf(root_side) <= CONTACT_EPSILON:
				root_side = preferred.dot(body_normal)
			normal = body_normal * (-1.0 if root_side < 0.0 else 1.0)
		var side: float = normal.dot(spine.perps[i])
		var solid: float = _contact_solid(i, uv.y, side, last)
		if solid <= 0.0:
			continue
		var body_radius: float = lerpf(body.widths[i], body.widths[i + 1], uv.y) * solid
		var overlap: float = radius + body_radius - distance
		if overlap <= deepest:
			continue
		deepest = overlap
		out = normal * overlap
	return out


## How much tissue is still standing around one spine point, as a fraction of
## the width the silhouette would have there. The probe is a circle about the
## axis, so it takes the wider of the two flanks — a body eaten open on one side
## is still as wide as the side that survived.
func _solid_at(i: int, last: int) -> float:
	var tissue: TissueGrid = anatomy.tissue
	if i == 0:
		return tissue.head_solid()
	var t: float = float(i) / float(maxi(last, 1))
	return maxf(tissue.body_solid(t, 1.0), tissue.body_solid(t, -1.0))


## Sheds the part of the forward speed that is driving into a contact.
##
## Position alone is not enough, and the difference is not subtle. Corrected
## only positionally, a creature walking into another keeps walking: it either
## grinds through, or — measured — shoves a stationary creature across the world
## ahead of it at its own full speed, with no resistance at all. Scaling `speed`
## by how squarely the contact opposes travel stops it dead head-on and leaves
## it entirely free to slide along a flank, which is the difference between
## another creature reading as solid and reading as sticky.
##
## Heading is deliberately untouched, so a creature pressed against another can
## always turn away and walk off.
##
## `share` is the fraction of the contact this creature's mass made it responsible
## for, and scaling the brake by it is what gives weight a consequence in motion
## rather than only in position. A heavy creature walking into a light one is
## barely slowed by it and pushes it along ahead of itself; a light one walking
## into a heavy one stops as dead as it always did. At equal masses this is half
## the old rate, which still collapses the speed within a few ticks.
func _brake_into(push: Vector2, share: float) -> void:
	if push == Vector2.ZERO or is_zero_approx(speed):
		return
	var into: float = -(move_dir * speed).normalized().dot(push.normalized())
	if into > 0.0:
		speed = move_toward(speed, 0.0, absf(speed) * into * clampf(share, 0.0, 1.0))


## The displacement that would just lift a circle of `radius` at `at` clear of
## this creature's body, or ZERO if it is already clear.
## Tested against the same chain of variable-radius capsules the view fills, so
## creatures collide with exactly the silhouette that is drawn. Only the deepest
## overlap is returned: consecutive capsules share their end caps, so summing
## them would push out by several times the actual penetration.
##
## Each capsule is narrowed to the tissue that is actually still there, per
## side, so a body eaten open is open: a flank chewed halfway in stops pushing
## at the new surface, and a station eaten clean through stops colliding at all
## and can be walked straight into. Without this the hole would be a hole you
## could see through and not one you could reach through, which is the same
## illusion as painting the ground colour over it.
func push_out_of_body(at: Vector2, radius: float) -> Vector2:
	if body == null or spine == null:
		return Vector2.ZERO
	var last: int = mini(body.last_index, spine.size() - 1)
	var tissue: TissueGrid = anatomy.tissue
	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	for i in range(last):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = AnatomyState.segment_u(at, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var delta: Vector2 = at - axis
		var distance: float = delta.length()
		var side: float = delta.dot(spine.perps[i])
		var solid: float = tissue.body_solid((float(i) + u) / float(maxi(last, 1)), side)
		if solid <= 0.0:
			continue
		var overlap: float = radius + lerpf(body.widths[i], body.widths[i + 1], u) * solid - distance
		if overlap <= deepest:
			continue
		deepest = overlap
		# Dead centre on the axis there is no direction to leave by, so fall back
		# to the flank normal — sideways is the shortest way out of a body that
		# is far longer than it is wide.
		out = (delta / distance if distance > 0.0001 else spine.perps[i]) * overlap
	return out


## Refreshes the broad-phase bounding circle from the pose just solved. Built
## from the body's own cross-sections rather than from arc length, so a coiled
## creature gets a tight bound instead of one sized for a straight one.
func _update_bounds() -> void:
	if spine == null or body == null:
		return
	var last: int = mini(body.last_index, spine.size() - 1)
	var lo: Vector2 = spine.points[0]
	var hi: Vector2 = lo
	for i in range(last + 1):
		var w: float = body.widths[i]
		var at: Vector2 = spine.points[i]
		lo = Vector2(minf(lo.x, at.x - w), minf(lo.y, at.y - w))
		hi = Vector2(maxf(hi.x, at.x + w), maxf(hi.y, at.y + w))
	bounds_center = (lo + hi) * 0.5
	bounds_radius = lo.distance_to(hi) * 0.5


# ------------------------------------------------------------ body space ----
# A grip has to survive the pose being rebuilt from scratch every tick, and a
# structural rebuild on top of that, so it is stored the same way tissue damage
# is: in body space. These three convert between that and the world.

## World position of a point bound into this creature's body space. `bind` is
## (spine_t, lateral), lateral running -1..1 across the local half-width.
##
## Read off the live spine rather than the cached BodyShape frame, so it stays
## truthful inside the contact phase — where the creature may already have been
## translated this tick but the silhouette has not yet been rebuilt around it.
func body_point(bind: Vector2) -> Vector2:
	if spine == null or body == null or body.widths.is_empty():
		return head_pos
	var frame: Spine.Frame = spine.sample(clampf(bind.x, 0.0, 1.0))
	return frame.pos + frame.perp * (bind.y * _width_at(bind.x))


## The inverse: the body-space coordinates of a world point, clamped onto the
## silhouette so jaws closing just outside a flank still bind to the flesh rather
## than to the air beside it.
func body_bind(at: Vector2) -> Vector2:
	if spine == null or body == null or spine.size() < 2:
		return Vector2.ZERO
	var last: int = maxi(mini(body.last_index, spine.size() - 1), 1)
	var span: float = float(maxi(spine.size() - 1, 1))
	var best := Vector2.ZERO
	var best_distance: float = INF
	for i in range(last):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = AnatomyState.segment_u(at, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var d: float = at.distance_squared_to(axis)
		if d >= best_distance:
			continue
		best_distance = d
		var half: float = lerpf(body.widths[i], body.widths[i + 1], u)
		best = Vector2((float(i) + u) / span,
			clampf((at - axis).dot(spine.perps[i]) / maxf(half, 0.001), -1.0, 1.0))
	return best


## How much tissue is still standing where a bind sits, 0 if it has been eaten
## clean through. The lattice indexes the torso over the *clipped* spine while a
## bind runs over the whole chain, so the conversion lives here rather than being
## left loose in two coordinate systems at the call sites.
func bind_solid(bind: Vector2) -> float:
	if spine == null or body == null:
		return 0.0
	var span: float = float(maxi(spine.size() - 1, 1))
	# The same split the contact query uses: the explicit head cap owns the front
	# half of the first interval and the torso lattice owns everything behind it.
	# Without it a hold on the snout is judged by the first *torso* column, which
	# is a different piece of the creature entirely.
	if bind.x * span < 0.5:
		return anatomy.tissue.head_solid()
	var last: float = float(maxi(mini(body.last_index, spine.size() - 1), 1))
	return anatomy.tissue.body_solid(clampf(bind.x * span / last, 0.0, 1.0), bind.y)


## The hit points still standing in the single lattice cell a bind sits in — what
## the flesh in a set of jaws is actually made of, and so what a pull has to part
## to take it away. Split at the snout exactly the way `bind_solid` is, and for
## the same reason.
func bind_hp(bind: Vector2) -> float:
	if spine == null or body == null:
		return 0.0
	var span: float = float(maxi(spine.size() - 1, 1))
	if bind.x * span < 0.5:
		return anatomy.tissue.head_hp(bind.y)
	var last: float = float(maxi(mini(body.last_index, spine.size() - 1), 1))
	return anatomy.tissue.body_hp(clampf(bind.x * span / last, 0.0, 1.0), bind.y)


## World-space reconstruction of a point bound to one of the articulated limb
## primitives reported by AnatomyState. Segment 0 is socket->joint, segment 1 is
## joint->foot, and segment 2 is the foot itself.
func limb_point(key: String, segment: int, u: float) -> Vector2:
	var limb: Limb = _limb_by_key(key)
	if limb == null:
		return head_pos
	match segment:
		0:
			return limb.joints[0].lerp(limb.joints[1], clampf(u, 0.0, 1.0))
		1:
			return limb.joints[1].lerp(limb.joints[2], clampf(u, 0.0, 1.0))
		_:
			return limb.joints[2]


func limb_bind_solid(key: String, segment: int) -> float:
	return anatomy.tissue.limb_solid(key, clampi(segment, 0, 2))


func _limb_by_key(key: String) -> Limb:
	if gait == null:
		return null
	for limb in gait.limbs:
		if limb.key == key:
			return limb
	return null


func _width_at(t: float) -> float:
	var n: int = body.widths.size()
	if n < 2:
		return body.widths[0] if n == 1 else 1.0
	var s: float = clampf(t, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(floor(s)), 0, n - 2)
	return lerpf(body.widths[i], body.widths[i + 1], s - float(i))


## The centre of the jaw volume, in world space — where a bite is tested from and
## where a grip holds from.
##
## Built from the live spine rather than the cached head frame for the same
## reason `body_point` is: a contact or a grip may already have translated the
## creature this tick, and jaws a translation behind the body would drag their
## own hold along with them.
func jaw_point() -> Vector2:
	if spine == null or body == null or body.widths.is_empty():
		return head_pos
	return spine.points[0] \
		+ spine.forwards[0] * (body.widths[0] + params.bite_radius * size_scale * 0.35)


## Head-first collision test used by the food field.
func mouth_radius() -> float:
	return (body.head_radius if body != null else 10.0) + 6.0


func body_length() -> float:
	return spine.arc_length() if spine != null else 100.0


func feed(amount: int = 1) -> void:
	food_eaten += amount
	ate_food.emit(food_eaten)


## Queues one bite for the next solved physics pose. Clicks during an active
## strike or recovery are deliberately discarded rather than buffered, so one
## click always means at most one attack even when cooldown is tuned shorter
## than the lunge animation.
func request_bite(_aim_world: Vector2) -> bool:
	if not alive:
		return false
	if bite_cooldown_remaining > 0.0 or _bite_requested or bite_time >= 0.0:
		return false
	_bite_requested = true
	return true


func can_bite() -> bool:
	return bite_cooldown_remaining <= 0.0 and not _bite_requested and bite_time < 0.0


## Tracks the physical button independently from the one-shot bite request.
## Releasing a connected clamp does not cancel the bite; it simply lets the
## existing animation continue through recovery from the apex.
##
## With a hold in force the button means something else, and this is where the
## difference lives. Jaws already on flesh do not spring open the instant the
## button rises — they part, and a press taken while they are parting closes them
## again on the same bind. So a held button is a grip, working the button is
## chewing, and letting go is letting go.
func set_bite_held(held: bool) -> void:
	# A carcass's jaws are as limp as the rest of it. It can be bitten and held;
	# it cannot bite or hold.
	if not alive:
		return
	if held:
		bite_held = true
		if grip != null and grip.is_alive() and _regrasp_remaining > 0.0:
			_regrasp_remaining = 0.0
			_chew_requested = true
		return
	bite_held = false
	if grip != null and grip.is_alive():
		_regrasp_remaining = GRIP_REGRASP_WINDOW
		return
	_regrasp_remaining = 0.0
	bite_latched = false
	_chew_requested = false
	grip = null
	_grip_lockout = false


## Whether these jaws are shut on something. True through the parting window as
## well as while the button is down: the hold has not ended until the jaws have
## actually opened, and everything downstream — the clamped head, the suspended
## contact pass, the tether — has to agree about when that is.
func is_bite_latched() -> bool:
	return bite_latched and grip != null and (bite_held or _regrasp_remaining > 0.0)


## Whether something else has hold of this creature. Refreshed once per tick, so
## a reader outside the simulation sees the same answer the tick did.
func is_being_gripped() -> bool:
	return _held_by != null and _held_by.is_alive()


# ------------------------------------------------------------------ grip ----

## Takes up this creature's own share of the slack in whatever jaws are involved
## with it — its own, or somebody else's closed on it.
##
## Deliberately the same shape as the contact pass beside it: measure the current
## error, correct this creature by the fraction of it its mass makes it
## responsible for, and never write anything to the other party. Living bodies
## translate as a whole; carcasses accept the correction at the held anatomical
## point. Both sides run this against the same grip, so between them the slack is
## taken up once.
##
## Dragging is not implemented anywhere. It is what this does when the masses are
## uneven: the light body gets nearly the whole correction and is towed along
## behind jaws that barely move.
func _resolve_grip() -> void:
	if spine == null or body == null:
		return
	if grip != null:
		if not grip.is_alive():
			_release_grip()
		else:
			# Measured before either party moves, and only by the owner, so the load
			# the jaws are carrying is one number from one source rather than two
			# halves of a correction added up out of order.
			grip.tension = grip.slack().length()
			_take_up_slack(grip, grip.victim, 1.0)
	if _held_by != null and _held_by.is_alive():
		_take_up_slack(_held_by, _held_by.biter, -1.0)


## Whether a set of jaws — either creature's — currently joins this pair.
func _is_joined_to(other: Creature) -> bool:
	if grip != null and grip.victim == other:
		return true
	return _held_by != null and _held_by.biter == other


## `direction` is +1 for the biter, whose jaws move onto the flesh, and -1 for the
## victim, whose flesh is pulled back into the jaws.
func _take_up_slack(held: Grip, other: Creature, direction: float) -> void:
	var slack: Vector2 = held.slack()
	if slack == Vector2.ZERO:
		return
	var offset: Vector2 = slack.limit_length(MAX_CONTACT_PUSH) \
		* _contact_share(other) * direction
	if alive:
		_translate_contact(offset)
	else:
		_drag_grip(held, offset)


## Applies a tether correction to the anatomical structure in the jaws. Torso
## holds enter the free spine directly. Limb holds first articulate the particles
## on that bone; only the socket's share and any pull beyond the chain's maximum
## reach pass into the spine, so a foot folds and straightens before it tows the
## whole carcass.
func _drag_grip(held: Grip, offset: Vector2) -> void:
	if not held.holds_limb() or ragdoll == null or gait == null:
		_drag_at(held.anchor(), offset)
		return
	var limb: Limb = _limb_by_key(held.limb_key)
	if limb == null:
		_drag_at(held.anchor(), offset)
		return

	var socket_share: Vector2 = ragdoll.haul(
		gait.limbs, held.limb_key, held.limb_segment, held.limb_u, offset)
	if socket_share != Vector2.ZERO:
		_drag_at(limb.joints[0], socket_share)

	var max_reach: float
	match held.limb_segment:
		0:
			max_reach = limb.lengths[0] * held.limb_u
		1:
			max_reach = limb.lengths[0] + limb.lengths[1] * held.limb_u
		_:
			max_reach = limb.total_length
	var reach: Vector2 = held.anchor() - limb.joints[0]
	var distance: float = reach.length()
	if distance > max_reach and distance > 0.0001:
		_drag_at(limb.joints[0], reach * ((distance - max_reach) / distance))


## Takes up a pull on a carcass where the pull actually acts, and lets the free
## chain carry it the rest of the way.
##
## A living creature answers the same correction with `_translate_contact`, which
## moves the whole body as one rigid piece. That is not a stylistic choice there:
## its head is placed by input and re-pinned every tick, so a correction applied
## halfway down the spine is unpicked by the very next solve and the disagreement
## comes back out as flailing. Nothing re-pins this one — every point of it is
## simulated — so the honest thing is also the available one, and a body dragged
## by the jaws trails behind them instead of sliding after them in formation.
##
## Feathered over the neighbouring stations rather than applied to the single
## nearest particle, so it enters the chain as a haul on a region of flesh; a tug
## on one point is something the distance constraint then spends the next several
## ticks undoing. It is deliberately *not* normalised — the station the jaws are
## on takes the whole correction, because that is the one the tether measures its
## slack from, and the rest of the body is brought along by the constraint solve
## over the ticks that follow. That lag is the trailing.
func _drag_at(at: Vector2, offset: Vector2) -> void:
	if offset == Vector2.ZERO or spine == null:
		return
	var n: int = spine.size()
	var nearest: int = 0
	var best: float = INF
	for i in n:
		var d: float = spine.points[i].distance_squared_to(at)
		if d < best:
			best = d
			nearest = i
	for i in n:
		var weight: float = pow(DRAG_FALLOFF, absf(float(i - nearest)))
		if weight < 0.02:
			continue
		spine.haul(i, offset * weight)
	head_pos = spine.points[0]


## The consequences of the hold, resolved against the pose that has just been
## solved: what the jaws are carrying, whether they can still carry it, and
## whether they have come round to close again.
func _advance_grip(delta: float) -> void:
	if grip == null:
		return
	if not grip.is_alive() or not (bite_held or _regrasp_remaining > 0.0):
		_release_grip()
		return

	# Load, in the same currency as bite force. Two terms, and only two.
	#
	# Reduced mass is what a tether between two free bodies actually has to
	# restrain. It is dominated by the *lighter* of the pair, which is why holding
	# something small is easy however hard it fights, why being the small one and
	# holding something large is where jaws come off, and why a real contest only
	# happens between near-equals. Its root rather than itself, because the jaws
	# get a proportionally bigger hold of a bigger body at the same time as the
	# body becomes harder to hold: purchase grows with the flesh in them.
	#
	# Separation speed is how fast the two are actually coming apart — measured,
	# not intended, so a creature towed along quietly loads the jaws with nothing
	# and one thrashing on the spot loads them with everything. This is why a
	# grip is escaped by turning: heading is the one thing a load never slows.
	var mine: float = physique.mass
	var theirs: float = grip.victim.physique.mass
	var purchase: float = sqrt(mine * theirs / maxf(mine + theirs, 0.0001))
	var separation_speed: float = grip.tension / maxf(delta, 0.0001)
	var instant: float = purchase * separation_speed / GRIP_LOAD_REFERENCE
	grip.load = lerpf(grip.load, instant, 1.0 - exp(-GRIP_LOAD_RESPONSE * delta))

	# The mouthful the jaws were holding has come away. They take hold of the
	# surface it left behind rather than opening, and only let go when there is
	# nothing within them to hold at all.
	if grip.bind_is_hollow() and not _regrip():
		_release_grip(true)
		return

	if grip.load > physique.bite_force:
		_tear_free()
		return

	# A chew: the jaws opening and shutting once on what they are already holding.
	# It is an action taken, never a clock — holding on is holding on, and the only
	# thing that turns a hold into a wound by itself is the pull below. Routed
	# through the ordinary world resolver, so a chew sheds meat, picks its target
	# and reports a miss exactly the way the opening bite does.
	if _chew_requested:
		_chew_requested = false
		if _chew_cooldown <= 0.0:
			_chew_cooldown = maxf(params.chew_interval, 0.05)
			bite_started.emit(jaw_point(), params.bite_radius * size_scale)

	# The flesh's own half of the contest — see the tearing constants above. The
	# pull either sits inside what the tissue will take, in which case it holds
	# indefinitely, or it works it: drawing the meat out of the body, and given
	# long enough parting it. Stress is spent as fast as it is earned once the
	# struggling stops, so this is a consequence of force over time and never of
	# the button being down.
	var overload: float = grip.load / maxf(grip.tissue_strength(), 0.0001)
	if overload > TEAR_YIELD:
		grip.stress = minf(grip.stress + (overload - TEAR_YIELD) * delta / TEAR_WORK, 1.0)
	else:
		grip.stress = maxf(grip.stress - TEAR_RELAX * delta, 0.0)
	if grip.stress >= 1.0:
		_tear_out()


## How deep one closing of these jaws drives, in the tissue lattice's hit points.
##
## Full `bite_damage` for a free strike, which is what every bite in the game was
## until now. A latched one spends part of its force simply staying shut, so what
## is left to cut with falls away as the load rises.
##
## A tear is not a closing of the jaws at all and is not priced as one: what
## comes away is however much meat parted from the body, not however much these
## jaws could cut.
func bite_depth() -> float:
	if _tearing:
		return TEAR_DEPTH
	var strain: float = grip.strain() if grip != null and grip.is_alive() else 0.0
	return params.bite_damage \
		* clampf(1.0 - strain * CHEW_STRAIN_COST, CHEW_MIN_DEPTH, 1.0)


## Re-seats jaws whose mouthful has come away, on the surviving flesh inside
## them. Returns false when there is none, which is the one way chewing ends by
## succeeding.
##
## Without this a strong bite would *lose* its grip faster than a weak one: the
## better it chews, the sooner the cell it was bound to is gone. Re-seating is
## what turns a latch into chewing in — the wound deepens under jaws that stay
## shut, rather than the hold ending the moment it works. It is routed through
## the same anatomy query the world bites with, so what the jaws can find hold of
## is exactly what they could find to bite.
func _regrip() -> bool:
	if grip == null or not grip.is_alive():
		return false
	var jaw: Vector2 = jaw_point()
	var reach: float = params.bite_radius * size_scale * GRIP_GAPE
	var victim: Creature = grip.victim
	var best := Vector2.ZERO
	var best_distance: float = INF
	for k in REGRIP_STATIONS + 1:
		var t: float = float(k) / float(REGRIP_STATIONS)
		for lateral in REGRIP_LATERALS:
			var candidate := Vector2(t, lateral)
			# The same two questions the hold itself asks — does the body still
			# reach here, and is there anything in the cell — so jaws can never
			# re-seat onto a place they would immediately report as empty.
			if victim.bind_solid(candidate) <= 0.0 or victim.bind_hp(candidate) <= 0.0:
				continue
			var d: float = jaw.distance_to(victim.body_point(candidate))
			if d < best_distance:
				best_distance = d
				best = candidate
	if best_distance > reach:
		return false
	grip.bind_body(best)
	grip.rest_length = best_distance + GRIP_SLACK
	return true


## Jaws pulled off the flesh they were holding. They do not simply open — they
## take a mouthful with them, resolved through the same world path as any other
## bite so a tear sheds meat and opens tissue like one.
func _tear_free() -> void:
	var at: Vector2 = grip.anchor()
	_release_grip(true)
	bite_started.emit(at, params.bite_radius * size_scale)


## The flesh gave before the jaws did: the piece they were holding parts from the
## body and comes away in them.
##
## Centred on the anchor rather than on the jaws, because what is being removed is
## the meat that tore and not the volume the teeth occupy — under load the two
## have visibly drawn apart, which is the whole point of the stretch. Resolved
## through the same world path as every other closing of these jaws so a tear
## sheds, damages and reports identically; only its depth differs, and only
## because it is measured in flesh rather than in bite force.
##
## The jaws stay shut afterwards. They are re-seated on whatever is left inside
## them, exactly as they are when a mouthful is chewed away, so tearing deepens a
## wound instead of ending the hold that made it.
func _tear_out() -> void:
	grip.stress = 0.0
	var at: Vector2 = grip.anchor()
	_tearing = true
	bite_started.emit(at, params.bite_radius * size_scale)
	_tearing = false
	if grip != null and grip.bind_is_hollow() and not _regrip():
		_release_grip(true)


## `lost` marks a grip that ended by itself rather than by the button coming up.
## Jaws that were pulled off cannot silently take hold again while the button is
## still down: a bite is one press, and that has to stay true of the hold as well
## as of the strike.
func _release_grip(lost: bool = false) -> void:
	grip = null
	bite_latched = false
	_regrasp_remaining = 0.0
	_chew_requested = false
	_grip_lockout = lost


## The grip somebody else has on this creature, or null. Walks the creature group
## the same way the contact pass does, because the alternative — the biter
## registering itself on its victim — is precisely the cross-creature write the
## whole tick order is built to avoid.
func _find_grip_on_self() -> Grip:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.grip == null:
			continue
		if other.grip.victim == self and other.grip.is_alive():
			return other.grip
	return null


## How much of its own locomotion this creature keeps with something on the other
## end of a set of jaws — its own jaws, or the ones holding it.
##
## Force over load, in the currency the physique already works in: a creature can
## pull with `strength`, and a grip adds the whole of another body to what that
## strength has to move. Because strength goes as mass^(2/3) while the load goes
## as mass, this is the square-cube law arriving exactly where it matters — a
## Komodo tows a Gecko without noticing, a Gecko latched onto a Komodo can barely
## walk, and neither case needed a rule written for it.
##
## `speed_norm` is deliberately still measured against the *unhauled* top speed,
## so a creature straining against a load takes short shuffling strides and its
## undulation dies down. Effort reads off the gait for free.
func _haul_factor() -> float:
	var towed: float = 0.0
	if grip != null and grip.is_alive():
		towed += grip.victim.physique.mass
	if _held_by != null and _held_by.is_alive():
		towed += _held_by.biter.physique.mass
	if towed <= 0.0:
		return 1.0
	return clampf(physique.strength / (physique.strength + towed * HAUL_COST),
		HAUL_FLOOR, 1.0)


## Pure query used by the world combat resolver so only the closest creature is
## damaged when several procedural bodies overlap the same bite volume.
func query_bite(center: Vector2, radius: float) -> AnatomyState.Hit:
	return anatomy.hit_test(self, center, radius)


## Erodes this creature's tissue lattice wherever the bite circle covers it,
## and hands whatever came loose to the world.
func apply_bite(center: Vector2, radius: float, depth: float) -> float:
	var shed: Array = []
	var removed: float = anatomy.apply_bite(center, radius, depth, shed)
	if removed <= 0.0:
		return 0.0
	tissue_damaged.emit(anatomy.tissue.integrity())
	if not shed.is_empty():
		tissue_shed.emit(shed, center)
	return removed


## Called by the world after it has selected and damaged (or failed to find) a
## target, so the jaws know what they closed on.
##
## Also where a hold begins and ends, because a hold is exactly "the jaws found
## flesh and the button is still down". A chew routes through here too: the grip
## already knows its victim, so what the resolver adds is the one thing it cannot
## know for itself — whether there was still anything there to bite.
func resolve_bite(connected: bool, target: Creature = null, hit: AnatomyState.Hit = null) -> void:
	bite_connected = connected
	if grip != null:
		# A chew that closes on nothing is a chew that closes on nothing, and the
		# same goes for a tear. Neither ends the hold: what the jaws have hold of is
		# the bind, and the only things that end that are the flesh under it being
		# gone with nothing left to re-seat on, the load pulling them off, and the
		# jaws being given long enough to open.
		return
	if not (connected and bite_held) or target == null or _grip_lockout:
		bite_latched = false
		return
	_form_grip(target, hit)


## Closes the jaws on a specific creature and records where.
##
## The bind comes off the hit's own surface point when there is one, because the
## hit test is the world's answer to *what did these jaws close on* — it already
## knows which structure was reached and has already discounted tissue that is no
## longer there. The jaw centre is only the fallback.
func _form_grip(target: Creature, hit: AnatomyState.Hit) -> void:
	if target == null or target.spine == null or target.body == null:
		return
	var jaw: Vector2 = jaw_point()
	var held := Grip.new()
	held.biter = self
	held.victim = target
	if hit != null and hit.kind == AnatomyState.LIMB:
		held.bind_limb(hit.limb_key, hit.limb_segment, hit.limb_u)
	else:
		held.bind_body(target.body_bind(hit.world_point if hit != null else jaw))
	# Rest length is the gap the jaws actually closed at, plus their own play. A
	# fresh grip is therefore already satisfied and pulls nothing: it exists to
	# take up slack that appears *after* it, which is what stops it wrestling the
	# contact pass holding the two bodies apart at that same point, and what keeps
	# a biter's own spine settling under a clamped head from towing it forward.
	held.rest_length = jaw.distance_to(held.anchor()) + GRIP_SLACK
	grip = held
	bite_latched = true
	# The strike that took hold was itself one closing of these jaws, so the next
	# one waits out the same interval a chew does.
	_chew_cooldown = maxf(params.chew_interval, 0.05)


## The hit frame. Announces the jaw volume at full extension and lets the world
## resolve it against every creature in it.
func _strike() -> void:
	if body == null:
		return
	# The body is head-driven, so the truthful jaw direction is the solved head
	# frame; allowing the click vector to bypass it would make the creature bite
	# sideways before its visible head has reached the cursor.
	bite_started.emit(jaw_point(), params.bite_radius * size_scale)
