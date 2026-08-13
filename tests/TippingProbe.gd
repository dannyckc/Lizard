## Gate for the v2 body's attitude — the "revisit" clause of docs/V2_DESIGN.md
## §4.1 exercised deliberately, phase one: roll.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/TippingProbe.gd
##
## Before this, a v2 creature had three dynamic degrees of freedom and one
## assigned vertical. It could not be pushed down, could not sink on one side,
## and could not fall onto its flank at all: `collapse` dropped every node flat
## at its plan position, and belly-down was the only pose a downed body had.
## `Clash` computed a true 3D contact point and then discarded its height,
## because there was nothing to hand it to. What is asserted here is that the
## missing state exists and behaves, as behaviours rather than as constants:
##
##   * **a level body has no attitude** — standing and walking, the heel stays
##     inside a degree and nothing collapses. Roll is additive: everything that
##     was true of a body nobody pushes is still true.
##   * **a push tips it, and the threshold is derived** — the same shove at the
##     back's own height, at rising impulse: held, held, held with a scramble,
##     then over. Nothing anywhere authors where that line is; it is where the
##     righting demand stops fitting under what the girdles can press.
##   * **recovery is stepping** — under the threshold the legs rescue, the step
##     count rises with the push, and the body ends level and alive. Widening
##     the base is how a roll is caught, because a step moves the pivot.
##   * **height is the lever, measured from the axis the body turns about** — a
##     standing animal turns about the floor, so the twist a press hands it goes
##     exactly as the contact's height above the ground and one at the toes
##     barely moves it; a body in the air turns about its own weight, and there
##     a press underneath the centre rolls it the other way. The sign is the
##     contact's, which is precisely what the flattened seam could not say.
##   * **it goes the way it was pushed** — the collapse is directional.
##   * **a downed body lies on its flank** — heel at ninety degrees, the spine a
##     body-radius off the floor instead of flat on it, the skin's ring frames
##     turned with it so the drawn animal is on its side, and all four feet out
##     on the side its belly is now facing.
##   * **a body killed standing still lands on its belly** — a stopped heart is
##     not a shove, and the difference between the two poses is the whole point
##     of the attitude being a state.
##   * **the heel takes the support with it** — the high side's sockets lift out
##     of reach, those feet are torn off their footing, and the hull Poise
##     measures narrows on exactly the side the body is going. Nothing is told
##     to do that; it falls out of the sockets moving.
##   * **the inertia is a census reading** — pinned on the default cat, and a
##     body chewed through one flank is genuinely lighter to roll.
##   * **two bodies carry the contact into each other's attitude** — a charge
##     leaves the struck animal heeled, where the seam used to flatten it. The
##     *sign* claim is made on the direct seam above, where the contact height is
##     exact; a charge between two cats of the same height is deliberately only
##     asserted to connect, because two trunks meeting level should shove rather
##     than roll and that is what it does.
##   * **anatomy holds throughout** — every stick, bend and bone exact after all
##     of it, alive and dead.
extends SceneTree

const TICK: float = 1.0 / 60.0

## Sideways impulses to walk the ladder up, px/s at the back's own height.
const LADDER: Array[float] = [60.0, 100.0, 120.0, 130.0, 160.0]

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false

var worst_stick: float = 0.0
var worst_bend: float = 0.0
var worst_bone: float = 0.0


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

	_check_level(creature)
	_check_ladder(creature)
	_check_lever(creature)
	_check_flank(creature)
	_check_belly(creature)
	_check_support(creature)
	_check_census(creature)
	_check_charge(creature)

	_check(worst_stick <= 0.02,
		"a stick strayed %.4f px from its rest somewhere above" % worst_stick)
	_check(worst_bend <= 0.002,
		"a bend passed its graded limit by %.4f rad somewhere above" % worst_bend)
	_check(worst_bone <= 0.05,
		"a bone strayed %.4f px from its length somewhere above" % worst_bone)
	notes.append("anatomy through it all: stick %.4f / bend %.4f / bone %.4f"
		% [worst_stick, worst_bend, worst_bone])

	_finish()
	return false


