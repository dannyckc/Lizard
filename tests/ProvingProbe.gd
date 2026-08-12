## Gate for the proving ground — the lab's marked-off testing area.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/ProvingProbe.gd
##
## A room with things in it can still be wrong, and it is wrong in ways that
## quietly waste an afternoon: a step nobody can climb is a wall that has been
## mislabelled, an idle that drifts is a creature that will not be where it was
## left, and furniture in the corridor the other probes drive down makes every
## one of them measure a mount instead of a gait. So:
##
##   * **the course is walkable** — the flight is climbed to its top tread and
##     descended again, and the solid at the end of the lane stops the body
##     rather than admitting it;
##   * **the resident is alive and stationary** — its weight genuinely moves
##     over its feet, five minutes of it leaves the animal where it was put, and
##     a shove is answered by the loop walking the body back to its post;
##   * **the carcass is dead and inert** — flat, still, and staying that way;
##   * **the zone is out of the way** — nothing in it, animal or obstacle, is
##     within reach of the corridor the other probes walk down;
##   * **anatomy holds** — every stick, bend and bone exact after all of it.
extends SceneTree

const TICK: float = 1.0 / 60.0

## How wide a berth the zone owes the probes' corridor — the +x line out of the
## origin that ArmatureProbe, SkinProbe and MotionProbe all drive down.
const CORRIDOR: float = 100.0

var failures: Array[String] = []
var notes: Array[String] = []
var lab: Node
var zone: Proving
var checked: bool = false

var worst_stick: float = 0.0
var worst_bend: float = 0.0
var worst_bone: float = 0.0


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	zone = lab.get_node_or_null("Proving") as Proving
	_check(zone != null, "the lab has no proving ground")
	if zone == null:
		_finish()
		return false
	_check(zone.resident != null and zone.carcass != null,
		"the bays are empty")

	_check_out_of_the_way()
	_check_the_course()
	_check_the_resident()
	_check_the_carcass()

	notes.append("anatomy through it all: stick %.4f / bend %.4f / bone %.4f"
		% [worst_stick, worst_bend, worst_bone])
	_check(worst_stick < 0.01, "sticks drifted %.4f px" % worst_stick)
	_check(worst_bend < 0.01, "bends exceeded by %.4f rad" % worst_bend)
	_check(worst_bone < 0.01, "bones drifted %.4f px" % worst_bone)
	_finish()
	return false


# ------------------------------------------------------------ out of the way ----

## The zone is somewhere, and everywhere is somewhere else's plain. This is the
## claim that keeps the other probes honest — `habitat-now-has-terrain` cost an
## afternoon of reading a leg solver for what was an elephant walking into a
## boulder.
func _check_out_of_the_way() -> void:
	var nearest: float = INF
	for obstacle in zone.terrain.obstacles:
		nearest = minf(nearest, absf(obstacle.at.y) - obstacle.girth())
	for animal in [zone.resident, zone.carcass]:
		nearest = minf(nearest, absf(animal.centre().y) - animal.body.trunk_length)
	_check(nearest > CORRIDOR,
		"the zone comes within %.0f px of the probes' corridor" % nearest)
	notes.append("the zone keeps %.0f px clear of the corridor east of spawn"
		% nearest)


# ------------------------------------------------------------------ the course ----

## The lab's own creature, walked the length of the north lane: up the flight,
## over the kerb, into the boulder. Every claim here is about the *zone* — that
## what was laid out is the thing that was meant — and not about the mover,
## which MotionProbe already gates.
func _check_the_course() -> void:
	var c: Creature2 = lab.creature
	var lane: float = zone.at.y + Proving.COURSE
	var flight: float = Proving.TREAD * float(Proving.TREADS.size())
	# Every tread is the same rise, and the shorter pair of legs is the one that
	# has to make it: a flight the fore legs cannot climb is a wall in three
	# instalments.
	_check(Outlook.new().in_stride(Proving.TREAD, c.body.fore_leg_length),
		"a tread is taller than a fore leg can climb in stride")

	c.build(Vector2(zone.at.x - 380.0, lane), 0.0)
	var top: float = 0.0
	var floor_again: bool = false
	c.command.throttle = 1.0
	for i in int(9.0 / TICK):
		_tick(c)
		# What the planted feet are standing on — the carries are absolute
		# heights and include the stance, so they answer a different question.
		var under: float = c.travel.footwork.frame_ground()
		if under > top:
			top = under
		elif top >= flight - 1.0 and under < 2.0:
			floor_again = true
	c.command.throttle = 0.0

	_check(top >= flight - 1.0,
		"the flight tops out at %.1f px, not the %.0f it was built with"
			% [top, flight])
	_check(floor_again, "the body never came back down off the steps")
	_check(c.alive and not c.armature.collapsed,
		"walking the course collapsed the body")

	# ...and the far end of the lane is a solid: the walk arrives at the boulder
	# and stops outside it, which is the whole difference between an obstacle and
	# a decoration.
	var boulder: Obstacle = _obstacle("boulder")
	_check(boulder != null, "the course has no boulder")
	if boulder != null:
		var gap: float = c.centre().distance_to(boulder.at) - boulder.girth()
		_check(gap > 0.0, "the body finished %.1f px inside the boulder" % gap)
		notes.append("the course is walked: up %.0f px of steps and down again, %s"
			% [top, "held %.0f px off the boulder at %.0f px/s" % [gap, c.speed]])

	c.build(Vector2.ZERO, 0.0)


