## Where the animal is looking — the cursor half of the controls, ported from
## v1's head look (`Creature._update_head_look` / `_head_lead`).
##
## The mouse gives one bearing and it does two jobs, which is the whole of the
## control scheme:
##
##   * **the view.** The head is carried round to face what the pointer is on.
##     Not the body: the look is an articulation of the neck alone (`Armature.
##     look`, expressed in `Armature._aim_neck`), bounded by the cervical joints'
##     own bend limits, so a short-necked animal cannot look behind itself and
##     nobody had to write down that it cannot.
##   * **the steering.** A walking animal goes where it is looking. The head
##     reaches the bearing first because a neck is quicker than four legs, and
##     the body comes round after it — `lead`, a proportional demand handed to
##     the ordinary turn, so A and D still mean exactly what they meant and the
##     hand always has the last word.
##
## What it is *not* is a second aim. The strike is thrown along this same look
## (`Maw`), the jaws arrive where the head is pointing, and a latched mouth is
## aimed by what it is holding rather than by the cursor — so where the head
## points, where the teeth arrive and where the damage lands are one bearing.
##
## Deliberately separate from `heading`: the body direction the mover, the gait
## and the contacts all read is written in one place (`Travel`) and is never
## rewritten from here. All these two have between them is the one signed demand
## `lead` returns.
class_name Gaze
extends RefCounted

## How far off its own shoulders a head may be carried, and how quickly it gets
## there. v1's numbers, and the cap is a cap on top of the anatomy rather than
## instead of it — the neck's own joints usually run out first.
const MAX_ANGLE: float = deg_to_rad(82.0)
const RESPONSE: float = 14.0
## Inside this much of the neck root the pointer has no bearing worth tracking,
## px². A cursor resting on the animal's own shoulders would otherwise swing the
## head through a semicircle for a pixel of mouse movement.
const DEADZONE_SQ: float = 36.0

## How far off its own heading the head has to be carried before the body asks
## for the whole of its turn rate to follow it.
##
## A proportional band rather than a switch: inside it the body eases round,
## past it the animal is turning as hard as it can — and because the head keeps
## tracking the cursor throughout, the two converge rather than the head
## snapping back when the heading arrives.
const LEAD_BAND: float = deg_to_rad(30.0)

## Below this much residual offset a head that has stopped tracking anything has
## arrived home, and the neck is handed back to the solver.
const SETTLED: float = deg_to_rad(1.0)


var creature: Creature2

## The bearing the head is being carried on, and it as a direction. Written
## every tick and read by the strike, the steering and the marks.
var angle: float = 0.0
var dir: Vector2 = Vector2.RIGHT
## Whether the head is currently tracking anything at all.
var engaged: bool = false


func build(p_creature: Creature2) -> void:
	creature = p_creature
	reset()


## Back onto its own shoulders, wherever the body is pointing — a build, a
## reset, a revival. Nothing eases here: there is no previous pose to ease from.
func reset() -> void:
	angle = creature.heading if creature != null else 0.0
	dir = Vector2.RIGHT.rotated(angle)
	engaged = false
	if creature != null and creature.armature != null:
		creature.armature.look = NAN