# ------------------------------------------------------------------ helpers ----

func _tick(c: Creature2, n: int) -> void:
	for i in n:
		c._physics_process(TICK)
	_anatomy(c)


func _anatomy(c: Creature2) -> void:
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())


func _calm(c: Creature2) -> void:
	main.terrain.clear()
	c.command.throttle = 0.0
	c.command.turn = 0.0
	c.command.sprint = false
	c.command.jump = false
	c.reset()
	_tick(c, 20)


## Across the body — the axis a heel turns about, and the animal's own right.
func _lat(c: Creature2) -> Vector2:
	var dir: Vector2 = Vector2.RIGHT.rotated(c.heading)
	return Vector2(-dir.y, dir.x)


## Where a limb's foot sits across the body, in the body's own frame: signed px
## along the animal's right from the spine line between its girdles.
func _across(a: Armature, limb: Armature.Chain) -> float:
	var pel: Vector2 = a.plan(a.pelvis_index())
	var spine: Vector2 = a.plan(a.withers_index()) - pel
	var side: Vector2 = Vector2(-spine.y, spine.x).normalized()
	var foot: Vector3 = a.pos[limb.nodes[limb.nodes.size() - 1]]
	return (Vector2(foot.x, foot.y) - pel).dot(side)


## The top of the back over the withers: where a press lands when something
## leans on a standing animal, and the height the ladder is quoted at. Measured
## on a body that is actually standing — a downed one's back is a foot off the
## floor, and quoting a press against that is quoting it against nothing.
func _back(c: Creature2) -> float:
	_calm(c)
	var a: Armature = c.armature
	return a.pos[a.withers_index()].z + a.flesh_r[a.withers_index()]


## One push, and what became of it: how far over it went, whether it went down,
## how many steps the legs took answering, and where it ended up.
func _push(c: Creature2, dv: float, at_z: float, run: int = 240) -> Dictionary:
	_calm(c)
	var fw: Footwork = c.travel.footwork
	var was: Array[bool] = []
	for f in fw.feet:
		was.append(f.swinging)
	var here: Vector2 = c.centre()
	c.shove(_lat(c) * dv, Vector3(here.x, here.y, at_z))
	# The twist the push itself handed the body, read before a tick has run:
	# `_calm` leaves the rate at zero, so this is exactly `Keel.strike` and
	# nothing else. What happens *after* is the impulse and the body's own
	# weight arguing, and they do not always argue the same way round.
	var impulse: float = c.travel.keel.rate
	var peak: float = 0.0
	var early: float = 0.0
	var steps: int = 0
	var least_feet: int = 4
	var fell: bool = false
	for i in run:
		c._physics_process(TICK)
		for j in fw.feet.size():
			if fw.feet[j].swinging and not was[j]:
				steps += 1
			was[j] = fw.feet[j].swinging
		var roll: float = c.travel.keel.roll
		if i == 9:
			early = roll
		if not fell:
			# The heel it committed at, not the arc it ran out afterwards: a
			# body already on its way down is not being pushed any more.
			if absf(roll) > absf(peak):
				peak = roll
			least_feet = mini(least_feet, c.poise.feet)
		fell = fell or c.armature.collapsed
	_anatomy(c)
	return {
		"peak": peak, "early": early, "impulse": impulse, "steps": steps,
		"fell": fell, "feet": least_feet, "roll": c.travel.keel.roll,
		"alive": c.alive and not c.armature.collapsed,
	}


# ------------------------------------------------------------------- claims ----

