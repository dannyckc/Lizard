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
	_check_the_marker_is_where_the_bite_lands(player, target)
	_check_reaching_down(player)
	_check_refusing_what_it_cannot_reach(player, target)
	_check_flat_world_unchanged(player)
	_check_broken_ground_is_walked_not_juddered(player)
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
	# surface rather than something to step around, and 16 px high — which is over
	# a sprawled animal's sockets and well under an upright one's.
	var kerb: float = 16.0
	var verdicts: Dictionary = {}
	for preset in ["Lizard", "Cat", "Elephant"]:
		verdicts[preset] = Traversal.assess(readings[preset], 0.0, kerb, 60.0, 0.0)
	var spread: Array[String] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		spread.append("%s %s" % [preset, Traversal.name_of(verdicts[preset])])
	summary.append("16 px kerb: %s" % ", ".join(spread))
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
	# Wide enough that wherever thirteen seconds of this build's own cruise ends,
	# it ends well inside the surface — the walk is held to the speed the sheet
	# asks for, so the span is sized to that rather than to a distance.
	main.terrain.add(Vector2(750.0, 0.0), 1100.0, ledge, 0.0, "ledge")
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


## The second half of the cursor, and the half that is about the animal holding
## it: not what is under the pointer, but what would happen if this body acted on
## it now.
##
## Two corrections, and the reason both exist is that a marker sitting on the
## pixel the mouse is over is a marker that lies about a game with a third axis in
## it. A cursor dragged across a deep-chested animal selects the flank on the far
## side of it, which is not where any mouth arrives; a cursor thrown across the
## paddock selects something no mouth arrives at at all.
func _check_the_marker_is_where_the_bite_lands(player: Creature, target: Creature) -> void:
	main.terrain.clear()
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(230.0, 0.0), PI)
	for _tick in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	# Stood against the elephant's flank, because the correction under test is
	# across a body rather than along the road: a lizard half a paddock away is out
	# of reach in the horizontal, and what happens to a marker then is the *other*
	# half of this function.
	var beside: Vector2 = target.body_point(Vector2(0.5, 1.0))
	var outward: Vector2 = target.spine.sample(0.5).perp
	player.reset(beside + outward * 34.0, (-outward).angle())
	for _tick in 24:
		player._physics_process(TICK)
		target._physics_process(TICK)

	# --- onto the surface the jaws meet ---------------------------------------
	# Both flanks of one station on the elephant's back, and the cursor put on the
	# one the lizard is *not* standing beside. What comes back has to be the other.
	var station: float = _spine_t_nearest(target, player.jaw_point())
	var mouth: Vector2 = player.jaw_point()
	var flanks: Array[Vector2] = [target.body_point(Vector2(station, -1.0)),
		target.body_point(Vector2(station, 1.0))]
	var near: Vector2 = flanks[0] if mouth.distance_to(flanks[0]) < mouth.distance_to(flanks[1]) \
		else flanks[1]
	var far: Vector2 = flanks[1] if near == flanks[0] else flanks[0]
	# Just inside the far flank rather than exactly on it: a cursor sitting on a
	# surface is scored at nothing, and nothing does not beat the open ground.
	var on_far: Reticle.Pick = Reticle.pick(self,
		target.body_point(Vector2(station, 1.0 if far == flanks[1] else -1.0)) \
			.lerp(target.spine.sample(station).pos, 0.25), 8.0, player)
	_check(on_far.creature == target and on_far.hit != null,
		"a cursor on an elephant's far flank selected %s" % on_far.describe())
	var picked_at: Vector2 = on_far.at
	var met: Reticle.Pick = Reticle.resolve(on_far, player)
	_check(met.at.distance_to(near) < met.at.distance_to(far),
		"the marker stayed on the far side of the body the bite would come from")
	_check(met.at.distance_to(mouth) < picked_at.distance_to(mouth),
		"resolving the pick against the animal did not bring it nearer its mouth (%.1f -> %.1f px)"
			% [picked_at.distance_to(mouth), met.at.distance_to(mouth)])
	# ...and at the height the jaws are actually brought to, rather than the middle
	# of the band or the top of it. It is the same reading the reach test makes, so
	# the ring and the bite cannot disagree about where they are aimed.
	_check(is_equal_approx(met.height, Reach.meeting(player, met.band)),
		"the marker sat at %.1f px on a target the mouth meets at %.1f"
			% [met.height, Reach.meeting(player, met.band)])
	_check(Volume.contains(met.band, met.height),
		"the marker's height %.1f was outside the band it is on (%s)"
			% [met.height, Volume.describe(met.band)])
	_check(met.beyond == null,
		"something the animal is standing next to was reported as beyond its reach")
	summary.append("marker crosses to the near flank %.0f px in"
		% picked_at.distance_to(met.at))

	# --- and in to arm's length, when it is past it ----------------------------
	# The arm onto the floor, because that is where the brought-in point is: the
	# neck spends part of its plan reach sweeping the mouth down to the ground,
	# so the marker sits just inside `span_onto` rather than the level span — the
	# same number the reach test refuses at, which is the whole claim.
	var span: float = Reach.span_onto(player, Volume.ground())
	var away: Vector2 = mouth + Vector2.RIGHT.rotated(deg_to_rad(12.0)) * (span * 6.0)
	var reached: Reticle.Pick = Reticle.resolve(Reticle.pick(self, away, 8.0, player), player)
	_check(reached.beyond != null,
		"a marker thrown six times the animal's reach was left out there")
	var out: float = reached.at.distance_to(mouth)
	_check(out <= span + 0.5 and out > span * 0.9,
		"the marker was brought in to %.1f px of a %.1f px reach" % [out, span])
	_check((reached.at - mouth).normalized().dot((away - mouth).normalized()) > 0.999,
		"the marker was brought in off the line it was aimed along")
	var got: Reach = Reach.solve(player, reached.at, reached.band, main.terrain)
	_check(got.possible,
		"the furthest point the animal was offered is one it cannot reach (%s)" % got.describe())
	# The whole purpose of it: the click still happens, and it happens toward the
	# place that was pointed at.
	player.aim_at(reached)
	_check(player.can_reach_aim() and player.request_bite(reached.at),
		"a click at something past the animal's reach was swallowed")
	player.aim_at(null)
	_strike_through(player, target)
	summary.append("reach clamp %.0f px" % out)
	target.reset(Vector2(0.0, 8000.0), 0.0)
	_apply(player, "Lizard")


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
	# The multiplier has to be large, and it is larger than it used to be for a
	# good reason: the Elephant is no longer built on stilts. Its legs used to be
	# four tenths of its own body long and stood it a third higher than it was deep
	# through the chest, so it was already most of the way to not reaching its feet
	# and a modest stretch tipped it over. Proportioned like an animal, it takes a
	# real distortion to put the ground out of its reach — which is the honest
	# version of the same claim.
	_apply(player, "Elephant")
	var on_its_legs: float = player.stature.bite.x
	player.params.arm_length *= 2.6
	player.params.leg_length *= 2.6
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
	# Pointing at it is not reaching for it. A cursor resting on the floor is a
	# question about the world; sixty ticks of it and the animal is standing
	# exactly as it was, because what folds a body is the decision to bite and
	# nothing else.
	_check(player.crouch < 0.02 and player.gait.support > upright - 2.0,
		"an elephant folded %.0f%% of its legs at a target nobody had clicked on"
			% (player.crouch * 100.0))
	# ...and the click is what folds it. Read across the strike rather than after
	# it: the fold is spent getting the mouth down there and released with the
	# rest of the movement, so by the time the jaws have opened again the animal
	# is already on its way back up.
	var folded: float = 0.0
	var lowest: float = INF
	player.request_bite(down.at)
	for _tick in 240:
		player._physics_process(TICK)
		folded = maxf(folded, player.crouch)
		lowest = minf(lowest, player.gait.support)
		if player.can_bite():
			break
	# That it folds at all, rather than how much: how much is a consequence of how
	# far its mouth has to travel, and a correctly proportioned animal needs less
	# of its legs to reach its own feet than one on stilts did. The claim with teeth
	# in it is the next one — that the fold arrives at the body.
	_check(folded > 0.1,
		"an elephant told to feed at its feet folded %.0f%% of its legs" % (folded * 100.0))
	_check(lowest < upright - 2.0,
		"the crouch never reached the body: it rode %.1f px before and %.1f px at its lowest"
			% [upright, lowest])
	summary.append("elephant crouches %.0f -> %.0f px" % [upright, lowest])
	player.aim_at(null)
	for _tick in 90:
		player._physics_process(TICK)
	_check(player.gait.support > upright - 2.0,
		"the animal never stood back up after it stopped reaching (%.1f of %.1f)"
			% [player.gait.support, upright])
	_apply(player, "Lizard")


