## Headless check for a body nobody is driving — see Creature._dead_process.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/RagdollTest.gd
##
## Asserts the four things a carcass claims to be. That it is *found* at rest and
## not standing to attention: a slumped spine, limbs sprawled short of the walking
## stance, and no foot at any height. That being limp costs it none of its
## anatomy: exact segment lengths, exact bone lengths, and no bend past the limit,
## held over thousands of ticks of a solver with no pinned point in it. That it is
## still a body in the world — solid, weighed, shoved, held and dragged. And that
## it is the *same* carcass every run.
extends SceneTree

const TICK: float = 1.0 / 60.0
const SETTLE_TICKS: int = 600

var failures: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	_run_checks()
	return false


func _run_checks() -> void:
	var player: Creature = main.creature
	var body: Creature = main.target_creature
	_check(body != null and player != null, "the habitat did not build its bodies")
	if body == null or player == null:
		_finish()
		return

	_check(not body.alive, "the body in the habitat was not placed as a carcass")
	_check(body.ragdoll != null, "a carcass was built without a ragdoll to own its limbs")

	_check_slumped(body)
	_check_at_rest(body)
	_check_invariants(body)
	_check_limbs_limp(body)
	_check_deterministic(body)
	_check_solid(player, body)
	_check_dragged(player, body)
	_check_limb_dragged(player, body)
	_finish()


## Found lying down, not standing to attention. `rebuild` lays a spine out dead
## straight and nothing downstream ever bends one with no head driving it, so a
## carcass that did not arrive curved would stay a plank forever.
func _check_slumped(body: Creature) -> void:
	var curvature: float = _total_turn(body.spine)
	_check(curvature > deg_to_rad(20.0),
		"the carcass is laid out straight: %.1f deg of total bend over the whole spine"
			% rad_to_deg(curvature))

	# ...and lying down is where it starts, not somewhere it gets to. A body that
	# had to collapse first is one nobody arriving late ever sees fall.
	var arrival: PackedVector2Array = body.spine.points.duplicate()
	_run(body, SETTLE_TICKS)
	var moved: float = 0.0
	for i in body.spine.size():
		moved = maxf(moved, arrival[i].distance_to(body.spine.points[i]))
	_check(moved < 1.0,
		"the carcass was not settled when it spawned — it moved %.2f px finding its pose" % moved)


## Ground friction has to actually bring it to rest and keep it there. A free
## Verlet chain with no damping worth the name simply drifts.
func _check_at_rest(body: Creature) -> void:
	var before: Vector2 = body.head_pos
	var pose: PackedVector2Array = body.spine.points.duplicate()
	_run(body, SETTLE_TICKS)
	var drift: float = 0.0
	for i in body.spine.size():
		drift = maxf(drift, pose[i].distance_to(body.spine.points[i]))
	_check(drift < 0.05,
		"an undisturbed carcass drifted %.3f px in ten seconds" % drift)
	_check(before.distance_to(body.head_pos) < 0.05,
		"an undisturbed carcass's head wandered %.3f px" % before.distance_to(body.head_pos))


## Limp is not the same as broken. `step_free` moves both ends of every distance
## constraint and alternates the direction of its passes, and the whole risk of
## doing that is that a chain with no authoritative point quietly stretches — so
## this is measured after the body has also been shoved and hauled about.
func _check_invariants(body: Creature) -> void:
	var seg_len: float = body.params.segment_length * body.size_scale
	var max_bend: float = deg_to_rad(body.params.max_bend_deg)
	var worst_segment: float = 0.0
	var worst_bend: float = 0.0
	var worst_bone: float = 0.0
	for _tick in SETTLE_TICKS:
		body._physics_process(TICK)
		var s: Spine = body.spine
		for i in range(1, s.size()):
			worst_segment = maxf(worst_segment,
				absf(s.points[i].distance_to(s.points[i - 1]) - seg_len))
			if i >= 2:
				var incoming: Vector2 = s.points[i - 1] - s.points[i - 2]
				var outgoing: Vector2 = s.points[i] - s.points[i - 1]
				var turn: float = absf(wrapf(outgoing.angle() - incoming.angle(), -PI, PI))
				worst_bend = maxf(worst_bend, turn - max_bend)
		for limb in body.gait.limbs:
			worst_bone = maxf(worst_bone,
				absf(limb.joints[0].distance_to(limb.joints[1]) - limb.lengths[0]))
			worst_bone = maxf(worst_bone,
				absf(limb.joints[1].distance_to(limb.joints[2]) - limb.lengths[1]))

	_check(worst_segment < 0.01,
		"a free spine stretched: %.4f px of segment error" % worst_segment)
	_check(worst_bend < 0.0001,
		"a dead spine bent %.3f deg past its limit" % rad_to_deg(worst_bend))
	_check(worst_bone < 0.05, "a dead limb's bones changed length by %.4f px" % worst_bone)


