## Focused first-slice test for mouse aim, anatomy queries, the layered tissue
## lattice, procedural body/limb contacts and the click/hold bite contract.
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

	_check_skeleton(target)
	_check_tissue(target)
	_check_voids(target)

	# The mouse supplies an articulated-head target, never a locomotion turn or
	# point-and-go throttle. ControlsTest owns the detailed pose geometry.
	var mouse_input := MovementInput.new()
	var aimed: MovementInput.Command = mouse_input.read(Vector2.ZERO, 0.0, Vector2(0.0, 100.0))
	_check(absf(aimed.turn) < 0.001, "mouse aim still wrote the body's turn command")
	_check(absf(aimed.throttle) < 0.001, "mouse aim still applied point-and-go throttle")
	_check(aimed.aim_active and aimed.aim_world.is_equal_approx(Vector2(0.0, 100.0)),
		"enabled mouse look did not carry its aim target into the command")

	_check_bite_contract(player, target)

	_check_contacts(player, target)

	main.queue_free()
	_finish()


## A press starts one strike. If that strike connects while the button remains
## down, it stays clamped at the hit frame without becoming repeated damage;
## release resumes the original recovery. Misses and quick clicks never clamp.
func _check_bite_contract(player: Creature, target: Creature) -> void:
	const APEX: float = Creature.LUNGE_WINDUP + Creature.LUNGE_STRIKE
	var apex_ticks: int = int(ceil(APEX / TICK)) + 2

	# Connected hold: exercise the same synchronous signal/world resolver path as
	# a real left-button press, then keep it held well past every ordinary timer.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(50.0, 0.0), PI)
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected a held bite request")
	var stand: Vector2 = player.head_pos
	player._physics_process(TICK)
	_check(player.is_lunging(), "an accepted held bite did not start a lunge")
	_check(player.lunge_offset < 0.0, "the held lunge skipped its wind-up")
	_check(not main.bite_cue.is_showing(), "the Bite cue appeared before impact")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), 1.0),
		"the held bite landed before the lunge had extended")

	var extension: float = 0.0
	for _i in apex_ticks:
		player._physics_process(TICK)
		extension = maxf(extension, player.body.head.pos.distance_to(player.head_pos))
	var latched_integrity: float = target.anatomy.tissue.integrity()
	_check(latched_integrity < 1.0,
		"the held lunge never resolved into a bite on the nearby target")
	_check(extension > player.params.bite_reach * 0.5,
		"the head was never thrown appreciably forward (%.1f px)" % extension)
	_check(main.bite_cue.is_showing(),
		"the bite impact did not show its world-space Bite cue")
	_check(player.head_pos.is_equal_approx(stand),
		"lunging displaced the creature itself")
	_check(player.bite_connected, "landed held bite was reported as a miss")
	_check(player.is_bite_latched(), "holding a connected bite did not latch it")
	_check(is_equal_approx(player.bite_time, APEX),
		"a connected latch did not hold at the bite apex")
	_check(player.bite_cooldown_remaining > 0.0, "bite did not start its cooldown")

	var held_ticks: int = int(ceil(
		(maxf(player.params.bite_cooldown, Creature.LUNGE_TOTAL) + 0.25) / TICK))
	for _i in held_ticks:
		player._physics_process(TICK)
	_check(player.is_bite_latched(), "connected bite released itself while click stayed held")
	_check(player.is_lunging() and is_equal_approx(player.bite_time, APEX),
		"held bite drifted away from full extension")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), latched_integrity),
		"holding one bite applied tissue damage more than once")
	_check(player.bite_cooldown_remaining <= 0.0,
		"latch test did not actually outlast the cooldown")
	_check(not player.request_bite(Vector2(100.0, 0.0)),
		"second bite was accepted while the first was latched")
	_check(main.scrap_field.scraps.size() > 0,
		"a bite through skin and muscle shed nothing edible into the world")

	# Release must leave the latch immediately, then finish the existing recovery.
	player.set_bite_held(false)
	_check(not player.is_bite_latched(), "button release left the bite latched")
	for _i in int(ceil(Creature.LUNGE_RECOVER / TICK)) + 2:
		player._physics_process(TICK)
	_check(not player.is_lunging(), "released latch never finished its recovery")
	_check(is_equal_approx(player.lunge_offset, 0.0),
		"released latch did not return the head to rest")
	_check(player.can_bite(), "released bite did not become ready after recovery")

	# Holding empty air is still one ordinary bite: it must never manufacture a
	# latch, retry automatically, or remain at full extension.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), PI)
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected a held miss request")
	var miss_latched: bool = false
	for _i in int(ceil(Creature.LUNGE_TOTAL / TICK)) + 4:
		player._physics_process(TICK)
		miss_latched = miss_latched or player.is_bite_latched()
	_check(not miss_latched, "a held miss latched without a target")
	_check(not player.bite_connected, "a bite into empty space reported a connection")
	_check(not player.is_lunging(), "holding a miss prevented normal recovery")
	_check(is_equal_approx(player.lunge_offset, 0.0),
		"held miss did not return the head to rest")
	player.set_bite_held(false)

	# Reset is authoritative even in the middle of a live clamp.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(50.0, 0.0), PI)
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected the reset latch precondition")
	for _i in apex_ticks:
		player._physics_process(TICK)
	_check(player.is_bite_latched(), "reset case never reached its latch precondition")
	player.reset(Vector2.ZERO, 0.0)
	_check(not player.bite_held and not player.bite_latched,
		"reset retained held or latched bite state")
	_check(not player.is_lunging() and is_equal_approx(player.lunge_offset, 0.0),
		"reset retained an active lunge")
	_check(player.can_bite(), "reset did not make the bite immediately ready")

	# A quick press/release before the next physics tick still performs one bite.
	# A deliberately coarse step must stop at its apex rather than skipping damage.
	target.reset(Vector2(50.0, 0.0), PI)
	var quick_before: float = target.anatomy.tissue.integrity()
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected a quick bite request")
	player.set_bite_held(false)
	player._physics_process(Creature.LUNGE_TOTAL * 2.0)
	var quick_impact: float = target.anatomy.tissue.integrity()
	_check(quick_impact < quick_before,
		"a coarse tick stepped over the quick bite's hit frame")
	_check(player.bite_connected, "quick released bite was reported as a miss")
	_check(not player.is_bite_latched(), "quick released bite latched after release")
	player._physics_process(Creature.LUNGE_TOTAL * 2.0)
	_check(not player.is_lunging(), "quick released bite never completed recovery")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), quick_impact),
		"one quick click resolved more than one bite")


