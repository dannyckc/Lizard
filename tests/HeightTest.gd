## Headless check for the vertical axis — see Elevation, Stature and Posture.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/HeightTest.gd
##
## The whole 2.5D layer is one scalar and one rule: things interact when the
## heights they occupy overlap. So this is weighted toward the *seams* rather
## than toward the arithmetic — the places where a second question is now asked
## after the horizontal one, and where getting it wrong would either break the
## flat game or quietly do nothing at all.
##
## The four states first, because they are read rather than written and a state
## machine that has been reintroduced by accident would show up here. Then the
## mechanics the layer exists for: leaping over a charge, being out of reach in
## the air, a low animal that can only get at a tall one's legs, and forage a
## short neck cannot reach. And last, the guarantee everything else rests on:
## with every band overlapping, the game behaves exactly as it did on one plane.
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

	_check_bands(player)
	_check_states()
	_check_leap(player)
	_check_over_a_charge(player, target)
	_check_walking_over(player, target)
	_check_out_of_reach(player, target)
	_check_legs_only(player, target)
	_check_browsing(player)
	_check_flat_world_unchanged(player, target)
	_finish()
	return false


# ------------------------------------------------------------------ bands ----

## A body's heights are read off its legs and its silhouette, not set on it. The
## claim is that they are ordered like an animal: feet on the ground, belly above
## them, back above that, and the jaws reaching from the floor to somewhere over
## the head.
func _check_bands(player: Creature) -> void:
	_apply(player, "Lizard")
	var s: Stature = player.stature
	_check(s.limbs.x <= 0.001, "the legs did not reach the ground (%.1f)" % s.limbs.x)
	_check(s.torso.x > s.limbs.x, "the belly was not above the feet")
	_check(s.torso.y > s.torso.x, "the torso had no thickness at all")
	_check(s.head.y >= s.torso.x, "the head was below the whole animal")
	_check(s.bite.x <= 0.001,
		"a creature standing on the ground could not get its mouth to it (%.1f)" % s.bite.x)
	_check(s.bite.y > s.torso.y,
		"the jaws could not reach as high as this animal's own back")
	_check(Stature.overlaps(s.whole, s.torso) and Stature.overlaps(s.whole, s.limbs),
		"the union of a body's bands did not contain its parts")

	# Longer legs are a taller animal, with nothing else touched. This is the one
	# check that the height is genuinely derived: change the thing that holds the
	# body up and the body goes up.
	var stood: float = s.clearance
	player.params.leg_length *= 2.0
	player.params.arm_length *= 2.0
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	_check(player.stature.clearance > stood * 1.6,
		"doubling the legs barely raised the body (%.1f -> %.1f)"
			% [stood, player.stature.clearance])
	_apply(player, "Lizard")

	# Two bands that do not meet do not overlap, and touching exactly counts.
	_check(not Stature.overlaps(Vector2(0.0, 10.0), Vector2(11.0, 20.0)),
		"two separated bands reported an overlap")
	_check(Stature.overlaps(Vector2(0.0, 10.0), Vector2(10.0, 20.0)),
		"two bands meeting at a point reported no overlap")


# ----------------------------------------------------------------- states ----