## No gait, no lift, and no stance being held. The last one is the difference
## between a body that is limp and one that is merely standing still: a live
## creature holds its feet at `stance_reach` of full extension, and a dead one is
## folded under its own weight well inside that.
func _check_limbs_limp(body: Creature) -> void:
	var reach: float = 0.0
	for limb in body.gait.limbs:
		_check(not limb.stepping, "a carcass took a step")
		_check(is_zero_approx(limb.lift), "a dead foot was %.2f px in the air" % limb.lift)
		_check(limb.ground.is_equal_approx(limb.joints[2]),
			"a dead foot's shadow was not under the foot")
		reach = maxf(reach, limb.joints[0].distance_to(limb.joints[2]) / limb.total_length)

		# Sprawled, but not through its own ribcage.
		for joint in 3:
			var inside: Vector2 = body.push_out_of_body(limb.joints[joint], 0.0)
			_check(inside.length() < limb.total_length * 0.35,
				"a dead limb was lying %.1f px inside its own body" % inside.length())

	_check(reach < body.params.stance_reach,
		"a dead limb was held out at %.2f of its length — as far as a walking one (%.2f)"
			% [reach, body.params.stance_reach])


## The same body in the same place has to lie the same way every run. A carcass
## that rearranged itself on reload would not read as something that had come to
## rest at all. Two bodies placed apart must still differ.
func _check_deterministic(body: Creature) -> void:
	var first: PackedVector2Array = body.spine.points.duplicate()
	body.reset(body.spawn_position, body.spawn_heading)
	var second: PackedVector2Array = body.spine.points.duplicate()
	var difference: float = 0.0
	for i in first.size():
		difference = maxf(difference, first[i].distance_to(second[i]))
	_check(difference < 0.001,
		"the same carcass lay %.3f px differently on a second build" % difference)

	body.reset(body.spawn_position + Vector2(500.0, 0.0), body.spawn_heading)
	var elsewhere: float = _total_turn(body.spine)
	body.reset(body.spawn_position, body.spawn_heading)
	_check(absf(elsewhere - _total_turn(body.spine)) > deg_to_rad(1.0),
		"two carcasses placed in different spots slumped identically")


## Weight and collision. A carcass is not a ghost and it is not scenery: it takes
## its mass-weighted share of every contact exactly as a living creature does,
## because it goes through exactly the same pass.
func _check_solid(player: Creature, body: Creature) -> void:
	player.params.apply_preset("Lizard")
	body.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	body.reset(Vector2(150.0, 0.0), PI)
	_check(body.physique.mass > 0.1,
		"a carcass weighed %.3f — nothing would ever shove it" % body.physique.mass)

	var start: Vector2 = body.head_pos
	var pose_before: PackedFloat32Array = _joint_angles(body.spine)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 240:
		player.command = drive
		player._physics_process(TICK)
		body._physics_process(TICK)
	var shoved: float = start.distance_to(body.head_pos)
	_check(shoved > 20.0, "a creature walked into a carcass and only moved it %.1f px" % shoved)
	_check(player.head_pos.distance_to(body.head_pos) > 20.0,
		"a creature walked clean through a carcass")
	var pose_after: PackedFloat32Array = _joint_angles(body.spine)
	var deformation: float = 0.0
	for i in pose_before.size():
		deformation = maxf(deformation,
			absf(wrapf(pose_after[i] - pose_before[i], -PI, PI)))
	_check(deformation > deg_to_rad(1.0),
		"a shove moved the carcass rigidly without bending it (%.2f deg)" % rad_to_deg(deformation))

	# Once the pusher leaves, ground friction must drain angular motion as well as
	# translation. Track the body's long axis rather than its head alone so a
	# rotating carcass cannot pass the ordinary drift check by spinning in place.
	player.command = MovementInput.Command.new()
	player.reset(Vector2(-1000.0, 0.0), 0.0)
	var axis: float = (body.spine.points[0] - body.spine.points[body.spine.size() - 1]).angle()
	var early_turn: float = 0.0
	var late_turn: float = 0.0
	for tick in 900:
		body._physics_process(TICK)
		var next_axis: float = (body.spine.points[0] - body.spine.points[body.spine.size() - 1]).angle()
		var turn: float = absf(wrapf(next_axis - axis, -PI, PI))
		if tick < 300:
			early_turn += turn
		elif tick >= 600:
			late_turn += turn
		axis = next_axis
	_check(late_turn < deg_to_rad(2.0),
		"a shoved carcass kept spinning: %.1f deg in the final five seconds (%.1f deg initially)"
			% [rad_to_deg(late_turn), rad_to_deg(early_turn)])