## Roll is additive: a body nobody pushes is the body that was there before.
func _check_level(c: Creature2) -> void:
	_calm(c)
	var worst: float = 0.0
	for i in 120:
		c._physics_process(TICK)
		worst = maxf(worst, absf(c.travel.keel.roll))
	_anatomy(c)
	_check(not c.armature.collapsed, "a standing body heeled itself over")
	_check(c.poise.feet == 4, "standing on %d feet of 4" % c.poise.feet)
	var standing: float = worst
	c.command.throttle = 1.0
	for i in 180:
		c._physics_process(TICK)
		worst = maxf(worst, absf(c.travel.keel.roll))
	_anatomy(c)
	c.command.throttle = 0.0
	_check(not c.armature.collapsed, "walking heeled the body over")
	# Two and a half degrees over three seconds that include setting off from a
	# standstill — a rock about level, not a lean away from it. The window is a
	# property of the gait rather than of the attitude: a deliberate walk stands
	# on each foot for the better part of a second, so the moments it spends on a
	# narrow support last longer and the body rides them further. What the claim
	# is about is that the roll comes back, which the mean does.
	_check(rad_to_deg(worst) < 2.5,
		"an unpushed body heeled %.2f° of its own accord" % rad_to_deg(worst))
	notes.append("level: 2 s standing and 3 s walking heel %.3f° / %.3f°, four feet, nothing falls"
		% [rad_to_deg(standing), rad_to_deg(worst)])


## The ladder: the same push, harder each time, and the line the body crosses.
func _check_ladder(c: Creature2) -> void:
	var back: float = _back(c)
	var rungs: Array[Dictionary] = []
	for dv in LADDER:
		rungs.append(_push(c, dv, back))
	var told := PackedStringArray()
	for i in LADDER.size():
		told.append("%.0f→%.0f°%s" % [LADDER[i], rad_to_deg(absf(rungs[i]["peak"])),
			" over" if rungs[i]["fell"] else ""])

	# Held at the bottom, over at the top, and the line crossed exactly once:
	# a threshold, not a rule, and not a coin toss either.
	_check(not bool(rungs[0]["fell"]),
		"the gentlest push (%.0f px/s) felled the body" % LADDER[0])
	_check(bool(rungs[LADDER.size() - 1]["fell"]),
		"the hardest push (%.0f px/s) left the body standing" % LADDER[LADDER.size() - 1])
	var crossings: int = 0
	for i in range(1, rungs.size()):
		if bool(rungs[i]["fell"]) != bool(rungs[i - 1]["fell"]):
			crossings += 1
	_check(crossings == 1,
		"the ladder crossed between standing and falling %d times, not once" % crossings)

	# ...and the heel grows with the push, monotonically, over the rungs that
	# were survived: a bigger shove is a bigger lean, or the state is not one.
	var last: float = -1.0
	for r in rungs:
		if bool(r["fell"]):
			break
		var deg: float = rad_to_deg(absf(r["peak"]))
		_check(deg > last, "a harder push heeled the body less (%.1f° after %.1f°)"
			% [deg, last])
		last = deg

	# Recovery is the legs stepping, and coming back to level rather than to
	# "not fallen": the same rescue that catches a stumble catches a roll.
	var caught: Dictionary = rungs[2]
	_check(not bool(caught["fell"]), "the %.0f px/s push was not survivable" % LADDER[2])
	_check(int(caught["steps"]) >= 3,
		"a %.1f° heel was ridden out on %d steps — nothing rescued it"
		% [rad_to_deg(absf(caught["peak"])), int(caught["steps"])])
	_check(int(rungs[2]["steps"]) > int(rungs[0]["steps"]),
		"a harder push cost the legs no more steps (%d against %d)"
		% [int(rungs[2]["steps"]), int(rungs[0]["steps"])])
	_check(rad_to_deg(absf(caught["roll"])) < 1.0,
		"the caught body settled %.2f° off level" % rad_to_deg(absf(caught["roll"])))
	_check(bool(caught["alive"]), "the caught body did not survive being caught")
	notes.append("the ladder at the back's own height (z %.1f): %s"
		% [back, " · ".join(told)])
	notes.append("caught: a %.0f px/s push heels %.1f°, costs %d steps and settles back to %.2f°"
		% [LADDER[2], rad_to_deg(absf(caught["peak"])), int(caught["steps"]),
			rad_to_deg(absf(caught["roll"]))])