## Grounded, leaping, gliding, flying — and every one of them read off the
## scalar and the wings rather than stored. Driven directly here rather than
## through a creature, because what is being checked is that no fifth thing is
## keeping the state and can therefore disagree with the height.
func _check_states() -> void:
	var air := Elevation.new()
	_check(air.state() == Elevation.GROUNDED, "a body on the ground did not read as grounded")
	_check(air.is_grounded() and not air.is_airborne(), "grounded and airborne disagreed")

	# No wings: leaping is the only airborne state available, and nothing had to
	# forbid the other two.
	_check(air.leap(120.0), "a standing creature refused to leap")
	air.advance(TICK, 0.0, 0.0, 200.0)
	_check(air.state() == Elevation.LEAPING, "a body thrown into the air was not leaping")
	_check(not air.leap(120.0), "a creature already in the air leapt again")
	var apex: float = 0.0
	var airtime: int = 0
	for _tick in 400:
		air.advance(TICK, 1.0, 0.0, 200.0)
		apex = maxf(apex, air.height)
		if air.is_airborne():
			airtime += 1
		# Holding the climb key with nothing to climb with must change nothing.
		if air.state() != Elevation.GROUNDED and air.state() != Elevation.LEAPING:
			_check(false, "a wingless creature reached %s" % air.state_name())
			break
	_check(absf(apex - 120.0) < 6.0, "a leap for 120 px peaked at %.1f" % apex)
	_check(air.is_grounded(), "a leap never came back down")
	_check(air.landed or airtime > 0, "the landing was never reported")

	# Wings: the same scalar, and now the two flight states are reachable. Which
	# of them it is, is the height against what the wings can hold.
	var flier := Elevation.new()
	flier.leap(40.0)
	var seen_glide: bool = false
	var seen_flight: bool = false
	for _tick in 900:
		flier.advance(TICK, 1.0, 1.0, 200.0)
		if flier.state() == Elevation.GLIDING:
			seen_glide = true
		elif flier.state() == Elevation.FLYING:
			seen_flight = true
	_check(seen_glide, "a climbing flier never passed through low flight")
	_check(seen_flight, "a flier holding the climb never reached high flight")
	_check(flier.height <= flier.ceiling() + 0.01,
		"a flier climbed past its own ceiling (%.1f of %.1f)"
			% [flier.height, flier.ceiling()])

	# Folding the wings mid-air is a stall, and it is a stall because the state is
	# derived: nothing sets it, the lift simply stops being asked for.
	flier.advance(TICK, -1.0, 1.0, 200.0)
	_check(flier.state() == Elevation.LEAPING,
		"a flier that folded up was still %s" % flier.state_name())

	# Whatever was holding it up can also just stop.
	flier.ground()
	_check(flier.state() == Elevation.GROUNDED and flier.height == 0.0,
		"a body dropped out of the sky did not land")


# ------------------------------------------------------------------ leaps ----

## What the legs can do is what decides whether there is a leap at all, and it is
## an anatomical trait rather than a control: a columnar animal has no way to
## throw itself into the air and nothing anywhere says so.
##
## Held-and-released rather than pressed, because that is what the control is now
## — see Jump. The creature gathers, crouches, winds whatever it has to wind, and
## goes when the key comes up; a body that never releases never leaves the floor,
## which is why every helper below lets go.
func _check_leap(player: Creature) -> void:
	_check(_peak_leap(player, "Cat") > 0.0, "a Cat could not leave the ground")
	_check(_peak_leap(player, "Elephant") <= 0.0,
		"an Elephant left the ground")
	_check(_peak_leap(player, "Cat") > _peak_leap(player, "Lizard"),
		"a Cat did not out-jump a Lizard")

	# Off the ground, the legs stop being placed and start being carried. A foot
	# planted in mid-air would be the gait solving against a floor that is not
	# there.
	_apply(player, "Cat")
	var climb := MovementInput.Command.new()
	climb.climb = 1.0
	player.command = climb
	var footfalls: int = 0
	var aloft: int = 0
	for tick in 120:
		# Long enough to be at full charge, and then let go. Everything after that
		# is the arc.
		player.command.climb = 1.0 if tick < 60 else 0.0
		player._physics_process(TICK)
		if player.elevation.is_airborne():
			aloft += 1
			footfalls += player.gait.landed.size()
	_check(aloft > 20, "a leaping Cat was only airborne for %d ticks" % aloft)
	_check(footfalls == 0, "a creature in mid-air planted %d feet" % footfalls)
	_apply(player, "Lizard")


## The apex of one fully charged standing jump.
##
## Sixty ticks of holding is comfortably past every preset's own charge time —
## which is a limb's swing period and so is longest on the largest animal — and
## the release is a real one: the command goes to zero and the body pushes off
## whatever it managed to wind.
func _peak_leap(creature: Creature, preset: String) -> float:
	_apply(creature, preset)
	var climb := MovementInput.Command.new()
	creature.command = climb
	var peak: float = 0.0
	for tick in 260:
		climb.climb = 1.0 if tick < 60 else 0.0
		creature._physics_process(TICK)
		peak = maxf(peak, creature.elevation.height)
	creature.command = MovementInput.Command.new()
	return peak


# --------------------------------------------------------------- mechanics ----

