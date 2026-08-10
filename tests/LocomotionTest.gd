## Headless check for how a body walks on its legs — see Limb, Gait and Posture.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/LocomotionTest.gd
##
## Everything here follows from one change of mind about what a limb is. It used
## to be a flat chain drawn between a socket and a foot on the same plane, with
## the height painted on afterwards; it is now a chain spanning a real gap
## between a body held up in the air and a foot on the floor. That makes three
## claims that were previously unaskable, and they are the file:
##
##   * the bones are rigid *in the world*, not in the picture;
##   * the foot is where it was put, and the body is at the height its feet can
##     hold it — neither slides and neither floats;
##   * an upright animal walks underneath itself rather than beside itself.
##
## Then the two things the vertical axis buys once the limb has one: a step is a
## real height off the floor rather than a screen offset, and a body part
## collides with what is at its own height and passes what is not. The last check
## is the whole of that stated as one journey — a low animal walking the length of
## a tall one, under the belly, into the planted foot, under the raised one.
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
	# Out of the way. Everything until the last check is one animal walking on its
	# own legs, and the habitat's second body sits a few hundred pixels down the
	# road it walks — close enough to be trodden on inside five seconds, which
	# would make every stance measurement below a measurement of a collision.
	target.reset(Vector2(0.0, 6000.0), 0.0)
	# ...and so is the ground. Every claim in this file up to the last two is about
	# a body walking on a flat plane — how far its feet travel, how high its own
	# legs hold it, how much of its reach it spends sideways — and the habitat now
	# scatters things to walk over, which would turn each of those measurements
	# into a measurement of a climb. The layer is checked where it belongs, in
	# TraversalTest, on ground this test deliberately does not have.
	main.terrain.clear()

	_check_bones_are_rigid_in_the_world(player)
	_check_the_body_stands_on_its_feet(player)
	_check_feet_stay_where_they_are_put(player)
	_check_every_leg_walks(player)
	_check_the_body_rides_its_feet(player)
	_check_anatomy_sets_the_pace(player)
	_check_upright_walks_underneath_itself(player)
	_check_a_step_is_a_height(player)
	_check_the_knee_folds_in_its_own_plane(player)
	_check_walking_under_a_tall_animal(player, target)
	_finish()
	return false


# -------------------------------------------------------------------- bones ----

