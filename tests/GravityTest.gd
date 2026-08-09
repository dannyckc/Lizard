## Headless check that one pull acts on everything — see Gravity, Droop, Balance.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/GravityTest.gd
##
## The vertical axis was built one consumer at a time, and each of them was right
## about its own case and quiet about everybody else's. A creature fell because it
## had jumped. A leg lay on the floor because legs on the floor were the only kind
## the world had ever seen. A tail was level with the back because nothing had ever
## asked it what it weighed. Every one of those is a body being *positioned* rather
## than being *held up*, and the whole of this file is the difference.
##
## Four groups, and they are four different claims:
##
##   * **one pull** — that there is a single number and a single integrator, and
##     that the ballistic solutions the jump reads and the ones a dropped leg reads
##     are literally the same lines. Two gravities that agree today are two
##     gravities.
##   * **what falls** — that anatomy which stops being part of an animal falls from
##     where it was, arrives at what is underneath it, and is out of reach of the
##     floor for exactly as long as it is in the air.
##   * **what hangs** — that a tail is held up by muscle and bone rather than by
##     being drawn level, so it sags under its own weight, sags further when the
##     animal stops driving it, and sags further again where its vertebrae have
##     gone. And that the picture agrees: the cells are where the tail is.
##   * **what stands** — that standing is a claim about having enough leg under the
##     weight, checked every tick, rather than a pose a living creature is entitled
##     to. A conscious animal with no hind legs goes down; a two-legged one does
##     not; and neither does one that is merely in the air.
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
	# Flat, empty ground. Every measurement here is of one thing falling, and an
	# obstacle to land on would make several of them measurements of the obstacle.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	_check_one_pull()
	_check_a_fall_is_ballistic()
	_check_severed_anatomy_falls(player)
	_check_a_falling_part_is_out_of_reach(player)
	_check_a_tail_hangs(player)
	_check_a_dead_tail_hangs_further(player)
	_check_a_broken_back_drops_its_tail(player)
	_check_the_picture_agrees(player)
	_check_sag_is_the_same_at_any_size(player)
	_check_standing_is_support(player)
	_check_a_leap_is_not_a_collapse(player)
	_finish()
	return false


# -------------------------------------------------------------- one pull ----

## That there is one number, and that everything reads it.
##
## The point of the file, stated as flatly as it can be. `Elevation` used to own
## the constant, which was fine while a jumping creature was the only thing in the
## world that had a height it could lose.
func _check_one_pull() -> void:
	_check(is_equal_approx(Elevation.GRAVITY, Gravity.PULL),
		"the creature's gravity (%.1f) is not the world's (%.1f)"
		% [Elevation.GRAVITY, Gravity.PULL])
	_check(is_equal_approx(Elevation.TOUCHDOWN, Gravity.TOUCHDOWN),
		"a creature and a dropped leg disagree about what standing on something is")

	# The two ballistic solutions are each other's inverse. Both are used in anger —
	# the jump reads the first to work out how hard the legs threw the body, and the
	# tuck reads the second to normalise against the launch — so a drift between
	# them would be a jump that measured itself wrong.
	for peak in [10.0, 60.0, 240.0]:
		var rate: float = Gravity.launch_rate(peak)
		_check(absf(Gravity.peak_of(rate) - peak) < 0.01,
			"a launch of %.0f px came back as %.2f px" % [peak, Gravity.peak_of(rate)])
		# And the time to fall back from that apex is the time it took to reach it.
		var t: float = Gravity.fall_time(peak, 0.0)
		_check(absf(t - rate / Gravity.PULL) < 0.001,
			"a %.0f px drop took %.3f s against the %.3f s it took to rise"
			% [peak, t, rate / Gravity.PULL])
	notes.append("one pull at %.0f px/s²" % Gravity.PULL)


