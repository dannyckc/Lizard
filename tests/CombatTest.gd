## Focused first-slice test for mouse aim, anatomy queries, the layered tissue
## lattice and the one-click/one-bite cooldown contract.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/CombatTest.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

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
	var target: Creature = main.target_creature
	_check(player != null, "player creature was not instantiated")
	_check(target != null, "stationary target creature was not instantiated")
	if player == null or target == null:
		_finish()
		return

	_check(target.head_pos.is_equal_approx(Vector2(360.0, 0.0)),
		"target did not use its simulation-space spawn position")
	var stationary_mark: Vector2 = target.head_pos
	target._physics_process(TICK)
	_check(target.head_pos.distance_to(stationary_mark) < 0.001,
		"target moved without a command")

	# Each visible procedural primitive must map to the expected tissue family.
	var head_hit: AnatomyState.Hit = target.query_bite(target.body.head.pos, 1.0)
	_check(head_hit != null and head_hit.kind == AnatomyState.HEAD,
		"head circle did not resolve to head tissue")

	var torso_index: int = mini(4, target.body.last_index - 1)
	var torso_point: Vector2 = target.spine.points[torso_index] \
		+ target.spine.perps[torso_index] * target.body.widths[torso_index]
	var torso_hit: AnatomyState.Hit = target.query_bite(torso_point, 1.0)
	_check(torso_hit != null and torso_hit.kind == AnatomyState.TORSO,
		"body flank did not resolve to torso tissue")

	var test_limb: Limb = target.gait.limbs[0]
	var lower_midpoint: Vector2 = test_limb.joints[1].lerp(test_limb.joints[2], 0.5)
	var limb_hit: AnatomyState.Hit = target.query_bite(lower_midpoint, 1.0)
	_check(limb_hit != null and limb_hit.kind == AnatomyState.LIMB,
		"drawn limb capsule did not resolve to limb tissue")

	_check_tissue(target)

	# Mouse aim turns without secretly applying forward throttle.
	var mouse_input := MovementInput.new()
	var aimed: MovementInput.Command = mouse_input.read(Vector2.ZERO, 0.0, Vector2(0.0, 100.0))
	_check(aimed.turn > 0.9, "always-on mouse aim did not steer toward the cursor")
	_check(absf(aimed.throttle) < 0.001, "mouse aim still applied point-and-go throttle")

	# Put the two heads inside bite range and exercise the real signal/world
	# resolver path used by a left click.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(50.0, 0.0), PI)
	var accepted: bool = player.request_bite(Vector2(100.0, 0.0))
	_check(accepted, "ready player rejected a bite request")
	var stand: Vector2 = player.head_pos
	player._physics_process(TICK)
	_check(player.is_lunging(), "an accepted bite did not start a lunge")
	_check(player.lunge_offset < 0.0, "the lunge skipped its wind-up")
	_check(player.jaw_open() > 0.0, "the jaws never opened")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), 1.0),
		"the bite landed before the lunge had extended")

	# The strike resolves at full extension, several ticks after the click —
	# that is the point of the animation, so it is worth pinning down.
	var extension: float = 0.0
	for _i in int(ceil((Creature.LUNGE_WINDUP + Creature.LUNGE_STRIKE) / TICK)) + 1:
		player._physics_process(TICK)
		extension = maxf(extension, player.body.head.pos.distance_to(player.head_pos))
	_check(target.anatomy.tissue.integrity() < 1.0,
		"the lunge never resolved into a bite on the nearby target")
	_check(extension > player.params.bite_reach * 0.5,
		"the head was never thrown appreciably forward (%.1f px)" % extension)
	_check(is_equal_approx(player.jaw_open(), 0.0), "the jaws did not snap shut on impact")
	# The whole reason the throw is fed to the spine and not to the motion
	# state: a strike must not walk the creature forward by its own reach.
	_check(player.head_pos.is_equal_approx(stand),
		"lunging displaced the creature itself")
	_check(player.bite_connected, "landed bite was reported as a miss")
	_check(player.bite_cooldown_remaining > 0.0, "bite did not start its cooldown")
	_check(not player.request_bite(Vector2(100.0, 0.0)),
		"second click was accepted during bite cooldown")

	for _i in 32:
		player._physics_process(TICK)
	_check(player.can_bite(), "bite did not become ready after its cooldown")
	_check(not player.is_lunging(), "the lunge never ended")
	_check(is_equal_approx(player.lunge_offset, 0.0),
		"the lunge did not return the head to its resting position")
	_check(main.scrap_field.scraps.size() > 0,
		"a bite through skin and muscle shed nothing edible into the world")

	# One click is one hit frame however coarse the tick carrying it, and that
	# frame still resolves at full extension rather than from resting reach.
	var before: float = target.anatomy.tissue.integrity()
	_check(player.request_bite(Vector2(100.0, 0.0)), "ready player rejected a bite request")
	player._physics_process(Creature.LUNGE_TOTAL * 2.0)
	_check(target.anatomy.tissue.integrity() < before,
		"a tick longer than the whole lunge stepped over its hit frame")

	main.queue_free()
	_finish()