## Jumping over a charge. Two bodies that are not at the same height are not in
## each other's way, so the pair simply has no contact to resolve — which is the
## same exemption a grip already gets and lands in the same place.
##
## Two Cats, and the pairing is the point rather than a convenience. The contact
## pass compares the piece of one trunk that is actually meeting the piece of the
## other, so "on the ground" is not by itself enough to guarantee a collision:
## two animals of different builds standing on the same floor can have no height
## in common at all, which is the case checked immediately below this one. Matched
## builds are the fixture in which the leap is the only variable.
func _check_over_a_charge(player: Creature, target: Creature) -> void:
	_apply(player, "Cat")
	_apply(target, "Cat")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(70.0, 0.0), PI)
	for _tick in 10:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(Stature.overlaps(player.stature.whole, target.stature.whole),
		"two creatures standing on the same ground did not occupy the same heights")

	# The leap has to clear the *back* of the other animal, so the contest is a
	# real one rather than a dodge key: check the geometry before the dynamics.
	# Off what this body's legs actually come to rather than off a species number,
	# which is the point of the whole derivation — see Leap.
	_check(player.leap.peak(1.0) > target.stature.torso.y,
		"a Cat's leap (%.0f px) does not clear a Lizard's back (%.0f px) — nothing below can pass"
			% [player.leap.peak(1.0), target.stature.torso.y])

	# Walked into, the charger is shouldered aside exactly as it always was.
	var grounded_shove: float = _charge(player, target, false)
	_check(grounded_shove > 4.0,
		"a charge on the ground moved nothing (%.1f px) — the contact pass is not running"
			% grounded_shove)

	# Leapt over, the two never touch.
	var cleared_shove: float = _charge(player, target, true)
	_check(cleared_shove < grounded_shove * 0.35,
		"leaping over a charge still shoved the victim %.1f px (walked: %.1f)"
			% [cleared_shove, grounded_shove])
	summary = "charge %.0f px on the ground, %.0f px leapt over" % [grounded_shove, cleared_shove]


## Runs the player at the target and reports how far the target was pushed.
##
## With `leap` set the charge is held as the gap closes and dropped when the
## victim is close enough to clear — which is the control the player has, and is
## why the window is measured in distance rather than in ticks. Held all the way
## through, the creature would still be crouching when it arrived; held for no
## time at all it would hop. What is wanted is one committed jump, so it winds for
## as long as the approach allows and lets go.
func _charge(player: Creature, target: Creature, leap: bool) -> float:
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(300.0, 0.0), PI)
	for _tick in 10:
		player._physics_process(TICK)
		target._physics_process(TICK)
	var start: Vector2 = target.head_pos
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.sprint = true
	var jumped: bool = false
	# Both runs end on the same event — the charger's nose level with its
	# victim's — rather than on a tick count, so what is compared is the cost of
	# covering the same ground and not how long each took to do it. Running on
	# past that would only measure where the leap came down.
	for _tick in 260:
		drive.climb = 0.0
		if leap and not jumped and player.elevation.is_grounded():
			# Wind it up on the approach and let go inside the last stride. Both
			# halves are the same key: held, the animal is gathering; released, it
			# goes with whatever that came to.
			var gap: float = player.head_pos.distance_to(target.head_pos)
			drive.climb = 1.0 if gap >= 150.0 else 0.0
			jumped = gap < 150.0
		player.command = drive
		target.command = MovementInput.Command.new()
		player._physics_process(TICK)
		target._physics_process(TICK)
		if player.head_pos.x >= target.head_pos.x:
			break
	player.command = MovementInput.Command.new()
	if leap:
		_check(jumped, "the charging creature never got its leap away")
	return start.distance_to(target.head_pos)


