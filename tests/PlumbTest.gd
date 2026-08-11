## Headless check that the creature has a centre of gravity and stands on it —
## see Plumb, Balance, Gravity.topple, Locomotion.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/PlumbTest.gd
##
## Where an animal's weight is was the last thing in the simulation that nobody
## measured. Mass was counted honestly, cell by cell, and then *placed* by taking
## the middle of the drawn outline — a reading with no density in it, no legs in
## it, no damage in it and no height in it at all. Every consequence that should
## have followed from weight followed from a silhouette instead.
##
## Four groups, and they are four different claims:
##
##   * **it is a centre of mass** — that it is counted off the same cells the
##     scales are, so bone weighs more than the fat beside it, the legs are part
##     of the animal, and a body eaten through one end genuinely shifts its weight
##     toward the other. The outline can say none of those and was saying all of
##     them.
##   * **it is somewhere in three dimensions** — that it has a height, that the
##     height is inside the animal, and that it goes where the body goes rather
##     than where the picture of the body goes. The one that is easy to get wrong
##     and impossible to see: a leg is drawn foreshortened and stands on the
##     ground plane, and a centre of gravity that mixed the two would be a point
##     in neither.
##   * **the skeleton is under it** — that every build stands with its weight
##     inside its own feet, that a two-legged one puts its feet under its weight
##     rather than wherever a parameter said, and that a build whose weight is
##     out past what its legs can reach rears until it is not. These are
##     constraints on generation, so they are checked as constraints: a body that
##     already balances must come out untouched, to the digit.
##   * **gravity acts at it** — that the pull is a force at a place rather than a
##     number for a height, that a body with its weight over its feet is not being
##     tipped however tall it is, and that one with its weight out past them goes
##     down faster the further out it is.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.creature
	_check(player != null, "the habitat did not build a body")
	if player == null:
		_finish()
		return false
	# Flat, empty ground. Every measurement here is of one body standing on its
	# own feet, and a rock under one of them would make several of them
	# measurements of the rock.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	_check_it_is_a_centre_of_mass(player)
	_check_it_is_in_three_dimensions(player)
	_check_the_skeleton_is_under_it(player)
	_check_gravity_acts_at_it(player)
	_finish()
	return false


# ------------------------------------------------- it is a centre of mass ----

## That the weight is where the *tissue* is, and that it moves when the tissue
## does.
##
## Everything here holds the animal's own length fixed, and it has to: `along` is
## a fraction of the clipped body, which is the right unit for comparing it to a
## girdle station and the wrong one for comparing two bodies of different lengths.
## Switching a tail off shortens the ruler as well as removing the counterweight,
## so what it proves is nothing. Thickening one does not.
func _check_it_is_a_centre_of_mass(player: Creature) -> void:
	_stand(player, "Cat")
	var whole: float = player.plumb.along
	var mass: float = player.plumb.units
	_check(whole > 0.0 and whole < 1.0,
		"a Cat's centre of gravity is not inside its own body (%.2f)" % whole)
	_check(absf(mass - player.anatomy.tissue.lattice.standing_units) < 0.5,
		"the centre was weighed against a different census than the scales use")

	# That it is a centre of *gravity* and not a middle of cells, checked on the
	# axis where the answer has a direction anybody can argue about. A spine is
	# dorsal — see AnatomyLattice.SPINE_RISE — and bone is nearly twice the
	# density of the flesh around it, so weighing the cells rather than counting
	# them has to lift the centre toward the back. Along the body the same
	# reweighting is worth a fraction of a pixel, because a trunk's tissue stack
	# is much the same from one end of it to the other; up the body it is not,
	# because the stack is the whole point of the stack.
	for preset in ["Cat", "Elephant"]:
		_stand(player, preset)
		var bare: Vector3 = _unweighted_centre(player.anatomy.tissue.lattice)
		var lift: float = player.plumb.body.z - bare.z
		_check(lift > 0.0,
			"%s's skeleton did not weigh its centre of gravity toward its back (%.3f px)"
			% [preset, lift])
		notes.append("%s's dense dorsal bone lifts its centre %.2f px off the middle of its cells"
			% [preset, lift])
	_stand(player, "Cat")

	# The tail, which is the counterweight the whole of the hindquarters is built
	# around. Thickened rather than removed, so the animal is the same length and
	# the same shape everywhere else and only the mass at the back has changed.
	var base: float = player.params.tail_base_width
	var tip: float = player.params.tail_tip_width
	player.params.tail_base_width = maxf(base, 0.2) * 2.5
	player.params.tail_tip_width = maxf(tip, 0.1) * 2.5
	player.rebuild()
	_settle(player)
	var heavy_tail: float = player.plumb.along
	_check(heavy_tail > whole + 0.005,
		"a much heavier tail did not move a Cat's weight back (%.3f -> %.3f)"
		% [whole, heavy_tail])
	notes.append("a heavy tail carries the weight %.3f of the body aft"
		% (heavy_tail - whole))
	player.params.tail_base_width = base
	player.params.tail_tip_width = tip

	# And the head, at the other end, on the same fixed ruler.
	var wide: float = player.params.head_width
	player.params.head_width = wide * 1.8
	player.rebuild()
	_settle(player)
	var big_head: float = player.plumb.along
	_check(big_head < whole - 0.005,
		"a much bigger head did not move a Cat's weight forward (%.3f -> %.3f)"
		% [whole, big_head])
	player.params.head_width = wide

	# What a bite does to it, which is the whole reason this is counted off the
	# lattice. The hindquarters chewed out is weight that is on the floor, and it
	# has to stop being carried the tick it stops being attached.
	_stand(player, "Cat")
	var before: float = player.plumb.along
	_eat_hindquarters(player)
	var after: float = player.plumb.along
	_check(after < before - 0.005,
		"eating a Cat's hindquarters did not move its weight forward (%.3f -> %.3f)"
		% [before, after])
	_check(player.plumb.units < mass,
		"eating a Cat's hindquarters did not make it any lighter")
	notes.append("a chewed-out haunch moves the weight %.3f of the body forward"
		% (before - after))