## That the shared integrator is the physics it claims to be, and that it settles.
##
## Integrated rather than solved, so this is really asking whether the tick-by-tick
## answer matches the closed form to within a tick — which is the standard every
## other integrator in the simulation is held to.
func _check_a_fall_is_ballistic() -> void:
	var fall := Gravity.Fall.new()
	fall.start(400.0)
	var expected: float = Gravity.fall_time(400.0, 0.0)
	var elapsed: float = 0.0
	var guard: int = 0
	while not fall.landed and guard < 600:
		fall.advance(TICK)
		elapsed += TICK
		guard += 1
	_check(fall.landed, "a body dropped 400 px never arrived")
	_check(absf(elapsed - expected) < TICK * 2.0,
		"a 400 px drop took %.3f s against a predicted %.3f s" % [elapsed, expected])
	_check(absf(fall.impact - Gravity.launch_rate(400.0)) < 40.0,
		"it arrived at %.0f px/s against the %.0f px/s it fell for"
		% [fall.impact, Gravity.launch_rate(400.0)])

	# ...and then stops. A thing that bounces forever is a thing the habitat pays
	# for forever, so the settle is as much a claim as the fall.
	guard = 0
	while not fall.resting and guard < 900:
		fall.advance(TICK)
		guard += 1
	_check(fall.resting, "a dropped body never came to rest")
	_check(is_zero_approx(fall.height),
		"it came to rest %.2f px off the floor" % fall.height)

	# On something, not at zero. The habitat has terrain in it and a leg dropped on
	# a rock lies on the rock.
	var shelf := Gravity.Fall.new()
	shelf.start(200.0, 0.0, 60.0)
	guard = 0
	while not shelf.resting and guard < 900:
		shelf.advance(TICK, 60.0)
		guard += 1
	_check(absf(shelf.height - 60.0) < 0.5,
		"a body dropped onto a 60 px surface settled at %.1f px" % shelf.height)
	notes.append("a 400 px drop lands in %.2f s and settles" % elapsed)


# ---------------------------------------------------------- what falls ----

## That a limb bitten off a standing animal falls from the animal.
##
## The single most visible consequence of the whole file, and the one that was
## flatly wrong before it: a severed part was created at the position of the
## tissue and at the height of nothing, so a leg taken off a shoulder appeared
## already lying under the creature that had just lost it.
func _check_severed_anatomy_falls(player: Creature) -> void:
	_clear()
	_stand(player, "Elephant")
	var back: float = player.stature.reference
	var part: CarrionField.Part = _sever_tail(player)
	if part == null:
		_check(false, "cutting a tail off produced no part to drop")
		return
	_check(part.fall.height > 0.0,
		"a tail off a back held %.0f px up was born on the floor" % back)
	_check(part.fall.is_airborne(), "it was born already at rest")
	var born: float = part.fall.height
	var ticks: int = 0
	while not part.fall.resting and ticks < 600:
		main.carrion.settle(TICK)
		ticks += 1
	_check(part.fall.resting, "a severed tail never landed")
	_check(is_zero_approx(part.fall.height),
		"it came to rest %.1f px in the air" % part.fall.height)
	_check(ticks > 1, "it arrived on the tick it was created — that is not a fall")

	# And it falls from *this* animal rather than from a height anybody chose. The
	# same cut through the same place on a much shorter creature has much less to
	# fall, because the back it came off is lower — which is the whole claim,
	# stated as a comparison so no constant has to be believed.
	_clear()
	_stand(player, "Lizard")
	var low: CarrionField.Part = _sever_tail(player)
	if low != null:
		_check(low.fall.height < born,
			"a tail off a Lizard was born %.1f px up, against an Elephant's %.1f"
			% [low.fall.height, born])
		notes.append("a tail fell %.0f px off an Elephant and %.0f px off a Lizard"
			% [born, low.fall.height])
	else:
		notes.append("a tail off an Elephant fell %.0f px in %d ticks" % [born, ticks])


## That being in the air means being out of reach, for meat exactly as for animals.
##
## The vertical layer's one rule is that two things interact when their heights
## overlap. A part used to quote a constant band at the floor, which made it
## reachable by anything on the floor from the instant it existed — including,
## absurdly, while it was still notionally up at the shoulder it came off.
func _check_a_falling_part_is_out_of_reach(player: Creature) -> void:
	_clear()
	_stand(player, "Elephant")
	var part: CarrionField.Part = _sever_tail(player)
	if part == null:
		_check(false, "cutting a tail off produced no part to reach for")
		return
	var floor_jaws := Vector2(0.0, Volume.GROUND_THICKNESS)
	_check(not Volume.overlaps(floor_jaws, part.band()),
		"jaws at ground level could reach a leg still %.0f px up" % part.fall.height)
	# ...and the same jaws, on the same part, once it has arrived.
	var guard: int = 0
	while not part.fall.resting and guard < 600:
		main.carrion.settle(TICK)
		guard += 1
	_check(Volume.overlaps(floor_jaws, part.band()),
		"jaws at ground level could not reach a leg lying on the ground")
	_check(main.carrion.reach_of(part.pos, 40.0, floor_jaws) == part,
		"the field would not hand over a part lying at the asker's own height")


