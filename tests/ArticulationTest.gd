## Headless check for what a limb *is* — see Articulation, Posture and Stature.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/ArticulationTest.gd
##
## Three claims, and they are one claim seen from three places.
##
## **A joint is the trait.** How extended a leg stands, how far it may straighten
## and how tightly it folds used to be three lengths typed into a preset, and no
## value of them could produce a column: the reach cap sat a long way below
## straight, so every animal in the game — sprawled, upright, columnar, twenty-
## three times the weight of the next — stood in the same three-quarters-extended
## crouch. They are now one angle at the elbow or the knee, read through the
## stance the animal is in, and the checks below are that the angle actually
## arrives in the solved pose rather than being a number in a table.
##
## **A girdle is the unit.** The angle belongs to a shoulder or a hip rather than
## to a creature, so the two ends of an animal may be different limbs doing
## different jobs — a straight strut in front, a folded spring behind — which is
## most of what separates a cat from a scaled lizard. Nothing here names a cat:
## it asks that the two girdles differ and that the difference survives being
## walked on.
##
## **A limb is attached.** A socket is a joint on the flank of a round body, and
## the body hangs below it — so the whole of the top of a leg is inside the flesh
## it belongs to, in the volume and not merely in the picture. The last third of
## this file walks the lattice and asks that of every limb of every build in the
## file, standing, walking and crouching; and then asks the same of the three
## things that run through the join — the skeleton, the nerve and the vessel.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false
var notes: Array[String] = []


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
	# The same two conditions LocomotionTest sets: nothing to walk into and
	# nothing to climb, so every angle measured below is an angle a leg is
	# standing at rather than one it has been pushed to.
	target.reset(Vector2(0.0, 6000.0), 0.0)
	main.terrain.clear()

	_check_the_angle_arrives(player)
	_check_a_column_stays_a_column(player)
	_check_the_two_girdles_differ(player)
	_check_it_is_the_anatomy_and_not_the_species(player)
	_check_a_column_pushes_off_its_toe(player)
	_check_bones_divide_as_asked(player)
	_check_limbs_meet_the_body(player)
	_check_the_skeleton_crosses_the_girdle(player)
	_check_the_networks_cross_the_girdle(player)
	_finish()
	return false


# ------------------------------------------------------------------- joints ----

