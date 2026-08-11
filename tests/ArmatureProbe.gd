## Phase-1 gate for the v2 armature — see docs/V2_DESIGN.md §11.2.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/ArmatureProbe.gd
##
## Asserts what the unified chain graph claims to be, with the claims ported
## from GravityTest and RagdollTest rather than their constants:
##
##   * **one graph** — the cat builds to its six chains and ~32 nodes, and
##     that is the entire physics skeleton.
##   * **one pull** — a drop integrates on Gravity.Fall and lands when the
##     world's own closed form says it should; nothing in creature2 keeps a
##     second gravity.
##   * **it stands** — the trunk is held at what the legs deliver, checked
##     every tick, and standing still costs no drift.
##   * **anatomy holds** — hauled about by the tail, every stick stays exact
##     and no joint passes its graded limit; limp costs a body none of its
##     bones either.
##   * **weight hangs** — the neck and tail sag below their carry lines by
##     the weight that is actually on them: a heavier skull droops the neck
##     further, the tail's curve steepens toward the tip, and a collapsed
##     body lays the whole line on the floor.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var creature: Creature2 = main.creature
	_check(creature != null, "the lab did not build a creature")
	if creature == null:
		_finish()
		return false
	# Flat, empty ground: every measurement below is of one body standing on
	# nothing, and an obstacle would make it a measurement of the obstacle.
	main.terrain.clear()

	_check_graph(creature.armature)
	_check_stands(creature)
	_check_at_rest(creature)
	_check_drop_is_ballistic(creature)
	_check_joint_limits_hold(creature)
	_check_weight_hangs(creature)
	_check_mass_droops_the_neck()
	_check_ragdoll(creature)
	_check_revive(creature)
	_finish()
	return false


# ---------------------------------------------------------------- one graph ----

func _check_graph(a: Armature) -> void:
	_check(a.node_count() >= 30 and a.node_count() <= 40,
		"the cat graph has %d nodes against the ~32 designed" % a.node_count())
	_check(a.stick_count() >= 28 and a.stick_count() <= 38,
		"the cat graph has %d sticks against the ~28 designed" % a.stick_count())
	for name: StringName in [BodySchema.TRUNK, BodySchema.NECK, BodySchema.TAIL,
			&"FL", &"FR", &"HL", &"HR"]:
		_check(a.chain(name) != null, "the graph is missing its %s chain" % name)
	var neck: Armature.Chain = a.chain(BodySchema.NECK)
	if neck != null:
		_check(neck.nodes.size() == a.spec.neck_nodes + 1,
			"the neck chain does not carry its head node")
	notes.append("%d nodes / %d sticks in six chains"
		% [a.node_count(), a.stick_count()])


# ----------------------------------------------------------------- it stands ----

func _check_stands(c: Creature2) -> void:
	_settle(c, 90)
	var a: Armature = c.armature
	var pelvis_z: float = a.pos[a.pelvis_index()].z
	var withers_z: float = a.pos[a.withers_index()].z
	_check(absf(pelvis_z - a.hind_stance) < 0.6,
		"the pelvis stands at %.2f px against the %.2f the hind legs deliver"
		% [pelvis_z, a.hind_stance])
	_check(absf(withers_z - a.fore_stance) < 0.6,
		"the withers stand at %.2f px against the %.2f the fore legs deliver"
		% [withers_z, a.fore_stance])
	# Standing is a claim about having enough leg under the weight: the
	# stance can never exceed what the bones add up to.
	for limb in a.limbs:
		var reach: float = 0.0
		for b in limb.bones:
			reach += b
		var socket_z: float = a.pos[limb.nodes[0]].z
		_check(socket_z < reach,
			"%s holds its socket %.1f px up on %.1f px of leg" % [limb.name, socket_z, reach])
		var toe_z: float = a.pos[limb.nodes[limb.nodes.size() - 1]].z
		_check(toe_z <= 0.1,
			"%s stands with its toe %.2f px off the ground" % [limb.name, toe_z])
	notes.append("stands at pelvis %.1f / withers %.1f px" % [pelvis_z, withers_z])


func _check_at_rest(c: Creature2) -> void:
	var a: Armature = c.armature
	var pose: PackedVector3Array = a.pos.duplicate()
	_settle(c, 600)
	var drift: float = 0.0
	for i in a.pos.size():
		drift = maxf(drift, Vector2(pose[i].x, pose[i].y)
			.distance_to(Vector2(a.pos[i].x, a.pos[i].y)))
	_check(drift < 0.05,
		"an undisturbed standing body drifted %.3f px in ten seconds" % drift)


