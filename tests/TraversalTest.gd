## Headless check for getting past things, and for getting a mouth onto them —
## see Obstacle, Terrain, Traversal, Reach and Reticle.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/TraversalTest.gd
##
## The vertical layer already knew whether two things were in each other's way.
## What it did not know was what a body could *do* about one that was, and the
## whole risk in answering that is the answer being a rule about species. So this
## file is weighted almost entirely toward the one claim that matters: every
## verdict below is read off measurements of the animal asking, and changing a
## measurement changes the verdict on an obstacle that has not moved.
##
## Four things are checked, in the order they depend on each other:
##
##   * an obstacle is a footprint and a band, like everything else in the world;
##   * the verdict — under, over, onto, or stopped — comes out of the body's own
##     legs, and the three presets disagree about the same rock because they are
##     built differently rather than because they are named differently;
##   * a body that mounts something actually rises onto it: the feet find the
##     surface, the legs stay rigid, the height follows, and the bands go up with
##     the body;
##   * a mouth is aimed at a place with a height, reaches it by folding the body
##     if it has to, and is refused when the body cannot fold far enough.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false
var summary: Array[String] = []


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
	# Everything until the last section is one animal against the ground. The
	# habitat's second body is parked out of reach so nothing here is quietly
	# measuring a collision with it instead.
	target.reset(Vector2(0.0, 8000.0), 0.0)

	_check_objects_have_volume()
	_check_verdict_is_anatomy(player)
	_check_a_body_is_an_obstacle(player, target)
	_check_walking_over(player)
	_check_climbing_on(player)
	_check_stopped_by_a_wall(player)
	_check_passing_underneath(player)
	_check_cursor_has_a_height(player, target)
	_check_reaching_down(player)
	_check_refusing_what_it_cannot_reach(player, target)
	_check_flat_world_unchanged(player)
	_finish()
	return false


# ----------------------------------------------------------------- objects ----

## A thing in the world is described in the terms an animal already is: where its
## footprint is, and which heights it fills. If that is not true then none of the
## comparisons below mean anything, because they are all comparisons between an
## obstacle's numbers and a body's.
func _check_objects_have_volume() -> void:
	var rock := Obstacle.new(Vector2(100.0, 0.0), 40.0, Vector2(0.0, 30.0), "rock")
	_check(rock.base() == 0.0 and rock.top() == 30.0 and rock.rise() == 30.0,
		"an obstacle did not report the band it was built with")
	_check(rock.covers(Vector2(120.0, 0.0)) and not rock.covers(Vector2(200.0, 0.0)),
		"an obstacle's footprint did not answer for the ground it stands on")

	# A foothold is a margin rather than a yes: a foot near the middle has room
	# around it, a foot at the rim has none, and a foot past the edge is off.
	_check(rock.foothold(rock.at, 5.0) > rock.foothold(Vector2(130.0, 0.0), 5.0),
		"a foot in the middle of a ledge had no more room than one at its edge")
	_check(rock.foothold(Vector2(145.0, 0.0), 5.0) < 0.0,
		"a foot hanging off the edge of a ledge still had room on it")

	# Both halves of every test, and the second is the one that makes it a world
	# rather than a floor plan: something at a different height is not in the way.
	_check(rock.push_disc(Vector2(110.0, 0.0), 10.0, Vector2(0.0, 20.0)) != Vector2.ZERO,
		"a body standing inside a rock at the rock's own height was not pushed out")
	_check(rock.push_disc(Vector2(110.0, 0.0), 10.0, Vector2(60.0, 80.0)) == Vector2.ZERO,
		"a body sailing over a rock was shouldered aside by it")

	# ...and the same two questions asked along a line, which is the whole of what
	# an obstruction is.
	_check(rock.blocks(Vector2.ZERO, Vector2(200.0, 0.0), Vector2(0.0, 20.0)),
		"a rock between two points did not block the line between them")
	_check(not rock.blocks(Vector2.ZERO, Vector2(200.0, 0.0), Vector2(50.0, 60.0)),
		"a rock blocked a line passing well above it")
	_check(not rock.blocks(Vector2.ZERO, Vector2(40.0, 0.0), Vector2(0.0, 20.0)),
		"a rock beyond the far end of a line was still in the way of it")