## Missing what it cannot reach — and, just as much, connecting with what it can.
## A strike that landed on nothing whatever it was aimed at would pass half of
## this on its own.
##
## The claim used to be that the body declined to strike at all, and the reversal
## is deliberate: an input that vanishes is indistinguishable from one the game
## did not receive. So the animal throws the lunge either way and the height
## decides what is in its jaws at the end of it — which is where every other
## interaction in the game is already decided. What the reach knows is still
## exactly what it knew; it is now spent on telling the player beforehand rather
## than on swallowing the click.
func _check_refusing_what_it_cannot_reach(player: Creature, target: Creature) -> void:
	_apply(player, "Lizard")
	_apply(target, "Elephant")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(400.0, 0.0), PI)
	for _tick in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	# Stood beside the elephant's nearest foot and facing across it, because the
	# claim being made is about height and nothing else: a target the lizard cannot
	# reach because it is on the far side of the paddock would pass the same check
	# for the wrong reason. Both things it is about to be asked for — the foot and
	# the back directly over it — are within its jaws horizontally, and the only
	# question left is how far off the ground each of them is.
	#
	# Offset across the body rather than along it, and that is not tidiness. Where
	# the feet are is exactly what a posture changes: a columnar animal stands its
	# legs close underneath itself, so a lizard placed a fixed distance up the road
	# from a foot ends up somewhere quite different beside a sprawled animal and a
	# stacked one. Across the flank, the same offset means the same thing to both.
	var beside: Limb = _nearest_limb(target, player.head_pos)
	var across: Vector2 = target.body.anchors[beside.key].perp * beside.side
	# Close enough that the horizontal solve always succeeds — the refusal this
	# check exists to read is the vertical one, so the stand-off is inside any
	# build's lunge rather than calibrated to one species' head.
	#
	# Measured off the drawn foot rather than the plan one, because that is where
	# the flesh a bite has to arrive at actually is: a limb's cells and its hit
	# capsules live on the chain it is drawn along, hanging below the body, and on
	# an animal this deep through the chest that is most of a lizard away from the
	# spot the same foot stands on. Staged off the plan position the animal was
	# put a body-length from what it was about to be asked to bite, and only ever
	# reached it because the head used to leave on its own.
	player.reset(beside.joints[2] + across * 22.0, (-across).angle())
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
	_check(player.request_bite(high.at),
		"a lizard's click at something out of reach was swallowed rather than thrown")
	var back_before: float = target.anatomy.tissue.body_solid(over, 0.0)
	_strike_through(player, target)
	_check(is_equal_approx(target.anatomy.tissue.body_solid(over, 0.0), back_before),
		"a strike thrown at an elephant's back reached it from the floor (%.3f -> %.3f)"
			% [back_before, target.anatomy.tissue.body_solid(over, 0.0)])

	# ...and the foot standing next to it, which it can. Same animal, same lizard,
	# same instant: only the height of the target differs.
	#
	# Picked through the cursor's own resolver rather than assembled by hand,
	# because the pick carries which structure it is now, and the strike is sent
	# to where that structure's flesh is actually posed — a limb lives on its
	# drawn chain. The pointer goes on the drawn foot, exactly where a player's
	# would.
	var foot: Limb = _nearest_limb(target, player.jaw_point())
	var low: Reticle.Pick = Reticle.pick(self, foot.joints[2], 8.0, player)
	_check(low.hit != null and low.creature == target,
		"a cursor on the elephant's drawn foot selected %s" % low.describe())
	# Asked through the animal's own aim rather than of the pick's plan position,
	# because those are two different places on a limb and only one of them is
	# where the mouth is sent: `Creature.aim_contact` resolves a leg onto the chain
	# its cells and its capsules are posed along. Solving against the plan spot
	# instead measures a reach onto the patch of ground the foot stands on, which
	# on a deep-chested animal is most of a lizard from the foot.
	player.aim_at(low)
	var down: Reach = player.aim_reach
	_check(down != null and down.possible,
		"the same lizard could not reach the planted foot beside it (%s)"
			% ("no reach solved" if down == null else down.describe()))
	_check(player.request_bite(low.at),
		"a lizard refused to bite a foot it can reach")
	_strike_through(player, target)
	_check(player.bite_connected,
		"a lizard's strike at the foot beside it landed on nothing")
	summary.append("lizard on elephant: back missed, foot %s"
		% ["bitten" if player.bite_connected else "missed"])

	# Something solid in between is the same refusal from the third direction.
	main.terrain.clear()
	var mouth: Vector2 = player.jaw_point()
	var flesh: Vector2 = player.aim_contact
	main.terrain.add(mouth.lerp(flesh, 0.5), 30.0, 40.0, 0.0, "rock")
	var blocked: Reach = Reach.solve(player, flesh, low.band, main.terrain)
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
	# Long enough for the slowest thing in the file to walk clear of what it is
	# being asked to walk over. A body is held to the pace its own legs turn over
	# at now — see Locomotion.leg_speed — so an Elephant covers about a third of
	# the ground in four seconds that it used to, and four seconds was sized to
	# reach an obstacle two hundred pixels out.
	for _tick in 780:
		player.command = drive
		player._physics_process(TICK)
	player.command = MovementInput.Command.new()
	# ...and long enough afterwards for the body to settle onto its feet. The
	# settle is quoted per step cycle rather than per second — see
	# Locomotion.settle — so a slower gait takes proportionally longer about it,
	# and the ride height this returns is the settled one or it is nothing.
	for _tick in 90:
		player._physics_process(TICK)
	return player.gait.support