# ---------------------------------------------------------- what hangs ----

## That a tail is carried rather than drawn level.
##
## Every build in the file has to sag *some*, because every build has a tail with
## a weight, and none of them may sag to the floor while standing, because a live
## animal holds its tail up. Between those two the numbers are the body's own
## business and are reported rather than asserted.
func _check_a_tail_hangs(player: Creature) -> void:
	var readings: Array[String] = []
	for preset in ["Lizard", "Cat", "Elephant", "T. rex"]:
		_stand(player, preset)
		var back: float = player.stature.reference + player.stature.elevation
		var sag: float = player.droop.tip_sag
		_check(sag > 0.0, "a %s carried its tail perfectly level" % preset)
		_check(player.droop.heights[player.droop.heights.size() - 1] >= 0.0,
			"a %s's tail hung through the floor" % preset)
		_check(sag < back,
			"a standing %s let its tail down onto the ground (%.1f of %.1f px)"
			% [preset, sag, back])
		readings.append("%s %.0f%%" % [preset, 100.0 * sag / maxf(back, 0.001)])

	# And the sag is a curve rather than a hinge: a tail droops most at the tip,
	# because the tip is the thinnest section carrying the longest lever. Checked as
	# a *shape* rather than a value — the gap between consecutive stations has to
	# keep growing toward the end.
	_stand(player, "Lizard")
	var h: PackedFloat32Array = player.droop.heights
	var hip: int = clampi(int(round(player.droop.anchor * float(h.size() - 1))),
		0, h.size() - 2)
	var steepening: bool = true
	var previous: float = 0.0
	for i in range(hip, h.size() - 1):
		var step: float = h[i] - h[i + 1]
		if step + 0.0001 < previous:
			steepening = false
		previous = step
	_check(steepening, "a tail bent hardest at its root rather than at its tip")
	notes.append("tail sag: " + ", ".join(readings))


## That what holds a tail up is the animal, so a body that stops holding it drops
## it. The clearest statement in the file that this is muscle rather than pose.
func _check_a_dead_tail_hangs_further(player: Creature) -> void:
	_stand(player, "Cat")
	var alive_gap: float = player.stature.reference - player.droop.heights[
		player.droop.heights.size() - 1]
	player.collapse()
	for _i in 30:
		player._physics_process(TICK)
	var dead_tip: float = player.droop.heights[player.droop.heights.size() - 1]
	_check(dead_tip < 2.0,
		"a dead Cat still held its tail %.1f px off the ground" % dead_tip)
	notes.append("a Cat's tail: %.1f px below the back alive, on the floor dead"
		% alive_gap)
	_revive(player)


## And that it is *skeletal* as well as muscular, at the station where the skeleton
## has actually gone. A back broken at the pelvis drops the tail there and nowhere
## else, which is the same reading the spine solver already takes.
func _check_a_broken_back_drops_its_tail(player: Creature) -> void:
	_stand(player, "Cat")
	var sound: float = player.droop.tip_sag
	# Chew out the pelvis, which is what the tail hangs off.
	var tissue: TissueGrid = player.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	var shed: Array = []
	var pelvis: int = int(float(patch.cols) * 0.72)
	for col in range(pelvis, mini(pelvis + 3, patch.cols)):
		for row in patch.rows:
			for _i in 14:
				tissue.bite(BiteMark.mouthful(
					patch.centre_of(col * patch.rows + row), Vector2.RIGHT, 0.9, 9.0), shed)
	for _i in 6:
		player._physics_process(TICK)
	if not player.alive:
		# Chewing a body's pelvis out is quite capable of killing it, and a dead
		# animal's tail is already on the floor for a reason this check is not about.
		notes.append("a Cat with its pelvis chewed out died before its tail could hang")
		_revive(player)
		return
	_check(player.droop.tip_sag > sound,
		"a Cat with its pelvis chewed through held its tail exactly as well (%.1f vs %.1f px)"
		% [player.droop.tip_sag, sound])
	notes.append("a broken pelvis dropped a tail from %.1f to %.1f px"
		% [sound, player.droop.tip_sag])
	_revive(player)