## The layered lattice: bites eat strictly outside-in, land only where they
## land, cost far more through bone, and survive the pose being rebuilt — and
## the spine being restructured — underneath them.
func _check_tissue(target: Creature) -> void:
	var tissue: TissueGrid = target.anatomy.tissue
	var body: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	_check(body != null and body.live, "the body tissue lattice was never posed")
	if body == null or not body.live:
		return

	# Behind the ribcage and well off the midline, so this column is pure flesh
	# and can be eaten clean through.
	var station: int = clampi(int(round(float(target.body.last_index) * 0.75)),
		1, target.body.last_index - 1)
	var flank: Vector2 = target.spine.points[station] \
		+ target.spine.perps[station] * (target.body.widths[station] * 0.75)
	var cell: int = _nearest_cell(body, flank)
	var base: int = cell * TissueGrid.LAYERS
	_check(body.bone[cell] == 0, "the flank sample sits over bone, not flesh")

	var elsewhere: int = _nearest_cell(body, target.body.head.pos)
	var elsewhere_before: float = body.hp[elsewhere * TissueGrid.LAYERS]

	var shed: Array = []
	var removed: float = tissue.bite(flank, 10.0, TissueGrid.SKIN_HP * 0.5, shed)
	_check(removed > 0.0, "a bite on the flank removed no tissue")
	_check(not body.damaged.is_empty(), "damaged cells were not recorded for drawing")
	_check(body.hp[base + TissueGrid.SKIN] < TissueGrid.SKIN_HP,
		"skin directly under the bite was not eroded")
	_check(is_equal_approx(body.hp[base + TissueGrid.MUSCLE], TissueGrid.MUSCLE_HP),
		"muscle took damage before the skin over it was gone")
	_check(shed.is_empty(), "a bite that only grazed the skin still shed chunks")
	_check(is_equal_approx(body.hp[elsewhere * TissueGrid.LAYERS], elsewhere_before),
		"a bite damaged cells nowhere near where it landed")

	for _i in 6:
		tissue.bite(flank, 10.0, 2.0, shed)
	_check(body.hp[base + TissueGrid.MUSCLE] <= 0.0,
		"repeated bites never ate through skin and muscle")
	_check(shed.size() >= 2, "destroyed skin and muscle shed no edible chunks")

	# Bone is not merely more tissue: it yields at half rate and stops the bite,
	# so a skeletal cell has to outlast the flesh beside it by a wide margin.
	var midline: Vector2 = target.spine.points[station]
	var bone_cell: int = _nearest_cell(body, midline)
	_check(body.bone[bone_cell] == 1, "the midline sample is not over the vertebral column")
	var bone_hp: int = bone_cell * TissueGrid.LAYERS + TissueGrid.BONE
	var bites: int = 0
	while body.hp[bone_hp] > 0.0 and bites < 40:
		tissue.bite(midline, 6.0, 2.6, shed)
		bites += 1
	_check(bites > 4, "bone broke in %d bites — no harder to get through than flesh" % bites)

	# Damage is held in body space precisely so neither of these can wash it off.
	var scars: int = body.damaged.size()
	var integrity: float = tissue.integrity()
	_check(integrity < 1.0, "eating through the body did not reduce its integrity")
	target.rebuild()
	_check(is_equal_approx(tissue.integrity(), integrity),
		"a procedural rebuild restored lost tissue")
	_check(tissue.patch(TissueGrid.BODY_KEY).damaged.size() == scars,
		"a procedural rebuild erased the lattice's damage")

	target.params.segment_count = target.params.segment_count + 6
	target._physics_process(TICK)
	_check(target.spine.size() == target.params.segment_count,
		"changing segment count did not restructure the spine")
	_check(is_equal_approx(tissue.integrity(), integrity),
		"restructuring the spine remapped or erased existing damage")


func _nearest_cell(patch: TissueGrid.Patch, at: Vector2) -> int:
	var best: int = 0
	var best_distance: float = INF
	for cell in patch.cells:
		var d: float = patch.centre_of(cell).distance_squared_to(at)
		if d < best_distance:
			best_distance = d
			best = cell
	return best


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("combat slice OK — target, anatomy, layered tissue, lunge, aim and cooldown")
		quit(0)
	else:
		for failure in failures:
			print("COMBAT FAIL — ", failure)
		quit(1)