## The skeleton has to stay a frame rather than spread into a plate. If bone
## covers most of the body there is no such thing as eating through it: every
## wound bottoms out on the same pale surface, nothing ever opens onto the
## ground, and the skull, ribs and vertebrae stop being distinguishable.
func _check_skeleton(target: Creature) -> void:
	var body: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var boned: int = 0
	for cell in body.cells:
		boned += body.bone[cell]
	var covered: float = float(boned) / float(body.cells)
	_check(covered < 0.5,
		"bone covers %.0f%% of the body — that is a plate, not a skeleton" % (covered * 100.0))

	# Bone per column, so the *shape* can be asserted rather than just the total.
	# A column carrying only the vertebral column counts 1.
	var per_column: PackedInt32Array = PackedInt32Array()
	per_column.resize(body.cols)
	for c in body.cols:
		var n: int = 0
		for r in body.rows:
			n += body.bone[c * body.rows + r]
		per_column[c] = n

	# Every crossbar over the torso — girdle or rib — must have a flesh-only
	# column either side of it, or the chest is one continuous shell and a bite
	# can never land between two ribs.
	var freestanding: int = 0
	for c in range(TissueGrid.HEAD_COLS, TissueGrid.HEAD_COLS + TissueGrid.TORSO_COLS):
		if per_column[c] > 1 and per_column[c - 1] == 1 and per_column[c + 1] == 1:
			freestanding += 1
	_check(freestanding >= 3,
		"only %d free-standing crossbars over the torso — the ribcage is not a cage" % freestanding)

	# Behind the hips there is nothing but vertebrae.
	var tail_clear: bool = true
	for c in range(TissueGrid.HEAD_COLS + TissueGrid.TORSO_COLS, body.cols):
		tail_clear = tail_clear and per_column[c] == 1
	_check(tail_clear, "the tail carries more than a vertebral column")

	# The frame has to be one piece, joined bone to bone. Flesh is what a bite
	# takes first, so a skeleton whose parts only meet through muscle falls into
	# floating fragments exactly when a creature has been chewed down to it —
	# which is the one time the skeleton is the whole of what you are looking at.
	var reached: Dictionary = {}
	var stack: Array[int] = []
	for r in body.rows:
		if body.bone[r] == 1:  # seed from the snout column, at the far end of it
			reached[r] = true
			stack.append(r)
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		var c: int = cell / body.rows
		var r2: int = cell % body.rows
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: int = c + step.x
			var nr: int = r2 + step.y
			if nc < 0 or nc >= body.cols or nr < 0 or nr >= body.rows:
				continue
			var n: int = nc * body.rows + nr
			if body.bone[n] == 1 and not reached.has(n):
				reached[n] = true
				stack.append(n)
	_check(reached.size() == boned,
		"%d bone cells are not joined to the skull — the skeleton is in pieces"
			% (boned - reached.size()))

	# ...and the limbs hang off it. A socket over flesh means a limb bone tied to
	# the axial skeleton by nothing but the meat around it.
	for limb in target.gait.limbs:
		_check(body.bone[_nearest_cell(body, limb.joints[0])] == 1,
			"the %s socket sits over flesh, not over a girdle" % limb.key)


