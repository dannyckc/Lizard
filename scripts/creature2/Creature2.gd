## The v2 creature as it stands in the lab: one armature, one census, one weight.
##
## Deliberately thin. The corpus owns the anatomy, the armature owns the physics,
## poise carries the one into the other (baked node masses in, posed centre of mass
## out), and the attitude says which of its own stances the body is in. What this
## file owns is the ordering — the sequence below is the whole of it:
##
##   census → stance → the chain settles → the body is carried → the limbs are
##   solved → the weight is posed and checked against the feet → the skin.
##
## **The locomotion is the loop in `motion/Travel.gd`** — intent → desired
## velocity → delivered acceleration → the body shifts → the legs support and
## rebalance → the physical result → repeat. This file only sequences it into
## the tick; `travel` and its stages own every decision, and they write the
## same seam the phase-3 reopening left behind:
##
##   * `command` is written every tick by the lab and read by the intent. It is
##     what is being *asked* of the animal; what it gets is what the loop
##     delivers.
##   * `speed`, `speed_norm`, `ang_vel`, `heading`, `move_dir` and `head_pos`
##     are the mover's publications: the armature's lateral wave and the
##     attitude's hysteresis are quoted against `speed_norm`, and the chain
##     follows `head_pos` because the head is the one point that is placed
##     rather than solved.
##   * `armature.fore_carry`/`hind_carry` and the limbs' `foot_target`/
##     `socket_rise`/`foot_driven`/`grounded` are Footwork's: the girdles ride
##     at what the planted feet actually deliver, and a foot is a world-fixed
##     anchor until the body's own motion demands it step.
##
## The flesh is drawn by `Likeness`, a child node reading `contour` — the skin,
## posed at the end of the tick once every bone has been placed. What *this* node
## draws is the solved skeleton itself, and only when `debug` is set: sticks at
## their bone radii, feet where they are standing, a shadow under whatever is off
## the ground, and the plumb line against the support the feet actually make. A
## debug view, but an honest one — every mark is state the systems put somewhere.
class_name Creature2
extends Node2D

## Where a body is drawn against the others. One band for everything alive, and
## one above it for an animal with its jaws in something — see `_physics_process`.
const BAND: int = 10
const BAND_BITING: int = 11

const INK := Color(0.16, 0.15, 0.13)
const LIMB_INK := Color(0.35, 0.33, 0.30)
const SHADOW := Color(0.0, 0.0, 0.0, 0.10)
const FOOT := Color(0.72, 0.34, 0.18)
const PLUMB := Color(0.18, 0.42, 0.65)
const SUPPORT := Color(0.18, 0.42, 0.65, 0.25)
## How much a node's height lightens its ink — enough to read a carried neck
## against a dropped tail without pretending the top-down view has a horizon.
const HEIGHT_LIFT: float = 0.006


## What is being asked of the animal this tick. The lab writes it from the
## keyboard; nothing in the body cares where it came from — and, until the
## locomotion is rewritten, nothing in the body reads it either.
class Command extends RefCounted:
	var throttle: float = 0.0
	var turn: float = 0.0
	var sprint: bool = false
	var jump: bool = false
	## Where the cursor is, and whether it is saying anything. Purely aim: the
	## head tracks it and — through `Gaze.lead` — the walk follows the head, but
	## nothing device-specific reaches the body and no other axis is touched, so
	## an animal crossing the paddock while the pointer is over a slider keeps
	## going exactly where it was pointed.
	var aim_world: Vector2 = Vector2.ZERO
	var aim_active: bool = false


@export var body: BodySpec
## Draws the skeleton over the flesh — the state, rather than the animal.
@export var debug: bool = false
## Where this body is built, and facing where. Read once, at `_ready`, and kept
## by the armature as the spawn a reset returns to.
@export var spawn_position: Vector2 = Vector2.ZERO
@export var spawn_heading: float = 0.0

