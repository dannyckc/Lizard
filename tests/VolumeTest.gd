## Headless check for the volumetric layer — see Volume, TissueGrid and Stature.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/VolumeTest.gd
##
## HeightTest already covers the vertical axis as a property of whole animals: a
## body is at a height, jaws reach a band, a leap clears a charge. This suite is
## about the layer underneath that one — the claim that the *cells* are in three
## dimensions rather than the creatures.
##
## The difference is not academic and it is what everything here is aimed at. A
## band per animal can only ever say "that creature is out of reach". A band per
## cell says which part of it is, and it says so without anyone having enumerated
## the parts: the neck is between the head and the back because the cells of the
## neck are, the middle of a leg is bitable because the cells there stand at knee
## height, and a bite that straddles a flank and the leg hanging under it takes
## whichever of the two it was actually level with. None of that is written down
## anywhere as a rule, so the only way to know it is true is to measure it.
##
## Four things are checked, in the order they depend on each other:
##
##   * the lattice is genuinely a solid — every cell has a place and a thickness,
##     and the thicknesses describe a round animal rather than a flat one;
##   * the cell heights and the structure heights are the same heights, so the
##     coarse description and the fine one can never disagree;
##   * every channel that can make two things interact asks the third axis:
##     damage, targeting, collision, limb routing, and the world's food;
##   * with every band unbounded, all of it behaves exactly as a flat world.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false
var summary: String = ""


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.creature
	var target: Creature = main.target_creature
	_check(player != null and target != null, "the habitat did not build its bodies")
	if player == null or target == null:
		_finish()
		return false
	target.alive = true
	target.reset(target.spawn_position, target.spawn_heading)

	_check_algebra()
	_check_every_cell_is_somewhere(player)
	_check_the_body_is_round(player)
	_check_cells_agree_with_the_body(player)
	_check_a_leg_is_a_column(player)
	_check_damage_is_volumetric(player, target)
	_check_targeting_is_volumetric(player, target)
	_check_collision_is_volumetric(player, target)
	_check_the_world_is_volumetric(player)
	_check_unbounded_is_the_flat_world(player, target)
	_finish()
	return false


# ---------------------------------------------------------------- algebra ----

## The rule itself, before any body is involved. Three lines of arithmetic that
## every interaction in the game now runs through, so they are worth stating
## once in isolation — particularly the edges, which is where "resting on" and
## "just clear of" are decided.
func _check_algebra() -> void:
	_check(Volume.overlaps(Vector2(0.0, 10.0), Vector2(5.0, 15.0)), "two overlapping bands did not")
	_check(Volume.overlaps(Vector2(0.0, 10.0), Vector2(10.0, 20.0)),
		"something resting exactly on a surface was not touching it")
	_check(not Volume.overlaps(Vector2(0.0, 10.0), Vector2(10.001, 20.0)),
		"a band a thousandth of a pixel clear still collided")
	_check(Volume.overlaps(Vector2(0.0, 10.0), Volume.UNBOUNDED)
			and Volume.overlaps(Volume.UNBOUNDED, Vector2(-900.0, -800.0)),
		"the unbounded band failed to reach something")
	_check(Volume.contains(Vector2(0.0, 10.0), 10.0) and not Volume.contains(Vector2(0.0, 10.0), 11.0),
		"a band disagreed about which heights are inside it")

	# `union` has to be usable as an accumulator, which means NOWHERE has to be
	# its identity. Everything that builds a band out of parts starts there.
	var built: Vector2 = Volume.NOWHERE
	built = Volume.union(built, Vector2(4.0, 6.0))
	built = Volume.union(built, Vector2(-2.0, 1.0))
	_check(built == Vector2(-2.0, 6.0), "a union of two bands was not the smallest containing both")
	_check(Volume.union(Volume.NOWHERE, Vector2(3.0, 5.0)) == Vector2(3.0, 5.0),
		"the empty band was not the identity for union")

	_check(is_equal_approx(Volume.shared(Vector2(0.0, 10.0), Vector2(6.0, 20.0)), 4.0),
		"two bands sharing four pixels did not say so")
	_check(Volume.shared(Vector2(0.0, 10.0), Vector2(16.0, 20.0)) < 0.0,
		"two bands that miss each other reported a positive overlap")
	_check(is_equal_approx(Volume.clearance(Vector2(0.0, 10.0), Vector2(30.0, 40.0)), 20.0),
		"the room under a raised band was measured wrong")

	# The three-axis test, which is the one the world actually calls. Both halves
	# have to be able to veto it on their own, or it is not a volume test.
	var low := Vector2(0.0, 5.0)
	var high := Vector2(100.0, 105.0)
	_check(Volume.meet(Vector2.ZERO, 10.0, low, Vector2(5.0, 0.0), 10.0, low),
		"two discs in the same place at the same height did not meet")
	_check(not Volume.meet(Vector2.ZERO, 10.0, low, Vector2(5.0, 0.0), 10.0, high),
		"two discs in the same place at different heights met anyway")
	_check(not Volume.meet(Vector2.ZERO, 10.0, low, Vector2(500.0, 0.0), 10.0, low),
		"two discs at the same height but far apart met anyway")