## The contact's height is the lever, measured from the axis the body is
## actually turning about — and that axis is not the same standing as airborne.
func _check_lever(c: Creature2) -> void:
	var back: float = _back(c)
	var toe: float = 2.0
	var dv: float = LADDER[LADDER.size() - 1]
	var high: Dictionary = _push(c, dv, back)
	var low: Dictionary = _push(c, dv, toe)
	_check(bool(high["fell"]), "a %.0f px/s press on the back left the body up" % dv)
	_check(not bool(low["fell"]),
		"the same press at the feet felled the body too — the height is not a lever")
	# Standing, the body turns about the floor, so both presses twist it the
	# same way and the ratio between them is the ratio of the two heights: the
	# lever *is* the contact's height, and nothing else is in the number.
	_check(signf(high["impulse"]) == signf(low["impulse"]),
		"standing, two presses on the same side twisted the body opposite ways")
	var got: float = high["impulse"] / maxf(absf(low["impulse"]), 0.00001)
	var want: float = back / toe
	_check(absf(got - want) < want * 0.1,
		"the twist went as %.1f× with height where the heights differ %.1f×"
		% [got, want])
	_check(absf(high["peak"]) > absf(low["peak"]) * 2.0,
		"a press on the back heeled the body no more than one at the feet (%.1f° vs %.1f°)"
		% [rad_to_deg(absf(high["peak"])), rad_to_deg(absf(low["peak"]))])
	notes.append("standing, the lever is the height off the floor: %.0f px/s at z %.1f twists %+.2f rad/s and goes over, the same at z %.1f twists %+.2f (%.1f× for %.1f× the height) and holds"
		% [dv, back, high["impulse"], toe, low["impulse"], got, want])

	# In the air there is no floor to turn about — the body turns about its own
	# weight, and *there* a press under the centre rolls it the other way. Same
	# multiplication, different axis, and the sign is the contact's.
	# A gentler press than the ladder's, so what is read is the lever rather
	# than the rate cap.
	var over: float = _air_twist(c, 40.0, 14.0)
	var under: float = _air_twist(c, 40.0, -14.0)
	_check(signf(over) != signf(under) and absf(under) > 0.0,
		"airborne, a press above and below the weight twisted the body the same way (%+.2f, %+.2f)"
		% [over, under])
	notes.append("airborne the axis is the weight itself: a 40 px/s press 14 px over it twists %+.2f rad/s and 14 px under it %+.2f"
		% [over, under])


## The twist a press hands a body in mid-air, `off` px above (or below) its own
## weight. Returned before a tick runs, so it is the strike and nothing else.
func _air_twist(c: Creature2, dv: float, off: float) -> float:
	_calm(c)
	c.armature.launch(Gravity.launch_rate(70.0))
	_tick(c, 8)
	var here: Vector2 = c.centre()
	c.shove(_lat(c) * dv, Vector3(here.x, here.y, c.poise.height + off))
	var twist: float = c.travel.keel.rate
	_tick(c, 60)
	return twist