var armature: Armature = Armature.new()
var corpus: Corpus = Corpus.new()
var contour: Contour = Contour.new()
var poise: Poise = Poise.new()
var attitude: Attitude = Attitude.new()
var command: Command = Command.new()
var travel: Travel = Travel.new()
## What keeps it alive, and the jaws it defends that with. The vitals are the
## consequences of wounds (blood, the heart — death is a stopped heart); the
## maw is the whole strike pipeline.
var vitals: Vitals = Vitals.new()
var maw: Maw = Maw.new()
## Where the animal is looking. The cursor's half of the controls: it carries
## the head round, it leads the walk, and the strike is thrown along it.
var gaze: Gaze = Gaze.new()

# ------------------------------------------------------------------- aim ----
# What this creature has been pointed at, and what its jaws make of it. Written
# from outside — the world resolves a cursor into one target and hands it over —
# because which of the several things under a pointer was meant is a question
# about the world rather than about any one animal in it.

## The selected target: which flesh of which body, or bare ground. Null when
## nothing has been pointed at, which is the state every line downstream falls
## back to and behaves exactly as it did before aiming existed.
var aim: Quarry.Pick = null
## Whether the jaws can be got onto it and, when they cannot, why not — `Maw.
## aim`'s answer, re-asked every tick because both halves of it move.
var aim_reach: Dictionary = {}
## Where the aimed flesh is, on the plan: the point the mouth is sent to and the
## point the head is pointed at, so where the animal looks, where the teeth
## arrive and where the damage lands are one place.
var aim_contact: Vector2 = Vector2.ZERO
## Whether the button is down. A held button is a grip, and letting go is
## letting go — see `Maw.hold`.
var bite_held: bool = false

## Where the head is being led, and on what bearing. The body follows it: the head
## is the one point on the chain that is placed rather than solved. With no mover
## these hold wherever the build or a mouse drag left them.
var head_pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var move_dir: Vector2 = Vector2.RIGHT
## How fast the body is travelling, and that as a share of `cruise_speed`. Written
## by the locomotion, and read by the wave and the stance hysteresis — both of
## which honour zero correctly, which is why a body with no mover is simply a
## still one rather than a broken one.
var speed: float = 0.0
var speed_norm: float = 0.0
var ang_vel: float = 0.0
var alive: bool = true

var terrain: Terrain


func _ready() -> void:
	if body == null:
		body = load("res://scripts/creature2/CatBody.tres")
	# Over the terrain, which draws at 1: an animal standing behind a boulder is
	# behind it because of where its feet are, never because the rock was painted
	# afterwards. v1's CreatureView holds the same band for the same reason.
	z_index = BAND
	# Every living body in the lab presses on every other — the group is the
	# contact stage's roster (Clash).
	add_to_group("creatures2")
	terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	build(spawn_position, spawn_heading)


## Builds every structure in the one order they may be built in: the stance first
## (the census reads the stance the animal is *built* in), then the chain, then the
## census, then the reductions that read it.
func build(at: Vector2, p_heading: float) -> void:
	attitude.rebuild(body)
	armature.build(body, at, p_heading)
	corpus.build(body)
	poise.bake(corpus, armature)
	attitude.derive(poise)
	contour.build(corpus, armature)
	contour.pose()
	head_pos = armature.plan(armature.head_index())
	heading = p_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	speed = 0.0
	speed_norm = 0.0
	ang_vel = 0.0
	armature.take_head(head_pos)
	travel.build(self)
	_measure()
	vitals = Vitals.new()
	maw.build(self)
	gaze.build(self)
	aim = null
	aim_reach = {}
	aim_contact = Vector2.ZERO
	bite_held = false


## The weight, against the feet, right now. Every tick ends with this (below),
## and so must every jump the body makes outside a tick: a build, a reset, a
## revival. The loop's stages read the *last* measurement — that is what a
## control loop does — so a body that has just been put somewhere else with the
## old numbers still standing would spend its first tick balancing against feet
## it no longer has, and the attitude would have it over before Poise caught up.
func _measure() -> void:
	poise.pose(armature)
	poise.stand(armature)


