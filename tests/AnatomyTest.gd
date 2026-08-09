## The anatomy slice: that the body is built out of the structures it claims to
## be, that those structures protect each other in the order they are stacked in,
## and that losing one of them has the consequence it is supposed to have — all
## the way through to how the creature walks.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/AnatomyTest.gd
##
## The checks are deliberately weighted toward the seam this whole system exists
## to create: that *what happened* and *what it does* are two different questions
## with two different answers. A limb whose nerve is cut and a limb whose muscle
## is gone are both weak, and nothing but this suite says they are weak for
## different reasons and behave differently as a result.
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
	var subject: Creature = main.target_creature
	if subject == null:
		_check(false, "no creature to dissect")
		_finish()
		return
	# The habitat's body is placed as a carcass. Everything below is about a living
	# animal losing function, so it is revived first — exactly as CombatTest does.
	subject.alive = true
	subject.reset(subject.spawn_position, subject.spawn_heading)
	subject._physics_process(TICK)

	_check_composition(subject)
	_check_organs_are_enclosed(subject)
	_check_networks_are_trees(subject)
	_check_healthy_body_is_nominal(subject)
	_check_fat_cushions(subject)
	_check_skull_protects_brain(subject)
	_check_shielding_separates_the_networks(subject)
	_check_muscle_nerve_blood_are_independent(subject)
	_check_ischaemia_is_progressive(subject)
	_check_bone_is_structural(subject)
	_check_limp_is_asymmetry(subject)
	_check_dead_nerve_drags(subject)
	_check_damage_costs_travel(subject)
	_check_brain_collapses_the_body(subject)
	_check_heart_stops_it_slowly(subject)
	_check_severed_limb_leaves(subject)
	_check_severance_needs_every_tissue(subject)
	_check_broken_limb_dangles(subject)
	_check_tail_comes_off(subject)
	_check_a_severed_head_takes_the_brain(subject)
	_check_a_cut_sheds_only_what_is_past_it(subject)
	_finish()


# ------------------------------------------------------------ composition ----

## Every tissue the design lists is actually in the lattice, in the right place.
func _check_composition(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	var body: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)

	var skinned: int = 0
	var fatted: int = 0
	var muscled: int = 0
	var boned: int = 0
	var organed: int = 0
	for cell in body.cells:
		var base: int = cell * TissueGrid.LAYERS
		skinned += 1 if body.hp[base + TissueGrid.SKIN] > 0.0 else 0
		fatted += 1 if body.hp[base + TissueGrid.FAT] > 0.0 else 0
		muscled += 1 if body.hp[base + TissueGrid.MUSCLE] > 0.0 else 0
		boned += 1 if body.hp[base + TissueGrid.BONE] > 0.0 else 0
		organed += 1 if body.hp[base + TissueGrid.ORGAN] > 0.0 else 0
	_check(skinned == body.cells, "not every body cell has skin")
	_check(fatted == body.cells, "not every body cell carries fat")
	_check(muscled == body.cells, "not every body cell has muscle")
	_check(boned > 0 and boned < body.cells, "bone is either absent or a solid plate")
	_check(organed > 0, "no organ tissue anywhere in the body")

	# Regions have to partition the animal — every cell in exactly one, and none
	# of the plan's regions empty, or the functional layer is quoting averages
	# over parts of a creature that do not exist.
	var populated: PackedInt32Array = PackedInt32Array()
	populated.resize(BodyPlan.REGIONS)
	for key in tissue.patches:
		var patch: TissueGrid.Patch = tissue.patches[key]
		for cell in patch.cells:
			populated[patch.region[cell]] += 1
	for index in BodyPlan.REGIONS:
		_check(populated[index] > 0,
			"region %s has no cells in it" % c.anatomy.plan.region_name(index))

	# And fat has to be laid down as a profile, not a constant: it is body shape
	# as well as protection, so a trunk padded exactly like an ankle is wrong.
	var trunk: float = tissue.region_layer(BodyPlan.LUMBAR, TissueGrid.FAT)
	_check(is_equal_approx(trunk, 1.0), "an untouched trunk was not fully fat")
	var plan: BodyPlan = c.anatomy.plan
	_check(plan.fat_at(TissueGrid.BODY_KEY, BodyPlan.HEAD_COLS + BodyPlan.LUMBAR_COL, 0.9)
			> plan.fat_at("FL", 8, 0.0) * 2.0,
		"fat is spread evenly over the animal rather than laid over its trunk")


## The brain is in the skull and the heart is in the ribcage — physically, as a
## fact about which cells they occupy, and not as a rule enforced anywhere.
##
## This is the check that makes the protection claim true rather than intended:
## the depth stack only shields an organ if there is bone in the same cell, so an
## organ cell without bone is an organ lying in the open however central it looks.
func _check_organs_are_enclosed(c: Creature) -> void:
	var body: TissueGrid.Patch = c.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var brain: int = 0
	var heart: int = 0
	var exposed: int = 0
	for cell in body.cells:
		var which: int = body.organ[cell]
		if which == BodyPlan.NO_ORGAN:
			continue
		if body.bone[cell] == 0:
			exposed += 1
		if which == BodyPlan.BRAIN:
			brain += 1
			_check(cell / BodyPlan.BODY_ROWS < BodyPlan.HEAD_COLS,
				"a piece of brain was laid outside the head")
		else:
			heart += 1
	_check(brain > 0, "the creature has no brain")
	_check(heart > 0, "the creature has no heart")
	_check(exposed == 0,
		"%d organ cells have no bone over them — they are not enclosed by anything" % exposed)