# ------------------------------------------- it is in three dimensions ----

## That the centre has a height, that the height is inside the animal, and that
## the point it comes down at is on the ground plane rather than in the picture.
##
## The last one is the subtle failure and the one worth a test of its own. A
## limb's tissue is posed through `Limb.joints`, which is the drawn chain with the
## view's foreshortening already in it; its foot is nailed to the world through
## `Limb.plan`, which is not. A centre of gravity that read the first and was
## compared against the second would be wrong by the whole of the perspective —
## silently, and only on the axis the animal walks along.
func _check_it_is_in_three_dimensions(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Elephant"]:
		_stand(player, preset)
		var pl: Plumb = player.plumb
		var st: Stature = player.stature
		_check(pl.posed, "%s never posed a centre of gravity" % preset)
		_check(pl.height > 0.0 and pl.height < st.stand_height(),
			"%s carries its weight outside its own body (%.1f, standing %.1f)"
			% [preset, pl.height, st.stand_height()])
		# Below the middle of the torso, always, and for one reason: the legs.
		# Four limbs are a tenth of an animal and every one of them hangs beneath
		# it, so a body with legs has its weight lower than a body drawn without.
		_check(pl.height < st.reference,
			"%s's legs did not pull its weight below the middle of its trunk (%.1f vs %.1f)"
			% [preset, pl.height, st.reference])

	# On the ground plane. The body is solved along +x with the head at the
	# origin, so the centre must lie back down the animal's own axis and square
	# on it — a foreshortened reading would be displaced across the axis by the
	# perspective and would not be.
	_stand(player, "Elephant")
	var pl: Plumb = player.plumb
	var head: Vector2 = player.spine.points[0]
	var tail: Vector2 = player.spine.points[player.body.last_index]
	var axis: Vector2 = tail - head
	var across: float = absf((pl.centre - head).cross(axis.normalized()))
	_check(across < 2.0,
		"a symmetric Elephant carries its weight %.1f px off its own midline" % across)
	var down: float = (pl.centre - head).dot(axis.normalized()) / axis.length()
	_check(absf(down - pl.along) < 0.05,
		"the posed centre and the built centre disagree about the animal (%.2f vs %.2f)"
		% [down, pl.along])
	notes.append("an Elephant's weight sits %.0f px up and %.0f%% down its own axis"
		% [pl.height, 100.0 * down])


# --------------------------------------------- the skeleton is under it ----

## That every build stands on its weight, and that the constraint which makes it
## so costs a balanced build nothing.
##
## Both halves are the claim. A stance constraint that quietly retuned every
## animal in the file would be a worse thing than no constraint at all — the
## presets were calibrated by eye against animals that stand, and their numbers
## are the calibration. So what is checked is that the floors are *inactive* on
## them, and active on a build that needs them.
func _check_the_skeleton_is_under_it(player: Creature) -> void:
	# Every quadruped, standing still, with its line inside its own feet.
	for preset in ["Lizard", "Cat", "Elephant", "Cheetah"]:
		_stand(player, preset)
		var pl: Plumb = player.plumb
		_check(pl.feet == 4, "%s was not standing on four feet (%d)" % [preset, pl.feet])
		_check(pl.clearance > 0.0,
			"%s stands with its weight %.1f px outside its own feet"
			% [preset, -pl.clearance])
		# ...and untouched: the species' own stance, to the digit.
		_check(is_equal_approx(player.locomotion.foot_bias.x, player.params.front_foot_bias)
				and is_equal_approx(player.locomotion.foot_bias.y, player.params.rear_foot_bias),
			"%s's stance was retuned by a constraint it did not need (%s)"
			% [preset, player.locomotion.foot_bias])
		_check(player.locomotion.carriage_deg <= 0.0,
			"%s was asked to rear and has four legs" % preset)
	notes.append("all four quadrupeds stand inside their own feet, none retuned")

	# A two-legged build puts its feet under its weight, and the number it was
	# given about where to stand cannot overrule statics.
	for preset in ["T. rex", "Kangaroo"]:
		_stand(player, preset)
		var pl: Plumb = player.plumb
		var hip: float = player.params.rear_limb_t
		# Feet forward of the hips exactly when the weight is forward of them,
		# which on any animal built like this is always.
		_check(pl.along < hip, "%s is not nose-heavy about its hips" % preset)
		_check(player.locomotion.foot_bias.y > player.params.rear_foot_bias,
			"%s left its feet behind its own weight (%.2f)"
			% [preset, player.locomotion.foot_bias.y])
		# The line comes down on the pair of feet, which is the whole of what a
		# biped standing still is. A segment has no area, so it is on the line
		# rather than inside anything.
		_check(absf(pl.clearance) < maxf(pl.span * 0.25, 8.0),
			"%s stands %.1f px off the line between its own feet"
			% [preset, -pl.clearance])
	notes.append("T. rex plants its feet %.2f of a stride forward, Kangaroo %.2f"
		% [_bias_of(player, "T. rex"), _bias_of(player, "Kangaroo")])

	# And the build the constraint exists for. A head grown until the animal's
	# weight is out past its own shoulders is a creature that would have nosed
	# into the floor; what it does instead is reach its forefeet out under its
	# own jaw, because that is where standing up requires them.
	_stand(player, "Cat")
	var kept: float = player.params.front_foot_bias
	player.params.head_width = player.params.head_width * 4.0
	player.params.front_limb_t = 0.55
	player.rebuild()
	_settle(player)
	_check(player.plumb.along < player.params.front_limb_t,
		"a Cat with a huge head did not end up front-heavy of its own shoulders")
	_check(player.locomotion.foot_bias.x > kept + 0.01,
		"a front-heavy build did not reach its forefeet out under its weight (%.2f)"
		% player.locomotion.foot_bias.x)
	notes.append("a front-heavy build reaches its forefeet %.2f -> %.2f"
		% [kept, player.locomotion.foot_bias.x])

	# The other end of the same constraint: a two-legged animal whose weight is
	# further in front of its hips than its legs can reach has one thing left to
	# do about it, and it is to stand up.
	_stand(player, "T. rex")
	var level: float = player.locomotion.carriage_deg
	player.params.tail_enabled = false
	player.params.head_width = player.params.head_width * 2.5
	player.rebuild()
	_settle(player)
	_check(player.locomotion.carriage_deg > level,
		"a tailless, big-headed biped was not made to rear (%.0f deg)"
		% player.locomotion.carriage_deg)
	_check(player.locomotion.carried_deg(player.params)
			>= player.locomotion.carriage_deg,
		"the carried trunk angle came out under the angle balance demands")
	notes.append("a tailless T. rex has to rear %.0f deg to stand"
		% player.locomotion.carriage_deg)


# --------------------------------------------------- gravity acts at it ----

## That the pull is a force at a place.
##
## `topple` is the whole of the new claim and it is three lines of statics, so it
## is checked as arithmetic first: nothing at all over the pivot however tall the
## body, nothing at all on a body with no height, a maximum where the overhang
## equals the height, and never more than half the pull. Then the consequence —
## that a creature whose weight is far outside what is left of its feet goes down
## sooner than one whose weight is barely outside them, which is the difference
## between a stumble and a fall and used to be no difference at all.
func _check_gravity_acts_at_it(player: Creature) -> void:
	_check(Gravity.topple(0.0, 100.0) == 0.0,
		"a body with its weight over the pivot was still being tipped")
	_check(Gravity.topple(50.0, 0.0) == 0.0,
		"a body with no height to fall through was still being tipped")
	var peak: float = Gravity.topple(80.0, 80.0)
	_check(absf(peak - Gravity.PULL * 0.5) < 0.01,
		"the hardest topple is not half the pull (%.1f)" % peak)
	for over in [10.0, 40.0, 80.0, 160.0, 400.0]:
		_check(Gravity.topple(over, 80.0) <= Gravity.PULL * 0.5 + 0.001,
			"a topple at %.0f px of overhang exceeded half the pull" % over)
	_check(Gravity.topple(30.0, 90.0) > Gravity.topple(5.0, 90.0),
		"leaning further out did not tip a body harder")

	# And the same statement about a whole animal. Both hind legs off is a body
	# whose weight is a long way past the two feet it has left, and it must not
	# be given the same window to recover in as one that has merely stumbled.
	_stand(player, "Cat")
	_check(player.balance._urgency(player.plumb) == 1.0,
		"a Cat standing on its own weight was already being hurried to the floor")
	_sever(player, "RR")
	_sever(player, "RL")
	var ticks: int = 0
	while player.alive and ticks < 600:
		player._physics_process(TICK)
		ticks += 1
	_check(not player.alive, "a Cat with no hind legs stood there indefinitely")
	_check(float(ticks) * TICK < player.balance.grace,
		"a Cat whose weight was right out past its feet still took the whole recovery window")
	notes.append("a toppling Cat goes down in %.2f s against a %.2f s window"
		% [float(ticks) * TICK, player.balance.grace])
	_revive(player)


# ------------------------------------------------------------- fixtures ----

## The middle of the standing cells, counting every one of them the same. What
## the centre of gravity would be if tissue had no density — which is what the
## check above is measuring the distance from.
func _unweighted_centre(lattice: AnatomyLattice) -> Vector3:
	var sum := Vector3.ZERO
	var n: int = 0
	for i in lattice.count:
		if lattice.gone[i] != 0:
			continue
		sum += lattice.pos[i]
		n += 1
	return sum / maxf(float(n), 1.0)


func _bias_of(player: Creature, preset: String) -> float:
	_stand(player, preset)
	return player.locomotion.foot_bias.y


func _stand(c: Creature, preset: String) -> void:
	_revive(c)
	c.params.apply_preset(preset)
	c.rebuild()
	c.anatomy.reset()
	c.reset(Vector2.ZERO, 0.0)
	_settle(c)


## Long enough for the body to be standing on its own feet rather than part way
## through arriving on them — the gait eases the trunk onto its legs over a step
## cycle, and a centre of gravity read before it has finished is a reading of an
## animal in the middle of standing up.
func _settle(c: Creature) -> void:
	for _i in 180:
		c._physics_process(TICK)


func _revive(c: Creature) -> void:
	c.alive = true
	c.ragdoll = null
	c.balance.reset()
	c.plumb.reset()
	c.anatomy.reset()
	c.reset(Vector2.ZERO, 0.0)


## Chews the flesh out of the columns just behind the hips, leaving the animal
## attached to it. Not a severance: what is being tested is that weight which is
## still part of the outline but no longer part of the tissue has stopped being
## carried, and a piece that came away would be the easy version of that.
func _eat_hindquarters(c: Creature) -> void:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	if patch == null:
		return
	var shed: Array = []
	var first: int = TissueGrid.HEAD_COLS + int(round(
		clampf(c.params.rear_limb_t, 0.0, 1.0) * float(TissueGrid.TORSO_COLS)))
	for col in range(first, mini(first + 4, patch.cols)):
		for row in patch.rows:
			for _i in 12:
				tissue.bite(BiteMark.mouthful(
					patch.centre_of(col * patch.rows + row),
					Vector2.RIGHT, 0.9, 8.0), shed)
	for _i in 4:
		c._physics_process(TICK)


func _sever(c: Creature, key: String) -> void:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(key)
	if patch == null:
		return
	var shed: Array = []
	for col in 2:
		for row in BodyPlan.LIMB_ROWS:
			for _i in 16:
				tissue.bite(BiteMark.mouthful(
					patch.centre_of(col * BodyPlan.LIMB_ROWS + row),
					Vector2.RIGHT, 0.9, 12.0), shed)
	c._physics_process(TICK)
	c._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("plumb OK — the weight is measured, the legs are under it, and gravity "
			+ "acts at it: %s" % " · ".join(notes))
	else:
		print("PLUMB FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