## Tissue eaten through every layer has to be genuinely gone, not painted the
## colour of the ground. Ground-coloured cells look right only against an empty
## background: they still hide whatever is behind the creature, and — the part
## that actually matters — the body still collides and hit-tests as though the
## tissue were there, so a creature can be eaten hollow and still be a wall.
##
## So three things have to agree that a hole is a hole: the lattice retires the
## cell, the body stops colliding where it used to be, and the bite query stops
## finding anything to bite there.
func _check_voids(target: Creature) -> void:
	target.anatomy.reset()
	target._physics_process(TICK)
	var tissue: TissueGrid = target.anatomy.tissue
	var body: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	var last: int = target.body.last_index
	_check(body.gone_count == 0, "an untouched creature already had holes in it")

	# Well behind the ribcage, so this is flesh over a single vertebra rather
	# than over a crossbar, and a bite can reach every layer of it.
	var station: int = clampi(int(round(float(last) * 0.75)), 2, last - 2)
	var t: float = float(station) / float(last)
	var perp: Vector2 = target.spine.perps[station]
	var axis: Vector2 = target.spine.points[station]
	var flank: Vector2 = axis + perp * (target.body.widths[station] * 0.7)

	_check(is_equal_approx(tissue.body_solid(t, 1.0), 1.0),
		"an intact flank did not report its full width")
	_check(target.push_out_of_body(flank, 1.0) != Vector2.ZERO,
		"the intact flank collided with nothing — the probe proves nothing")
	_check(target.query_bite(flank, 1.0) != null, "the intact flank was not hit-testable")

	# One flank first: eating into a body from one side must not thin the other.
	var shed: Array = []
	for _i in 10:
		tissue.bite(flank, 7.0, 3.0, shed)
	_check(body.gone_count > 0, "cells stripped of every layer were never retired")
	_check(body.gone[_nearest_cell(body, flank)] == 1,
		"the cell under a bite that ate skin, muscle and all was still reported as tissue")
	_check(tissue.body_solid(t, 1.0) < 1.0,
		"eating a flank open did not narrow the body there")
	_check(is_equal_approx(tissue.body_solid(t, -1.0), 1.0),
		"eating one flank thinned the other one too")

	# Now the whole cross-section, three stations wide so the neighbouring
	# capsules cannot reach the probe and answer for the piece that is gone.
	for s in range(station - 1, station + 2):
		for _i in 16:
			tissue.bite(target.spine.points[s], 13.0, 3.0, shed)
	_check(is_equal_approx(tissue.body_solid(t, 1.0), 0.0)
			and is_equal_approx(tissue.body_solid(t, -1.0), 0.0),
		"a station eaten clean through still reported tissue standing on it")
	_check(target.push_out_of_body(axis, 1.0) == Vector2.ZERO,
		"a hole eaten clean through the body is still solid to walk into")
	_check(target.query_bite(axis, 1.0) == null,
		"jaws closing on a hole still found tissue to bite")

	# Both halves of a contact have to know about the hole, not just the body
	# being walked into: a creature eaten open must also stop shoving others
	# away at the width it no longer has.
	_check(is_equal_approx(target._solid_at(station, last), 0.0),
		"an eaten-through station still probed other bodies at its old width")
	_check(target._solid_at(1, last) > 0.0,
		"an intact station stopped probing other bodies at all")

	# The rest of the creature is untouched by any of that — the void is local,
	# not a body that has quietly stopped colliding altogether.
	var intact: Vector2 = target.spine.points[1]
	_check(target.push_out_of_body(intact, 1.0) != Vector2.ZERO,
		"opening a hole in the tail stopped the whole body colliding")
	_check(target.query_bite(intact, 1.0) != null,
		"opening a hole in the tail made the whole body un-biteable")


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

	# The damage solver stays cell-precise, but neighbouring cells destroyed by
	# one tear must leave as fewer, larger pieces rather than one scrap each.
	var cohort := TissueGrid.new()
	cohort.update(target)
	var cohort_shed: Array = []
	cohort.bite(flank, 12.0, 8.0, cohort_shed)
	var cohort_body: TissueGrid.Patch = cohort.patch(TissueGrid.BODY_KEY)
	var destroyed_layers: int = 0
	for cohort_cell in cohort_body.cells:
		var cohort_base: int = cohort_cell * TissueGrid.LAYERS
		destroyed_layers += 1 if cohort_body.hp[cohort_base + TissueGrid.SKIN] <= 0.0 else 0
		destroyed_layers += 1 if cohort_body.hp[cohort_base + TissueGrid.MUSCLE] <= 0.0 else 0
	_check(destroyed_layers > cohort_shed.size(),
		"one bite still emitted one loose scrap per destroyed tissue cell")
	var reference_extent: float = cohort_body.extent_of(_nearest_cell(cohort_body, flank))
	var largest_piece: float = 0.0
	for piece in cohort_shed:
		largest_piece = maxf(largest_piece, piece.size)
	_check(largest_piece > reference_extent * 1.25,
		"adjacent destroyed cells did not form a visibly larger piece")

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
	var found_weighty_piece: bool = false
	for piece in shed:
		found_weighty_piece = found_weighty_piece or (piece.size > 3.0 and piece.mass > 9.0)
	_check(found_weighty_piece, "shed tissue still consisted only of cell-sized pixels")
	# Nothing under the flesh there, so eating it opens a hole clean through to
	# the ground rather than bottoming out on a skeleton.
	_check(body.hp[base + TissueGrid.BONE] <= 0.0,
		"a cell with no skeleton under it still had bone left to stop the bite")

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