## Runs a queued strike through its hit frame and out the far side of its own
## cooldown, with both bodies ticking and the habitat's resolver attached — so
## what the jaws close on is decided exactly as it is in play, by the world,
## rather than by this file deciding what it thinks should have happened.
func _strike_through(player: Creature, target: Creature) -> void:
	for _tick in 300:
		player._physics_process(TICK)
		target._physics_process(TICK)
		if player.can_bite():
			return
	_check(false, "a strike never finished: the animal is still mid-lunge")


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


## Crossing broken ground has to look like walking, and the two ways it did not
## are both measurable on a planted foot.
##
## Getting over one ledge was already right; what a field of things to climb adds
## is that the answers keep changing. Every tick each foot asks what is under it,
## and the place it is asking about moves — it is dragged along its own envelope,
## shoved by contacts, and the height it may be lifted to rises and falls with the
## body's own walking bob. Near the rim of anything, that carries the answer back
## and forth across an edge.
##
## Two claims, and neither is about terrain:
##
##   * **A foot that is standing still is standing still.** It may not be
##     somewhere else next tick because the query changed its mind, so what is
##     under a planted foot is followed at the speed that foot moves in its own
##     step. Taken whole, the foot teleports — and a leg near its own lock-out
##     turns a few pixels of that into a joint swinging through tens of degrees,
##     which is what the judder was.
##   * **A foothold is a place with room on it.** The stride aims a step and knows
##     nothing about what is underfoot, so it lands on rims as readily as on tops;
##     a foot that has almost none of its own footprint on a surface is standing
##     on the thing it is about to come off. It looks for somewhere better before
##     it commits, which is a foot placed more carefully rather than a leg hunting.
func _check_broken_ground_is_walked_not_juddered(player: Creature) -> void:
	for preset in ["Lizard", "Cat"]:
		_apply(player, preset)
		main.terrain.clear()
		# Steps right at the top of what this body can lift a foot to, which is
		# where the per-foot ceiling is the thing being decided, and narrow enough
		# that a foot regularly comes down near an edge. Sized off the animal, so
		# both builds are asked the same question.
		var ceiling: float = player.gait.shoulder_height
		for i in 20:
			main.terrain.add(Vector2(180.0 + float(i) * 52.0,
				(-1.0 if i % 2 == 0 else 1.0) * 14.0), 17.0,
				ceiling * (0.94 + 0.04 * float(i % 3)), 0.0, "brink")

		player.reset(Vector2.ZERO, 0.0)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var was_stepping: Dictionary = {}
		var last_height: Dictionary = {}
		var worst_snap: float = 0.0
		var perched: int = 0
		var stance: int = 0
		for _tick in 420:
			player.command = drive
			player._physics_process(TICK)
			for limb in player.gait.limbs:
				# Only a foot planted on this tick and the one before it. A landing
				# and a lift-off both move a foot for good reasons.
				var settled: bool = not limb.stepping \
					and not was_stepping.get(limb.key, true)
				if settled and last_height.has(limb.key):
					worst_snap = maxf(worst_snap,
						absf(limb.foot_height - float(last_height[limb.key])))
				if settled:
					stance += 1
					if limb.surface > 0.5 and limb.foothold < 0.0:
						perched += 1
				last_height[limb.key] = limb.foot_height
				was_stepping[limb.key] = limb.stepping
		player.command = MovementInput.Command.new()

		# What one step of this animal moves a foot vertically in a tick, which is
		# the fastest anything on it moves that foot and so the most a planted one
		# may follow a change by. Doubled, because the measurement spans a tick in
		# which the foot may also have rolled onto its toe.
		var reachable: float = maxf(player.gait._foot_speed(player.gait.limbs[0])
			* TICK * 2.0, 1.0)
		_check(worst_snap <= reachable,
			"%s stood still and its foot moved %.1f px in one tick, which is %.1fx what a step of its own moves it"
				% [preset, worst_snap, worst_snap / reachable])
		# Counted in ticks, which is why the share moved when the gait slowed down: a
		# foot stays planted a good deal longer per step now — the swing is held open
		# to the limb's own pendulum instead of being clipped, see
		# Locomotion.SWING_HURRY — so the same one badly-chosen foothold is counted
		# for nine ticks where it used to be counted for one. What the check is for
		# is a body habitually standing on nothing, and two placements in three
		# hundred steps is not that.
		_check(float(perched) <= float(stance) * 0.025,
			"%s spent %d of %d stance ticks (%.1f%%) on a surface it had no room on"
				% [preset, perched, stance, 100.0 * float(perched) / maxf(float(stance), 1.0)])
		summary.append("%s over broken ground: foot moves %.1f px/tick planted, %d/%d ticks perched"
			% [preset, worst_snap, perched, stance])
	main.terrain.clear()


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