# ----------------------------------------------------------------- verdict ----

## The claim the whole feature rests on: the verdict is arithmetic on the body.
##
## Two ways of showing it, and the second is the stronger. First that the three
## builds disagree about one object — which could still be three rules in a
## trench coat. Then that changing *one measurement* of one animal, with its name
## and its posture and the obstacle all untouched, changes its answer. Nothing
## that branched on species could do that.
func _check_verdict_is_anatomy(player: Creature) -> void:
	var readings: Dictionary = {}
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		readings[preset] = Traversal.of(player)
		summary.append("%s %s" % [preset, readings[preset].describe()])

	# A tall animal carries its shoulder higher and can therefore reach a foot up
	# onto more; it also spends more of its leg standing there and has less spare
	# to straddle with. Both are consequences and neither was written down.
	_check(readings["Elephant"].socket > readings["Cat"].socket
			and readings["Cat"].socket > readings["Lizard"].socket,
		"the three builds did not carry their shoulders at three different heights")

	# One kerb, and the three builds do not agree about it. Broad enough to be a
	# surface rather than something to step around, and 11 px high — which is over
	# a sprawled animal's shoulder and well under an upright one's.
	var kerb: float = 11.0
	var verdicts: Dictionary = {}
	for preset in ["Lizard", "Cat", "Elephant"]:
		verdicts[preset] = Traversal.assess(readings[preset], 0.0, kerb, 60.0, 0.0)
	var spread: Array[String] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		spread.append("%s %s" % [preset, Traversal.name_of(verdicts[preset])])
	summary.append("11 px kerb: %s" % ", ".join(spread))
	_check(verdicts["Lizard"] == Traversal.BLOCKED,
		"a sprawled animal climbed a kerb standing higher than its own shoulder (%s)"
			% Traversal.name_of(verdicts["Lizard"]))
	_check(verdicts["Cat"] != Traversal.BLOCKED and verdicts["Elephant"] != Traversal.BLOCKED,
		"the same kerb stopped the two builds that carry their shoulders above it (%s, %s)"
			% [Traversal.name_of(verdicts["Cat"]), Traversal.name_of(verdicts["Elephant"])])

	# ...and one animal, two sets of legs. Longer legs carry the shoulder higher
	# and leave more of themselves spare, so a rock that was a wall becomes a step
	# — with the preset, the posture and the obstacle all exactly as they were.
	_apply(player, "Lizard")
	var wall: float = 26.0
	var before: int = Traversal.assess(Traversal.of(player), 0.0, wall, 90.0, 0.0)
	player.params.arm_length *= 3.0
	player.params.leg_length *= 3.0
	_apply(player, "Lizard")  # re-applies the preset, so the legs go back after
	player.params.arm_length *= 3.0
	player.params.leg_length *= 3.0
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 30:
		player._physics_process(TICK)
	var after: int = Traversal.assess(Traversal.of(player), 0.0, wall, 90.0, 0.0)
	_check(before == Traversal.BLOCKED,
		"a 26 px wall was not a wall to a sprawled lizard in the first place (%s)"
			% Traversal.name_of(before))
	_check(after != Traversal.BLOCKED,
		"tripling the same animal's legs did not change what it could get over (%s)"
			% Traversal.name_of(after))
	_apply(player, "Lizard")

	# Room underneath is the same comparison pointed the other way, and it has to
	# be about the whole animal rather than about its belly: what fits under an
	# overhang is what is shorter than it.
	var branch_base: float = 60.0
	_check(Traversal.assess(readings["Lizard"], branch_base, branch_base + 40.0,
			100.0, 0.0) == Traversal.UNDER,
		"a low animal could not walk under something 60 px off the ground")
	_check(Traversal.assess(readings["Elephant"], branch_base, branch_base + 40.0,
			100.0, 0.0) == Traversal.BLOCKED,
		"an animal taller than the gap walked under it anyway")

	# And a surface too narrow to stand on is not a surface, however low it is.
	var perch: int = Traversal.assess(readings["Cat"], 0.0, 8.0, 0.5, 0.0)
	_check(perch != Traversal.MOUNT,
		"a body climbed onto something narrower than one of its own feet")