## Bodies are solid. A creature driven at another is stopped by it, two that
## start inside each other push apart without stretching either spine, and a
## creature with nobody near it is not displaced by the pass at all.
func _check_contacts(player: Creature, target: Creature) -> void:
	# Held at full throttle straight into a stationary body for four seconds —
	# twice as long as it takes to cover the gap.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(220.0, 0.0), PI)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _i in 240:
		player.command = drive
		player._physics_process(TICK)
		target._physics_process(TICK)
	var nose_to_nose: float = player.head_pos.distance_to(target.head_pos)
	_check(player.head_pos.x < target.head_pos.x,
		"a creature driven at another walked straight through it")
	_check(nose_to_nose < player.body.head_radius + target.body.head_radius + 6.0,
		"the driven creature stopped %.0f px short of anything to stop it" % nose_to_nose)
	_check(absf(player.speed) < player.params.move_speed * 0.25,
		"a creature pressed against another kept its walking speed (%.0f px/s)" % player.speed)
	_check(_deepest_overlap(player, target) < 1.0,
		"a creature driven at another came to rest inside it")
	_check(player._push_out_of_creature(target).length() < 1.0,
		"capsule contacts found a resting overlap that point probes missed")

	# Laid down alongside each other, deeply interpenetrating: the worst case for
	# a chain solve, since the correction has to survive the constraint pass that
	# runs immediately after it.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(-70.0, 5.0), 0.0)
	var overlap_before: float = _deepest_overlap(player, target)
	_check(overlap_before > 10.0,
		"the contact case did not start overlapping (%.1f px) — it proves nothing" % overlap_before)

	# A contact correction is a change in the creature's world position, not a
	# deformation. Every current and previous particle must receive exactly the
	# same shift or the constraint solver will turn separation into body flailing.
	var points_before: PackedVector2Array = player.spine.points.duplicate()
	var prev_before: PackedVector2Array = player.spine.prev.duplicate()
	var head_before: Vector2 = player.head_pos
	player._resolve_contacts()
	var rigid_shift: Vector2 = player.head_pos - head_before
	_check(rigid_shift.length() > 0.1, "deep contact produced no correction")
	var nonrigid_error: float = 0.0
	for i in player.spine.size():
		nonrigid_error = maxf(nonrigid_error,
			(player.spine.points[i] - points_before[i] - rigid_shift).length())
		nonrigid_error = maxf(nonrigid_error,
			(player.spine.prev[i] - prev_before[i] - rigid_shift).length())
	_check(nonrigid_error < 0.001,
		"contact bent the spine while separating it (%.3f px non-rigid shift)" % nonrigid_error)

	# Reset because the direct pass above intentionally stopped between the
	# contact phase and the normal spine/body rebuild.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(-70.0, 5.0), 0.0)

	for _i in 180:
		player._physics_process(TICK)
		target._physics_process(TICK)
	var overlap_after: float = _deepest_overlap(player, target)
	_check(overlap_after < 1.0,
		"two creatures inside each other never separated (%.1f px still overlapping)" % overlap_after)
	_check(_worst_segment_error(player) < 0.05 and _worst_segment_error(target) < 0.05,
		"contact pushes stretched a spine past its segment lengths")

	# Nothing near it, nothing done to it: the contact pass must be inert at range
	# or every creature in the world would drift.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)
	var undisturbed: Vector2 = player.head_pos
	for _i in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(player.head_pos.is_equal_approx(undisturbed),
		"a creature with nobody near it was displaced by the contact pass")

	# Put another creature's snout directly through a lower foreleg while the
	# two torsos remain clear. The procedural gait must route the chain around
	# that body, retain exact bone lengths, and persist the displaced plant
	# instead of drawing the same penetrating pose again on every tick.
	player.reset(Vector2.ZERO, 0.0)
	var contact_limb: Limb = player.gait.limbs[0]
	var obstacle_at: Vector2 = contact_limb.joints[1].lerp(contact_limb.joints[2], 0.55)
	var relative_knee_before: Vector2 = contact_limb.joints[1] - contact_limb.joints[0]
	target.reset(obstacle_at, -PI * 0.5)
	var torso_overlap: float = player._push_out_of_creature(target).length()
	var limb_overlap_before: float = _limb_body_overlap(player, contact_limb, target)
	_check(torso_overlap < 1.0,
		"limb collision case also overlapped the torsos (%.2f px)" % torso_overlap)
	_check(limb_overlap_before > 8.0,
		"limb collision case did not start deeply intersecting (%.2f px)" % limb_overlap_before)

	for _i in 12:
		player._physics_process(TICK)
	var limb_overlap_after: float = _limb_body_overlap(player, contact_limb, target)
	var relative_knee_after: Vector2 = contact_limb.joints[1] - contact_limb.joints[0]
	_check(limb_overlap_after < 1.0,
		"procedural limb stayed inside the other body (%.2f px)" % limb_overlap_after)
	_check(relative_knee_after.distance_to(relative_knee_before) > 2.0,
		"colliding limb did not change its bend around the obstacle")
	for bone in 2:
		var actual: float = contact_limb.joints[bone].distance_to(contact_limb.joints[bone + 1])
		_check(absf(actual - contact_limb.lengths[bone]) < 0.05,
			"limb collision changed bone %d length by %.2f px" \
				% [bone, absf(actual - contact_limb.lengths[bone])])

	# Sparse, narrow chains crossing halfway along two long segments. None of
	# their spine points is inside the other body, so the former point-probe
	# solver saw no collision at all even though the drawn capsules intersected.
	var saved_player := CreatureParams.new()
	var saved_target := CreatureParams.new()
	saved_player.copy_from(player.params)
	saved_target.copy_from(target.params)
	for p: CreatureParams in [player.params, target.params]:
		p.segment_count = 6
		p.segment_length = 40.0
		p.body_wave = 0.0
		p.head_width = 1.0
		p.chest_width = 1.0
		p.waist_width = 1.0
		p.hip_width = 1.0
		p.tail_tip_width = 1.0
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(-20.0, 20.0), PI * 0.5)
	var endpoint_overlap: float = maxf(
		_deepest_overlap(player, target), _deepest_overlap(target, player))
	var capsule_overlap: float = player._push_out_of_creature(target).length()
	_check(endpoint_overlap < 0.001,
		"mid-segment regression accidentally touched an endpoint (%.2f px)" % endpoint_overlap)
	_check(capsule_overlap > 1.5,
		"crossing capsule axes were missed (%.2f px overlap reported)" % capsule_overlap)

	for _i in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(player._push_out_of_creature(target).length() < 0.1,
		"crossing mid-segments remained interlocked after contact resolution")

	player.params.copy_from(saved_player)
	target.params.copy_from(saved_target)
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)