# ----------------------------------------------------------------- solid ----

## Every cell is somewhere, and somewhere is three numbers.
##
## The weakest possible claim and the one everything else rests on: walk the
## whole lattice of a standing animal and there must not be a single cell without
## a place, without a thickness, or standing at a height the animal as a whole
## does not occupy. A cell with a zero band is a cell that can never be hit and
## never collided with — an invisible hole in the creature — and the arithmetic
## that produces one (an ellipse evaluated on its own edge, a limb with no solved
## heights) is easy to write and impossible to see.
func _check_every_cell_is_somewhere(player: Creature) -> void:
	_apply(player, "Elephant")
	var tissue: TissueGrid = player.anatomy.tissue
	var whole: Vector2 = tissue.whole_band()
	var flat: int = 0
	var stray: int = 0
	var counted: int = 0
	for key in tissue.patches:
		var patch: TissueGrid.Patch = tissue.patches[key]
		_check(patch.live, "the %s lattice was never posed" % key)
		for cell in patch.cells:
			counted += 1
			var band: Vector2 = patch.band_of(cell)
			if band.y - band.x <= 0.01:
				flat += 1
			if band.x < whole.x - 0.01 or band.y > whole.y + 0.01:
				stray += 1
	_check(counted > 0, "the lattice had no cells in it at all")
	_check(flat == 0, "%d of %d cells had no thickness — they are holes nothing can touch"
		% [flat, counted])
	_check(stray == 0, "%d cells stood outside the animal's own height (%s)"
		% [stray, Volume.describe(whole)])
	summary = "%d cells placed in three axes" % counted


## The cross-section is an ellipse, so the animal is deepest over its spine and
## tapers to nothing at the flank.
##
## This is the difference between a volume and a slab with a height written on
## it, and it is worth a check of its own because both look identical from
## directly above. A creature made of slabs is one whose flanks are as tall as
## its back — so jaws skimming the side of it would meet the full depth of the
## body, and something passing beside it at shoulder height would be stopped by
## air.
func _check_the_body_is_round(player: Creature) -> void:
	_apply(player, "Elephant")
	var patch: TissueGrid.Patch = player.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	# A column across the widest part of the trunk: same station, every row from
	# one flank to the other.
	var col: int = TissueGrid.HEAD_COLS + TissueGrid.TORSO_COLS / 2
	var spine_row: int = patch.rows / 2
	var over_spine: Vector2 = patch.band_of(col * patch.rows + spine_row)
	var on_flank: Vector2 = patch.band_of(col * patch.rows)
	_check(over_spine.y - over_spine.x > (on_flank.y - on_flank.x) * 1.3,
		"a cell over the spine (%.1f px deep) was no deeper than one on the flank (%.1f px) — this body is a slab"
			% [over_spine.y - over_spine.x, on_flank.y - on_flank.x])
	_check(on_flank.y - on_flank.x > 0.0, "the flank of the animal had no thickness at all")
	# Both are centred on the same back, whatever their depth. A taper that moved
	# the middle of the body about would be a bent animal rather than a round one.
	_check(absf((over_spine.x + over_spine.y) - (on_flank.x + on_flank.y)) < 0.01,
		"the flank and the spine were not centred on the same height")