## Both networks reach every region from their root, and each is a tree rather
## than a set of disconnected runs.
func _check_networks_are_trees(c: Creature) -> void:
	var state: BodyState = c.anatomy.state
	for index in BodyPlan.REGIONS:
		_check(state.nerves.delivery[index] > 0.9,
			"an intact body does not innervate %s" % state.plan.region_name(index))
		_check(state.vessels.delivery[index] > 0.9,
			"an intact body does not perfuse %s" % state.plan.region_name(index))
	# One root apiece, and they are different ones — which is the whole reason a
	# broken neck and an opened chest are different injuries.
	_check(state.plan.nerve_root != state.plan.vessel_root,
		"the two networks are fed from the same place")
	var roots: int = 0
	for run in state.plan.nerves:
		roots += 1 if run.parent < 0 else 0
	_check(roots == 1, "the nervous system has %d roots" % roots)


## An animal nobody has touched must report itself entirely nominal, because
## every consuming system short-circuits on that and would otherwise be quietly
## multiplying its gait by numbers that are almost, but not quite, one.
func _check_healthy_body_is_nominal(c: Creature) -> void:
	_restore(c)
	for _i in 120:
		c._physics_process(TICK)
	var state: BodyState = c.anatomy.state
	_check(not state.impaired, "an undamaged creature reported itself impaired")
	_check(not state.collapsed, "an undamaged creature reported itself collapsed")
	_check(state.support == BodyPlan.LIMB_REGIONS.size(),
		"an undamaged creature was not standing on all its legs")
	_check(is_equal_approx(state.locomotion, 1.0) and is_equal_approx(state.coordination, 1.0),
		"an undamaged creature does not have all of its locomotion")
	for limb in c.gait.limbs:
		_check(is_equal_approx(limb.drive, 1.0) and is_equal_approx(limb.reach, 1.0),
			"limb %s was modulated on an undamaged creature" % limb.key)


# -------------------------------------------------------------- protection ----

## Padding is protection, and specifically it is protection *of what is under it*.
## The same jaws closing the same distance into a fat animal reach less of its
## muscle, because the fat spent part of the bite on the way through.
func _check_fat_cushions(c: Creature) -> void:
	var cell: int = _flank_cell(c)
	var lean: float = _muscle_after_bite(c, 0.0, cell)
	var padded: float = _muscle_after_bite(c, 3.0, cell)
	_check(padded > lean + 0.2,
		"fat did not cushion: the same bite left %.2f muscle on a lean body and %.2f on a padded one"
			% [lean, padded])
	c.params.fat_reserve = 1.0
	_restore(c)


## Muscle left in one cell after one identical bite, at a given fat reserve.
func _muscle_after_bite(c: Creature, reserve: float, cell: int) -> float:
	c.params.fat_reserve = reserve
	c.rebuild()
	c._physics_process(TICK)
	_bite_cell(c, TissueGrid.BODY_KEY, cell, 3.0, 1)
	var body: TissueGrid.Patch = c.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	return body.hp[cell * TissueGrid.LAYERS + TissueGrid.MUSCLE]