func _physics_process(delta: float) -> void:
	# The consequences first: open vessels drain whether or not anything else
	# happens this tick, and a heart that stops stops the animal — however it
	# stopped, and whoever noticed first.
	vitals.tick(delta)
	if vitals.arrested and not armature.collapsed:
		armature.collapse()
		maw.release()
	alive = not armature.collapsed and not vitals.arrested
	# The bake is revision-keyed: an ordinary tick bakes nothing, a wound re-bakes
	# once and the weight genuinely moves.
	poise.bake(corpus, armature)

	var airborne: bool = armature.fall.is_airborne()
	attitude.tick(delta, speed_norm, command.sprint, airborne)
	# The rig reads its stand preferences off the posture actually being
	# carried, so a blending stance folds the limbs the way it holds them.
	armature.rig.carriage = attitude.active

	# Where the animal is looking, before the mover reads it: the bearing the
	# steering leads on and the bearing the neck is swept to have to be the same
	# one, or the head would be chasing a turn it caused. What it measures itself
	# against is last tick's solved shoulders — the neck being clamped is part of
	# the pose being solved, and there is no ordering that avoids that.
	gaze.tick(delta)

	var ground: float = _ground_under(armature.centre(), body.trunk_length * 0.25)

	# The fall's floor, in the frame the carries quote: while the body is
	# airborne the ground it is over may not be the ground it took off from,
	# and the arc has to end on the one it is actually over. Grounded (or
	# collapsed, where the carries say nothing) the feet are the frame and the
	# floor is simply 0.
	var fall_floor: float = 0.0
	if airborne and not armature.collapsed:
		fall_floor = ground - travel.footwork.frame_ground()

	# The loop's front half: intent → velocity → the head is carried. Before the
	# plan solve, so the chain follows this tick's motion.
	travel.steer(delta, ground)
	if not armature.collapsed:
		armature.take_head(head_pos)
	armature.advance(delta, fall_floor, speed_norm, attitude.active.wave_gain)
	# The world's solid half presses back: an intrusion changes the body's real
	# position, velocity and turn rate, and everything after reacts to that.
	travel.collide()
	# ...and the world's living half, through the same seams: other bodies
	# press this one out, and this one's jaws do whatever they are doing —
	# both positional changes the support has not answered yet.
	Clash.press(self)
	maw.tick(delta)
	# The attitude, once both contact stages have landed whatever they landed:
	# the body's weight against the feet it is standing on, plus the twists the
	# presses came with. Before the vertical, because how far over the body is
	# being held is a term in how high it is being held.
	travel.tip(delta)
	# The sockets have moved; now the feet answer — the legs support and
	# rebalance, and the carries become a measurement of the planted feet.
	travel.support(delta, ground)
	# ...and only now the vertical, because how high the body is held is a
	# measurement of the feet the support just made.
	armature.carry(ground)
	travel.perch()
	armature.settle(delta, ground)

	poise.pose(armature)
	poise.stand(armature)
	# The physical result, reviewed: a weight over its edge demands rescue
	# steps; one past rescue falls, and next tick's loop starts from that.
	travel.review(delta)
	# ...and the loop written down, for whatever is watching it. Last, so what is
	# recorded is the tick as it finished, and free while nothing is looking.
	travel.observe(delta)
	# ...and last of all the skin, over bones that have finished moving. Nothing
	# reads back from it, which is why it can be last: the flesh is a consequence
	# of the tick, never a term in it.
	contour.pose()
	# ...and where this body is painted against the others. An animal with its
	# jaws in another one is in front of it, because that is where its head
	# actually is: over the back for a bite from above, inside the flank for one
	# from the side. Two bodies alive on the same floor are otherwise the same
	# band and the picture settles them by nothing better than which was added to
	# the scene first, so a bite painted the other way round hides the mouth
	# behind the mouthful — the one thing the player has to be able to see.
	var band: int = BAND_BITING if maw.lunging() or maw.latched() else BAND
	if z_index != band:
		z_index = band
	# The aim, re-read off the skin that has just been posed: the flesh under the
	# cursor moved with the body it belongs to, so the point the head is tracking
	# and the reach it is priced at are both a tick old the moment they are not
	# re-asked. Held as an address rather than a place, exactly as a latched
	# mouth is, which is why a walking target stays selected.
	_update_aim()
	queue_redraw()