## That the drawing tells the truth about it.
##
## The lattice is what the creature is bitten through, and the view draws the
## lattice — so if the tail's cells are at the tail's height, the picture and the
## volume are the same claim. This is the check that stops the sag being a
## decoration: a creature could otherwise be drawn with a hanging tail and bitten
## on a level one.
func _check_the_picture_agrees(player: Creature) -> void:
	_stand(player, "Lizard")
	var patch: TissueGrid.Patch = player.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	_check(patch != null and patch.live, "the lattice was never posed")
	if patch == null or not patch.live:
		return
	var back: float = player.stature.reference + player.stature.elevation
	var tip: float = patch.mids[patch.mids.size() - 1]
	_check(tip < back - 0.5,
		"the tail's cells sat at the back's height (%.1f against %.1f)" % [tip, back])
	_check(absf(tip - player.droop.at(1.0)) < 0.5,
		"the cells at the tail tip (%.1f) and the tail tip (%.1f) are two different heights"
		% [tip, player.droop.at(1.0)])
	# ...and the cells behind the hips have to occupy lower heights than the cells
	# over them, or a bite aimed at a hanging tail would land on a level one. Asked
	# of the lattice's own stations rather than of the belly, because how far a
	# tail can get below the belly is a fact about how high the animal stands and
	# this is a claim about the tail.
	var hip_station: int = clampi(
		int(round(player.droop.anchor * float(TissueGrid.TORSO_COLS)))
		+ TissueGrid.HEAD_COLS, 0, patch.mids.size() - 1)
	_check(tip < patch.mids[hip_station] - 0.5,
		"the tail's cells (%.1f) sat no lower than the cells over the hips (%.1f)"
		% [tip, patch.mids[hip_station]])
	notes.append("the tail's cells hang %.1f px below the back" % (back - tip))


## That none of it needs re-tuning for scale.
##
## Both sides of the division in `Droop.update` go as the cube of the body, so a
## creature drawn twice the size has to sag twice as far in pixels and exactly as
## far as a share of itself. If that were not true the constant would be a per-size
## fudge and every new species would need one.
func _check_sag_is_the_same_at_any_size(player: Creature) -> void:
	_stand(player, "Lizard")
	var small_len: float = player.body_length()
	var small: float = player.droop.tip_sag / maxf(small_len, 0.001)
	var was: float = player.size_scale
	player.size_scale = was * 2.0
	player.rebuild()
	player.reset(Vector2.ZERO, 0.0)
	for _i in 90:
		player._physics_process(TICK)
	var big: float = player.droop.tip_sag / maxf(player.body_length(), 0.001)
	player.size_scale = was
	player.rebuild()
	player.reset(Vector2.ZERO, 0.0)
	_check(absf(big - small) < maxf(small, 0.02) * 0.35,
		"a Lizard drawn twice the size sagged %.1f%% of itself against %.1f%%"
		% [big * 100.0, small * 100.0])
	notes.append("sag holds at %.1f%% of body length across a doubling"
		% (small * 100.0))


# --------------------------------------------------------- what stands ----

## That standing is a claim about support and is checked rather than granted.
##
## Three bodies and three different answers, all out of the same expression: a
## sound quadruped stands, a two-legged animal stands on the two it has, and a
## quadruped with both hind legs bitten off goes down while fully conscious. That
## last one is the whole point — nothing about its brain has changed.
func _check_standing_is_support(player: Creature) -> void:
	_stand(player, "Cat")
	_check(player.balance.hold >= 1.0,
		"a sound Cat was only %.2f held up" % player.balance.hold)
	_check(player.alive, "a sound Cat fell over standing still")

	_stand(player, "T. rex")
	_check(player.balance.hold >= 1.0,
		"a two-legged animal was only %.2f held up by the two legs it has"
		% player.balance.hold)
	_check(player.alive, "a T. rex fell over for having no forelimbs on the ground")

	_stand(player, "Cat")
	var conscious_before: bool = not player.anatomy.state.collapsed
	_sever(player, "RR")
	_sever(player, "RL")
	var ticks: int = 0
	while player.alive and ticks < 600:
		player._physics_process(TICK)
		ticks += 1
	_check(not player.alive,
		"a Cat with both hind legs bitten off stood there indefinitely (hold %.2f)"
		% player.balance.hold)
	_check(conscious_before,
		"the Cat was already unconscious before its legs came off — this proves nothing")
	notes.append("a Cat with no hind legs went down in %.2f s" % (float(ticks) * TICK))
	_revive(player)