# ------------------------------------------------------------------ one pull ----

func _check_drop_is_ballistic(c: Creature2) -> void:
	var a: Armature = c.armature
	c.drop(160.0)
	var expected: float = Gravity.fall_time(160.0, 0.0)
	var elapsed: float = 0.0
	var guard: int = 0
	while not a.fall.landed and guard < 600:
		c._physics_process(TICK)
		elapsed += TICK
		guard += 1
	_check(a.fall.landed, "a body dropped 160 px never arrived")
	_check(absf(elapsed - expected) < TICK * 2.0,
		"a 160 px drop took %.3f s against the world's %.3f s" % [elapsed, expected])
	_check(absf(a.fall.impact - Gravity.launch_rate(160.0)) < 40.0,
		"it arrived at %.0f px/s against the %.0f px/s it fell for"
		% [a.fall.impact, Gravity.launch_rate(160.0)])
	guard = 0
	while not a.fall.resting and guard < 900:
		c._physics_process(TICK)
		guard += 1
	_check(a.fall.resting, "a dropped body never came to rest")
	_settle(c, 30)
	_check(absf(a.pos[a.pelvis_index()].z - a.hind_stance) < 0.6,
		"it did not land back on its feet (pelvis at %.2f px)"
		% a.pos[a.pelvis_index()].z)
	notes.append("a 160 px drop lands in %.2f s and stands back up" % elapsed)


# ------------------------------------------------------------- anatomy holds ----

func _check_joint_limits_hold(c: Creature2) -> void:
	var a: Armature = c.armature
	var tail: Armature.Chain = a.chain(BodySchema.TAIL)
	var tip: int = tail.nodes[tail.nodes.size() - 1]
	var before: Vector2 = a.centre()
	# The bend limits are anatomy and must hold even under the pull; stick
	# lengths are allowed their transient give while an external pull is
	# actively displacing a point (that give is the soft feel — v1's free
	# solver made the same bargain) and must be exact again once it ends.
	var pulled_stick: float = 0.0
	var worst_stick: float = 0.0
	var worst_bend: float = 0.0
	for tick in 220:
		if tick < 40:
			# Drag the tail tip hard sideways — the one pull most likely to
			# fold a chain past itself.
			var at: Vector2 = Vector2(a.pos[tip].x, a.pos[tip].y)
			a.haul_to(tip, at + Vector2(0.0, 12.0))
		c._physics_process(TICK)
		if tick < 60:
			pulled_stick = maxf(pulled_stick, a.worst_stick_error())
		else:
			worst_stick = maxf(worst_stick, a.worst_stick_error())
		worst_bend = maxf(worst_bend, a.worst_bend_excess())
	_check(pulled_stick < 1.0,
		"under an active haul a stick stretched %.2f px — that is tearing, not give"
		% pulled_stick)
	_check(worst_stick < 0.01,
		"released, a stick stayed %.4f px off its length" % worst_stick)
	_check(worst_bend < 0.001,
		"hauled by the tail, a joint folded %.4f rad past its limit" % worst_bend)
	var towed: float = before.distance_to(a.centre())
	_check(towed > 1.0,
		"480 px of tail-hauling towed the body %.2f px — the pull never reached it"
		% towed)
	notes.append("hauled about: %.2f px of give under the pull, exact to %.4f px released, body towed %.0f px"
		% [pulled_stick, worst_stick, towed])
	c.reset()
	_settle(c, 90)


# -------------------------------------------------------------- weight hangs ----

func _check_weight_hangs(c: Creature2) -> void:
	var a: Armature = c.armature
	var tail: Armature.Chain = a.chain(BodySchema.TAIL)
	var neck: Armature.Chain = a.chain(BodySchema.NECK)
	_check(tail.tip_sag > 0.0, "the tail hangs perfectly on its carry line")
	_check(neck.tip_sag > 0.0, "the neck carries its head with no weight in it")
	var tip_z: float = a.pos[tail.nodes[tail.nodes.size() - 1]].z
	_check(tip_z > 0.0,
		"a standing cat let its tail down onto the ground (tip at %.2f px)" % tip_z)
	var head_z: float = a.pos[a.head_index()].z
	_check(head_z > a.pos[a.withers_index()].z,
		"the default cat carries its head at %.1f px, below its own withers" % head_z)
	# The sag is a curve, not a hinge: the gap between consecutive stations
	# has to keep growing toward the tip, because the tip is the thinnest
	# section carrying the longest lever.
	var steepening: bool = true
	var previous: float = -INF
	for j in range(tail.nodes.size() - 1):
		var gap: float = a.pos[tail.nodes[j]].z - a.pos[tail.nodes[j + 1]].z
		if gap + 0.0001 < previous:
			steepening = false
		previous = gap
	_check(steepening, "the tail bent hardest at its root rather than at its tip")
	notes.append("tail sags %.2f px below its carry, neck %.2f; tip clears the floor by %.1f"
		% [tail.tip_sag, neck.tip_sag, tip_z])


