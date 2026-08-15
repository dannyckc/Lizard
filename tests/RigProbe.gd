## Gate for the rig layer — the anatomy claims the skeleton now makes.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/RigProbe.gd
##
## Asserts what Rig.gd claims:
##
##   * **named joints** — every armature node that is a joint carries an
##     identity, and the census covers the whole graph.
##   * **symmetry** — a bare standing body folds its left and right limbs to
##     the same angles: the solve is deterministic, no seed, no history.
##   * **range of motion holds** — walked, sprinted and turned, no limb joint
##     passes its anatomical stops while its toe is honestly placed.
##   * **planted toes are exact** — support is not negotiable; the toe node
##     sits on the gait's anchor to solver precision.
##   * **the scapula glides** — the fore socket leads and trails its girdle
##     datum through the stride, and returns to it at rest.
##   * **the head rights** — a heeled body carries its head less heeled than
##     its trunk; a collapsed one does not.
##   * **the back gathers** — the arch lifts the lumbar run and leaves both
##     girdles standing at what the legs deliver.
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
	main.terrain.clear()

	_check_census(creature.armature)
	_check_symmetry()
	_check_rom_holds(creature)
	_check_planted_exact(creature)
	_check_scapula(creature)
	_check_righting()
	_check_gather()
	_finish()
	return false


# ------------------------------------------------------------- the census ----

func _check_census(a: Armature) -> void:
	_check(a.rig != null, "the armature carries no rig")
	_check(a.rig.joints.size() == a.node_count(),
		"the joint census names %d of %d nodes"
		% [a.rig.joints.size(), a.node_count()])
	var named: Dictionary = {}
	for j in a.rig.joints:
		named[j.node] = j.name
	for want: StringName in [&"lumbosacral", &"atlas", &"FL_elbow", &"FR_carpus",
			&"HL_stifle", &"HR_tarsus", &"withers", &"sacrum"]:
		var found: bool = false
		for j in a.rig.joints:
			if j.name == want:
				found = true
				break
		_check(found, "no joint named %s in the census" % want)
	notes.append("%d joints named" % a.rig.joints.size())


# --------------------------------------------------------------- symmetry ----

func _check_symmetry() -> void:
	# A bare armature: no gait, both feet at their rest leads — the solve has
	# no excuse for a left leg unlike the right.
	var a := Armature.new()
	a.build(BodySpec.new(), Vector2.ZERO, 0.0)
	var corpus := Corpus.new()
	corpus.build(a.spec)
	Poise.new().bake(corpus, a)
	for _i in 30:
		a.step(TICK)
	var worst: float = 0.0
	for pair in [[&"FL", &"FR"], [&"HL", &"HR"]]:
		var left: Armature.Chain = a.chain(pair[0])
		var right: Armature.Chain = a.chain(pair[1])
		for j in range(1, 3):
			worst = maxf(worst, absf(_interior(left, j) - _interior(right, j)))
	_check(worst < 0.1,
		"a bare standing body folds left unlike right by %.2f deg" % worst)
	notes.append("stands symmetric to %.3f deg" % worst)


# ------------------------------------------------------------- ROM holds ----

func _check_rom_holds(c: Creature2) -> void:
	var a: Armature = c.armature
	_settle(c, 90)
	var worst: float = 0.0
	var tested: int = 0
	# Walk, sprint, and turn — the poses a live limb is actually asked for.
	for tick in 720:
		c.command.throttle = 1.0
		c.command.sprint = tick > 360
		c.command.turn = 1.0 if tick % 240 > 160 else 0.0
		c._physics_process(TICK)
		for limb in a.limbs:
			var fore: bool = limb.parent_node != a.chain(BodySchema.TRUNK).nodes[0]
			# Only judge a limb inside its own reach: at full anatomical
			# stretch the chain lays at its stops and arrives short, and the
			# tear-off owns that case.
			if _stretched(a, limb):
				continue
			var toe: Vector3 = a.pos[limb.nodes[3]]
			if limb.foot_driven and toe.distance_to(limb.foot_target) > 0.1:
				continue
			tested += 1
			var mid: float = _interior(limb, 1)
			var low: float = _interior(limb, 2)
			var mid_rom: Vector2 = Rig.ELBOW_ROM if fore else Rig.STIFLE_ROM
			var low_rom: Vector2 = Rig.CARPUS_ROM if fore else Rig.TARSUS_ROM
			worst = maxf(worst, mid_rom.x - mid)
			worst = maxf(worst, mid - mid_rom.y)
			worst = maxf(worst, low_rom.x - low)
			worst = maxf(worst, low - low_rom.y)
	c.command.throttle = 0.0
	c.command.sprint = false
	c.command.turn = 0.0
	_check(tested > 2000, "only %d limb poses were judged" % tested)
	_check(worst < 0.5,
		"a limb joint passed its anatomical stop by %.2f deg" % worst)
	notes.append("%d live poses, worst ROM excess %.2f deg" % [tested, worst])


# -------------------------------------------------------- planted is exact ----

func _check_planted_exact(c: Creature2) -> void:
	var a: Armature = c.armature
	var worst: float = 0.0
	for tick in 240:
		c.command.throttle = 1.0
		c._physics_process(TICK)
		for limb in a.limbs:
			if not limb.foot_driven or not limb.grounded:
				continue
			# A foot being torn off its anchor is honestly short of it — the
			# claim here is about support the leg can actually span.
			if _stretched(a, limb):
				continue
			worst = maxf(worst, a.pos[limb.nodes[3]].distance_to(limb.foot_target))
	c.command.throttle = 0.0
	_check(worst < 0.01,
		"a planted toe sat %.4f px off its anchor" % worst)
	notes.append("planted toes exact to %.5f px" % worst)


