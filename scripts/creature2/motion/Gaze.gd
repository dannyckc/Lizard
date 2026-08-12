## Where the animal is looking — the cursor half of the controls, ported from
## v1's head look (`Creature._update_head_look` / `_head_lead`).
##
## The mouse gives one bearing and it does exactly one job: the head is carried
## round to face what the pointer is on, as long as the pointer is inside the
## animal's own field — `radius`, the cervical joints' own sum, so a short-necked
## animal has a narrow field and nobody had to write down that it does. Not the
## body: the look is an articulation of the neck alone (`Armature.look`,
## expressed in `Armature._aim_neck`), bounded by those same joints. Past the
## radius the pointer stops reaching the head altogether and the neck simply
## keeps the bearing it was left on — see `tick`, where that one line is the
## aiming rule.
##
## **The hand steers and the eye does not**, and the separation is total: nothing
## in this file returns a demand, and `Travel` asks it for none. The mouse aims
## the head; A and D turn the body; W and S move it. There was a `lead` here once
## — a walking animal turning to follow its own gaze — and it was a good idea
## about animals and a bad one about controls. Two things wanted the heading, the
## player only had authority over one of them, and every glance across the lab to
## look at something quietly re-aimed the walk. An animal you steer with the
## keyboard while looking somewhere else with the mouse is one you can actually
## drive; the cost is that a creature no longer turns to follow its eyes on its
## own, and the player turns it, which is the point of a control.
##
## What the look is *not* is a second aim. The strike is thrown along this same
## look (`Maw`), the jaws arrive where the head is pointing, and a latched mouth
## is aimed by what it is holding rather than by the cursor — so where the head
## points, where the teeth arrive and where the damage lands are one bearing. The
## bite *window* is this same neck's range, read by `Maw.window`.
##
## Deliberately separate from `heading`: the body direction the mover, the gait
## and the contacts all read is written in one place (`Travel`) and is never
## rewritten from here. These two share nothing at all.
class_name Gaze
extends RefCounted

## How far off its own shoulders a head may be carried, and how quickly it gets
## there. v1's numbers, and the cap is a cap on top of the anatomy rather than
## instead of it — the neck's own joints usually run out first.
const MAX_ANGLE: float = deg_to_rad(82.0)
const RESPONSE: float = 14.0

## The fastest a neck sweeps a head about, rad/s.
##
## The ease alone is proportional, so a small correction is gentle and a large
## one is violent: a cursor crossing from one shoulder to the other asks for the
## whole field at once and `RESPONSE` pays it out at better than two thousand
## degrees a second, which is a cut rather than a turn. This is the muscle's own
## ceiling under it — quick enough that no ordinary aim ever meets it, and the
## whole-field swing becomes a fast head turn instead of a snap.
const SWEEP_RATE: float = deg_to_rad(480.0)

## How far past the radius a pointer already being watched may stray before the
## head lets go of it. Hysteresis on the *release* only, so the radius stays the
## honest thing — what the neck can deliver is what the head will follow — and
## all this buys is that a pointer wandering along the edge of the field is
## either being watched or is not, rather than being taken up and dropped every
## other frame. The head hardly shows it either way (it is at the limit in both
## states); everything reading `tracking` does.
const RELEASE: float = deg_to_rad(4.0)

## Inside this much of the neck root the pointer has no bearing worth tracking,
## px². A cursor resting on the animal's own shoulders would otherwise swing the
## head through a semicircle for a pixel of mouse movement.
const DEADZONE_SQ: float = 36.0

## Below this much residual offset a head that has stopped tracking anything has
## arrived home, and the neck is handed back to the solver.
const SETTLED: float = deg_to_rad(1.0)


var creature: Creature2

## The bearing the head is being carried on, and it as a direction. Written
## every tick and read by the strike, the steering and the marks.
var angle: float = 0.0
var dir: Vector2 = Vector2.RIGHT
## Whether the cursor is saying anything at all — over the world rather than
## over a drawer, and not on flesh the jaws already have.
var addressed: bool = false
## Whether the cursor is inside the animal's field and therefore driving the
## head. False both when nothing is being pointed at and when what is being
## pointed at is somewhere this neck cannot look; `addressed` separates those.
var tracking: bool = false
## Where the pointer is relative to the shoulders, radians, NAN for nothing —
## the ask, before the neck has had its say. Kept because the *body* still
## answers it after the head has run out (see `lead`).
var ask: float = NAN
## How far off its shoulders the head is actually being carried, radians. What
## the neck delivered, which past the radius is the radius.
var craned: float = 0.0