# ---------------------------------------------------------------- the resident ----

## A living animal with nothing asked of it. Three things have to be true at
## once and the first two pull against each other: it must not be *still* (a
## frozen body is a diorama), it must not *go* anywhere (a body that wanders is
## not a fixture), and it must be a body rather than a display — which is
## checked by shoving it and watching the locomotion loop, not this file, put it
## back on its feet and back on its spot.
##
## Note what is deliberately *not* asserted: a step count. Steps here are
## triggered by need and nothing else, so how often one happens is an output of
## the loop and pinning it would be pinning the loop through the back door.
func _check_the_resident() -> void:
	var r: Creature2 = zone.resident
	var post: Vector2 = r.centre()
	var travelled: float = 0.0
	var away: float = 0.0
	var weight_step: float = 0.0
	var last: Vector2 = r.poise.centre
	var footless: int = 0

	var seconds: float = 300.0
	var ticks: int = int(seconds / TICK)
	for i in ticks:
		zone._physics_process(TICK)
		_tick(r)
		var off: float = r.centre().distance_to(post)
		travelled = maxf(travelled, off)
		away += off
		weight_step = maxf(weight_step, r.poise.centre.distance_to(last))
		last = r.poise.centre
		if r.poise.feet < 2:
			footless += 1
	var mean: float = away / float(ticks)

	_check(r.alive and not r.armature.collapsed,
		"the resident fell over standing still")
	# Bounded, and bounded well inside its own bay: the animal shifts about, it
	# does not go for a walk, and it has no term in it that prefers a direction.
	_check(travelled < 40.0,
		"the resident wandered %.1f px from its post in %.0f s"
			% [travelled, seconds])
	_check(mean < 15.0,
		"the resident averaged %.1f px off its post — it has moved in" % mean)
	# The weight moving is what "shifts its balance" means: the posed centre of
	# mass is a measurement of the whole body against its feet, and it cannot
	# move without the body having moved. Measured tick to tick, so a body that
	# only crept would not pass by having crept a long way.
	_check(weight_step > 0.01,
		"the resident's weight never moved between ticks — it is a statue")
	_check(footless == 0,
		"the resident was down to one foot on %d ticks" % footless)
	notes.append(("the resident stands: %.1f px off its post at the worst, "
		+ "%.1f px on average over %.0f s, weight live to %.3f px a tick")
		% [travelled, mean, seconds, weight_step])

	# ...and it is a body: shoved, the loop catches it and brings it home.
	r.shove(Vector2(140.0, 0.0))
	var caught: float = 0.0
	var home: float = INF
	for i in int(60.0 / TICK):
		zone._physics_process(TICK)
		_tick(r)
		var off: float = r.centre().distance_to(post)
		caught = maxf(caught, off)
		if i > int(10.0 / TICK):
			home = minf(home, off)
	_check(r.alive and not r.armature.collapsed,
		"a 140 px/s shove put the resident on the floor")
	_check(caught > 8.0, "a 140 px/s shove moved the resident %.1f px" % caught)
	# Home again — the closest it gets once the shove itself is spent. Not the
	# final tick: the animal is a live body and goes on shifting about, so what
	# is being asked is whether the post was recovered, not whether the last
	# frame happened to catch it standing on the spot. Relative to how far it was
	# thrown, because that is the claim — most of the way back — and an absolute
	# pixel count here would be pinning the idle's own wander by the back door.
	_check(home < caught * 0.4,
		"shoved %.1f px, the resident only got back to %.1f px of its post"
			% [caught, home])
	notes.append(("shoved 140 px/s it is carried %.1f px away and walks itself "
		+ "back to %.1f px of its post") % [caught, home])


# ----------------------------------------------------------------- the carcass ----

## Dead, and dead on arrival: the scene opens on a body that has already
## finished falling, and it does not get up or crawl off.
func _check_the_carcass() -> void:
	var d: Creature2 = zone.carcass
	_check(d.armature.collapsed and not d.alive, "the carcass is not dead")

	var high: float = 0.0
	for i in d.armature.pos.size():
		high = maxf(high, d.armature.pos[i].z)
	_check(high < 6.0, "the carcass is still %.1f px off the ground" % high)

	var where: Vector2 = d.centre()
	for i in int(10.0 / TICK):
		_tick(d)
	var crept: float = d.centre().distance_to(where)
	_check(crept < 0.5, "the carcass crept %.2f px lying dead" % crept)
	for limb in d.armature.limbs:
		_check(not limb.foot_driven,
			"something is still placing the carcass's %s" % limb.name)
	notes.append("the carcass lies at %.1f px and creeps %.2f px in 10 s"
		% [high, crept])


# ---------------------------------------------------------------------- harness ----

func _tick(c: Creature2) -> void:
	c._physics_process(TICK)
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())


func _obstacle(kind: String) -> Obstacle:
	for obstacle in zone.terrain.obstacles:
		if obstacle.kind == kind:
			return obstacle
	return null


func _check(ok: bool, complaint: String) -> void:
	if not ok:
		failures.append(complaint)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("proving OK — one marked zone, walkable and inhabited: "
			+ " · ".join(notes))
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(1)