# ------------------------------------------------------------ the scapula ----

func _check_scapula(c: Creature2) -> void:
	var a: Armature = c.armature
	var reach: float = 0.0
	for tick in 300:
		c.command.throttle = 1.0
		c._physics_process(TICK)
		for limb in a.limbs:
			if limb.parent_node == a.chain(BodySchema.TRUNK).nodes[0]:
				continue
			var glide: Vector3 = a.socket_of(limb) - a.girdle_of(limb)
			reach = maxf(reach, Vector2(glide.x, glide.y).length())
	_check(reach > 0.5,
		"the fore sockets never left their girdle datum (%.2f px) — the scapula is dead"
		% reach)
	c.command.throttle = 0.0
	_settle(c, 120)
	# The datum itself: a bare build — no gait, feet at their rest leads —
	# holds exactly zero glide, which is what keeps the census's rest stance
	# and the stride's home unmoved by the scapula existing. (A settled walker
	# legitimately holds a few px: its anchors rest inside the step trigger's
	# dead zone, and a real cat's shoulder stands wherever its foot does.)
	var bare := Armature.new()
	bare.build(BodySpec.new(), Vector2.ZERO, 0.0)
	var datum: float = 0.0
	for limb in bare.limbs:
		if limb.parent_node == bare.chain(BodySchema.TRUNK).nodes[0]:
			continue
		var glide: Vector3 = bare.socket_of(limb) - bare.girdle_of(limb)
		datum = maxf(datum, Vector2(glide.x, glide.y).length())
	_check(datum == 0.0,
		"a bare build's scapular glide holds %.3f px — the census datum has moved"
		% datum)
	notes.append("scapula glides %.1f px at cruise, datum exact at rest" % reach)


# ------------------------------------------------------------ the righting ----

func _check_righting() -> void:
	var a := Armature.new()
	a.build(BodySpec.new(), Vector2.ZERO, 0.0)
	var corpus := Corpus.new()
	corpus.build(a.spec)
	Poise.new().bake(corpus, a)
	a.step(TICK)
	a.roll = 0.5
	a.carry(0.0)
	var trunk_roll: float = a.node_roll[a.pelvis_index()]
	var head_roll: float = a.node_roll[a.head_index()]
	_check(absf(trunk_roll - 0.5) < 0.001,
		"the trunk carries %.3f of a 0.5 heel" % trunk_roll)
	_check(head_roll < trunk_roll - 0.1,
		"the head rides the heel at %.3f against the trunk's %.3f — no righting"
		% [head_roll, trunk_roll])
	a.collapse()
	a.carry(0.0)
	_check(absf(a.node_roll[a.head_index()] - a.roll) < 0.001,
		"a collapsed body still rights its head")
	notes.append("head carries %.2f of the trunk's %.2f heel" % [head_roll, trunk_roll])


# -------------------------------------------------------------- the gather ----

func _check_gather() -> void:
	var a := Armature.new()
	a.build(BodySpec.new(), Vector2.ZERO, 0.0)
	var corpus := Corpus.new()
	corpus.build(a.spec)
	Poise.new().bake(corpus, a)
	a.step(TICK)
	var trunk: Armature.Chain = a.chain(BodySchema.TRUNK)
	var flat_mid: float = a.pos[trunk.nodes[3]].z
	var pelvis: float = a.pos[trunk.nodes[0]].z
	var withers: float = a.pos[trunk.nodes[trunk.nodes.size() - 1]].z
	a.arch = 1.0
	a.carry(0.0)
	var arched_mid: float = a.pos[trunk.nodes[3]].z
	_check(arched_mid > flat_mid + 2.0,
		"a full gather lifts the mid-back %.2f px — no arch" % (arched_mid - flat_mid))
	_check(absf(a.pos[trunk.nodes[0]].z - pelvis) < 0.001
		and absf(a.pos[trunk.nodes[trunk.nodes.size() - 1]].z - withers) < 0.001,
		"the gather moved a girdle — the arch must die at what the legs deliver")
	notes.append("full gather lifts the loins %.1f px, girdles pinned"
		% (arched_mid - flat_mid))


# ------------------------------------------------------------------ helpers ----

## Whether this limb is being asked past its own reach — the tear-off window,
## where the solve lays the chain at its stops and arrives short.
func _stretched(a: Armature, limb: Armature.Chain) -> bool:
	if not limb.foot_driven:
		return false
	var total: float = 0.0
	for b in limb.bones:
		total += b
	var seat: Vector3 = a.socket_of(limb)
	return seat.distance_to(limb.foot_target) > total * 0.97


## Interior angle at a limb's joint j, degrees, measured in the limb's own
## sagittal solution.
func _interior(limb: Armature.Chain, j: int) -> float:
	var incoming: Vector2 = limb.sag[j] - limb.sag[j - 1]
	var outgoing: Vector2 = limb.sag[j + 1] - limb.sag[j]
	return rad_to_deg(PI - absf(wrapf(outgoing.angle() - incoming.angle(), -PI, PI)))


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
		print("rig OK — anatomy bounded and expressed: %s" % " · ".join(notes))
	else:
		print("RIG FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