## What the locomotion loop decided this tick, and what it has been deciding —
## the one seam anything watching the mover reads (`MotionReadout`). Assembled by
## `Travel`, which is already the only writer of the published motion state, so a
## panel never reaches into `Footwork`, `Rhythm`, `Poise` or `Keel` and can never
## hold a second opinion about a body that has one.
##
## Inert until something calls `watch(true)` on it: the loop pays for the reading
## only while it is being read.
func motion_readout() -> MotionReadout:
	return travel.readout


## The speed this creature walks at flat out without sprinting — the denominator
## every pace in the game is quoted against. Deliberately the request: delivery
## has no closed form in the new loop (it emerges from press, drift and swing
## tempo), so the ask is the stable ruler and `speed_norm` reports honestly
## against it — a body whose legs cannot keep up simply never reaches 1.
func cruise_speed() -> float:
	return maxf(body.move_speed, 1.0)


## The speed it would travel at with everything open — deliberately the request
## alone, where `cruise_speed` takes the lower of the two once there are legs to
## take it against. Effort has to mean the same thing from one tick to the next.
func flat_out() -> float:
	return maxf(body.move_speed * body.sprint_multiplier, 1.0)


func centre() -> Vector2:
	return armature.centre()


func reset() -> void:
	# The reset is the lab's do-over: whatever killed the body on the last
	# run — a fall the review gave up on, a stopped heart — is undone with
	# the pose, or the next tick would knock the restored body straight
	# back down.
	vitals.revive()
	maw.release()
	bite_held = false
	aim = null
	aim_reach = {}
	gaze.reset()
	armature.reset()
	head_pos = armature.plan(armature.head_index())
	heading = armature.spawn_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	speed = 0.0
	speed_norm = 0.0
	ang_vel = 0.0
	if not armature.collapsed:
		armature.take_head(head_pos)
	travel.reset()
	_measure()
	contour.pose()


func toggle_collapsed() -> void:
	if armature.collapsed:
		# The lab's revival restarts the heart as well as the legs — a body
		# stood back up around a stopped heart would fall inside a second.
		vitals.revive()
		armature.revive()
		head_pos = armature.plan(armature.head_index())
		armature.take_head(head_pos)
		travel.reset()
		_measure()
	else:
		# The same collapse a death is: the K key stops the heart, because a
		# body on the floor with nothing wrong with it is not what the
		# carcass bay is for.
		vitals.arrested = true
		armature.collapse()
		maw.release()
	alive = not armature.collapsed and not vitals.arrested


func drop(height: float) -> void:
	armature.drop(height)


## Runs the body forward on its own, off the frame clock — the same tick, taken
## by hand. What a carcass needs to be *already* dead when the scene opens rather
## than dying through its first second of it, and what a probe needs to advance a
## creature it is not displaying.
func simulate(seconds: float) -> void:
	var step: float = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	for _i in int(maxf(seconds, 0.0) / step):
		_physics_process(step)


## An external force, arriving as the plan velocity it imparted and — where the
## caller knows it — the place it landed. The seam a charge, a collision or a
## knock pushes through. Physics is not overridden: the state changes here, and
## the loop recovers from it or fails to.
##
## `at` is a world point in three dimensions, and its height is the whole
## difference between a body shoved along and a body rolled over: the lever is
## the contact's height above the animal's own weight. Left out, the push acts
## through the weight and does nothing to the attitude.
func shove(dv: Vector2, at: Vector3 = Vector3.INF) -> void:
	travel.shove(dv, at)


## The rotational half of the same seam: an external twist, as the turn rate
## it caused. A glancing charge is a shove and a spin together.
func spin(dw: float) -> void:
	travel.spin(dw)