## One tick of looking.
##
## Runs before the mover, so the bearing the steering leads on and the bearing
## the neck is swept to are the same one. The datum it is measured against is
## last tick's solved shoulders — the neck this angle is clamped against is
## itself part of the pose being solved, and there is no ordering that avoids
## it; sixteen milliseconds of an eased turn, and the head still arrives.
func tick(delta: float) -> void:
	var a: Armature = creature.armature
	if a == null or a.collapsed:
		engaged = false
		if a != null:
			a.look = NAN
		return
	# The solved shoulders are the truthful centre of the head's range. Not the
	# heading: the heading is a logical bearing the body eases onto and the neck
	# genuinely hangs off the withers, so clamping against the heading would let
	# the first cervical joint exceed the limit the solver holds it to.
	var datum: float = a.fwd[a.withers_index()].angle()
	var most: float = minf(MAX_ANGLE, a.neck_sweep())
	var desired: float = datum

	var at: Vector2 = _addressed()
	if at.x < INF:
		# Measured from the joint the head is carried on, and not from the
		# shoulders, because that is the bearing the neck actually delivers —
		# v1 read it off the same node for the same reason. From further back,
		# flesh already in the mouth would read as a demand to swing the head
		# off it, and a latched animal would chew its way out of its own grip.
		var toward: Vector2 = at - a.plan(a.nape_index())
		if toward.length_squared() > DEADZONE_SQ:
			desired = datum + clampf(wrapf(toward.angle() - datum, -PI, PI), -most, most)

	angle = lerp_angle(angle, desired, 1.0 - exp(-RESPONSE * delta))
	# Clamped again after the ease, because the neck may itself have swung
	# sharply this tick while the head angle was still coming round.
	var off: float = clampf(wrapf(angle - datum, -PI, PI), -most, most)
	angle = wrapf(datum + off, -PI, PI)
	dir = Vector2.RIGHT.rotated(angle)
	# ...and the neck is given back the moment the head has nothing to track and
	# has come home, so a body nobody is pointing bends the way the solve bends
	# it rather than being held straight by a look at nothing.
	engaged = at.x < INF
	a.look = angle if engaged or absf(off) > SETTLED else NAN


## Where the head is being pointed, in the plan, or INF for nothing.
##
## Two answers, in this order, because the animal's own business outranks the
## player's:
##
##   * **jaws shut on flesh are not looking at it — they have it.** A hold is
##     already a geometry, and the tether owns it: the mouth is kept within its
##     own slack of the flesh it closed on and the carry keeps it at its height,
##     so the head is on its dinner without anything aiming it there. Pointing
##     the same head at the same flesh is a second mechanism on one bone, and
##     the two spend the hold arguing over a pixel — which is the pixel that
##     parts a grip a chew has just made shallower. So a latched mouth looks at
##     nothing, and the cursor does not get a say either: a mouse that could
##     swing the head off a mouthful would be undoing the grip the player is
##     asking for by holding the button.
##   * **otherwise the cursor.** The selected target's own contact point where
##     the pointer has hold of something — which is where the jaws can actually
##     meet it, see `Creature2.aim_contact` — and the bare pointer where it has
##     not.
##
## What is deliberately *not* here is the strike. A committed lunge does not
## take the head anywhere the look was not already taking it: the throw is the
## body moving (`Maw`), and a neck swept sideways to help it arrive would be the
## reach a body-moving lunge exists to refuse — the jaws would land somewhere
## the animal never went and let go of it again as the sweep came home. So a
## strike is thrown along whatever the head was already doing, which for an
## aimed bite is the flesh itself.
func _addressed() -> Vector2:
	if creature.maw != null and creature.maw.latched():
		return Vector2.INF
	if creature.aim != null and creature.aim.creature != null:
		return creature.aim_contact
	var cmd: Creature2.Command = creature.command
	return cmd.aim_world if cmd.aim_active else Vector2.INF


## How much of its turn the body is asking for to follow its own head, −1..1.
##
## Bounded three ways, and every one of them is a statement about what walking
## after your own eyes is:
##
##   * only going forward. A creature backing away from something keeps looking
##     at it, and steering by that would drive it in a circle round the thing it
##     is retreating from.
##   * only while it is actually being pointed. With no cursor the head settles
##     onto the neck, the lead is nothing, and every existing caller — the
##     probes, the carcass, whatever drives a creature next — behaves exactly as
##     it did before there was a mouse.
##   * scaled by the throttle, because it is a property of the walking. Half a
##     throttle is half a commitment and turns half as hard for it.
func lead() -> float:
	var cmd: Creature2.Command = creature.command
	if not engaged or cmd.throttle <= 0.0:
		return 0.0
	var off: float = wrapf(angle - creature.heading, -PI, PI)
	return clampf(off / LEAD_BAND, -1.0, 1.0) * clampf(cmd.throttle, 0.0, 1.0)