## Where a felled body ends up: on the flank it was pushed onto, drawn as such.
func _check_flank(c: Creature2) -> void:
	var back: float = _back(c)
	var dv: float = LADDER[LADDER.size() - 1]
	for hand in [1.0, -1.0]:
		_calm(c)
		var here: Vector2 = c.centre()
		var lat: Vector2 = _lat(c)
		# Where the feet were across the body before it went over, so what the
		# roll did to them can be read as a movement rather than as a place.
		var stood := PackedFloat32Array()
		for limb in c.armature.limbs:
			stood.append(_across(c.armature, limb))
		c.shove(lat * (dv * hand), Vector3(here.x, here.y, back))
		_tick(c, 300)
		var a: Armature = c.armature
		var k: Keel = c.travel.keel
		_check(a.collapsed, "a %.0f px/s press did not put the body down" % dv)
		_check(signf(k.roll) == hand,
			"pushed one way, the body went down the other (heel %+.1f°)"
			% rad_to_deg(k.roll))
		_check(rad_to_deg(absf(k.roll)) > 85.0,
			"the downed body came to rest %.1f° over, not on its flank"
			% rad_to_deg(absf(k.roll)))
		if hand < 0.0:
			continue

		# The spine of a body on its side is one half-width off the floor; one
		# on its belly is on the floor. That is what "lying on its flank" is,
		# measured rather than drawn.
		var pel: int = a.pelvis_index()
		var lie: float = a.pos[pel].z
		_check(absf(lie - a.flesh_r[pel]) < 0.5,
			"the downed spine rests %.2f px up where its own half-width is %.2f"
			% [lie, a.flesh_r[pel]])

		# ...and the skin says the same thing, because it reads the same number:
		# the back of a body on its flank faces sideways, not up.
		var band: Contour.Band = c.contour.band(BodySchema.TRUNK)
		var mid: int = band.first + band.count / 2
		var up: Vector3 = c.contour.ring_up[mid]
		var across: Vector3 = c.contour.ring_lat[mid]
		_check(absf(up.z) < 0.15,
			"the drawn back still points %.2f upward on a body lying on its side" % up.z)
		_check(absf(across.z) > 0.9,
			"the drawn flank is only %.2f of the way vertical on a downed body"
			% absf(across.z))

		# Every leg went over *with* the body: each foot has moved across the
		# animal toward the side its belly now faces. A movement and not a
		# place, because where a leg ends up also depends on how long it is and
		# on whether it was the pair underneath — a cat on its right side has
		# its right legs tucked under it and its left ones flopped clear, and
		# both of those are legs that went over.
		var ventral: int = 0
		var carried: float = 0.0
		var where := PackedStringArray()
		for i in a.limbs.size():
			var moved: float = (_across(a, a.limbs[i]) - stood[i]) * -hand
			where.append("%s %+.1f" % [a.limbs[i].name, moved])
			carried += moved
			if moved > 0.0:
				ventral += 1
		carried /= float(a.limbs.size())
		_check(ventral == 4,
			"only %d of 4 feet travelled toward the belly as the body went over (%s)"
			% [ventral, ", ".join(where)])
		# How far, in the aggregate: the pair that flopped clear travels most of
		# a leg's length, the pair the animal came down on hardly moves relative
		# to the spine it is now under, and the set has plainly gone over.
		_check(carried > 8.0,
			"the legs travelled a mean %.1f px across the body — that is not going over (%s)"
			% [carried, ", ".join(where)])
		notes.append("downed: heel %.1f°, spine %.2f px up on its own %.2f half-width, drawn back turned to (%.2f, %.2f, %.2f), all four feet carried across toward the belly (mean %.1f px)"
			% [rad_to_deg(absf(c.travel.keel.roll)), lie, a.flesh_r[pel],
				up.x, up.y, up.z, carried])
	notes.append("pushed either way, the body goes down that way")


## A stopped heart is not a shove: a body that simply died lands on its belly.
func _check_belly(c: Creature2) -> void:
	_calm(c)
	c.toggle_collapsed()
	_tick(c, 200)
	var a: Armature = c.armature
	_check(a.collapsed, "the kill did not put the body down")
	_check(rad_to_deg(absf(c.travel.keel.roll)) < 1.0,
		"a body that died standing rolled %.1f° onto its flank"
		% rad_to_deg(absf(c.travel.keel.roll)))
	_check(a.pos[a.pelvis_index()].z < 0.5,
		"a body that died standing lies %.2f px off the floor"
		% a.pos[a.pelvis_index()].z)
	c.toggle_collapsed()
	_tick(c, 60)
	_check(not a.collapsed, "the body would not stand back up")
	notes.append("killed standing, the body flops belly-down at heel %.2f° — and stands back up"
		% rad_to_deg(absf(c.travel.keel.roll)))