## Walking underneath something that stands higher than you reach.
##
## The leap's companion, and the same rule with nothing added to it. An Elephant
## carries its trunk a whole leg off the ground, so a Lizard standing directly
## beneath it — crown and all — shares no height with any part of that body and
## the contact pass has nothing to resolve. Nothing anywhere is about elephants:
## the two simply have no band in common, exactly as a leaping animal has none
## with the charge passing under it.
##
## What keeps this from being a hole in the world is the legs. A leg spans the
## whole gap under an animal, so the Elephant's are squarely inside the Lizard's
## band the entire time — going underneath a body means going between its legs,
## and that is a contact like any other.
func _check_walking_over(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(500.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(target.stature.torso.x > player.stature.trunk.y,
		"an Elephant's belly (%.1f) did not clear a Lizard's crown (%.1f) — nothing to test"
			% [target.stature.torso.x, player.stature.trunk.y])

	# Straight underneath, with no tick in between: the claim is about the pass
	# itself, so nothing else gets to move either body first.
	player.reset(target.spine.points[4], 0.0)
	_resettle(player)
	_check(player._push_out_of_creature(target) == Vector2.ZERO,
		"a body underneath another one's belly was still shouldered aside by it")

	# The same two bodies in the same two places, one number changed: lift the
	# Lizard to the Elephant's own chest and the identical pass throws it out hard.
	# Nothing but the height differs, so nothing but the height can be the reason.
	player.elevation.height = target.stature.reference
	_resettle(player)
	_check(player._push_out_of_creature(target) != Vector2.ZERO,
		"two bodies in the same place at the same height did not collide at all")
	player.elevation.reset()
	_resettle(player)

	# And the legs are still down there. If they were not, "underneath" would mean
	# "through", and a tall animal would be a hologram on four sticks.
	var underfoot: bool = false
	for limb in target.gait.limbs:
		for segment in 3:
			underfoot = underfoot or Volume.overlaps(player.stature.trunk,
				target.anatomy.tissue.limb_band(limb.key, segment))
	_check(underfoot,
		"nothing on the taller animal reached down into the shorter one's height")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(target.spawn_position, target.spawn_heading)


## Flying beyond the reach of a terrestrial predator. The gate is the same one
## that decides everything else — the jaws' band against what they are aimed at —
## so being out of reach is not a rule about flight, it is a height.
func _check_out_of_reach(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(30.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	var mark: BiteMark = player.bite_mark(player.jaw_point(), player.bite_depth())
	_check(target.query_bite(mark.center, mark.radius, mark.reach) != null,
		"a bite at point-blank range on the ground found nothing to hit")

	# Lift the victim well clear and the identical bite finds nothing — while the
	# purely horizontal query still finds it, which is what proves the vertical
	# gate is the thing doing the work rather than the two having drifted apart.
	target.elevation.height = 400.0
	_resettle(target)
	_check(target.query_bite(mark.center, mark.radius) != null,
		"the horizontal hit test stopped seeing a creature that only went up")
	_check(target.query_bite(mark.center, mark.radius, mark.reach) == null,
		"a grounded creature bit something 400 px above its head")
	_check(not Stature.overlaps(player.stature.whole, target.stature.whole),
		"a creature in the air still shared a height with one on the ground")

	# And it works both ways: the flier cannot reach down either, so an attack
	# from above is a dive rather than a hover.
	target.params.wing_lift = 1.0
	_resettle(target)
	var from_above: BiteMark = target.bite_mark(target.jaw_point(), target.bite_depth())
	_check(player.query_bite(from_above.center, from_above.radius, from_above.reach) == null,
		"a creature 400 px up bit something standing on the ground")
	target.params.wing_lift = 0.0
	target.elevation.reset()
	_resettle(target)


## A low animal on a tall one. The interesting half of the vertical layer: the
## legs are the one structure that runs from the ground to the body, so they are
## the only thing a short reach can find — and the body above them is untouchable
## without anybody having written a rule about legs.
func _check_legs_only(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(300.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	var reach: Vector2 = player.stature.bite
	_check(reach.y < target.stature.torso.x,
		"a Lizard's jaws (%.0f) reached as high as an Elephant's belly (%.0f)"
			% [reach.y, target.stature.torso.x])
	_check(Stature.overlaps(reach, target.stature.limbs),
		"a Lizard could not even reach an Elephant's legs")
	_check(not Stature.overlaps(reach, target.stature.head),
		"a Lizard could reach an Elephant's head")

	# Put the jaws on the flank, where a torso hit is what the flat game would
	# return, and the query answers with the leg standing under it or nothing.
	var flank: Vector2 = target.spine.points[4]
	var wide: float = target.body.widths[4] + 40.0
	var flat: AnatomyState.Hit = target.query_bite(flank, wide)
	var raised: AnatomyState.Hit = target.query_bite(flank, wide, reach)
	_check(flat != null and flat.kind == AnatomyState.TORSO,
		"the flat query did not find the flank it was aimed at")
	_check(raised == null or raised.kind == AnatomyState.LIMB,
		"a bite that only reaches knee height took the body above it")

	# ...and the damage has to agree with the query, or the lattice would quietly
	# erode a flank the jaws never got near.
	var body_patch: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var before: int = body_patch.gone_count
	for _repeat in 30:
		var deep := BiteMark.mouthful(flank, Vector2.RIGHT, 26.0, 40.0)
		deep.reach = reach
		target.apply_bite(deep)
	_check(body_patch.gone_count == before,
		"thirty bites that could not reach an Elephant's body opened %d holes in it"
			% (body_patch.gone_count - before))
	# The same mark with a reach that does cover the body goes straight through it,
	# so the gate is what stopped it and not the mark.
	var tall := BiteMark.mouthful(flank, Vector2.RIGHT, 26.0, 40.0)
	tall.reach = target.stature.torso
	target.apply_bite(tall)
	_check(body_patch.gone_count > before,
		"a bite at the right height did not reach the body either")
	target.reset(target.spawn_position, target.spawn_heading)


## Browsing. There is no browse action and no second kind of food: some forage
## simply grows higher than some animals can reach.
func _check_browsing(player: Creature) -> void:
	var field: FoodField = main.food_field
	_apply(player, "Lizard")
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)

	var at: Vector2 = player.body.head.pos
	var high: float = player.stature.bite.y + 60.0
	field.pellets = PackedVector2Array([at, at])
	field.heights = PackedFloat32Array([0.0, high])
	_check(field.consume(at, player.mouth_radius(), player.stature.bite) == 1,
		"a short-necked animal ate the forage over its head as well as the forage at its feet")
	_check(field.pellets.size() == 1 and field.heights.size() == 1,
		"eating a pellet left its height behind")

	# Give it the neck and the same pellet is food. One parameter, and the whole
	# of what a browser is.
	player.params.neck_lift = 0.6
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	_check(player.stature.bite.y > high,
		"a long neck did not raise what the jaws can reach (%.0f, needed %.0f)"
			% [player.stature.bite.y, high])
	_check(field.consume(player.body.head.pos, player.mouth_radius() + 40.0,
		player.stature.bite) == 1, "a browser could not reach forage over its head")
	_apply(player, "Lizard")
	field.pellets.clear()
	field.heights.clear()


# ------------------------------------------------------------------- flat ----

## The guarantee the whole layer is built on: with nothing off the ground, every
## line above is inert. An unbounded reach hits what it always hit, two creatures
## standing on the same floor collide as they always did, and the lattice erodes
## the cells it always eroded.
func _check_flat_world_unchanged(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(30.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(player.elevation.is_grounded() and target.elevation.is_grounded(),
		"a creature nobody asked to jump left the ground")

	var at: Vector2 = target.spine.points[3]
	var gated := BiteMark.mouthful(at, Vector2.RIGHT, 14.0, 30.0)
	gated.reach = player.stature.bite
	var open := BiteMark.mouthful(at, Vector2.RIGHT, 14.0, 30.0)
	_check(open.reach == Stature.UNBOUNDED,
		"a mark built without a mouth did not default to reaching everything")
	var patch: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var removed_gated: float = target.apply_bite(gated)
	target.reset(Vector2(30.0, 0.0), PI)
	for _tick in 4:
		target._physics_process(TICK)
	var removed_open: float = target.apply_bite(open)
	_check(absf(removed_gated - removed_open) < 0.01,
		"the same bite took %.2f through the height gate and %.2f without it"
			% [removed_gated, removed_open])
	_check(patch != null, "the victim lost its lattice")
	target.reset(target.spawn_position, target.spawn_heading)


# ------------------------------------------------------------------ tools ----

## Re-derives everything downstream of a body's height, without advancing time.
##
## Two steps rather than one, and the second is the one that is easy to forget:
## the heights a creature occupies are no longer only in its stature, they are on
## every cell of its tissue lattice. A test that lifts a body off the ground and
## re-reads the stature alone leaves the flesh where it was — which is exactly the
## disagreement the volumetric layer exists to make impossible, so it must not be
## allowed to happen here either. The tick does the same two in the same order.
func _resettle(creature: Creature) -> void:
	creature._update_stature()
	creature.anatomy.update(creature)


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
		print("height OK — four states read off one scalar, and reach is a band: %s" % summary)
		quit(0)
	else:
		for failure in failures:
			print("HEIGHT FAIL — ", failure)
		quit(1)