func build(p_creature: Creature2) -> void:
	creature = p_creature
	reset()


## Back onto its own shoulders, wherever the body is pointing — a build, a
## reset, a revival. Nothing eases here: there is no previous pose to ease from.
func reset() -> void:
	angle = creature.heading if creature != null else 0.0
	dir = Vector2.RIGHT.rotated(angle)
	addressed = false
	tracking = false
	ask = NAN
	craned = 0.0
	if creature != null and creature.armature != null:
		creature.armature.look = NAN


## The aiming radius: how far off its own shoulders this animal can look, either
## way. The cervical joints' own sum, under the cap — so a long-necked animal
## has a wide field and a short-necked one has to turn its body, and neither
## number was authored for the species.
##
## The one radius the whole control scheme is stated in: inside it the pointer
## has the head, outside it the pointer has the body instead.
func radius() -> float:
	if creature == null or creature.armature == null:
		return MAX_ANGLE
	return minf(MAX_ANGLE, creature.armature.neck_sweep())


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
		addressed = false
		tracking = false
		ask = NAN
		if a != null:
			a.look = NAN
		return
	# The solved shoulders are the truthful centre of the head's range. Not the
	# heading: the heading is a logical bearing the body eases onto and the neck
	# genuinely hangs off the withers, so clamping against the heading would let
	# the first cervical joint exceed the limit the solver holds it to.
	var datum: float = a.fwd[a.withers_index()].angle()
	var most: float = radius()

	ask = NAN
	var at: Vector2 = _addressed()
	if at.x < INF:
		# Measured from the joint the head is carried on, and not from the
		# shoulders, because that is the bearing the neck actually delivers —
		# v1 read it off the same node for the same reason. From further back,
		# flesh already in the mouth would read as a demand to swing the head
		# off it, and a latched animal would chew its way out of its own grip.
		var toward: Vector2 = at - a.plan(a.nape_index())
		if toward.length_squared() > DEADZONE_SQ:
			ask = wrapf(toward.angle() - datum, -PI, PI)
	addressed = not is_nan(ask)
	# The radius, and it is the whole of the aiming rule. Inside it the pointer
	# has the head; outside it the pointer has nothing to say about the head at
	# all, and the neck is left holding the bearing the cursor last gave it.
	#
	# The alternative — pinning the head at the limit and letting it go on
	# following a cursor it cannot reach — is what a clamp does if you let it,
	# and it is wrong in the one place it shows: a pointer crossing the line
	# dead astern flips the sign of the ask, and the head whips from one
	# shoulder to the other for a pixel of mouse movement. Holding is also the
	# truthful pose, because an animal that cannot see a thing is not looking at
	# it.
	tracking = addressed and absf(ask) <= (most + RELEASE if tracking else most)

	if tracking:
		_sweep(datum + ask, delta)
	elif not addressed:
		# Nothing is being pointed at: the head comes home to its own shoulders.
		_sweep(datum, delta)
	# ...and the third case is not written, because it is the point: a head that
	# has been left off the cursor is eased nowhere. It keeps the bearing it had,
	# and the only thing that ever moves it again is the clamp below, carrying it
	# round when the body turns far enough to take it out of the neck's range —
	# which is a drag rather than a snap, because nothing is re-aimed.

	# Clamped after the ease, because the neck may itself have swung sharply this
	# tick while the head angle was still coming round.
	craned = clampf(wrapf(angle - datum, -PI, PI), -most, most)
	angle = wrapf(datum + craned, -PI, PI)
	dir = Vector2.RIGHT.rotated(angle)
	# ...and the neck is given back the moment the head has nothing to track and
	# has come home, so a body nobody is pointing bends the way the solve bends
	# it rather than being held straight by a look at nothing. A head merely
	# holding still is very much being held: it keeps the neck.
	a.look = angle if addressed or absf(craned) > SETTLED else NAN


## Carries the head toward a bearing: eased, and then held to what a neck can
## actually sweep in the time. Both, in that order — the ease is what makes an
## aim settle instead of arriving, and the rate is what keeps the arrival from
## being instantaneous when the ease has a whole field to pay out at once.
func _sweep(toward: float, delta: float) -> void:
	var eased: float = lerp_angle(angle, toward, 1.0 - exp(-RESPONSE * delta))
	var step: float = wrapf(eased - angle, -PI, PI)
	angle = wrapf(angle + clampf(step, -SWEEP_RATE * delta, SWEEP_RATE * delta),
		-PI, PI)


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