## And that being off the ground is not being unable to stand.
##
## The one way this whole mechanism could ruin the game: a jump has no feet down at
## all, so a balance check that ran during one would put every leaping animal on
## the floor at the top of its own arc.
func _check_a_leap_is_not_a_collapse(player: Creature) -> void:
	_stand(player, "Cat")
	player.command.climb = 1.0
	var airborne: bool = false
	var ticks: int = 0
	while ticks < 240 and player.alive:
		if ticks == 40:
			player.command.climb = 0.0
		player._physics_process(TICK)
		if player.elevation.is_airborne():
			airborne = true
			_check(player.balance.unheld <= 0.0,
				"a Cat in mid-air was %.2f s into falling over" % player.balance.unheld)
		ticks += 1
	_check(airborne, "the Cat never left the ground, so nothing was tested")
	_check(player.alive, "a Cat collapsed for having jumped")
	player.command.climb = 0.0
	_stand(player, "Lizard")


# ----------------------------------------------------------------- helpers ----

func _clear() -> void:
	main.carrion.clear()
	main.scrap_field.clear()


## A live creature of this species, standing still on flat ground and settled onto
## its own legs. Everything measured below is measured off one of these.
func _stand(c: Creature, preset: String) -> void:
	_revive(c)
	c.params.apply_preset(preset)
	c.rebuild()
	c.anatomy.reset()
	c.reset(Vector2.ZERO, 0.0)
	for _i in 90:
		c._physics_process(TICK)


## Puts a body back on its feet with its tissue whole. Not a mechanic — a fixture,
## so one check's carcass is not the next check's subject.
func _revive(c: Creature) -> void:
	c.alive = true
	c.ragdoll = null
	c.balance.reset()
	c.anatomy.reset()
	c.reset(Vector2.ZERO, 0.0)


## Cuts the back through just behind the hips, so what comes away is the tail —
## the one structure a standing animal carries at its own back height along the
## whole of its length, which is what makes it the honest thing to drop.
func _sever_tail(c: Creature) -> CarrionField.Part:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	if patch == null:
		return null
	var shed: Array = []
	# One cross-section, taken right through. Behind the last girdle, so the piece
	# that comes away is tail and the animal keeps its legs.
	var cut: int = TissueGrid.HEAD_COLS + int(round(
		clampf(c.params.rear_limb_t, 0.0, 1.0) * float(TissueGrid.TORSO_COLS))) + 1
	for col in range(cut, mini(cut + 2, patch.cols)):
		for row in patch.rows:
			for _i in 16:
				tissue.bite(BiteMark.mouthful(
					patch.centre_of(col * patch.rows + row),
					Vector2.RIGHT, 0.9, 10.0), shed)
	c._physics_process(TICK)
	c._physics_process(TICK)
	return main.carrion.parts[-1] if not main.carrion.parts.is_empty() else null


## Eats a limb off at the socket, through the real erosion path, and returns the
## part it became.
func _sever(c: Creature, key: String) -> CarrionField.Part:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(key)
	if patch == null:
		return null
	var shed: Array = []
	# Two columns rather than one, and well past the bone. A cut that only mostly
	# goes through leaves the limb hanging by a row of skin, and what comes off is
	# then the foot rather than the leg — which tests the same machinery from a
	# much less interesting height.
	for col in 2:
		for row in BodyPlan.LIMB_ROWS:
			for _i in 16:
				tissue.bite(BiteMark.mouthful(
					patch.centre_of(col * BodyPlan.LIMB_ROWS + row),
					Vector2.RIGHT, 0.9, 12.0), shed)
	c._physics_process(TICK)
	c._physics_process(TICK)
	return main.carrion.parts[-1] if not main.carrion.parts.is_empty() else null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("gravity OK — one pull, and everything under it: %s" % " · ".join(notes))
	else:
		print("GRAVITY FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