## The body pressed bodily out of something solid — a wall, another animal. The
## armature moves and the mover's own anchor goes with it, so the head is carried
## along by the body it sits on.
##
## Unless the teeth are in something, and then the head stays exactly where they
## are and the neck bends instead. A grip is held on by flesh, not by posture: the
## chest being pressed off the animal the mouth has hold of is the ordinary case,
## and it is what a neck is *for*. Without this a bite taken from above cannot
## exist at all — the head has to be over the target at a moment when the body
## certainly cannot be, and the very contact that keeps the body out would drag
## the mouth out along with it.
func press_out(push: Vector2) -> void:
	armature.shift(push)
	if not maw.latched():
		head_pos += push


## Asks the jaws whether flesh at `at` on `target` is takeable from here —
## the hover's preview, commitment-free.
func aim_bite(target: Creature2, at: Vector2) -> Dictionary:
	return maw.aim(target, at)


## Commits the strike: the lunge is the body moving, the jaws close on where
## the flesh actually is, and `latch` keeps the hold for towing and feeding.
func bite(target: Creature2, at: Vector2, latch: bool = false) -> bool:
	return maw.strike(target, at, latch)


# ------------------------------------------------------------------- aim ----

## Points this creature at something. The world resolves a cursor into one
## target — which flesh of which body, or bare ground — and hands it over; what
## the animal makes of it is everything below.
##
## Null clears it, which is what happens when nothing is being pointed and what
## every line downstream treats as "no target", behaving exactly as this file did
## before it could be aimed.
func aim_at(target: Quarry.Pick) -> void:
	aim = target
	_update_aim()


## One tick of being pointed at something.
##
## The reach is re-solved every tick, because both the animal and its target are
## moving and an answer from last tick is an answer about somewhere neither of
## them is. That much is unconditional, and it is *all* that happens while the
## player is merely pointing: a hover asks a question about the world and the
## answer is drawn, not performed. An animal that lowered itself toward every
## pixel the cursor passed over would be reading the mouse rather than hunting,
## and a body that had already crept into position before the button went down
## takes the drama out of pressing it. The click is what commits — and what the
## body then spends is the maw's throw and its carry, both of them measured.
func _update_aim() -> void:
	if aim == null:
		aim_reach = {}
		return
	if aim.creature != null and aim.creature.contour != null \
			and not aim.contact.is_empty():
		# The flesh, not the pixel: the address the cursor landed on is followed
		# through the target's own pose, so a selected shin stays the same shin
		# while its owner walks.
		var flesh: Vector3 = aim.creature.contour.place(aim.contact["band"],
			aim.contact["t"], aim.contact["theta"])
		aim.at = Vector2(flesh.x, flesh.y)
		aim.height = flesh.z
		aim.seen = Contour.seen(flesh)
	aim_contact = aim.at
	# The address goes with the point. Which *surface* of the target was pointed
	# at is a fact only the picture could supply, and dropping it here is what
	# made a bite at a back and a bite at the flank under it the same bite: the
	# jaws would re-derive their own address from the plan coordinate at mouth
	# height and always land between the two.
	aim_reach = maw.aim(aim.creature, aim.at, aim.contact) \
		if aim.creature != null else {}


## Whether the jaws could be got onto whatever this creature is pointed at.
##
## True with nothing selected, because an animal with no target has not been
## refused anything — a bite thrown at nothing in particular is still a bite.
## False for a pointer the world has already found to be outside the bite zone,
## which is the one case where there is no target *because* it could not be
## reached, and reading that as "nothing was refused" would draw the refusal as
## a hit.
func can_reach_aim() -> bool:
	if aim == null:
		return true
	if aim.outside:
		return false
	return aim.creature == null or bool(aim_reach.get("ok", false))


# ------------------------------------------------------------------ bite ----

## One click: a strike thrown at whatever the cursor is on.
##
## Thrown at the selected target when there is one and at the bare point when
## there is not, and thrown either way — the reach decides how it *goes*, never
## whether it goes. Presses during a strike or its recovery are discarded rather
## than buffered, so one click is always at most one attack.
func request_bite(at: Vector2) -> bool:
	if not alive:
		return false
	var target: Creature2 = aim.creature if aim != null else null
	var point: Vector2 = aim_contact if target != null else at
	# ...and the flesh, as an address, so the strike goes to the surface that was
	# clicked rather than to the nearest one to it — see `_update_aim`.
	return maw.strike(target, point, bite_held,
		aim.contact if target != null else {})