## Nothing reaches the brain until the skull has actually been broken through.
##
## Asserted every bite of the way rather than only at the end, because the claim
## is an invariant and not an outcome: while there is any bone left in that cell,
## the organ under it must be untouched.
func _check_skull_protects_brain(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	var body: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	var cell: int = _organ_cell(body, BodyPlan.BRAIN)
	_check(cell >= 0, "could not find a brain cell to bite")
	if cell < 0:
		return

	var base: int = cell * TissueGrid.LAYERS
	var breached: int = -1
	for attempt in 24:
		_bite_cell(c, TissueGrid.BODY_KEY, cell, 4.0, 1)
		var bone: float = body.hp[base + TissueGrid.BONE]
		var organ: float = body.hp[base + TissueGrid.ORGAN]
		if bone > 0.0:
			_check(is_equal_approx(organ, TissueGrid.ORGAN_HP),
				"a bite reached the brain through %.1f hit points of intact skull" % bone)
		elif breached < 0:
			breached = attempt
	_check(breached > 0, "the skull never gave way at all")
	_check(breached >= 2,
		"the skull was through in %d bites — that is not a braincase" % (breached + 1))
	_check(tissue.organ(BodyPlan.BRAIN) < 1.0,
		"the brain was never damaged even with the skull open")


# ------------------------------------------------------------ connectivity ----

## The one structural difference between the two networks, and what it buys.
##
## The spinal cord runs inside the vertebrae and the great vessels run against
## them. So a wound deep enough to take the muscle over the spine opens the vessel
## and leaves the cord alone; only breaking the bone itself cuts the cord. Two
## injuries in the same place with entirely different consequences, and neither is
## written down anywhere as a case.
func _check_shielding_separates_the_networks(c: Creature) -> void:
	_restore(c)
	var state: BodyState = c.anatomy.state
	var cell: int = _cord_cell(c, BodyPlan.LUMBAR)

	# Down to the bone, and no further.
	_bite_to_bone(c, cell)
	c._physics_process(TICK)
	_check(state.vessels.integrity[BodyPlan.LUMBAR] <= 0.01,
		"taking the flesh off the spine did not open the vessel lying on it (%.2f)"
			% state.vessels.integrity[BodyPlan.LUMBAR])
	_check(state.nerves.integrity[BodyPlan.LUMBAR] > 0.9,
		"the spinal cord was cut without the vertebra being broken (%.2f)"
			% state.nerves.integrity[BodyPlan.LUMBAR])
	_check(state.regions[BodyPlan.RL].control > 0.9,
		"a hind leg lost command from a wound that never reached the cord")

	# Now the vertebra itself.
	_bite_cell(c, TissueGrid.BODY_KEY, cell, 4.0, 12)
	c._physics_process(TICK)
	_check(state.nerves.integrity[BodyPlan.LUMBAR] <= 0.01,
		"grinding the vertebra through did not cut the cord inside it")
	_check(state.regions[BodyPlan.RL].control <= 0.05
			and state.regions[BodyPlan.RR].control <= 0.05,
		"a cord cut at the waist left the hind legs still taking orders")
	_check(state.regions[BodyPlan.FL].control > 0.5,
		"a cord cut at the waist also silenced a foreleg in front of it")
	# And the limb itself is untouched — which is the entire point.
	_check(state.regions[BodyPlan.RL].muscle > 0.99
			and state.regions[BodyPlan.RL].stability > 0.99,
		"the hind leg was physically damaged by a wound to the spine")
	_restore(c)


## Force is fibre times command times supply, and the three are separable.
##
## Destroying the muscle of a limb and cutting the nerve to a limb both leave it
## weak, and this is what says they are not the same event: one of them leaves an
## animal with a leg it no longer commands and no damage to the leg at all.
func _check_muscle_nerve_blood_are_independent(c: Creature) -> void:
	_restore(c)
	var state: BodyState = c.anatomy.state

	_cut_limb_supply(c, "FL")
	c._physics_process(TICK)
	var denervated: BodyState.Region = state.limb("FL")
	_check(denervated.control <= 0.05, "cutting a limb's nerve left it still commanded")
	_check(denervated.muscle > 0.85,
		"cutting a limb's nerve destroyed its muscle too (%.2f)" % denervated.muscle)
	_check(denervated.stability > 0.9,
		"cutting a limb's nerve broke its bone too (%.2f)" % denervated.stability)
	_check(denervated.strength <= 0.05,
		"a limb with no command still produced force (%.2f)" % denervated.strength)
	# Range of motion is passive and must survive: the limb can still be moved,
	# there is simply nothing moving it.
	_check(denervated.motion_range > 0.7,
		"a denervated limb lost its passive range of motion (%.2f)" % denervated.motion_range)
	_restore(c)


## Losing the blood supply is not an event, it is a decline. This is the one
## behaviour a hit-point model cannot produce at all, so it is asserted as a
## shape over time rather than as a value.
func _check_ischaemia_is_progressive(c: Creature) -> void:
	_restore(c)
	var state: BodyState = c.anatomy.state
	# Opened over the waist, down to the bone and no further: the great vessel is
	# cut and the cord inside the vertebra is not. So the hindquarters keep every
	# order they are given and lose the blood to carry them out — which is the only
	# way to watch ischaemia on its own, with no nerve damage confusing it.
	_bite_to_bone(c, _cord_cell(c, BodyPlan.LUMBAR))
	c._physics_process(TICK)

	var hind: BodyState.Region = state.limb("RL")
	_check(hind.control > 0.9,
		"the vessel-only wound also cut command to the hind leg (%.2f)" % hind.control)
	_check(hind.strength > 0.5,
		"a limb lost its force on the very tick its supply was cut (%.2f) — blood is not a switch"
			% hind.strength)

	for _i in 60:
		c._physics_process(TICK)
	var after_second: float = hind.vitality
	for _i in 480:
		c._physics_process(TICK)
	var after_nine: float = hind.vitality

	_check(after_second > after_nine + 0.25,
		"a starved limb did not decline over time (%.2f at one second, %.2f at nine)"
			% [after_second, after_nine])
	_check(after_second > 0.55,
		"a starved limb failed almost immediately (%.2f after one second) — that is a switch, not ischaemia"
			% after_second)
	_check(after_nine < 0.4,
		"a limb starved for nine seconds was still fine (%.2f)" % after_nine)
	# It is still commanded the whole way down. The animal is trying; there is
	# simply nothing left to try with.
	_check(hind.control > 0.5,
		"the starved limb quietly lost its nerve supply as well (%.2f)" % hind.control)
	# And a foreleg, fed from in front of the wound, is not starved with it.
	_check(state.limb("FR").vitality > after_nine + 0.3,
		"a wound at the waist starved a foreleg in front of it as badly as the hind legs")
	_restore(c)


## Bone is structure, not another pool. Breaking it costs load-bearing and
## stability without costing muscle, and the loss is the *break* rather than the
## amount: sound bone either side of a gap does not splint it.
func _check_bone_is_structural(c: Creature) -> void:
	_restore(c)
	var state: BodyState = c.anatomy.state
	var before: float = state.limb("RR").load
	_break_limb_bone(c, "RR")
	c._physics_process(TICK)
	var region: BodyState.Region = state.limb("RR")
	_check(region.stability < 0.2,
		"grinding a limb bone through left it structurally sound (%.2f)" % region.stability)
	_check(region.load < before * 0.35,
		"a broken limb bone still bears %.0f%% of its load" % (region.load / before * 100.0))
	_check(state.support < BodyPlan.LIMB_REGIONS.size(),
		"a creature with a broken leg was still standing on all four")
	_restore(c)


# --------------------------------------------------------------- animation ----

## A limp, without anything anywhere deciding to limp.
##
## One weakened leg takes a shorter stride and a slower swing than the sound leg
## on the same end of the animal. Nothing in the gait knows what a limp is; the
## asymmetry is the whole of it, and the distance-triggered step cycle turns it
## into a rhythm on its own.
func _check_limp_is_asymmetry(c: Creature) -> void:
	_restore(c)
	_waste_limb_muscle(c, "RL")
	_walk(c, 90)

	var lame: Limb = _limb(c, "RL")
	var sound: Limb = _limb(c, "RR")
	_check(lame.drive < sound.drive * 0.6,
		"wasting a limb's muscle did not weaken it (%.2f vs %.2f)" % [lame.drive, sound.drive])
	_check(lame.stride < sound.stride * 0.85,
		"the weak leg took the same stride as the sound one (%.1f vs %.1f)"
			% [lame.stride, sound.stride])
	# Laboured means the foot itself moves more slowly through its swing. Raw
	# duration is the wrong measure — the weak leg's stride shrank as well, so a
	# shorter step in a shorter time can still be a leg working much harder.
	var lame_swing: float = lame.stride / maxf(lame.step_duration, 0.0001)
	var sound_swing: float = sound.stride / maxf(sound.step_duration, 0.0001)
	_check(lame_swing < sound_swing * 0.8,
		"the weak leg swung as briskly as the sound one (%.0f px/s against %.0f px/s)"
			% [lame_swing, sound_swing])
	_restore(c)


## A limb with no command is not a limb that steps badly — it is a limb that
## never steps, and is therefore towed along the ground by a body that keeps
## walking out from under it. The drag is a consequence of the foot never being
## picked up, and reuses the skid the gait already had.
func _check_dead_nerve_drags(c: Creature) -> void:
	_restore(c)
	_cut_limb_supply(c, "FL")
	_walk(c, 30)

	var dead: Limb = _limb(c, "FL")
	var live: Limb = _limb(c, "FR")
	var dead_steps: int = 0
	var live_steps: int = 0
	var dead_lift: float = 0.0
	for _i in 240:
		_walk(c, 1)
		dead_steps += 1 if dead.stepping else 0
		live_steps += 1 if live.stepping else 0
		# How far the foot is off whatever it is standing on. Not `foot_height`,
		# which is measured from the world's floor and so reads a leg standing on a
		# ledge as a foot in the air.
		dead_lift = maxf(dead_lift, dead.foot_height - dead.surface)
	_check(dead_steps == 0,
		"a limb with no nerve took %d ticks of steps" % dead_steps)
	_check(live_steps > 0, "the sound limb stopped walking too")
	_check(is_zero_approx(dead_lift),
		"a dragged limb still lifted %.2f px clear of the ground" % dead_lift)
	# Dragged, not abandoned: it is still attached, still solved, and still held
	# inside the envelope a real limb could reach.
	var socket: Vector2 = dead.joints[0]
	_check(socket.distance_to(dead.joints[2]) <= dead.total_length + 0.01,
		"the dragged limb was stretched past its own bones")
	_restore(c)


## The whole animal is slower for it. Same command, same duration, less ground.
func _check_damage_costs_travel(c: Creature) -> void:
	_restore(c)
	var healthy: float = _distance_walked(c, 180)
	_restore(c)
	_cut_limb_supply(c, "RL")
	_cut_limb_supply(c, "RR")
	var crippled: float = _distance_walked(c, 180)
	_check(crippled < healthy * 0.8,
		"losing both hind legs cost almost no ground (%.0f px against %.0f px)"
			% [crippled, healthy])
	_check(crippled > 0.0, "a creature with two working legs could not move at all")
	_restore(c)


# ------------------------------------------------------------------ organs ----

## The brain destroyed is the body stopping, immediately and everywhere. It is
## also the moment the ragdoll takes over from the gait, in place, from the pose
## the creature was standing in.
func _check_brain_collapses_the_body(c: Creature) -> void:
	_restore(c)
	_walk(c, 40)
	var standing: Vector2 = c.head_pos
	_destroy_organ(c, BodyPlan.BRAIN)
	c._physics_process(TICK)

	_check(c.anatomy.tissue.organ(BodyPlan.BRAIN) <= 0.0, "the brain survived being destroyed")
	_check(c.anatomy.state.consciousness <= BodyState.COLLAPSE,
		"a destroyed brain left the creature conscious (%.2f)" % c.anatomy.state.consciousness)
	_check(not c.alive, "a destroyed brain left the creature driving itself")
	_check(c.ragdoll != null, "nothing took over the body when it died")
	# In place: a collapse is the body it was, going down. Not a corpse swapped in
	# somewhere else in a pose it never held.
	_check(c.head_pos.distance_to(standing) < 30.0,
		"the body moved %.0f px at the instant it collapsed"
			% c.head_pos.distance_to(standing))
	for _i in 120:
		c._physics_process(TICK)
	_check(c.spine != null and c.spine.size() > 2, "the collapsed body lost its spine")
	_restore(c)


## The heart destroyed is the same ending arrived at the other way: nothing is
## wrong with the brain, and it goes out anyway because nothing is feeding it.
## Crucially it takes time, which is what makes it circulation and not a second
## kill switch.
func _check_heart_stops_it_slowly(c: Creature) -> void:
	_restore(c)
	_destroy_organ(c, BodyPlan.HEART)
	c._physics_process(TICK)
	_check(c.anatomy.tissue.organ(BodyPlan.HEART) <= 0.0, "the heart survived being destroyed")
	_check(c.alive, "a stopped heart killed the creature on the same tick")
	_check(c.anatomy.state.circulation <= 0.01,
		"a destroyed heart still circulated blood (%.2f)" % c.anatomy.state.circulation)

	var ticks: int = 0
	while c.alive and ticks < 1800:
		c._physics_process(TICK)
		ticks += 1
	_check(not c.alive, "a creature with no heart was still going after 30 seconds")
	_check(ticks > 60,
		"the body collapsed %.1f s after its heart stopped — that is a switch, not circulation"
			% (float(ticks) * TICK))
	_restore(c)


## A limb eaten through at the socket comes off: it stops being solved, stops
## being drawn, stops being bitten, and what was left of it enters the world as
## meat.
func _check_severed_limb_leaves(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch("RR")
	var pieces: Array = []
	var handle: Callable = func(taken: Array) -> void: pieces.append_array(taken)
	c.part_severed.connect(handle)

	# Eat the whole proximal cross-section away — the cells that join the limb to
	# the animal, and nothing else.
	for row in BodyPlan.LIMB_ROWS:
		_bite_cell(c, "RR", row, 6.0, 8)
	# Measured with the cut made and the limb not yet told: everything still
	# standing in the patch is what should walk into the world, to the hit point.
	var standing: float = _flesh_in(patch)
	# Twice: the gait is solved before the anatomy is re-read within a tick, so
	# the limb comes off on the first and the gait is told on the second.
	c._physics_process(TICK)
	c._physics_process(TICK)

	_check(tissue.region_attachment(BodyPlan.RR) <= 0.0, "the socket cells survived being eaten")
	_check(c.anatomy.state.limb("RR").severed, "a limb eaten off at the socket was not severed")
	_check(_limb(c, "RR").severed, "the gait was not told the limb had come off")
	_check(patch.gone_count == patch.cells,
		"a severed limb left %d cells still attached" % (patch.cells - patch.gone_count))
	_check(pieces.size() == 1,
		"a limb coming off produced %d pieces where it should have produced one"
			% pieces.size())
	# ...and it came off *intact*. Nothing destroyed it, so nothing about it is
	# spent: the tissue that walked into the world is the tissue the leg was
	# standing with a tick earlier, bone included. What turns it into meat is
	# something biting it, which nothing has yet.
	if pieces.size() == 1:
		var piece: TissueGrid.Piece = pieces[0]
		_check(absf(piece.flesh - standing) < 0.001,
			"a severed limb arrived with %.1f of the %.1f it was standing with"
				% [piece.flesh, standing])
		_check(_layer_in(piece, TissueGrid.BONE) > 0.0 and _layer_in(piece, TissueGrid.SKIN) > 0.0,
			"a severed limb arrived without its bone and skin — it was ground up, not cut off")
		_check(piece.share > 0.0 and piece.share < 1.0,
			"a severed limb reported %.2f of the whole animal" % piece.share)
	# Gone means gone, through the machinery that was already there.
	_check(tissue.limb_solid("RR", 0) <= 0.0 and tissue.limb_solid("RR", 2) <= 0.0,
		"a severed limb still occupies space")
	var hit: AnatomyState.Hit = c.query_bite(_limb(c, "RR").joints[2], 6.0)
	_check(hit == null or hit.limb_key != "RR", "a severed limb could still be bitten")

	# The rest of the animal is unharmed and still walking on what it has left.
	_check(not c.anatomy.state.limb("RL").severed, "the wrong limbs came off")
	_walk(c, 120)
	_check(c.alive, "losing one leg killed the creature")
	c.part_severed.disconnect(handle)
	_restore(c)


## Severance is *every* tissue between the part and the body being gone, and not
## any one of them in particular.
##
## The socket is eaten down to the bone first: skin, fat and muscle all destroyed
## across the whole proximal cross-section, and a leg still firmly on the animal
## because a bone is still bridging the gap. Only when that last bone goes does
## the limb come off — and nothing anywhere named bone as the thing that was
## holding it, which is why the same check would pass if the survivor had been the
## skin instead.
func _check_severance_needs_every_tissue(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	var state: BodyState = c.anatomy.state
	var patch: TissueGrid.Patch = tissue.patch("FR")
	var core: int = BodyPlan.LIMB_CORE_ROW

	for row in BodyPlan.LIMB_ROWS:
		_bite_limb_to_bone(c, "FR", row)
	c._physics_process(TICK)

	var base: int = core * TissueGrid.LAYERS
	_check(patch.hp[base + TissueGrid.BONE] > 0.0,
		"the socket's bone was destroyed by a bite that was meant to stop at it")
	_check(patch.hp[base + TissueGrid.MUSCLE] <= 0.0
			and patch.hp[base + TissueGrid.SKIN] <= 0.0,
		"the soft tissue over the socket survived being eaten off")
	_check(not state.limb("FR").severed,
		"a limb still joined by an unbroken bone was treated as severed")
	_check(state.limb("FR").attached > 0.0,
		"a limb joined by one surviving tissue reported nothing holding it on")
	_check(patch.gone[core] == 0, "the one cell still bridging the socket was emptied")

	# And now the last of it.
	_bite_cell(c, "FR", core, 5.0, 14)
	c._physics_process(TICK)
	c._physics_process(TICK)
	_check(patch.gone[core] != 0, "grinding the socket's last bone through left tissue in it")
	_check(state.limb("FR").severed,
		"a limb with every connecting tissue destroyed was still attached (%.2f)"
			% state.limb("FR").attached)
	_check(_limb(c, "FR").severed, "the gait was not told the limb had come off")
	_restore(c)


## A part still held on by flesh after its bone has broken: on the animal,
## carrying nothing, doing nothing, and hanging rather than being posed.
##
## This is the case the two readings are kept apart for. Attachment says the leg
## is still there — its cells are standing, it is drawn, it can be bitten, it has
## not entered the world as meat. Skeletal continuity says nothing is holding it
## out. Everything below is what those two answers together produce, and none of
## it is a mode: the gait stops placing a limb it cannot place, and the solver for
## a chain nobody is posing takes it instead.
func _check_broken_limb_dangles(c: Creature) -> void:
	_restore(c)
	var state: BodyState = c.anatomy.state
	var patch: TissueGrid.Patch = c.anatomy.tissue.patch("RR")
	var pieces: Array = []
	var handle: Callable = func(taken: Array) -> void: pieces.append_array(taken)
	c.part_severed.connect(handle)

	_break_limb_bone(c, "RR")
	_walk(c, 2)

	var region: BodyState.Region = state.limb("RR")
	_check(region.hanging, "a limb with its bone ground through was not left hanging")
	_check(not region.severed,
		"a limb still held on by its own flesh was treated as having come off")
	_check(region.attached > 0.3,
		"a limb hanging by flesh reported only %.2f of it still joined on" % region.attached)
	_check(patch.gone_count < patch.cells,
		"a limb that was only broken was emptied as though it had been severed")
	_check(pieces.is_empty(),
		"a broken limb put %d pieces into the world without coming off" % pieces.size())

	# It bears nothing and is asked for nothing.
	_check(region.load <= 0.05,
		"a limb with no skeleton left still bore %.2f of its load" % region.load)
	_check(not state.limb_usable("RR"), "a limb hanging by flesh was still reported usable")
	_check(state.support < BodyPlan.LIMB_REGIONS.size(),
		"a creature was still standing on a leg that had been broken through")

	# And it is carried rather than placed: no stride, no plant, no lift, and bones
	# that still measure what they always did.
	var hurt: Limb = _limb(c, "RR")
	var sound: Limb = _limb(c, "RL")
	_check(hurt.carried, "a limb nothing was holding out was still being walked")
	_check(c.ragdoll != null, "nothing took over the limb the gait had let go of")
	_check(c.alive, "breaking one leg killed the creature")

	var steps: int = 0
	var lift: float = 0.0
	var stretched: float = 0.0
	var sound_steps: int = 0
	for _i in 240:
		_walk(c, 1)
		steps += 1 if hurt.stepping else 0
		sound_steps += 1 if sound.stepping else 0
		lift = maxf(lift, hurt.foot_height)
		stretched = maxf(stretched, absf(
			hurt.joints[0].distance_to(hurt.joints[1]) - hurt.lengths[0]))
		stretched = maxf(stretched, absf(
			hurt.joints[1].distance_to(hurt.joints[2]) - hurt.lengths[1]))
	_check(steps == 0, "a limb hanging by flesh took %d ticks of steps" % steps)
	_check(sound_steps > 0, "the sound legs stopped walking too")
	_check(is_zero_approx(lift),
		"a dangling limb picked itself %.2f px off the ground" % lift)
	# Naturally: it hangs off the socket on its own bones. A limp chain that
	# stretches is a rope, and a limb drawn past its own length is the one thing
	# that would make this read as a bug rather than as an injury.
	_check(stretched < 0.5,
		"the dangling limb's bones stretched by %.2f px" % stretched)
	_check(hurt.joints[0].distance_to(hurt.joints[2]) <= hurt.total_length + 0.01,
		"the dangling limb was pulled out past its own bones")

	c.part_severed.disconnect(handle)
	_restore(c)


## The same mechanism on a part that is not a limb, which is the whole claim: a
## tail bitten through comes off for exactly the reason a leg does, and nothing
## anywhere had to be taught what a tail is.
func _check_tail_comes_off(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	var pieces: Array = []
	var handle: Callable = func(taken: Array) -> void: pieces.append_array(taken)
	c.part_severed.connect(handle)

	# Straight through the animal at the root of the tail: every row of one column,
	# vertebra included.
	var col: int = BodyPlan.HEAD_COLS + BodyPlan.LOIN_COL
	var beyond: int = (col + 3) * BodyPlan.BODY_ROWS + BodyPlan.SPINE_ROW
	_check(patch.gone[beyond] == 0, "the tail was already missing before it was cut")
	for row in BodyPlan.BODY_ROWS:
		_bite_cell(c, TissueGrid.BODY_KEY, col * BodyPlan.BODY_ROWS + row, 6.0, 20)
	c._physics_process(TICK)
	c._physics_process(TICK)

	var state: BodyState = c.anatomy.state
	_check(state.regions[BodyPlan.TAIL].severed,
		"a tail cut clean through at its root was still on the animal (%.2f)"
			% state.regions[BodyPlan.TAIL].attached)
	_check(patch.gone[beyond] != 0,
		"the tail was severed but the tissue behind the cut stayed on the body")
	_check(pieces.size() == 1,
		"a tail coming off produced %d pieces, not one" % pieces.size())
	# Gone means gone, through the same machinery a limb uses.
	_check(tissue.body_solid(0.95, 1.0) <= 0.0 and tissue.body_solid(0.95, -1.0) <= 0.0,
		"a severed tail still occupies space")
	# The animal in front of the cut is unharmed and keeps going.
	_check(not state.regions[BodyPlan.THORAX].severed
			and not state.limb("FL").severed and not state.limb("RL").severed,
		"cutting the tail off took the rest of the animal with it")
	_walk(c, 120)
	_check(c.alive, "losing its tail killed the creature")

	c.part_severed.disconnect(handle)
	_restore(c)


## The same walk, on the one part whose loss the animal cannot survive — and it
## does not survive it for a reason nothing states: the brain is cells in the
## head, so a head that leaves takes its brain with it, and a body with no brain
## has already been unable to hold itself up since long before any of this existed.
func _check_a_severed_head_takes_the_brain(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	_check(tissue.organ(BodyPlan.BRAIN) > 0.99, "the creature started without a brain")

	# Clean through the neck: the first torso column, every row of it, vertebra and
	# all. Nothing is aimed at the skull and nothing touches it.
	for row in BodyPlan.BODY_ROWS:
		_bite_cell(c, TissueGrid.BODY_KEY, BodyPlan.HEAD_COLS * BodyPlan.BODY_ROWS + row,
			6.0, 20)
	for _i in 4:
		c._physics_process(TICK)

	var head: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	var standing: int = 0
	for col in BodyPlan.HEAD_COLS:
		for row in BodyPlan.BODY_ROWS:
			standing += 1 if head.gone[col * BodyPlan.BODY_ROWS + row] == 0 else 0
	_check(standing == 0, "%d cells of head stayed on a body it was cut off from" % standing)
	_check(c.anatomy.state.regions[BodyPlan.HEAD].severed,
		"a head cut clean off was still reported attached")
	_check(tissue.organ(BodyPlan.BRAIN) <= 0.0,
		"the brain stayed behind when the head it sits in left (%.2f)"
			% tissue.organ(BodyPlan.BRAIN))
	_check(not c.alive, "a decapitated creature was still driving itself")
	_restore(c)


## Where the cut is decides how much leaves, and nothing else does.
##
## A limb bitten clean through part of the way down keeps everything between the
## cut and the body, and loses everything past it — including tissue the bite
## never touched, which is the entire difference between severing a leg and eating
## one. Nobody nominated the shin as a place a limb can come apart at; it came
## apart there because that is where the last cell joining the two halves was.
func _check_a_cut_sheds_only_what_is_past_it(c: Creature) -> void:
	_restore(c)
	var tissue: TissueGrid = c.anatomy.tissue
	var state: BodyState = c.anatomy.state
	var patch: TissueGrid.Patch = tissue.patch("FL")
	var pieces: Array = []
	var handle: Callable = func(taken: Array) -> void: pieces.append_array(taken)
	c.part_severed.connect(handle)

	# Straight through the shin, well short of the foot.
	var cut: int = 4
	for row in BodyPlan.LIMB_ROWS:
		_bite_cell(c, "FL", cut * BodyPlan.LIMB_ROWS + row, 6.0, 14)
	c._physics_process(TICK)
	c._physics_process(TICK)

	var above: int = 0
	for col in range(0, cut - 1):
		for row in BodyPlan.LIMB_ROWS:
			above += 1 if patch.gone[col * BodyPlan.LIMB_ROWS + row] == 0 else 0
	var past: int = 0
	for col in range(BodyPlan.LIMB_BONE_COLS, BodyPlan.LIMB_COLS):
		for row in BodyPlan.LIMB_ROWS:
			past += 1 if patch.gone[col * BodyPlan.LIMB_ROWS + row] == 0 else 0

	_check(above > 0, "cutting through a shin took the thigh above it as well")
	_check(past == 0,
		"%d cells of foot survived a limb cut through above them" % past)
	_check(pieces.size() == 1,
		"a limb coming apart at the shin produced %d pieces, not one" % pieces.size())
	_check(tissue.limb_solid("FL", 2) <= 0.0, "a detached foot still occupies space")
	_check(tissue.limb_solid("FL", 0) > 0.0, "the whole limb left when only its shin was cut")
	# What is left is a stump, wholly joined on — and hanging, because the bone it
	# would have stood on is exactly what was cut. The two readings compose without
	# either knowing about the other.
	var region: BodyState.Region = state.limb("FL")
	_check(not region.severed, "a limb cut at the shin came off at the shoulder")
	_check(region.hanging, "a limb cut through its own bone was still held out by it")
	_walk(c, 90)
	_check(c.alive, "cutting through one shin killed the creature")

	c.part_severed.disconnect(handle)
	_restore(c)


# ----------------------------------------------------------------- helpers ----

func _restore(c: Creature) -> void:
	c.alive = true
	c.params.fat_reserve = 1.0
	c.anatomy.reset()
	c.reset(c.spawn_position, c.spawn_heading)
	c.command = MovementInput.Command.new()
	c._physics_process(TICK)


func _limb(c: Creature, key: String) -> Limb:
	for limb in c.gait.limbs:
		if limb.key == key:
			return limb
	return null


## One closing of a very small set of jaws on exactly one cell, through the real
## erosion path — so these tests exercise the same code a bite does rather than
## writing hit points by hand.
func _bite_cell(c: Creature, patch_key: String, cell: int, depth: float,
		times: int = 1) -> void:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(patch_key)
	var shed: Array = []
	for _i in times:
		tissue.bite(BiteMark.mouthful(patch.centre_of(cell), Vector2.RIGHT, 0.8, depth), shed)


## Every hit point standing in a patch.
func _flesh_in(patch: TissueGrid.Patch) -> float:
	var total: float = 0.0
	for i in patch.hp.size():
		total += patch.hp[i]
	return total


## Every hit point of one tissue in a piece that has come away.
func _layer_in(piece: TissueGrid.Piece, layer: int) -> float:
	var total: float = 0.0
	for cell in piece.cells:
		total += piece.hp[cell * TissueGrid.LAYERS + layer]
	return total


## Chews one cell down to its bone and stops there, whatever the bone costs.
func _bite_to_bone(c: Creature, cell: int) -> void:
	var patch: TissueGrid.Patch = c.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var base: int = cell * TissueGrid.LAYERS
	# Shallow, and one bite at a time. A deep bite that happens to finish the
	# muscle spills its remaining budget into the bone behind it, and this helper
	# exists precisely to produce a wound that has *not* touched the skeleton.
	for _i in 40:
		if patch.hp[base + TissueGrid.MUSCLE] <= 0.0:
			return
		_bite_cell(c, TissueGrid.BODY_KEY, cell, 1.0, 1)


## The cord/aorta cell in the middle of an axial region.
func _cord_cell(c: Creature, region: int) -> int:
	var run: BodyPlan.Conduit = c.anatomy.plan.nerves[region]
	return run.cells[run.cells.size() / 2]


## A flank cell well behind the ribs, where the body is flesh over one vertebra.
func _flank_cell(c: Creature) -> int:
	var col: int = BodyPlan.HEAD_COLS + BodyPlan.LOIN_COL
	return col * BodyPlan.BODY_ROWS + 1


func _organ_cell(patch: TissueGrid.Patch, which: int) -> int:
	for cell in patch.cells:
		if patch.organ[cell] == which:
			return cell
	return -1


## Cuts the neurovascular bundle running down a limb, without breaking its bone.
func _cut_limb_supply(c: Creature, key: String) -> void:
	for col in 3:
		_bite_limb_to_bone(c, key, col * BodyPlan.LIMB_ROWS + BodyPlan.LIMB_CORE_ROW)
	c._physics_process(TICK)


func _bite_limb_to_bone(c: Creature, key: String, cell: int) -> void:
	var patch: TissueGrid.Patch = c.anatomy.tissue.patch(key)
	var base: int = cell * TissueGrid.LAYERS
	for _i in 40:
		if patch.hp[base + TissueGrid.MUSCLE] <= 0.0:
			return
		_bite_cell(c, key, cell, 1.0, 1)


## Grinds a limb's bone through at one station, leaving it discontinuous.
func _break_limb_bone(c: Creature, key: String) -> void:
	var cell: int = 2 * BodyPlan.LIMB_ROWS + BodyPlan.LIMB_CORE_ROW
	_bite_cell(c, key, cell, 5.0, 14)


## Takes the meat off a limb without cutting its core supply, so what is left is
## a limb that is commanded, supplied and simply has nothing to pull with.
func _waste_limb_muscle(c: Creature, key: String) -> void:
	for col in BodyPlan.LIMB_BONE_COLS:
		for row in BodyPlan.LIMB_ROWS:
			if row == BodyPlan.LIMB_CORE_ROW:
				continue
			_bite_cell(c, key, col * BodyPlan.LIMB_ROWS + row, 3.0, 4)
	c._physics_process(TICK)


func _destroy_organ(c: Creature, which: int) -> void:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	for cell in patch.cells:
		if patch.organ[cell] == which:
			_bite_cell(c, TissueGrid.BODY_KEY, cell, 8.0, 12)


func _walk(c: Creature, ticks: int) -> void:
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _i in ticks:
		c.command = drive
		c._physics_process(TICK)


func _distance_walked(c: Creature, ticks: int) -> float:
	var from: Vector2 = c.head_pos
	_walk(c, ticks)
	return from.distance_to(c.head_pos)


func _check(condition: bool, message: String) -> void:
	if not condition and not message.is_empty():
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("anatomy OK — skin, fat, muscle, vessels, nerves, bone, heart and brain;",
			" enclosed, connected, and felt in the gait")
		quit(0)
	else:
		for failure in failures:
			print("ANATOMY FAIL — ", failure)
		quit(1)