## What the table says and what the pose does are the same thing.
##
## The joint angle is never an input to the solve — the chain is posed from a
## socket to a foot and the angle is whatever falls out of that — so this is the
## claim that the two ends of the system agree. It is checked standing, because a
## standing animal is the one case where nothing else is going on.
func _check_the_angle_arrives(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_apply(player, name)
		for limb in player.gait.limbs:
			if not limb.bearing:
				continue
			var wanted: float = rad_to_deg(
				player.articulation.of(limb.pair).stand_angle)
			var got: float = rad_to_deg(limb.joint_angle())
			_check(absf(got - wanted) < 14.0,
				"a standing %s carries its %s joint at %.0f degrees, and its anatomy says %.0f"
					% [name, limb.key, got, wanted])


## An elephant's legs are columns, standing and moving.
##
## The whole of the original complaint, stated as the thing that would have
## caught it: not "does it look right" but "how bent is the knee", measured every
## tick of a walk. A hundred and fifty degrees is the line between a leg that
## reads as a pillar and one that reads as an animal about to sit down, and the
## old build sat at a hundred and eighteen degrees standing still.
##
## The second half is what makes it locomotion rather than a pose. A columnar
## limb may not buy its stride by folding — that is the one thing it cannot do —
## so the angle has to stay inside a narrow band for the whole cycle rather than
## sweeping through one and happening to pass the test at the ends.
func _check_a_column_stays_a_column(player: Creature) -> void:
	_apply(player, "Elephant")
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var lowest: float = 180.0
	var highest: float = 0.0
	for tick in 420:
		player.command = drive
		player._physics_process(TICK)
		if tick < 120:
			continue
		for limb in player.gait.limbs:
			# Standing legs only. A limb in the air is folding on purpose — that is
			# what picking a foot up *is* — and measuring it would be measuring the
			# step rather than the stance.
			if limb.stepping:
				continue
			var angle: float = rad_to_deg(limb.joint_angle())
			lowest = minf(lowest, angle)
			highest = maxf(highest, angle)
	player.command = MovementInput.Command.new()
	_check(lowest > 150.0,
		"a walking Elephant bent a leg to %.0f degrees — that is a crouch, not a column"
			% lowest)
	_check(highest - lowest < 22.0,
		"an Elephant's stance leg swung through %.0f degrees of knee over a stride — it is walking by folding"
			% (highest - lowest))
	notes.append("elephant column %.0f-%.0f deg" % [lowest, highest])


## The two ends of a cat are different limbs.
##
## Measured over a walk rather than in the rest pose, because the claim is about
## locomotion: a foreleg that is a strut while standing and folds like a hind leg
## the moment it is used has not got the anatomy, it has got a pose.
func _check_the_two_girdles_differ(player: Creature) -> void:
	_apply(player, "Cat")
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var count: float = 0.0
	var hind_count: float = 0.0
	var fore_mean: float = 0.0
	var hind_mean: float = 0.0
	for tick in 420:
		player.command = drive
		player._physics_process(TICK)
		if tick < 120:
			continue
		for limb in player.gait.limbs:
			if limb.stepping:
				continue
			var angle: float = rad_to_deg(limb.joint_angle())
			if limb.pair == Limb.FRONT:
				fore_mean += angle
				count += 1.0
			else:
				hind_mean += angle
				hind_count += 1.0
	player.command = MovementInput.Command.new()
	fore_mean /= maxf(count, 1.0)
	hind_mean /= maxf(hind_count, 1.0)
	_check(fore_mean > 130.0,
		"a walking Cat carried its elbows at %.0f degrees — the foreleg is not standing as a support"
			% fore_mean)
	_check(hind_mean < fore_mean - 20.0,
		"a Cat's knee (%.0f deg) was as straight as its elbow (%.0f) — the two girdles are one limb"
			% [hind_mean, fore_mean])
	# ...and level over the two of them, which is the point of the pairing: a
	# longer hind leg folded further and a shorter foreleg held straight arrive at
	# the same height, and nothing levels the body to make them.
	_check(absf(player.gait.shoulder_height - player.gait.hip_height)
			< player.gait.support * 0.18,
		"a Cat stood %.1f px out of level over legs that are meant to arrive at the same height"
			% absf(player.gait.shoulder_height - player.gait.hip_height))
	notes.append("cat fore %.0f deg / hind %.0f deg" % [fore_mean, hind_mean])


## And none of it is about elephants or cats.
##
## The same two numbers moved on the default sprawled build straighten its legs
## and stiffen its joints, with nothing else touched — no preset, no posture, no
## species. That is the difference between a system and two hard-coded fixes, and
## it is the one check here that would fail if the behaviour had been patched in
## at the point of use.
func _check_it_is_the_anatomy_and_not_the_species(player: Creature) -> void:
	_apply(player, "Lizard")
	var crouched: float = rad_to_deg(_mean_angle(player))
	var folded: float = player.stature.fold
	player.params.fore_flex_deg = -60.0
	player.params.hind_flex_deg = -60.0
	player.rebuild()
	player._physics_process(TICK)
	var straightened: float = rad_to_deg(_mean_angle(player))
	_check(straightened > crouched + 40.0,
		"straightening the joints of an ordinary build did nothing to its legs (%.0f -> %.0f deg)"
			% [crouched, straightened])
	# ...and the fold is a second, separate axis. Take the range away and the same
	# animal can no longer draw its legs up, which is the whole of why a heavy
	# build can neither crouch to the floor nor gather itself to jump.
	_apply(player, "Lizard")
	player.params.fore_fold_range = 0.15
	player.params.hind_fold_range = 0.15
	player.rebuild()
	player._physics_process(TICK)
	_check(player.stature.fold < folded * 0.6,
		"a joint that no longer closes left the same crouch behind it (%.1f -> %.1f px)"
			% [folded, player.stature.fold])
	_apply(player, "Lizard")


## A column has to move itself somehow, and it is the foot that does it.
##
## The propulsion claim, and it is checked as a measurement rather than as an
## intention: a planted foot on a build with a toe genuinely leaves the surface
## it is standing on, late in its stance and not at the start, and the leg above
## it does not fold to do it. On a flat-footed build it does not happen at all,
## which is what makes it anatomy rather than an animation everything gets.
func _check_a_column_pushes_off_its_toe(player: Creature) -> void:
	_apply(player, "Elephant")
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var rise: float = 0.0
	var early: float = 0.0
	for tick in 300:
		player.command = drive
		player._physics_process(TICK)
		if tick < 120:
			continue
		for limb in player.gait.limbs:
			if limb.stepping or not limb.bearing:
				continue
			var lift: float = limb.foot_height - limb.surface
			rise = maxf(rise, lift)
			# A push-off belongs at the end of the stance. A foot that is up while
			# it is still out in front of its own socket is not pushing, it is
			# hovering.
			var a: Spine.Frame = player.body.anchors[limb.key]
			if limb.local(a, limb.planted - a.pos).y > limb.rest_fore:
				early = maxf(early, lift)
	player.command = MovementInput.Command.new()
	_check(rise > 1.0,
		"an Elephant's planted feet never came up off the ground at all (%.2f px) — nothing is pushing it along"
			% rise)
	_check(early < rise * 0.25,
		"a foot was %.1f px up while still ahead of its own shoulder — that is not a push-off"
			% early)

	_apply(player, "Lizard")
	player.params.toe_push = 0.0
	player.rebuild()
	var flat: float = 0.0
	for tick in 300:
		player.command = drive
		player._physics_process(TICK)
		if tick < 120:
			continue
		for limb in player.gait.limbs:
			if not limb.stepping:
				flat = maxf(flat, limb.foot_height - limb.surface)
	player.command = MovementInput.Command.new()
	_check(is_zero_approx(flat),
		"a build with no toe at all still lifted a planted foot %.2f px" % flat)
	_apply(player, "Lizard")
	notes.append("elephant toe %.1f px" % rise)


## The two bones divide as the anatomy asks, and the chain still solves.
##
## A graviportal limb carries its weight high and close in and a cursorial one
## leaves a long light segment at the bottom; both are the same two-bone chain
## with the length split differently, and the thing that could go wrong is the
## solver rather than the proportion. So: the split arrives, and the bones are
## still exactly their own length in the world afterwards.
func _check_bones_divide_as_asked(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_apply(player, name)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var worst: float = 0.0
		for _tick in 180:
			player.command = drive
			player._physics_process(TICK)
			for limb in player.gait.limbs:
				worst = maxf(worst, limb.bone_error())
		player.command = MovementInput.Command.new()
		_check(worst < 0.005,
			"a walking %s stretched a bone by %.1f%% on unequal proportions"
				% [name, worst * 100.0])
		for limb in player.gait.limbs:
			var share: float = limb.lengths[0] / (limb.lengths[0] + limb.lengths[1])
			var wanted: float = player.articulation.of(limb.pair).upper
			_check(absf(share - wanted) < 0.01,
				"%s's %s divided its bones %.2f/%.2f instead of %.2f"
					% [name, limb.key, share, 1.0 - share, wanted])


# --------------------------------------------------------------- attachment ----

## Every limb is joined to the body, in the volume rather than in the picture.
##
## Two conditions and both are about the lattice the creature is actually made
## of, not about where a line is drawn. The socket has to be inside the flesh
## across the body — nearer the spine than the flank at its own station — and
## inside it *through* the body, which is the one that used to fail: a socket was
## placed out on the flank at the height the legs were holding, and the body was
## drawn with its underside at that same height, so the joint sat below the
## ellipse of its own cross-section with nothing but air between it and the
## tissue it belonged to. Nobody saw it from overhead because the torso is drawn
## over the legs. It was there in every band, every bite and every network.
##
## Asked of every build in the file, standing, walking, and folded right down —
## because an attachment that holds in the rest pose and opens when the animal
## crouches is not an attachment.
func _check_limbs_meet_the_body(player: Creature) -> void:
	var worst_gap: float = 0.0
	var worst_where: String = ""
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_apply(player, name)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		for tick in 240:
			player.command = drive
			# Half the run folded as far down as this build's joints will go, so the
			# crouch is under test rather than being avoided by it.
			player.crouch = 0.0 if tick < 120 else 1.0
			player._physics_process(TICK)
			if tick < 30:
				continue
			for limb in player.gait.limbs:
				var gap: float = _socket_gap(player, limb)
				if gap > worst_gap:
					worst_gap = gap
					worst_where = "%s %s" % [name, limb.key]
		player.command = MovementInput.Command.new()
		player.crouch = 0.0
	_check(worst_gap <= 0.0,
		"a limb socket sat %.2f px outside the body it hangs off (%s)"
			% [worst_gap, worst_where])
	notes.append("worst socket gap %.2f px" % worst_gap)


## How far outside its own body a socket is, in world pixels. Zero or less is a
## joint inside the flesh.
##
## Asked of the lattice rather than worked out again from the parameters, and that
## is the point of it: the body a creature is *made* of is the grid of cells, each
## of which knows the band of heights it occupies, so the honest form of "this leg
## is joined on" is that the top of the leg is inside one of them. Anything else
## is a second opinion, and a second opinion that agreed with the first would only
## prove the arithmetic was copied correctly.
func _socket_gap(player: Creature, limb: Limb) -> float:
	var tissue: TissueGrid = player.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(BodyPlan.BODY_KEY)
	if patch == null or not patch.live:
		return 0.0
	# Both gradients of the lean the body is carrying, because a body is tipped in
	# two directions at once: nose-up or nose-down along its own axis, and rolled
	# onto one flank across it. The renderer shears by exactly this pair — see
	# Posture.tip — and the lattice stores a level slab, so reading its bands
	# through the same two numbers is asking about the same leaning body a player
	# is looking at rather than about a second one.
	var pair: Array = player.gait.girdle_line()
	var fwd: Vector2 = pair[1]
	var out := Vector2(-fwd.y, fwd.x)
	# Two pieces of flesh, and the question is whether they share any height at
	# all — not whether a point lands inside a box. The top of a limb is a
	# cross-section of the leg's own girth, exactly as each cell of the body is a
	# box of flesh, and a join is the two of them overlapping. Asked of the socket
	# as a point instead, an animal rolled onto one side would report a gap at the
	# very moment its shoulder is buried deepest in its own chest.
	#
	# Against the girdle it hangs from and the flesh either side of it, because
	# that is the piece of animal a limb is welded to — see
	# BodyPlan.limb_socket_cells, which is the same span the flood fill, the
	# skeleton and both networks cross.
	var half: float = limb.girth(player.size_scale) * 0.5
	var at: float = limb.socket_height + player.stature.elevation
	var col: int = int(player.anatomy.plan.limb_socket_col[limb.key])
	var gap: float = INF
	for c in range(maxi(col - 1, 0), mini(col + 2, patch.cols)):
		for row in BodyPlan.BODY_ROWS:
			var cell: int = c * BodyPlan.BODY_ROWS + row
			# Only flesh the socket is actually beside. A cell across the far flank
			# is body, and it is not what this leg is joined to.
			var centre: Vector2 = patch.centre_of(cell)
			if centre.distance_to(limb.plan[0]) > half + patch.extent_of(cell):
				continue
			var away: Vector2 = centre - (pair[0] as Vector2)
			var lean: float = away.dot(fwd) * player.gait.pitch \
				+ away.dot(out) * player.gait.roll
			var band: Vector2 = patch.band_of(cell) + Vector2(lean, lean)
			gap = minf(gap, maxf(band.x - (at + half), (at - half) - band.y))
	return 0.0 if is_inf(gap) else gap


# ----------------------------------------------------------------- networks ----

## The skeleton is continuous through the join.
##
## A limb's bone core runs its whole length and the girdle is a bar across the
## body under its socket; between them there must be no gap, and the bar must be
## under the socket rather than under wherever the default build happened to put
## one. That second half is what breaks on a build that carries its shoulders a
## quarter of the way down its back: the plan used to name two fixed columns, so
## such an animal's forelimbs were welded to a rib.
func _check_the_skeleton_crosses_the_girdle(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_apply(player, name)
		var plan: BodyPlan = player.anatomy.plan
		var tissue: TissueGrid = player.anatomy.tissue
		for key in BodyPlan.LIMB_KEYS:
			var col: int = int(plan.limb_socket_col[key])
			var wanted: int = plan.torso_column(player.params.front_limb_t
				if key.begins_with("F") else player.params.rear_limb_t)
			_check(absi(col - wanted) <= 1,
				"%s hangs its %s off column %d while the girdle carrying it is at %d"
					% [name, key, wanted, col])
			# Bone the whole way from the vertebral column out to the socket...
			for cell in plan.limb_socket_cells(key):
				_check(tissue.patch(TissueGrid.BODY_KEY).bone[cell] != 0,
					"%s's %s girdle has no bone in it at cell %d" % [name, key, cell])
			# ...and down the limb from the socket.
			_check(tissue.bone_span(key, 0, BodyPlan.LIMB_BONE_COLS) > 0.99,
				"%s's %s has a break in its own bone before anything has bitten it"
					% [name, key])


## And so do the nerve and the vessel.
##
## Both run out of the body over the girdle before they run down the limb, so the
## test is the consequence rather than the geometry: chew the shoulder out and
## the limb goes dark, with nothing on the limb itself touched. Before the runs
## crossed the join they were read from the limb's own cells alone, so a leg with
## its shoulder eaten to the bone reported a perfectly sound nerve.
func _check_the_networks_cross_the_girdle(player: Creature) -> void:
	_apply(player, "Lizard")
	var plan: BodyPlan = player.anatomy.plan
	var state: BodyState = player.anatomy.state
	var region: int = int(plan.limb_region["FL"])
	_check(state.nerves.delivery[region] > 0.9,
		"a sound Lizard's foreleg was not receiving anything to begin with")

	# The drawn run has to be continuous as well as functional: the last cell of
	# the crossing and the first cell of the limb are two ends of one line, and a
	# gap between them is the floating thread the overlay used to draw.
	var tissue: TissueGrid = player.anatomy.tissue
	var run: BodyPlan.Conduit = plan.nerves[region]
	_check(not run.link_cells.is_empty(),
		"a limb's nerve had no run through the body at all")
	if not run.link_cells.is_empty():
		var body: TissueGrid.Patch = tissue.patch(BodyPlan.BODY_KEY)
		var limb: TissueGrid.Patch = tissue.patch("FL")
		var joinery: float = body.centre_of(run.link_cells[run.link_cells.size() - 1]) \
			.distance_to(limb.centre_of(run.cells[0]))
		var reach: float = limb.extent_of(run.cells[0]) * 3.0
		_check(joinery < reach,
			"a limb's nerve jumped %.1f px of open air between the body and the leg"
				% joinery)
		# The body end of it has to arrive at the spinal cord, or the branch is
		# hanging off the flank rather than off the animal.
		var spine_cell: int = int(plan.limb_socket_col["FL"]) * BodyPlan.BODY_ROWS \
			+ BodyPlan.SPINE_ROW
		_check(run.link_cells[0] == spine_cell,
			"a limb's nerve started out on the flank instead of at the vertebral column")

	# ...and the consequence. The shoulder alone, and the limb goes dark.
	for cell in plan.limb_socket_cells("FL"):
		_bite_cell(player, BodyPlan.BODY_KEY, cell, 6.0, 14)
	player._physics_process(TICK)
	_check(state.nerves.delivery[region] < 0.2,
		"a foreleg with its shoulder chewed out still had %.2f of its nerve"
			% state.nerves.delivery[region])
	_check(state.vessels.delivery[region] < 0.2,
		"a foreleg with its shoulder chewed out still had %.2f of its blood"
			% state.vessels.delivery[region])
	_apply(player, "Lizard")


# ------------------------------------------------------------------- tools ----

## One closing of a very small set of jaws on exactly one cell, through the real
## erosion path — the same helper AnatomyTest uses, and for the same reason: a
## test that writes hit points by hand is testing something the game never does.
func _bite_cell(c: Creature, patch_key: String, cell: int, depth: float,
		times: int = 1) -> void:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(patch_key)
	if patch == null or not patch.live:
		return
	var shed: Array = []
	for _i in times:
		tissue.bite(BiteMark.mouthful(patch.centre_of(cell), Vector2.RIGHT, 0.8, depth),
			shed)
	c.anatomy.state.update(tissue, TICK)


func _mean_angle(player: Creature) -> float:
	var total: float = 0.0
	var count: float = 0.0
	for limb in player.gait.limbs:
		if not limb.bearing:
			continue
		total += limb.joint_angle()
		count += 1.0
	return total / maxf(count, 1.0)


func _apply(player: Creature, preset: String) -> void:
	player.set_bite_held(false)
	player.crouch = 0.0
	player.params.apply_preset(preset)
	player.anatomy.reset()
	player.command = MovementInput.Command.new()
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 20:
		player._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("articulation OK — a joint is the trait, a girdle is the unit, ",
			"and every limb is joined to the body: ", " · ".join(notes))
		quit(0)
	else:
		for failure in failures:
			print("ARTICULATION FAIL — ", failure)
		quit(1)