## The one case the brief names outright, and the one a rule about creature types
## would get wrong: a cat does not rise over another cat merely because they have
## collided, while a lizard goes over a low body part.
##
## Nothing here is about cats. A cat's back is carried at about twice the height
## its own shoulder is, so there is nothing up there a foot of its can reach; a
## lizard's shoulder is above a lizard's tail. Both fall out of the first of the
## three mount conditions, asked of a body part exactly as it is asked of a rock —
## which is the point of a body part being a footprint and a band like everything
## else.
func _check_a_body_is_an_obstacle(player: Creature, target: Creature) -> void:
	_apply(player, "Cat")
	_apply(target, "Cat")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(120.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	var back: Vector2 = target.stature.trunk
	var flank: float = target.body.widths[4]
	var cat_on_cat: int = Traversal.assess(Traversal.of(player), back.x, back.y, flank, 0.0)
	_check(cat_on_cat == Traversal.BLOCKED,
		"a cat rose over another cat's back (%s) — the two collided and that was taken for permission"
			% Traversal.name_of(cat_on_cat))

	# The same animal, the same rule, a lower part of the same kind of body — a
	# planted foot, because that genuinely is the low part. The lattice carries the
	# whole trunk at the height of the back, tail included, so the thing lying near
	# the floor on a quadruped is the end of a leg.
	_apply(player, "Lizard")
	_apply(target, "Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(120.0, 0.0), PI)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)
	var planted: Limb = target.gait.limbs[0]
	var foot_band: Vector2 = target.anatomy.tissue.limb_band(planted.key, 2)
	var over_foot: int = Traversal.assess(Traversal.of(player), foot_band.x, foot_band.y,
		planted.foot_radius(target.size_scale), 0.0)
	_check(over_foot != Traversal.BLOCKED,
		"a lizard could not get over another lizard's planted foot (%s, band %s)"
			% [Traversal.name_of(over_foot), Volume.describe(foot_band)])
	summary.append("cat on cat %s, lizard on foot %s"
		% [Traversal.name_of(cat_on_cat), Traversal.name_of(over_foot)])
	target.reset(Vector2(0.0, 8000.0), 0.0)


# ---------------------------------------------------------------- crossing ----

## Something the gait walks straight over. The claim is that nothing adapts: the
## body does not rise, the contact pass does not fire, and the animal arrives on
## the far side without its height, its stance or its stride having noticed.
##
## A narrow post rather than a broad plateau, and the difference is the whole
## point of there being two verdicts. Something wide and low is a floor at a new
## height and a body that walked onto it *should* come up onto it — that is the
## check below this one. Something narrower than the animal's own stance is a
## thing its feet fall either side of, and its belly is already above.
func _check_walking_over(player: Creature) -> void:
	_apply(player, "Elephant")
	main.terrain.clear()
	var flat: float = _walk_and_measure(player)
	main.terrain.clear()
	var post: Obstacle = main.terrain.add(Vector2(280.0, 0.0), 10.0, 11.0, 0.0, "post")
	_check(player.traversal(post) == Traversal.OVER,
		"a columnar animal did not simply walk over an 11 px post narrower than one of its feet (%s)"
			% Traversal.name_of(player.traversal(post)))
	var crossed: float = _walk_and_measure(player)
	_check(absf(crossed - flat) < 6.0,
		"a columnar animal changed how high it stood (%.1f -> %.1f) to walk over a post it steps either side of"
			% [flat, crossed])
	_check(player.head_pos.x > post.at.x + 200.0,
		"a columnar animal was stopped by an 11 px post (nose at %.0f, post at %.0f)"
			% [player.head_pos.x, post.at.x])
	# ...and the contact pass genuinely never fired, which is the mechanism rather
	# than the symptom: a crossable obstacle is not a wall, so nothing was pushed.
	player.reset(post.at, 0.0)
	for _tick in 20:
		player._physics_process(TICK)
	_check(player._push_out_of_terrain() == Vector2.ZERO,
		"an animal standing on top of something it can walk over was shoved off it")
	main.terrain.clear()


## Climbing on. Four things have to be true together or the body is cheating:
## the feet have to find the surface, the bones have to stay their own length, the
## body has to rise by about what it climbed, and its bands have to rise with it —
## because the bands are what everything else in the game asks about.
func _check_climbing_on(player: Creature) -> void:
	_apply(player, "Lizard")
	main.terrain.clear()
	var stood: float = _walk_and_measure(player)
	var ledge: float = 7.0
	main.terrain.clear()
	main.terrain.add(Vector2(600.0, 0.0), 520.0, ledge, 0.0, "ledge")
	var climbed: float = _walk_and_measure(player)

	var feet_up: int = 0
	var worst_bone: float = 0.0
	for limb in player.gait.limbs:
		if limb.surface > ledge * 0.5:
			feet_up += 1
		worst_bone = maxf(worst_bone, limb.bone_error())
	_check(feet_up >= 2,
		"%d of four feet found the top of a ledge the animal had walked onto" % feet_up)
	_check(worst_bone < 0.01,
		"a leg standing on a ledge was stretched by %.1f%% of its own bone"
			% (worst_bone * 100.0))
	_check(climbed > stood + ledge * 0.5,
		"a body on a %.0f px ledge rode only %.1f px higher than it did on the floor (%.1f -> %.1f)"
			% [ledge, climbed - stood, stood, climbed])
	_check(player.stature.torso.x > ledge * 0.5,
		"the animal was standing on the ledge and its belly band was still on the floor (%s)"
			% Volume.describe(player.stature.torso))
	summary.append("ledge %.0f px: rides %.1f -> %.1f" % [ledge, stood, climbed])
	main.terrain.clear()


## And a wall is a wall. The same walk into something none of the three
## conditions can be met for, and the animal is stopped by it rather than
## strolling through.
func _check_stopped_by_a_wall(player: Creature) -> void:
	_apply(player, "Cat")
	main.terrain.clear()
	main.terrain.add(Vector2(420.0, 0.0), 150.0, 120.0, 0.0, "wall")
	player.reset(Vector2.ZERO, 0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 300:
		player.command = drive
		player._physics_process(TICK)
	player.command = MovementInput.Command.new()
	var wall: Obstacle = main.terrain.obstacles[0]
	_check(player.traversal(wall) == Traversal.BLOCKED,
		"a 120 px wall was not a wall to a cat (%s)"
			% Traversal.name_of(player.traversal(wall)))
	_check(player.head_pos.x < wall.at.x,
		"a creature walked through a wall it could not climb (nose at %.0f, wall at %.0f)"
			% [player.head_pos.x, wall.at.x])
	_check(player.bounds_center.distance_to(wall.at) > wall.girth() * 0.5,
		"a creature ended up inside a wall it had walked into")
	main.terrain.clear()


## Underneath. The same object with its band lifted off the floor, and the same
## one comparison: what fits, passes, and it passes without touching anything.
func _check_passing_underneath(player: Creature) -> void:
	_apply(player, "Lizard")
	main.terrain.clear()
	var branch: Obstacle = main.terrain.add(Vector2(400.0, 0.0), 130.0, 40.0, 70.0, "branch")
	_check(player.traversal(branch) == Traversal.UNDER,
		"a lizard could not get under a branch 70 px over its head (%s)"
			% Traversal.name_of(player.traversal(branch)))
	player.reset(Vector2.ZERO, 0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 400:
		player.command = drive
		player._physics_process(TICK)
	player.command = MovementInput.Command.new()
	_check(player.head_pos.x > branch.at.x + branch.girth(),
		"a lizard that fits under a branch was stopped by it (got to %.0f, branch ends at %.0f)"
			% [player.head_pos.x, branch.at.x + branch.girth()])

	# ...and the one that does not fit is stopped by the identical object.
	_apply(player, "Elephant")
	_check(player.traversal(branch) == Traversal.BLOCKED,
		"an elephant walked under a branch its back does not clear (%s)"
			% Traversal.name_of(player.traversal(branch)))
	main.terrain.clear()
	_apply(player, "Lizard")


# ------------------------------------------------------------------ cursor ----

## A click has two numbers and the world has three. The claim is that the missing
## one comes back — and comes back attached to the right piece of the right body,
## because a bite has to land on what was pointed at rather than near it.
func _check_cursor_has_a_height(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(400.0, 0.0), PI)
	for _tick in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)

	# A foot, and the back over it. Two clicks in nearly the same place on the
	# ground plane, and they must not answer with the same thing.
	var foot: Limb = target.gait.limbs[0]
	var on_foot: Reticle.Pick = Reticle.pick(self, foot.joints[2], 8.0, player)
	_check(on_foot.creature == target and on_foot.hit != null
			and on_foot.hit.kind == AnatomyState.LIMB,
		"clicking an elephant's foot selected %s" % on_foot.describe())
	_check(on_foot.hit != null and on_foot.hit.limb_key == foot.key,
		"clicking one foot selected a different leg")
	_check(on_foot.at.distance_to(foot.plan[2]) < 12.0,
		"a foot's target was reported at the place it is drawn rather than the place it stands")

	var spine_at: Vector2 = target.spine.points[5]
	var on_back: Reticle.Pick = Reticle.pick(self, spine_at, 8.0, player)
	_check(on_back.creature == target and on_back.hit != null
			and on_back.hit.kind == AnatomyState.TORSO,
		"clicking an elephant's back selected %s" % on_back.describe())
	_check(on_back.band.x > on_foot.band.y,
		"the back and the foot of the same animal came back at overlapping heights (%s and %s)"
			% [Volume.describe(on_back.band), Volume.describe(on_foot.band)])

	# The ground is a real answer rather than a null, because putting a mouth on
	# bare earth is a thing an animal does.
	var nothing: Reticle.Pick = Reticle.pick(self, Vector2(-4000.0, -4000.0), 8.0, player)
	_check(nothing != null and nothing.kind == "ground" and nothing.band == Volume.ground(),
		"clicking open ground did not come back as the ground")

	# ...and an object in the world is picked in the picture, so its top face is
	# selectable at the height it is drawn rather than at the ground beneath it.
	main.terrain.clear()
	var rock: Obstacle = main.terrain.add(Vector2(-600.0, 0.0), 50.0, 60.0, 0.0, "rock")
	var on_top: Reticle.Pick = Reticle.pick(self, rock.drawn(rock.top()), 4.0, player)
	_check(on_top.obstacle == rock and on_top.height > rock.top() * 0.5,
		"clicking the top of a rock came back at %.0f of a %.0f px rock"
			% [on_top.height, rock.top()])
	main.terrain.clear()
	target.reset(Vector2(0.0, 8000.0), 0.0)


# ------------------------------------------------------------------- reach ----

## Getting a mouth onto the floor. The clamp this replaced simply granted it, so
## the interesting half of the mechanic — a tall animal folding itself down to
## something at its feet — was invisible. Now it is three lengths added up, and
## an animal is either long enough in the neck and loose enough in the leg or it
## is not.
func _check_reaching_down(player: Creature) -> void:
	main.terrain.clear()
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		_check(player.stature.fold > 0.0,
			"a standing %s had no fold left in its legs at all" % preset)
		_check(player.stature.bite.x <= 0.0,
			"a %s could not get its mouth to the ground it is standing on (%s)"
				% [preset, Volume.describe(player.stature.bite)])
		summary.append("%s folds %.0f px" % [preset, player.stature.fold])

	# The elephant is the case that shows it, because it needs all three and has
	# almost nothing to spare — which is exactly why the clamp was hiding
	# something. Stand the same animal on much longer legs and it can no longer
	# reach its own feet: the fold and the neck grew with nothing, and the height
	# they have to cover grew with the legs. One parameter, and the whole of what
	# a tall short-necked browser's problem is.
	_apply(player, "Elephant")
	var on_its_legs: float = player.stature.bite.x
	player.params.arm_length *= 1.8
	player.params.leg_length *= 1.8
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 30:
		player._physics_process(TICK)
	_check(player.stature.bite.x > on_its_legs,
		"putting an elephant on much longer legs did not make the ground harder to reach (%.1f -> %.1f)"
			% [on_its_legs, player.stature.bite.x])
	_check(player.stature.bite.x > 0.0,
		"an animal standing far taller than its neck and its fold add up to still reached the floor (%s)"
			% Volume.describe(player.stature.bite))

	# And the reach is not merely a band: it comes with the movement that earns
	# it. Pointed at the floor, the body actually folds.
	_apply(player, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 20:
		player._physics_process(TICK)
	var upright: float = player.gait.support
	var down := Reticle.Pick.new()
	down.at = player.jaw_point()
	down.band = Volume.ground()
	down.height = 0.0
	player.aim_at(down)
	for _tick in 60:
		player._physics_process(TICK)
	_check(player.crouch > 0.2,
		"an elephant told to feed at its feet folded %.0f%% of its legs" % (player.crouch * 100.0))
	_check(player.gait.support < upright - 2.0,
		"the crouch never reached the body: it rode %.1f px before and %.1f px after"
			% [upright, player.gait.support])
	summary.append("elephant crouches %.0f -> %.0f px" % [upright, player.gait.support])
	player.aim_at(null)
	for _tick in 90:
		player._physics_process(TICK)
	_check(player.gait.support > upright - 2.0,
		"the animal never stood back up after it stopped reaching (%.1f of %.1f)"
			% [player.gait.support, upright])
	_apply(player, "Lizard")


## Refusing what it cannot reach — and, just as much, not refusing what it can.
## A refusal that fired on everything would pass half of this on its own.
func _check_refusing_what_it_cannot_reach(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(400.0, 0.0), PI)
	for _tick in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	# Stood right beside the elephant's nearest leg, because the claim being made
	# is about height and nothing else: a target the lizard cannot reach because it
	# is on the far side of the paddock would pass the same check for the wrong
	# reason. Everything below is within its jaws horizontally, and the only
	# question left is how far off the ground it is.
	var near: Limb = _nearest_limb(target, player.head_pos)
	player.reset(near.plan[2] - Vector2(40.0, 0.0), 0.0)
	for _tick in 20:
		player._physics_process(TICK)
		target._physics_process(TICK)

	# The back, directly over the animal's own nose and a whole leg above anything
	# it can bring to bear.
	var high := Reticle.Pick.new()
	var over: float = _spine_t_nearest(target, player.jaw_point())
	high.at = target.spine.sample(over).pos
	high.band = target.anatomy.tissue.body_band(over)
	var up: Reach = Reach.solve(player, high.at, high.band)
	_check(not up.possible and up.refusal == "above",
		"a ground-level lizard reached an elephant's back (%s)" % up.describe())
	player.aim_at(high)
	_check(not player.request_bite(high.at),
		"a lizard threw a strike at something it cannot physically reach")

	# ...and the foot standing next to it, which it can. Same animal, same lizard,
	# same instant: only the height of the target differs.
	var foot: Limb = _nearest_limb(target, player.jaw_point())
	var low := Reticle.Pick.new()
	low.at = foot.plan[2]
	low.band = target.anatomy.tissue.limb_band(foot.key, 2)
	var down: Reach = Reach.solve(player, low.at, low.band)
	_check(down.possible,
		"the same lizard could not reach the planted foot beside it (%s)" % down.describe())
	player.aim_at(low)
	_check(player.request_bite(low.at),
		"a lizard refused to bite a foot it can reach")
	summary.append("lizard on elephant: back %s, foot %s"
		% ["refused" if not up.possible else "allowed",
			"allowed" if down.possible else "refused"])

	# Something solid in between is the same refusal from the third direction.
	main.terrain.clear()
	var mouth: Vector2 = player.jaw_point()
	main.terrain.add(mouth.lerp(low.at, 0.5), 30.0, 40.0, 0.0, "rock")
	var blocked: Reach = Reach.solve(player, low.at, low.band, main.terrain)
	_check(not blocked.possible and blocked.obstructed,
		"jaws closed on something on the far side of a rock (%s)" % blocked.describe())
	main.terrain.clear()
	player.aim_at(null)
	target.reset(Vector2(0.0, 8000.0), 0.0)
	_apply(player, "Lizard")


# -------------------------------------------------------------------- flat ----

## The guarantee the whole layer rests on, and the same one every other file in
## this game makes: with nothing on the ground and nothing pointed at, every line
## added here is inert. A creature walks the plain exactly as it did.
func _check_flat_world_unchanged(player: Creature) -> void:
	main.terrain.clear()
	_apply(player, "Lizard")
	player.aim_at(null)
	player.reset(Vector2.ZERO, 0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 240:
		player.command = drive
		player._physics_process(TICK)
	player.command = MovementInput.Command.new()
	for limb in player.gait.limbs:
		_check(limb.surface == 0.0,
			"a foot on the open plain was standing %.1f px above it" % limb.surface)
	_check(is_zero_approx(player.crouch),
		"an animal that was never pointed at anything was crouching %.2f" % player.crouch)
	_check(player.ground_height() == 0.0,
		"the floor of an empty world was not at zero")
	_check(player.can_reach_aim() and player.request_bite(player.jaw_point()),
		"a bite with nothing selected was refused")


# ------------------------------------------------------------------- tools ----

## Walks the creature forward and reports the height its own feet end up holding
## it at. Long enough to have crossed whatever is in the way and settled onto the
## far side of it.
func _walk_and_measure(player: Creature) -> float:
	player.reset(Vector2.ZERO, 0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 260:
		player.command = drive
		player._physics_process(TICK)
	player.command = MovementInput.Command.new()
	for _tick in 30:
		player._physics_process(TICK)
	return player.gait.support


## Where along a body's spine it comes closest to a point — so a target can be
## picked directly over the animal doing the pointing rather than at an arbitrary
## segment that may be half a body away.
func _spine_t_nearest(creature: Creature, to: Vector2) -> float:
	var best: float = 0.0
	var closest: float = INF
	for step in 24:
		var t: float = float(step) / 23.0
		var distance: float = creature.spine.sample(t).pos.distance_to(to)
		if distance < closest:
			closest = distance
			best = t
	return best


func _nearest_limb(creature: Creature, to: Vector2) -> Limb:
	var best: Limb = creature.gait.limbs[0]
	for limb in creature.gait.limbs:
		if limb.plan[2].distance_to(to) < best.plan[2].distance_to(to):
			best = limb
	return best


func _apply(creature: Creature, preset: String) -> void:
	creature.set_bite_held(false)
	creature.aim_at(null)
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
		print("traversal OK — under, over, onto or stopped, decided by the legs: %s"
			% " · ".join(summary))
		quit(0)
	else:
		for failure in failures:
			print("TRAVERSAL FAIL — ", failure)
		quit(1)