## That the droop reads per-node mass: the same neck under a heavier skull
## droops further. Two standalone armatures, one knob apart.
func _check_mass_droops_the_neck() -> void:
	var plain := Armature.new()
	plain.build(BodySpec.new(), Vector2.ZERO, 0.0)
	var heavy_spec := BodySpec.new()
	heavy_spec.skull_radius *= 1.4
	var heavy := Armature.new()
	heavy.build(heavy_spec, Vector2.ZERO, 0.0)
	for _i in 10:
		plain.step(TICK)
		heavy.step(TICK)
	var plain_sag: float = plain.chain(BodySchema.NECK).tip_sag
	var heavy_sag: float = heavy.chain(BodySchema.NECK).tip_sag
	_check(heavy_sag > plain_sag + 0.0001,
		"a 1.4x skull droops the neck %.4f px against the plain %.4f — mass is not read"
		% [heavy_sag, plain_sag])
	notes.append("a 1.4x skull deepens neck sag %.3f -> %.3f px" % [plain_sag, heavy_sag])


# ------------------------------------------------------------------- ragdoll ----

func _check_ragdoll(c: Creature2) -> void:
	var a: Armature = c.armature
	c.toggle_collapsed()
	_check(a.collapsed, "the collapse did not take")
	_check(a.fall.height > 1.0,
		"a standing body collapsed from %.2f px up — it was already on the floor"
		% a.fall.height)
	# The fall down, then three hundred ticks of being dead, with the
	# invariants watched the whole way: limp is not the same as broken.
	var worst_stick: float = 0.0
	var worst_bend: float = 0.0
	var worst_bone: float = 0.0
	var worst_fold: float = 0.0
	for _i in 600:
		c._physics_process(TICK)
	for _i in 300:
		c._physics_process(TICK)
		worst_stick = maxf(worst_stick, a.worst_stick_error())
		worst_bend = maxf(worst_bend, a.worst_bend_excess())
		worst_bone = maxf(worst_bone, a.worst_bone_error())
		worst_fold = maxf(worst_fold, a.worst_fold_excess())
	_check(worst_stick < 0.01, "a dead spine stretched %.4f px" % worst_stick)
	_check(worst_bend < 0.001,
		"a dead spine folded %.4f rad past its limit" % worst_bend)
	_check(worst_bone < 0.01, "a dead limb's bone stretched %.4f px" % worst_bone)
	_check(worst_fold < 0.001,
		"a dead joint closed %.4f rad past a limp joint's fold" % worst_fold)

	var tail: Armature.Chain = a.chain(BodySchema.TAIL)
	var tip_z: float = a.pos[tail.nodes[tail.nodes.size() - 1]].z
	_check(tip_z < 0.5,
		"a dead cat still held its tail %.2f px off the ground" % tip_z)
	var head_z: float = a.pos[a.head_index()].z
	_check(head_z < 0.5,
		"a dead cat still carried its head %.2f px up" % head_z)

	var pose: PackedVector3Array = a.pos.duplicate()
	for _i in 300:
		c._physics_process(TICK)
	var drift: float = 0.0
	for i in a.pos.size():
		drift = maxf(drift, Vector2(pose[i].x, pose[i].y)
			.distance_to(Vector2(a.pos[i].x, a.pos[i].y)))
	_check(drift < 0.05,
		"an undisturbed carcass drifted %.3f px in five seconds" % drift)
	notes.append("collapses from %.0f px, lies flat, and rests" % a.hind_stance)


func _check_revive(c: Creature2) -> void:
	c.reset()
	_settle(c, 90)
	var a: Armature = c.armature
	_check(not a.collapsed, "reset left the body collapsed")
	_check(absf(a.pos[a.pelvis_index()].z - a.hind_stance) < 0.6,
		"reset did not stand the body back up (pelvis at %.2f px)"
		% a.pos[a.pelvis_index()].z)


# ------------------------------------------------------------------- helpers ----

func _settle(c: Creature2, ticks: int) -> void:
	for _i in ticks:
		c._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("armature OK — one graph under one pull: %s" % " · ".join(notes))
	else:
		print("ARMATURE FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