## The cells and the stature describe one animal.
##
## Two descriptions of the same fact is the thing this whole layer is most at
## risk from: a bite resolved against cell heights and a collision resolved
## against a structure band can quietly diverge, and the symptom is a creature
## that can be eaten where it cannot be touched. So the coarse bands are checked
## against the fine ones rather than merely against themselves — the torso band
## has to be what the widest trunk cells actually occupy, and the head band what
## the snout cells do.
func _check_cells_agree_with_the_body(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var tissue: TissueGrid = player.anatomy.tissue
		var stature: Stature = player.stature
		var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
		# Against the *deepest* trunk cells, because that is what the stature's
		# own thickness is read off: an animal is as tall through the chest as its
		# chest is, and the taper fore and aft of it is the silhouette's business.
		# Anywhere else the cells are necessarily shallower, so comparing at an
		# arbitrary station would only be measuring the taper.
		var deepest: float = 0.0
		var off_level: float = 0.0
		var back: float = stature.reference + stature.elevation
		for k in range(TissueGrid.TORSO_COLS):
			var col: int = TissueGrid.HEAD_COLS + k
			# One cross-section rather than a cell's worth of two. A cell that
			# straddles the neck's slope occupies both of the heights its ends are
			# at, so it is honestly taller than the flesh in it is thick — which is
			# right for a collision and wrong for a measurement of the animal.
			var band: Vector2 = patch.column_band(col, col)
			deepest = maxf(deepest, band.y - band.x)
			# Past the neck the back is level, so every cross-section behind it has
			# to be centred on the one height the whole vertical layer is measured
			# from. A trunk that wandered up and down would be a body whose own
			# bands disagree with the height it is standing at.
			if float(k) / float(TissueGrid.TORSO_COLS) > TissueGrid.NECK_SHARE:
				off_level = maxf(off_level, absf((band.x + band.y) * 0.5 - back))
		_check(absf(deepest - stature.depth) < 2.0,
			"a %s's deepest trunk cells were %.1f px through where its stature says %.1f"
				% [preset, deepest, stature.depth])
		_check(off_level < 0.5,
			"a %s's trunk wandered %.1f px off the height it stands at" % [preset, off_level])
		var head: Vector2 = tissue.head_band()
		_check(Volume.overlaps(head, stature.head),
			"a %s's head cells (%s) and its head band (%s) were at different heights"
				% [preset, Volume.describe(head), Volume.describe(stature.head)])
		# The neck is the interesting one, because nothing declares it: it exists
		# only as the run of cells between the head's height and the back's. A
		# build whose head rides at shoulder level — a Lizard — has none, and that
		# is a fact about the animal rather than a gap in the lattice, so the claim
		# is conditional on the trait that produces it.
		if player.params.neck_lift > 0.0:
			_check(tissue.body_band(0.0).y > tissue.body_band(0.6).y + 1.0,
				"a %s carried the front of its trunk no higher than the middle — it has no neck"
					% preset)


## A leg is a column of flesh from the shoulder to the floor.
##
## The structure that makes the whole layer worth having. Everything else on an
## animal is a slab at one height, so a band per structure would have described
## it well enough; a leg is the one part that spans the entire gap underneath the
## body, and describing it with a single band throws away exactly the information
## a short predator needs. Per cell, the upper bone is up at the hip, the foot is
## on the floor, and the shin is in between — so there is a height at which a
## tall animal can be reached and a height at which it cannot.
func _check_a_leg_is_a_column(player: Creature) -> void:
	_apply(player, "Elephant")
	var tissue: TissueGrid = player.anatomy.tissue
	for key in TissueGrid.LIMB_KEYS:
		var upper: Vector2 = tissue.limb_band(key, 0)
		var lower: Vector2 = tissue.limb_band(key, 1)
		var foot: Vector2 = tissue.limb_band(key, 2)
		_check(upper.x > lower.x,
			"limb %s: the top of the leg started no higher than the bottom of it" % key)
		_check(foot.x < player.stature.torso.x,
			"limb %s: the foot (%s) was not below the belly (%.1f)"
				% [key, Volume.describe(foot), player.stature.torso.x])
		_check(foot.y < upper.y,
			"limb %s: the foot reached as high as the hip" % key)
		# And the column is continuous — a gap between the bones would be a height
		# at which the leg simply is not there, which is a hole to walk through.
		_check(Volume.overlaps(upper, lower) and Volume.overlaps(lower, foot),
			"limb %s: the leg had a gap in it (%s / %s / %s)"
				% [key, Volume.describe(upper), Volume.describe(lower), Volume.describe(foot)])


# ----------------------------------------------------------------- damage ----

## Damage lands where the jaws were, on all three axes.
##
## The same mark in the same place twice, differing only in the band it carries.
## Aimed at the flank of a tall animal it opens the flank; aimed at the height of
## its knees it opens nothing there at all, however squarely the footprint lies
## across the body. The lattice does not know what a knee is — it compares each
## cell's own band with the mark's, and the anatomy falls out of the comparison.
func _check_damage_is_volumetric(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(300.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	var patch: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var flank: Vector2 = target.spine.points[5]
	var wide: float = target.body.widths[5] + 30.0

	var low: int = _hammer(target, flank, wide, player.stature.bite)
	_check(low == 0,
		"jaws that reach knee height opened %d holes in a body held a leg above them" % low)

	var level: int = _hammer(target, flank, wide, target.stature.torso)
	_check(level > 0, "the same jaws at the body's own height did not reach it either")
	summary += ", %d cells opened at the right height and %d at the wrong one" % [level, low]

	# The legs, meanwhile, were reachable the whole time — so the low bite was
	# gated rather than merely feeble, and the animal is not immune to it.
	var legs: int = 0
	for key in TissueGrid.LIMB_KEYS:
		var leg: TissueGrid.Patch = target.anatomy.tissue.patch(key)
		var before: int = leg.gone_count
		for _repeat in 20:
			var mark := BiteMark.mouthful(leg.centre_of(leg.cells / 2), Vector2.RIGHT, 14.0, 40.0)
			mark.reach = player.stature.bite
			target.apply_bite(mark)
		legs += leg.gone_count - before
	_check(legs > 0,
		"a low animal could not open the legs of the creature standing over it either")
	target.reset(target.spawn_position, target.spawn_heading)


## Bites one spot thirty times with one reach, and reports how many cells of the
## trunk it destroyed. Thirty because a single mouthful is not meant to be enough
## — what is being measured is whether the jaws ever got there at all.
func _hammer(victim: Creature, at: Vector2, radius: float, reach: Vector2) -> int:
	var patch: TissueGrid.Patch = victim.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var before: int = patch.gone_count
	for _repeat in 30:
		var mark := BiteMark.mouthful(at, Vector2.RIGHT, radius, 40.0)
		mark.reach = reach
		victim.apply_bite(mark)
	return patch.gone_count - before


# --------------------------------------------------------------- targeting ----

## What the jaws can be brought to bear on, part by part.
##
## The hit test answers with a part rather than a creature, so the vertical gate
## has to be asked of the part. A low animal aiming squarely at a tall one's
## flank is offered the leg standing under it, because that is the only thing
## down there — not because anything preferred legs.
func _check_targeting_is_volumetric(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(300.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	var flank: Vector2 = target.spine.points[5]
	var wide: float = target.body.widths[5] + 40.0
	var flat: AnatomyState.Hit = target.query_bite(flank, wide)
	var low: AnatomyState.Hit = target.query_bite(flank, wide, player.stature.bite)
	_check(flat != null and flat.kind == AnatomyState.TORSO,
		"the query with no height at all did not find the flank it was aimed at")
	_check(low == null or low.kind == AnatomyState.LIMB,
		"a bite that only reaches knee height was offered the body above it")

	# And from far enough above, nothing at all — the animal is simply not there
	# as far as those jaws are concerned. Checked because the broad rejection that
	# makes this cheap is also the one that could reject a creature it should not.
	var sky := Vector2(4000.0, 4400.0)
	_check(target.query_bite(flank, wide, sky) == null,
		"jaws four thousand pixels up found something on the ground")
	target.reset(target.spawn_position, target.spawn_heading)


# --------------------------------------------------------------- collision ----

## Two things in the same place at different heights are not in each other's way.
##
## Checked directly on the capsule query the whole contact pass is built out of,
## with the same capsule in the same place twice. It is the cleanest statement of
## the rule anywhere in the suite: nothing moves, nothing is solved, and the only
## difference between the two calls is the band.
func _check_collision_is_volumetric(player: Creature, target: Creature) -> void:
	_apply(target, "Lizard")
	target.reset(Vector2.ZERO, 0.0)
	for _tick in 20:
		target._physics_process(TICK)

	var through: Vector2 = target.spine.points[3]
	var across_a: Vector2 = through + Vector2(0.0, -60.0)
	var across_b: Vector2 = through + Vector2(0.0, 60.0)
	var level: Vector2 = target.push_capsule_out_of_body(
		across_a, across_b, 6.0, Vector2.UP, target.stature.torso)
	_check(level != Vector2.ZERO,
		"a bar driven through a body at its own height was not pushed out of it")

	var over: Vector2 = target.push_capsule_out_of_body(
		across_a, across_b, 6.0, Vector2.UP, Volume.lift(target.stature.torso, 400.0))
	_check(over == Vector2.ZERO,
		"the same bar four hundred pixels overhead was still inside the body")

	var under: Vector2 = target.push_capsule_out_of_body(
		across_a, across_b, 6.0, Vector2.UP, Vector2(-500.0, -400.0))
	_check(under == Vector2.ZERO, "the same bar well below the ground was inside the body")

	# The limb router is the same rule reached through a different door, and it is
	# the one that decides where a walking animal may put its feet. A leg swung
	# through the air over something small must find nothing to route around.
	_apply(player, "Elephant")
	player.reset(Vector2(400.0, 0.0), 0.0)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)
	var foot: Vector2 = target.spine.points[3]
	var grounded: Vector2 = player._limb_contact_push(
		TissueGrid.LIMB_KEYS[0], 2, foot, foot, 10.0, Vector2(0.0, 8.0))
	var raised: Vector2 = player._limb_contact_push(
		TissueGrid.LIMB_KEYS[0], 2, foot, foot, 10.0, Vector2(400.0, 408.0))
	_check(grounded != Vector2.ZERO,
		"a foot set down on top of a body was not asked to go round it")
	_check(raised == Vector2.ZERO,
		"a foot carried four hundred pixels over a body still had to go round it")
	target.reset(target.spawn_position, target.spawn_heading)


# ------------------------------------------------------------------- world ----

## The habitat has heights too, and they are the same heights.
##
## Forage grows at a height and meat lies on the floor, so what a mouth can eat
## is decided by the same one comparison that decides what it can bite. The
## interesting direction is downward here: a creature that cannot get its jaws to
## the ground cannot scavenge, however much is lying at its feet.
func _check_the_world_is_volumetric(player: Creature) -> void:
	_apply(player, "Lizard")
	var scraps: ScrapField = main.scrap_field
	scraps.clear()
	var at: Vector2 = player.body.head.pos
	var chunk := TissueGrid.Shed.new()
	chunk.pos = at
	chunk.layer = TissueGrid.MUSCLE
	# A source id nothing here owns, so the "you may not eat yourself" rule is not
	# the thing being measured.
	scraps.scatter([chunk], at, 9901)
	_check(scraps.consume(at, 200.0, null, Vector2(300.0, 400.0)) == 0,
		"jaws held three hundred pixels up ate meat lying on the floor")
	_check(scraps.consume(at, 200.0, null, player.stature.bite) == 1,
		"an animal standing over a scrap could not get its mouth to it")
	scraps.clear()

	# Carrion answers the same question the same way, so a scrap and the carcass
	# it fell off cannot be reachable by different mouths.
	_check(Volume.overlaps(CarrionField.GROUND_BAND, Volume.ground()),
		"a carcass and a scrap on the same floor were at different heights")


# -------------------------------------------------------------------- flat ----

## With every band unbounded, this is the game that existed before the axis did.
##
## The guarantee the whole layer is built to keep: it is a second `and` on every
## test, never a replacement for the first. Anything that stopped happening when
## nobody declared a height would be a regression dressed up as a feature.
func _check_unbounded_is_the_flat_world(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(300.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	var flank: Vector2 = target.spine.points[5]
	_check(target.query_bite(flank, target.body.widths[5] + 40.0) != null,
		"a query with no reach declared found nothing on a body it was aimed straight at")

	# Before the bite rather than after it: thirty deep mouthfuls in one place eat
	# the column clean through, and a body with a hole in it stops colliding there
	# — correctly, and for a reason that has nothing to do with height.
	_check(target.push_capsule_out_of_body(flank + Vector2(0.0, -60.0),
			flank + Vector2(0.0, 60.0), 6.0, Vector2.UP) != Vector2.ZERO,
		"a capsule with no band was not pushed out of a body it was driven through")

	var patch: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var before: int = patch.gone_count
	for _repeat in 30:
		# No reach set at all, which is what BiteMark defaults to.
		target.apply_bite(BiteMark.mouthful(flank, Vector2.RIGHT,
			target.body.widths[5] + 30.0, 40.0))
	_check(patch.gone_count > before,
		"a bite that declared no height failed to damage the body under it")
	target.reset(target.spawn_position, target.spawn_heading)


# ------------------------------------------------------------------- rig ----

func _apply(creature: Creature, preset: String) -> void:
	creature.set_bite_held(false)
	creature.params.apply_preset(preset)
	creature.command = MovementInput.Command.new()
	creature.elevation.reset()
	creature.reset(creature.head_pos, creature.heading)
	creature._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("volume OK — every cell has three coordinates and every interaction asks for all of them: %s"
			% summary)
		quit(0)
	else:
		for failure in failures:
			print("VOLUME FAIL — ", failure)
		quit(1)