## Tracks the button. Held is a grip: jaws that close while it is down keep what
## they closed on, and go on working — a latched mouth chews. Letting go is
## letting go, at once, whether the mouth is on flesh or still on its way.
func set_bite_held(held: bool) -> void:
	# A carcass's jaws are as limp as the rest of it. It can be bitten and held;
	# it cannot bite or hold.
	if not alive and held:
		return
	bite_held = held
	maw.hold(held)


## Whether these jaws are shut on something.
func is_bite_latched() -> bool:
	return maw.latched()


## True while a strike is playing, at any phase.
func is_lunging() -> bool:
	return maw.lunging()


func pick_node(world: Vector2, radius: float) -> int:
	return armature.pick_node(to_local(world), radius)


func haul_node(i: int, world: Vector2) -> void:
	armature.haul_to(i, to_local(world))


# ---------------------------------------------------------------- the ground ----

## What is under a point — the one ground read anything outside the body takes
## of the world this creature is standing in.
func ground_at(at: Vector2) -> float:
	return _ground_under(at, 0.0)


func _ground_under(at: Vector2, radius: float) -> float:
	if terrain == null:
		return 0.0
	return terrain.surface(at, radius, INF).x


# ------------------------------------------------------------------ the view ----

func _draw() -> void:
	if not debug:
		return
	var a: Armature = armature
	# Shadows first: a soft line under any stick carried off the ground, so height
	# reads in a view that has no vertical axis.
	for s in a.stick_count():
		var pa: Vector3 = a.pos[a.stick_a[s]]
		var pb: Vector3 = a.pos[a.stick_b[s]]
		if maxf(pa.z, pb.z) > 1.0:
			draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y),
				SHADOW, a.stick_radius[s] * 2.0)
	for s in a.stick_count():
		var pa: Vector3 = a.pos[a.stick_a[s]]
		var pb: Vector3 = a.pos[a.stick_b[s]]
		var limb_stick: bool = a.stick_hold[s] < 1.0 or _is_limb_stick(s)
		var ink: Color = LIMB_INK if limb_stick else INK
		ink = ink.lightened(clampf((pa.z + pb.z) * 0.5 * HEIGHT_LIFT, 0.0, 0.35))
		draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y),
			ink, maxf(a.stick_radius[s] * 2.0, 1.5))
	# Feet: each limb's toe, marked where it has been put. Solid for one on the
	# ground and hollow for one carried off it — Poise's own plant test, so the
	# mark and the support hull below can never disagree about what is standing.
	for limb in a.limbs:
		var toe: Vector3 = a.pos[limb.nodes[limb.nodes.size() - 1]]
		if toe.z > Poise.PLANT_EPSILON:
			draw_arc(Vector2(toe.x, toe.y), 2.4, 0.0, TAU, 16, FOOT, 1.0)
		else:
			draw_circle(Vector2(toe.x, toe.y), 2.4, FOOT)
	# The head, so the animal has a front.
	var head: Vector3 = a.pos[a.head_index()]
	draw_circle(Vector2(head.x, head.y), a.spec.skull_radius,
		INK.lightened(clampf(head.z * HEIGHT_LIFT, 0.0, 0.35)))
	# The weight: where the plumb line comes down, against the support the planted
	# feet make. Both are live readouts — if the mark drifts outside the feet the
	# body genuinely is out over its own edge.
	if poise.posed:
		if poise.feet >= 2:
			for i in poise._prints.size():
				draw_line(poise._prints[i],
					poise._prints[(i + 1) % poise._prints.size()], SUPPORT, 1.2)
		draw_circle(poise.centre, 2.0, PLUMB)
		draw_arc(poise.centre, 4.0, 0.0, TAU, 24, PLUMB, 1.0)


func _is_limb_stick(s: int) -> bool:
	for limb in armature.limbs:
		if s in limb.sticks:
			return true
	return false