## Dragged by the jaws, a carcass trails. This is the one behaviour that could
## not be had by leaving the live correction alone: `_translate_contact` moves a
## whole body rigidly, and a rigidly-towed carcass keeps its pose in formation
## behind the biter like a barge. `_drag_at` applies the pull where the pull acts
## and lets the free chain carry it, so the body deforms on the way.
func _check_dragged(player: Creature, body: Creature) -> void:
	player.set_bite_held(false)
	player.params.apply_preset("Elephant")
	body.params.apply_preset("Cat")
	player.reset(Vector2.ZERO, 0.0)
	body.reset(Vector2(60.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		body._physics_process(TICK)

	player.set_bite_held(true)
	player.request_bite(Vector2(200.0, 0.0))
	for _tick in 20:
		player._physics_process(TICK)
		body._physics_process(TICK)
	if player.grip == null:
		failures.append("an Elephant could not get hold of a carcass at all")
		return

	var start: Vector2 = body.head_pos
	var pose_before: PackedFloat32Array = _joint_angles(body.spine)
	var drive := MovementInput.Command.new()
	drive.throttle = -1.0
	for _tick in 180:
		player.command = drive
		player.set_bite_held(true)
		player._physics_process(TICK)
		body._physics_process(TICK)

	_check(start.distance_to(body.head_pos) > 50.0,
		"a carcass held in an Elephant's jaws was towed only %.1f px" % start.distance_to(body.head_pos))

	var pose_after: PackedFloat32Array = _joint_angles(body.spine)
	var deformation: float = 0.0
	for i in pose_before.size():
		deformation = maxf(deformation, absf(wrapf(pose_after[i] - pose_before[i], -PI, PI)))
	_check(deformation > deg_to_rad(2.0),
		"a towed carcass kept its exact pose (%.2f deg) — it is sliding, not trailing"
			% rad_to_deg(deformation))
	player.set_bite_held(false)


## A hit on a limb stays on that articulated structure. The free particles take
## up the initial pull by folding and straightening the leg; once it is taut, the
## socket passes the load into the spine and the carcass follows.
func _check_limb_dragged(player: Creature, body: Creature) -> void:
	player.set_bite_held(false)
	player.params.apply_preset("Elephant")
	body.params.apply_preset("Cat")
	player.reset(Vector2.ZERO, 0.0)
	body.reset(Vector2(300.0, 0.0), PI)

	var limb: Limb = body.gait.limbs[0]
	var hit: AnatomyState.Hit = body.query_bite(limb.joints[2], 1.0)
	_check(hit != null and hit.kind == AnatomyState.LIMB,
		"the dead foot could not be selected as a movable bite target")
	if hit == null or hit.kind != AnatomyState.LIMB:
		return
	player._form_grip(body, hit)
	_check(player.grip != null and player.grip.holds_limb(),
		"a bite on a dead foot was rebound onto the torso")
	if player.grip == null or not player.grip.holds_limb():
		return
	var held: Grip = player.grip
	_check(held.anchor().distance_to(limb.joints[2]) < 0.1,
		"a limb grip did not reconstruct its anchor from the foot")

	# Isolate the victim-side correction from the biter's ordinary grip pass. The
	# retained Grip still supplies the same anatomical bind.
	player.grip = null
	player.bite_latched = false
	var foot_before: Vector2 = limb.joints[2]
	var radial: Vector2 = (foot_before - limb.joints[0]).normalized()
	var tangent := Vector2(-radial.y, radial.x)
	for _tick in 18:
		body._drag_grip(held, tangent * 5.0)
		body._physics_process(TICK)
	_check(foot_before.distance_to(limb.joints[2]) > 5.0,
		"pulling a dead foot did not articulate the limb")

	# The pull is re-aimed along the limb every tick, so once the carcass has been
	# hauled far enough the direction has swung round with it and the body settles
	# at a fixed offset instead of being towed away. What that offset comes out at
	# is geometry — limb length against body mass — so the threshold only has to
	# separate "the socket passes the load on" from "the leg absorbs all of it",
	# and the measured figure is quoted so a regression to the latter is legible
	# rather than a bare failure.
	var body_before: Vector2 = body.head_pos
	for _tick in 60:
		var outward: Vector2 = (held.anchor() - limb.joints[0]).normalized()
		body._drag_grip(held, outward * 8.0)
		body._physics_process(TICK)
	_check(body_before.distance_to(body.head_pos) > 3.0,
		"a taut dead limb never transmitted its pull into the spine (%.2f px)"
			% body_before.distance_to(body.head_pos))


# ------------------------------------------------------------------ util ----

func _run(body: Creature, ticks: int) -> void:
	for _tick in ticks:
		body._physics_process(TICK)


## Total absolute turn along the chain — how far it is from being a straight line.
func _total_turn(spine: Spine) -> float:
	var total: float = 0.0
	for angle in _joint_angles(spine):
		total += absf(angle)
	return total


## The turn taken at each interior joint, which is the pose with its position and
## heading divided out — so a body that has merely been carried somewhere reads as
## unchanged and only a body that has actually bent reads as different.
func _joint_angles(spine: Spine) -> PackedFloat32Array:
	var angles := PackedFloat32Array()
	for i in range(2, spine.size()):
		var incoming: Vector2 = spine.points[i - 1] - spine.points[i - 2]
		var outgoing: Vector2 = spine.points[i] - spine.points[i - 1]
		angles.append(wrapf(outgoing.angle() - incoming.angle(), -PI, PI))
	return angles


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("ragdoll OK — slumped on arrival, at rest, anatomy intact, solid, towable")
		quit(0)
	else:
		for failure in failures:
			print("RAGDOLL FAIL — ", failure)
		quit(1)