## Deepest interpenetration of `a`'s body into `b`'s, in pixels.
func _deepest_overlap(a: Creature, b: Creature) -> float:
	var worst: float = 0.0
	var last: int = mini(a.body.last_index, a.spine.size() - 1)
	for i in range(last + 1):
		worst = maxf(worst, b.push_out_of_body(a.spine.points[i], a.body.widths[i]).length())
	return worst


func _worst_segment_error(creature: Creature) -> float:
	var seg_len: float = creature.params.segment_length * creature.size_scale
	var worst: float = 0.0
	for i in range(1, creature.spine.size()):
		var d: float = creature.spine.points[i - 1].distance_to(creature.spine.points[i])
		worst = maxf(worst, absf(d - seg_len) / seg_len)
	return worst


## Deepest overlap of either bone or the foot with `obstacle`'s body.
func _limb_body_overlap(owner: Creature, limb: Limb, obstacle: Creature) -> float:
	var upper_radius: float = maxf(limb.total_length * 0.16, 2.5 * owner.size_scale) * 0.5
	var radii: Array[float] = [upper_radius, upper_radius * 0.72]
	var preferred: Vector2 = owner.bounds_center - obstacle.bounds_center
	var worst: float = 0.0
	for segment in 2:
		worst = maxf(worst, obstacle.push_capsule_out_of_body(
			limb.joints[segment], limb.joints[segment + 1], radii[segment], preferred).length())
	var foot_radius: float = maxf(limb.total_length * 0.10, 3.0 * owner.size_scale)
	worst = maxf(worst, obstacle.push_capsule_out_of_body(
		limb.joints[2], limb.joints[2], foot_radius, preferred).length())
	return worst


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
		print("combat slice OK — target, anatomy, tissue, lunge, cooldown, body and limb contacts")
		quit(0)
	else:
		for failure in failures:
			print("COMBAT FAIL — ", failure)
		quit(1)