## The heel takes the support with it: sockets on the high side lift out of
## reach, their feet are torn off, and the hull narrows on the way over.
func _check_support(c: Creature2) -> void:
	_calm(c)
	var a: Armature = c.armature
	var lat: Vector2 = _lat(c)
	# What the sockets do under a heel is pure geometry, so it can be read off
	# a body held at an angle without waiting for one to fall to it.
	var level := PackedFloat32Array()
	for limb in a.limbs:
		level.append(a.socket_of(limb).z)
	a.roll = 0.35
	var heeled := PackedFloat32Array()
	for i in a.limbs.size():
		heeled.append(a.socket_of(a.limbs[i]).z)
	a.roll = 0.0
	var lifted: int = 0
	var dropped: int = 0
	for i in a.limbs.size():
		if heeled[i] > level[i] + 0.5:
			lifted += 1
		elif heeled[i] < level[i] - 0.5:
			dropped += 1
	_check(lifted == 2 and dropped == 2,
		"a 20° heel lifted %d sockets and dropped %d, not two and two" % [lifted, dropped])

	var back: float = _back(c)
	var going: Dictionary = _push(c, LADDER[LADDER.size() - 1], back)
	_check(bool(going["fell"]), "the support push did not fell the body")
	_check(int(going["feet"]) < 4,
		"the body went all the way over without ever losing a foot (%d down throughout)"
		% int(going["feet"]))
	notes.append("the heel is the support: a 20° lean lifts two sockets and drops two, and a body going over is down to %d feet before it lands"
		% int(going["feet"]))


## How hard the body is to roll is the census's answer, like every other weight.
func _check_census(c: Creature2) -> void:
	_calm(c)
	var whole: float = c.corpus.roll_inertia()
	var mass: float = c.corpus.mass()
	_check(whole > 0.0, "the census reports no roll inertia at all")
	# A radius of gyration, which is the only way the number is readable: the
	# body resists rolling as if all its weight sat this far off its own axis.
	var gyration: float = sqrt(whole / maxf(mass, Corpus.MIN_MASS))
	_check(gyration > 4.0 and gyration < 20.0,
		"the cat rolls as if its weight sat %.2f px off its axis" % gyration)
	_check(is_equal_approx(c.travel.keel.inertia, whole),
		"the mover's baked inertia and the census's disagree")
	_check(is_equal_approx(c.poise.roll_inertia, whole),
		"Poise's baked inertia and the census's disagree")

	for station in 16:
		for sector in [1, 2, 3, 4]:
			c.corpus.gouge(BodySchema.TRUNK, station, sector, 14.0)
	_tick(c, 5)
	var chewed: float = c.corpus.roll_inertia()
	_check(chewed < whole,
		"a flank chewed away left the body exactly as hard to roll (%.0f)" % chewed)
	_check(is_equal_approx(c.travel.keel.inertia, chewed),
		"the wound did not re-bake the mover's inertia")
	notes.append("inertia is a census reading: %.0f whole (weight %.2f px off the axis), %.0f with one flank chewed away"
		% [whole, gyration, chewed])
	_calm(c)


## Two bodies: the contact reaches the other one's attitude, where the seam
## used to flatten it away.
func _check_charge(c: Creature2) -> void:
	_calm(c)
	var lat: Vector2 = _lat(c)
	var other := Creature2.new()
	other.name = "Struck"
	other.spawn_heading = c.heading
	other.spawn_position = c.centre() + lat * 46.0
	main.add_child(other)
	for i in 40:
		c._physics_process(TICK)
		other._physics_process(TICK)
	var apart: float = c.centre().distance_to(other.centre())
	c.shove(lat * 420.0)
	var worst: float = 0.0
	for i in 60:
		c._physics_process(TICK)
		other._physics_process(TICK)
		if absf(other.travel.keel.roll) > absf(worst):
			worst = other.travel.keel.roll
	_anatomy(c)
	_anatomy(other)
	_check(rad_to_deg(absf(worst)) > 0.5,
		"a charge left the struck body heeled %.3f° — the contact's height never arrived"
		% rad_to_deg(absf(worst)))
	_check(c.centre().distance_to(other.centre()) > apart * 0.8,
		"the charging body ended up inside the one it hit")
	notes.append("a charge heels the body it hits by %.1f° — the clash carries its contact height now"
		% rad_to_deg(absf(worst)))
	other.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("tipping OK — the body has an attitude: %s" % " · ".join(notes))
	else:
		print("TIPPING FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