## A bone is a bone in the world. The drawn chain is a projection of it and its
## screen lengths change with every pose, which is exactly why this is measured
## across the ground positions and the heights together rather than on the
## picture — measuring the picture would be measuring the perspective.
func _check_bones_are_rigid_in_the_world(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		drive.turn = 0.6
		var worst: float = 0.0
		var drawn: float = 0.0
		for _tick in 240:
			player.command = drive
			player._physics_process(TICK)
			for limb in player.gait.limbs:
				worst = maxf(worst, limb.bone_error())
				# ...and the drawn chain must genuinely differ, or the projection
				# is not doing anything and none of the rest of this means what it
				# says.
				for i in 2:
					drawn = maxf(drawn, absf(
						limb.joints[i].distance_to(limb.joints[i + 1]) - limb.lengths[i])
						/ limb.lengths[i])
		player.command = MovementInput.Command.new()
		_check(worst < 0.005,
			"a walking %s stretched a bone by %.1f%%" % [preset, worst * 100.0])
		if player.posture.kind != Posture.SPRAWLED:
			_check(drawn > 0.05,
				"%s's drawn legs measured their true bone length — the limb is not being foreshortened"
					% preset)


# ------------------------------------------------------------------ standing ----

## The body is at the height its legs can hold it at, and nowhere else. A leg is
## a fixed length, so a socket further from its foot than the leg is long is a
## body floating, and the check is simply that no supporting leg is ever asked
## for more than it has.
func _check_the_body_stands_on_its_feet(player: Creature) -> void:
	var lines: Array[String] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var worst: float = 0.0
		var limit: float = INF
		var low: float = INF
		var high: float = -INF
		for tick in 300:
			player.command = drive
			player._physics_process(TICK)
			if tick < 60:
				continue
			low = minf(low, player.gait.support)
			high = maxf(high, player.gait.support)
			for limb in player.gait.limbs:
				if limb.stepping:
					continue
				# Socket to *foot*, not socket to ground. The two are the same on a
				# flat-footed animal and they part company the moment one rolls onto
				# its toe at the end of a stance phase — the ankle comes off the floor
				# and the leg above it is no longer spanning the whole gap. Measured
				# to the ground it would read as a leg stretched past its own bones by
				# exactly the push-off, which is a limb doing its job.
				var lift: float = limb.socket_height - limb.foot_height
				var span: float = sqrt(
					limb.plan[0].distance_squared_to(limb.planted) + lift * lift)
				worst = maxf(worst, span / (limb.lengths[0] + limb.lengths[1]))
				limit = minf(limit, limb.lock)
		player.command = MovementInput.Command.new()
		_check(worst <= limit + 0.01,
			"a standing %s was held %.3f of a leg off its own foot (limit %.2f)"
				% [preset, worst, limit])
		_check(player.stature.clearance > 0.0, "%s stood at no height at all" % preset)
		lines.append("%s rides %.0f-%.0f px" % [preset, low, high])

	# ...and the height is a measurement rather than a setting. Take away some of
	# what the legs can extend to, touching nothing about the stance, and the body
	# comes down onto what is left — because there is nothing else deciding how
	# high it rides.
	# Take away some of what the joints can straighten to — a stance thirty degrees
	# more flexed, and nothing else touched — and the body comes down onto what is
	# left, because there is nothing else deciding how high it rides.
	_apply(player, "Elephant")
	var stood: float = player.gait.support
	player.params.fore_flex_deg += 30.0
	player.params.hind_flex_deg += 30.0
	player.rebuild()
	for _tick in 60:
		player._physics_process(TICK)
	_check(player.gait.support < stood - 4.0,
		"legs that could no longer extend as far left the Elephant standing at the same height (%.1f -> %.1f)"
			% [stood, player.gait.support])
	_apply(player, "Elephant")
	summary = " · ".join(lines)


## A planted foot is nailed to the world. It may be *overtaken* — a body that has
## outrun its own leg skids the foot along the edge of what the limb can reach,
## which is the drag a dead leg is made of and has to stay — so what is measured
## here is the foot that is not yet overdue. That one may not move at all.
func _check_feet_stay_where_they_are_put(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var slide: float = 0.0
		var last: Dictionary = {}
		for tick in 300:
			player.command = drive
			player._physics_process(TICK)
			for limb in player.gait.limbs:
				if limb.stepping:
					last.erase(limb.key)
					continue
				if tick > 60 and last.has(limb.key) and limb.error < limb.stride:
					slide = maxf(slide, last[limb.key].distance_to(limb.planted))
				last[limb.key] = limb.planted
		player.command = MovementInput.Command.new()
		_check(slide < 0.1,
			"a walking %s slid a planted foot %.2f px in one tick" % [preset, slide])


# ---------------------------------------------------------------------- gait ----

## All four legs walk, on every posture, and they take turns.
##
## The check that was missing, and its absence hid the worst thing the gait ever
## did. A columnar animal lifts one foot at a time; its two front legs were each
## spending half their cycle in the air, which is the whole of a single-support
## gait between the two of them, and the hind pair simply never found a gap. They
## were not stepping badly — they never stepped at all, for as long as the
## creature walked, and were towed along the ground behind a body that looked from
## the front as though it were walking perfectly well.
##
## Nothing above would have caught it. The bones stayed rigid, the body stood on
## its feet, the feet that were down stayed down. So this asks the one question
## none of them do: did this leg ever pick itself up?
func _check_every_leg_walks(player: Creature) -> void:
	var lines: Array[String] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var steps: Dictionary = {}
		var down: Dictionary = {}
		var was: Dictionary = {}
		var ticks: int = 0
		for limb in player.gait.limbs:
			steps[limb.key] = 0
			down[limb.key] = 0
			was[limb.key] = false
		for tick in 600:
			player.command = drive
			player._physics_process(TICK)
			if tick < 120:
				continue
			ticks += 1
			for limb in player.gait.limbs:
				if limb.stepping and not was[limb.key]:
					steps[limb.key] += 1
				was[limb.key] = limb.stepping
				if not limb.stepping:
					down[limb.key] += 1
		player.command = MovementInput.Command.new()

		var fewest: int = 1 << 30
		var most: int = 0
		var least_contact: float = 1.0
		for limb in player.gait.limbs:
			fewest = mini(fewest, steps[limb.key])
			most = maxi(most, steps[limb.key])
			least_contact = minf(least_contact,
				float(down[limb.key]) / maxf(float(ticks), 1.0))
		_check(fewest > 0,
			"a walking %s had a leg that never took a single step in eight seconds"
				% preset)
		# ...and they share the work. One leg stepping twice as often as another is
		# a pair being favoured and a pair being dragged, which is the same fault
		# one stage before it becomes total.
		_check(most <= fewest * 2,
			"a %s worked one leg %d times and another %d — the gait is favouring a pair"
				% [preset, most, fewest])
		# Ground contact is the duty factor, and the duty factor is the posture:
		# a build that keeps three feet down has each of them down three quarters
		# of the time. Quoted a little under, because a limb is allowed its swing.
		var wanted: float = float(player.posture.feet_down) / 4.0
		_check(least_contact > wanted - 0.12,
			"a %s that is supposed to keep %d feet down had one down only %.0f%% of the time"
				% [preset, player.posture.feet_down, least_contact * 100.0])
		lines.append("%s %d-%d steps, %.0f%% down" % [preset, fewest, most, least_contact * 100.0])
	summary += " · " + " · ".join(lines)


## The body rides up and down over its own feet, and the heavier it is the more
## of that shows.
##
## A leg is a fixed length with its foot nailed down, so a body passing over it
## rises as the foot comes underneath and falls as it leaves. That is not an
## effect laid over a walk — it is the only thing a walk is, seen from the side —
## so a creature whose back never moves is a creature sliding along on legs that
## happen to be waving. And how much of it survives into the picture is a
## question about muscle against weight: a light strong animal folds it away in
## its own joints and glides, and one carrying twenty times its own muscle's
## worth cannot, and rolls over each leg in turn.
func _check_the_body_rides_its_feet(player: Creature) -> void:
	var bob: Array[float] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var low: float = INF
		var high: float = -INF
		for tick in 400:
			player.command = drive
			player._physics_process(TICK)
			if tick < 120:
				continue
			low = minf(low, player.gait.shoulder_height)
			high = maxf(high, player.gait.shoulder_height)
		player.command = MovementInput.Command.new()
		bob.append(high - low)
		_check(high - low > 0.5,
			"a walking %s carried its shoulders at a dead constant height — it is not standing on its feet, it is gliding"
				% preset)
	_check(bob[2] > bob[1],
		"an Elephant transferred less weight than a Cat (%.1f px against %.1f) — the heavy build should be the one that cannot absorb it"
			% [bob[2], bob[1]])


## Acceleration is force over mass, and both of those are read off the animal.
##
## No preset says an Elephant is slow off the mark. It is twenty-three times the
## Lizard's weight and its muscle grew with the square of what its bulk grew with
## the cube of, so it has under half the Lizard's push per unit of weight — and
## that one division is the whole of why it labours into its speed while the Cat
## is gone. The check is the ordering rather than the numbers, because the
## numbers are consequences of a silhouette that the creation menu may restyle at
## any time.
func _check_anatomy_sets_the_pace(player: Creature) -> void:
	var power: Array[float] = []
	var ramp: Array[float] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var reached: float = -1.0
		for tick in 600:
			player.command = drive
			player._physics_process(TICK)
			if reached < 0.0 and player.speed_norm > 0.9:
				reached = float(tick) * TICK
		player.command = MovementInput.Command.new()
		power.append(player.locomotion.power)
		ramp.append(reached)
		_check(reached > 0.0, "a %s never reached its own top speed" % preset)
	_check(power[2] < power[0] and power[0] < power[1],
		"push per unit of weight did not fall with size (%.2f, %.2f, %.2f)"
			% [power[0], power[1], power[2]])
	_check(ramp[2] > ramp[0] and ramp[0] > ramp[1],
		"the heavy build did not take the longest to get going (%.2fs, %.2fs, %.2fs)"
			% [ramp[0], ramp[1], ramp[2]])


# -------------------------------------------------------------------- stance ----

## Where the feet fall, seen from above. This is the redesign: an upright limb
## does not merely reach less far than a sprawled one, it travels in a different
## plane. A sprawled animal rows in the frontal plane and its feet are flung out
## beside it; an upright one pendulums fore and aft directly beneath its own
## shoulder. So the track narrows sharply with the stance while the fore-and-aft
## excursion does not, and a columnar animal's feet come inside its own flanks.
func _check_upright_walks_underneath_itself(player: Creature) -> void:
	# Both shares are quoted against the animal's own plan-view reach, which is
	# what makes the three builds comparable at all: they are being asked how they
	# *spend* the reach they have, not how much of it there is.
	var sideways: Array[float] = []
	var forwards: Array[float] = []
	var inside: Array[bool] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var lat: float = 0.0
		var fore: float = 0.0
		var out: float = 0.0
		var flank: float = 0.0
		for tick in 300:
			player.command = drive
			player._physics_process(TICK)
			if tick < 60:
				continue
			for limb in player.gait.limbs:
				var here: Vector2 = limb.local(
					player.body.anchors[limb.key], limb.plan[2] - limb.plan[0])
				lat = maxf(lat, here.x / limb.plan_limit)
				fore = maxf(fore, absf(here.y) / limb.plan_limit)
				# ...and against the silhouette, which is the thing a player sees
				# the feet fall inside or outside of.
				var station: int = _station(player, limb)
				out = maxf(out, absf(
					(limb.plan[2] - player.spine.points[station]).dot(player.spine.perps[station])))
				flank = maxf(flank, player.body.widths[station])
		player.command = MovementInput.Command.new()
		sideways.append(lat)
		forwards.append(fore)
		inside.append(out < flank)

	_check(sideways[0] > sideways[1] and sideways[1] > sideways[2],
		"the feet did not come in under the body as the stance came upright (%.2f, %.2f, %.2f of the reach out to the side)"
			% [sideways[0], sideways[1], sideways[2]])
	_check(not inside[0],
		"a sprawled animal's feet came inside its own flanks — that stance is legs out to the side")
	_check(inside[2],
		"a columnar animal's feet still fell outside its own flanks")
	# The reach an upright build stops spending sideways has to be spent walking,
	# or this is an animal that pulled its legs in and stopped moving them. It is
	# the same total either way; the difference is what it is for.
	_check(forwards[2] > sideways[2] * 1.5,
		"a columnar animal's feet travelled no further fore-and-aft (%.2f) than they stood out to the side (%.2f)"
			% [forwards[2], sideways[2]])
	_check(forwards[2] > forwards[0] * 0.8,
		"an upright stance gave up its fore-and-aft travel along with its width (%.2f against a sprawled %.2f)"
			% [forwards[2], forwards[0]])
	# So the shift is in the balance rather than in the total. All three builds
	# work their limbs through most of the reach they have; what changes is
	# whether that reach is being spent standing wide or walking.
	var balance: Array[float] = []
	for i in 3:
		balance.append(forwards[i] / maxf(sideways[i], 0.001))
	_check(balance[0] < balance[1] and balance[1] < balance[2],
		"the stance did not swing round from frontal to parasagittal (%.1f, %.1f, %.1f fore-aft per unit of width)"
			% [balance[0], balance[1], balance[2]])


# --------------------------------------------------------------------- step ----

## A step is a height off the floor, in the same pixels as everything else, and
## it is a fraction of the animal taking it. Both halves matter: a real height is
## what something else can be shorter than, and a proportional one is what stops
## an elephant picking its feet up by a lizard's ankle.
func _check_a_step_is_a_height(player: Creature) -> void:
	var lifts: Array[float] = []
	for preset in ["Lizard", "Elephant"]:
		_apply(player, preset)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var top: float = 0.0
		var band_low: float = INF
		for _tick in 300:
			player.command = drive
			player._physics_process(TICK)
			for limb in player.gait.limbs:
				if limb.foot_height <= top:
					continue
				top = limb.foot_height
				band_low = limb.segment_band(2, player.size_scale).x
		player.command = MovementInput.Command.new()
		lifts.append(top)
		_check(top > 0.0, "a walking %s never picked a foot up" % preset)
		# The foot's own band has to come up with it, or the height is decorative.
		_check(band_low > 0.0,
			"a %s's raised foot still occupied the ground it had left" % preset)
	_check(lifts[1] > lifts[0],
		"an Elephant did not pick its feet up further than a Lizard (%.1f vs %.1f px)"
			% [lifts[1], lifts[0]])


## The joint folds in the plane containing the limb and the body's fore-aft axis:
## across the floor on a sprawled animal, through the air beneath the body on an
## upright one. That is what makes a knee unable to buckle sideways into the
## torso, so the check is the consequence — an upright animal's knee is between
## its socket and its foot in plan view, and well above the ground.
func _check_the_knee_folds_in_its_own_plane(player: Creature) -> void:
	_apply(player, "Elephant")
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var lowest: float = INF
	var worst_bulge: float = 0.0
	for tick in 240:
		player.command = drive
		player._physics_process(TICK)
		if tick < 60:
			continue
		for limb in player.gait.limbs:
			lowest = minf(lowest, limb.heights[1] / maxf(limb.socket_height, 1.0))
			# How far the knee swings out to the *side of the animal*, which is the
			# claim: a joint folding fore-and-aft cannot buckle into the torso.
			# Against the body's own lateral axis rather than across the
			# socket-to-foot line, because that line is exactly what a columnar limb
			# has none of at mid-swing — its foot passes directly beneath its own
			# socket — and a perpendicular to a line a few pixels long points
			# wherever the last of those pixels happened to.
			var out: Vector2 = player.body.anchors[limb.key].perp
			worst_bulge = maxf(worst_bulge,
				absf((limb.plan[1] - limb.plan[0]).dot(out)) / limb.anatomical_length)
	player.command = MovementInput.Command.new()
	_check(lowest > 0.2,
		"a columnar knee dropped to %.2f of the shoulder height — it is folding across the floor"
			% lowest)
	_check(worst_bulge < 0.35,
		"a columnar knee swung %.2f of a leg out sideways instead of folding fore-and-aft"
			% worst_bulge)


# ---------------------------------------------------------------- collision ----

## The journey the whole vertical layer exists for: a ground-level animal walking
## the length of a tall one.
##
## Three answers along one path, and none of them is a rule about elephants. The
## belly is above the lizard's head, so there is no contact to resolve and it
## walks underneath. The planted foot occupies the ground the lizard is standing
## on, so it is in the way. The same foot picked up high enough occupies a band
## above it, and is not.
func _check_walking_under_a_tall_animal(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	target.reset(Vector2.ZERO, 0.0)
	player.reset(Vector2(-260.0, 0.0), 0.0)
	for _tick in 30:
		target._physics_process(TICK)
		player._physics_process(TICK)

	_check(not Stature.overlaps(player.stature.trunk, target.stature.trunk),
		"a Lizard's body (%s) and an Elephant's (%s) were at the same height"
			% [player.stature.trunk, target.stature.trunk])
	_check(Stature.overlaps(player.stature.trunk, target.stature.limbs),
		"a Lizard could not reach the height an Elephant's legs pass through")

	# Under the belly: aimed down the gap the player can see between the two rows
	# of legs, which is not the animal's midline. Legs are drawn hanging below the
	# body they hang off — that is the whole of the projection — so the corridor
	# under a tall animal is between its drawn legs rather than under the middle of
	# its back. It must arrive on the far side having been pushed nowhere.
	var gap: float = 0.0
	for limb in target.gait.limbs:
		gap += limb.plan[2].y
	gap /= float(target.gait.limbs.size())
	var through: Dictionary = _lane(player, target, null, false, gap)
	_check(player.head_pos.x > 200.0,
		"the Lizard did not get out from under the Elephant (reached x=%.0f)" % player.head_pos.x)
	# Into a planted foot: the same walk, aimed at a leg instead of the gap. What
	# is measured is how far *into* the foot the lizard's body got, because the
	# leg routes around a body as readily as a body is pushed out of a leg — a
	# contact both parties answer can look like nothing happening if all you watch
	# is where the walker ended up.
	var leg: Limb = _planted_leg(target)
	var blocked: Dictionary = _lane(player, target, leg)
	_check(blocked["met"], "the Lizard never came near the foot it was aimed at")
	# Turned aside by something real: several pixels off its line, which open
	# ground never does. It is no longer quoted against the belly-corridor walk —
	# the legs either side of that corridor are sized to what they carry now (see
	# Limb.girth_of), so a body threading it brushes them and the corridor is a
	# mild obstacle in its own right. The clean height contrast is the
	# planted-against-raised pair below, where nothing changes but the height.
	_check(blocked["aside"] > 5.0,
		"a planted foot barely turned the Lizard aside (%.1f px)" % blocked["aside"])

	# ...and the identical walk with that foot held clear of the lizard's back is
	# a walk under a doorway. Nothing about the test changes but the height, and
	# the body goes straight through the space the foot is no longer in.
	var lifted: Dictionary = _lane(player, target, leg, true)
	_check(lifted["deepest"] > blocked["deepest"] + 6.0,
		"a raised foot was still in the way: the Lizard passed %.1f px through it, against %.1f under the planted one"
			% [lifted["deepest"], blocked["deepest"]])
	# How far into the foot's ground footprint the body ever got, against how far
	# it gets when the foot is not there — a fraction rather than a pixel count,
	# and deliberately so. `deepest` is a plan-view measurement, and a walking
	# Lizard's belly rides within a pixel of the top of an Elephant's toes: a build
	# a hair taller clears the foot's own band and is turned aside by the shank
	# above it instead, which moves the number several pixels without anything about
	# the mechanic having changed. What may not change is the contrast, because that
	# is the claim — a foot on the floor is in the way and the same foot in the air
	# is not.
	_check(blocked["deepest"] < lifted["deepest"] * 0.5,
		"an Elephant's planted foot barely slowed the Lizard: %.1f px in against %.1f px through the raised one"
			% [blocked["deepest"], lifted["deepest"]])
	summary += " · under an Elephant: %.0f px aside past the belly, %.0f px into a planted foot, %.0f px under a raised one" \
		% [through["aside"], blocked["deepest"], lifted["deepest"]]


## Walks the player from well behind the target to well past it, and reports how
## far it was pushed off its line and how deeply its body ever got inside `leg`'s
## foot. `hold_up` pins every one of the target's feet at a height clear of the
## walker, so the same journey can be made with and without a doorway.
func _lane(player: Creature, target: Creature, leg: Limb, hold_up: bool = false,
		lane: float = 0.0) -> Dictionary:
	# The spot the foot stands on, captured while it is standing on it. Fixed for
	# the whole walk on purpose: what the raised run has to show is the walker
	# going *through* the place the planted one stopped it, and a target that
	# moved up with the foot would be measuring something else.
	var aim: Vector2 = Vector2(0.0, lane) if leg == null else leg.planted
	player.reset(Vector2(aim.x - 260.0, aim.y), 0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var clearance: float = player.stature.trunk.y * 2.0
	# Where the target's feet are standing, captured once. Held there for the whole
	# walk in *both* runs, because the one thing being compared is the height and
	# nothing else may differ. A target leant on by a walker takes a step to keep
	# its balance, and a foot that steps aside is a foot the walker was never asked
	# to get past — which measures how readily an elephant shifts its weight rather
	# than whether a raised foot is a doorway.
	var pinned: Dictionary = {}
	for limb in target.gait.limbs:
		pinned[limb.key] = limb.ground
	# Twenty seconds, where seven used to do. What is being compared is how far a
	# walker is turned aside, and being turned aside is something that accumulates
	# while it leans on the obstacle — so the window has to be long enough for a
	# body held to the pace its own legs deliver to do the leaning. See
	# Locomotion.leg_speed.
	var out := {"aside": 0.0, "deepest": 0.0, "met": false}
	for _tick in 1200:
		target.command = MovementInput.Command.new()
		target._physics_process(TICK)
		if leg != null:
			# Held rather than stepped, because what is being isolated is the
			# height: the foot stays exactly where it is on the ground and only
			# leaves it, so nothing else about the walk has changed. Posed through
			# the ordinary solve, so the leg that reaches down to it is the leg the
			# game would draw and its bands are the bands the game would test.
			for limb in target.gait.limbs:
				limb.ground = pinned[limb.key]
				limb.planted = pinned[limb.key]
				limb.foot_height = clearance if hold_up else 0.0
				limb.visual = limb.ground + limb.rise()
				limb.solve_stance(target.body.anchors[limb.key], limb.ground,
					target.params.fabrik_iterations)
			# Posing a limb by hand is only half of moving it. The heights a leg
			# occupies live on its tissue cells, and those are re-derived once a
			# tick from the solve that has already been and gone — so without this
			# the foot is drawn and solved in the air while its flesh is still
			# lying on the floor, which is precisely the disagreement the whole
			# volumetric layer exists to rule out. The tick does the same thing in
			# the same place, immediately after the gait.
			target.anatomy.update(target)
		player.command = drive
		player._physics_process(TICK)
		out["aside"] = maxf(out["aside"], absf(player.head_pos.y - aim.y))
		if leg != null:
			var solid: float = leg.foot_radius(target.size_scale)
			for i in mini(player.body.last_index + 1, player.spine.size()):
				var gap: float = player.spine.points[i].distance_to(leg.plan[2])
				var reach: float = solid + player.body.widths[i]
				if gap < reach * 1.6:
					out["met"] = true
				out["deepest"] = maxf(out["deepest"], reach - gap)
		if player.head_pos.x > aim.x + 260.0:
			break
	player.command = MovementInput.Command.new()
	return out


## One of the target's legs that is standing on the ground, taken from the pair
## the walker will meet first.
func _planted_leg(target: Creature) -> Limb:
	for limb in target.gait.limbs:
		if not limb.stepping and limb.pair == Limb.REAR and limb.side > 0.0:
			return limb
	return target.gait.limbs[0]


# ------------------------------------------------------------------- tools ----

func _station(player: Creature, limb: Limb) -> int:
	var t: float = player.params.front_limb_t if limb.pair == Limb.FRONT \
		else player.params.rear_limb_t
	return clampi(int(round(t * float(player.spine.size() - 1))), 0, player.spine.size() - 1)


func _apply(player: Creature, preset: String) -> void:
	player.set_bite_held(false)
	player.params.apply_preset(preset)
	player.command = MovementInput.Command.new()
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("locomotion OK — legs solved from the foot up: %s" % summary)
		quit(0)
	else:
		for failure in failures:
			print("LOCOMOTION FAIL — ", failure)
		quit(1)
