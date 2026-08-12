## The controls, pinned — v2's cursor look and the bite hung off it.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/AimProbe.gd
##
## v1's ControlsTest and BiteReachTest claims, re-expressed against the v2 body.
## Behaviours, not constants:
##
##   * **the cursor is the view** — the head is carried round to what the
##     pointer is on, it stops where the animal's own cervical joints stop it,
##     and it comes home when the pointer stops saying anything. The *body* is
##     not moved by any of it: a standing animal watching something to its side
##     stays exactly where it was standing.
##   * **a walking animal goes where it is looking** — the head reaches the
##     bearing first and the heading follows it, at the rate the animal's own
##     legs turn it; the hand still outranks the head, and a body that is not
##     being asked forward only watches.
##   * **the click bites what the pointer is on** — the pick is made in the
##     picture, off the same posed rings the painter draws, so what is selected
##     is what is wounded; a bite at bare ground is still thrown.
##   * **the button is the grip** — jaws that close while it is down keep what
##     they closed on, and letting go lets go on the same frame.
##   * **the strike is a lunge** — the body is carried toward the flesh, by no
##     more than the support will pay for.
##   * **anatomy holds throughout** — every stick, bend and bone exact after
##     all of it, however far the head has been turned.
extends SceneTree

const TICK: float = 1.0 / 60.0

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
	var cat: Creature2 = main.creature
	_check(cat != null, "the lab did not build a creature")
	if cat == null:
		_finish()
		return false
	main.terrain.clear()
	var prey: Creature2 = _stand(Vector2(115.0, -25.0), PI / 2.0)
	_settle(cat, prey)

	_check_the_head_follows_the_cursor(cat)
	_check_the_neck_alone_does_the_looking(cat)
	_check_the_walk_follows_the_head(cat)
	_check_the_hand_outranks_the_head(cat)
	_check_the_pick_is_made_in_the_picture(cat, prey)
	_check_the_click_bites_what_is_pointed_at(cat, prey)
	_check_a_bite_at_nothing_is_still_thrown(cat, prey)
	_check_the_button_is_the_grip(cat, prey)

	_measure(cat)
	_measure(prey)
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


# ------------------------------------------------------------------- the look ----

## The head is carried to what the pointer is on, as far as the neck goes and no
## further, and it comes home when the pointer stops saying anything.
func _check_the_head_follows_the_cursor(cat: Creature2) -> void:
	_settle_one(cat)
	var rest: float = _head_bearing(cat)
	_check(absf(wrapf(rest - cat.heading, -PI, PI)) < 0.05,
		"an unaimed head was already turned %.2f rad off the body" % rest)

	# Something square off the animal's left, a long way out: the ask is a right
	# angle and the neck answers with whatever it has.
	_point(cat, cat.head_pos + Vector2(40.0, -260.0))
	_tick(cat, 40)
	var turned: float = absf(wrapf(_head_bearing(cat) - cat.heading, -PI, PI))
	var most: float = minf(Gaze.MAX_ANGLE, cat.armature.neck_sweep())
	_check(turned > deg_to_rad(20.0),
		"the head barely moved for a cursor at right angles (%.1f°)"
			% rad_to_deg(turned))
	_check(turned <= most + 0.02,
		"the head turned %.1f° past what the neck allows (%.1f°)"
			% [rad_to_deg(turned), rad_to_deg(most)])
	# ...and the cervical joints are the thing that stopped it, not a number:
	# what the head delivered has to be inside what the chain will give.
	_check(turned <= cat.armature.neck_sweep() + 0.02,
		"the head outran the cervical joints' own limits")

	_point(cat, Vector2.INF)
	_tick(cat, 60)
	var home: float = absf(wrapf(_head_bearing(cat) - cat.heading, -PI, PI))
	_check(home < 0.08,
		"the head stayed %.1f° off the body with nothing to look at"
			% rad_to_deg(home))
	_check(is_nan(cat.armature.look),
		"the neck was still being held to a bearing after the pointer went quiet")
	notes.append("look: %.0f° of head off the shoulders at right angles (neck gives %.0f°), home to %.1f° with no cursor"
		% [rad_to_deg(turned), rad_to_deg(cat.armature.neck_sweep()), rad_to_deg(home)])


## Looking is done with the neck. The body does not move, does not turn, and
## does not follow its own head anywhere unless it is being asked forward.
func _check_the_neck_alone_does_the_looking(cat: Creature2) -> void:
	_settle_one(cat)
	var stood: Vector2 = cat.centre()
	var faced: float = cat.heading
	var shoulders: float = cat.armature.fwd[cat.armature.withers_index()].angle()
	_point(cat, cat.head_pos + Vector2(30.0, -220.0))
	_tick(cat, 90)
	var walked: float = cat.centre().distance_to(stood)
	var swung: float = absf(wrapf(cat.heading - faced, -PI, PI))
	var girdle: float = absf(wrapf(
		cat.armature.fwd[cat.armature.withers_index()].angle() - shoulders, -PI, PI))
	_check(walked < 4.0,
		"a standing animal watching something was towed %.1f px by its own gaze" % walked)
	_check(swung < 0.06,
		"a standing animal turned %.1f° to look at something" % rad_to_deg(swung))
	_check(girdle < 0.10,
		"the shoulders swung %.1f° with the head — the girdle is following the neck"
			% rad_to_deg(girdle))
	notes.append("standing: the look costs the body %.2f px and %.1f° of heading, shoulders %.1f°"
		% [walked, rad_to_deg(swung), rad_to_deg(girdle)])
	_point(cat, Vector2.INF)


## Walking, the animal goes where it is looking: the head reaches the bearing
## first and the body comes round after it.
func _check_the_walk_follows_the_head(cat: Creature2) -> void:
	_settle_one(cat)
	var faced: float = cat.heading
	# Ahead and well off to one side, so the ask is a real turn rather than a
	# nudge, and re-pointed every tick because the animal is walking toward it.
	cat.command.throttle = 1.0
	for i in 150:
		_point(cat, Vector2(260.0, -260.0))
		cat._physics_process(TICK)
	_measure(cat)
	cat.command.throttle = 0.0
	var came: float = wrapf(cat.heading - faced, -PI, PI)
	var left: float = absf(wrapf(cat.heading
		- (Vector2(260.0, -260.0) - cat.head_pos).angle(), -PI, PI))
	_check(came < -0.3,
		"a walking animal did not come round toward what it was looking at (%.1f°)"
			% rad_to_deg(came))
	_check(left < 0.5,
		"the walk finished %.1f° off the bearing it was looking on" % rad_to_deg(left))

	# ...and a body that is not being asked forward only watches: the same look,
	# no throttle, no turn.
	_settle_one(cat)
	faced = cat.heading
	for i in 150:
		_point(cat, Vector2(260.0, -260.0))
		cat._physics_process(TICK)
	_measure(cat)
	var idle: float = absf(wrapf(cat.heading - faced, -PI, PI))
	_check(idle < 0.06,
		"a standing animal steered %.1f° by looking" % rad_to_deg(idle))
	notes.append("walk: came round %.0f° onto the look and finished %.1f° off it; standing, %.1f°"
		% [rad_to_deg(came), rad_to_deg(left), rad_to_deg(idle)])
	_point(cat, Vector2.INF)


## The hand outranks the head: a turn held by the player is the turn the body
## takes, however hard the head is pulling the other way.
func _check_the_hand_outranks_the_head(cat: Creature2) -> void:
	_settle_one(cat)
	var faced: float = cat.heading
	# Accumulated rather than differenced: a body turning as hard as it can goes
	# right round inside a second and a half, and the wrapped difference would
	# report that as having gone the other way.
	var went: float = 0.0
	cat.command.throttle = 1.0
	cat.command.turn = 1.0
	for i in 90:
		# The cursor hard over to the animal's left while the hand asks right.
		_point(cat, cat.head_pos + Vector2(20.0, -220.0))
		cat._physics_process(TICK)
		went += wrapf(cat.heading - faced, -PI, PI)
		faced = cat.heading
	_measure(cat)
	cat.command.throttle = 0.0
	cat.command.turn = 0.0
	_check(went > 0.3,
		"the head overrode the hand: asked hard right, the body went %.1f°"
			% rad_to_deg(went))
	notes.append("hand: %.0f° right with the cursor hard left" % rad_to_deg(went))
	_point(cat, Vector2.INF)


# ------------------------------------------------------------------ the bite ----

## The pick is made in the picture, off the same rings the painter draws — so
## the address the cursor lands on is the address a bite wounds through.
func _check_the_pick_is_made_in_the_picture(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey)
	# A known place on the prey's flank, taken to the picture and picked back up.
	var flank: Vector3 = prey.contour.place(BodySchema.TRUNK, 0.5, PI * 0.5)
	var cursor: Vector2 = Contour.seen(flank)
	var pick: Quarry.Pick = Quarry.pick(main.get_tree(), cursor, cat)
	_check(pick.creature == prey, "the cursor on a drawn flank picked %s"
		% ("nothing" if pick.creature == null else "the wrong body"))
	if pick.creature != prey:
		return
	_check(pick.contact["band"] == BodySchema.TRUNK,
		"a cursor on the trunk picked the %s" % pick.contact["band"])
	_check(absf(float(pick.contact["t"]) - 0.5) < 0.12,
		"the pick landed at t %.2f for a cursor on t 0.50" % float(pick.contact["t"]))
	_check(pick.height > 1.0,
		"the pick came back at ground height for a point up on the flank")

	# Bare floor well clear of everything is bare floor, and answers as ground
	# rather than by dragging the nearest animal under the pointer.
	var empty: Quarry.Pick = Quarry.pick(main.get_tree(),
		cat.head_pos + Vector2(0.0, 400.0), cat)
	_check(empty.creature == null, "a cursor on open floor selected a body")

	# ...and what the pointer cannot be got to is said before the button: the
	# same flesh, from further off than the purse pays for, comes back as a mark
	# brought in to the reach — on the aim line, inside what the maw will agree
	# to — with what was actually wanted kept behind it.
	_settle(cat, prey, Vector2(-260.0, 0.0), 0.0)
	var reachable: Vector3 = prey.contour.place(BodySchema.TRUNK, 0.5, PI * 0.5)
	var far: Quarry.Pick = Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(reachable), cat), cat)
	_check(far.beyond != null, "flesh two body lengths away was offered as reachable")
	if far.beyond != null:
		_check(far.beyond.creature == prey, "the mark forgot what it was brought in from")
		var root: Vector2 = cat.armature.plan(cat.armature.withers_index())
		_check(root.distance_to(far.at) <= cat.maw.plan_reach(far.height) + 0.5,
			"the mark stopped %.1f px out, past the %.1f px the mouth can be brought to"
				% [root.distance_to(far.at), cat.maw.plan_reach(far.height)])
		_check(absf(wrapf((far.at - root).angle()
			- (far.beyond.at - root).angle(), -PI, PI)) < 0.05,
			"the mark came in off the line it was pointed along")
	notes.append("pick: a cursor on the drawn flank names trunk t %.2f at z %.0f; open floor is ground; out of reach stops at the purse and keeps what was wanted"
		% [float(pick.contact["t"]), pick.height])


## A click bites what the pointer is on: the target loses flesh, and it loses it
## where the mark said it would.
func _check_the_click_bites_what_is_pointed_at(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey)
	# Somewhere on the prey the cat can actually get to, chosen the way a player
	# chooses it: by putting the pointer on the drawn body.
	var mouth: Dictionary = prey.contour.locate(
		Vector3(115.0, 5.0, cat.maw.jaw_point().z))
	var cursor: Vector2 = Contour.seen(mouth["at"])
	cat.aim_at(Quarry.resolve(Quarry.pick(main.get_tree(), cursor, cat), cat))
	_check(cat.aim != null and cat.aim.creature == prey,
		"the pointer on the prey's near flank did not select it")
	_check(cat.can_reach_aim(), "flesh at the jaws read as out of reach")
	var whole: float = prey.corpus.integrity()
	var was: Vector2 = cat.armature.plan(cat.armature.pelvis_index())
	_check(cat.request_bite(cursor), "the click was refused")
	_check(cat.is_lunging(), "the click did not throw a strike")
	var throw: float = cat.maw._throw
	_check(throw <= cat.maw.throw_cap() + 0.001,
		"the lunge (%.1f px) outran the support (%.1f px)"
			% [throw, cat.maw.throw_cap()])
	_tick_both(cat, prey, 20)
	var carried: float = cat.armature.plan(cat.armature.pelvis_index()).distance_to(was)
	_check(prey.corpus.integrity() < whole, "the bite took no flesh")
	_check(carried > 0.5 or throw < 1.0,
		"a %.1f px lunge moved the body %.1f px" % [throw, carried])
	notes.append("click: %.1f px thrown, body carried %.1f px, prey %.4f → %.4f whole"
		% [throw, carried, whole, prey.corpus.integrity()])


## A bite at nothing in particular is still a bite. The reach decides how the
## strike goes, never whether it goes — a click that did nothing at all would be
## indistinguishable from a click the game never received.
func _check_a_bite_at_nothing_is_still_thrown(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey, Vector2(-400.0, 0.0), 0.0)
	cat.aim_at(Quarry.resolve(Quarry.pick(main.get_tree(),
		cat.head_pos + Vector2(60.0, 0.0), cat), cat))
	_check(cat.aim != null and cat.aim.creature == null,
		"open floor in front of the animal selected a body")
	var was: Vector2 = cat.armature.plan(cat.armature.pelvis_index())
	_check(cat.request_bite(cat.head_pos + Vector2(60.0, 0.0)),
		"a strike at open ground was refused")
	_tick(cat, 20)
	var carried: float = cat.armature.plan(cat.armature.pelvis_index()).distance_to(was)
	_check(carried > 0.5, "the snap at nothing moved the body %.1f px" % carried)
	_check(cat.maw.holding.is_empty(), "the jaws came away from open ground holding something")
	notes.append("air: a snap at bare floor is thrown and carries the body %.1f px" % carried)


## The button is the grip: jaws that close while it is down keep what they
## closed on, and letting go lets go.
func _check_the_button_is_the_grip(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey, Vector2(12.0, 0.0), 0.0, Vector2(118.0, -28.0), PI / 2.0)
	prey.toggle_collapsed()
	prey.simulate(1.5)
	var mouth: Dictionary = prey.contour.locate(cat.maw.jaw_point())
	var cursor: Vector2 = Contour.seen(mouth["at"])
	cat.aim_at(Quarry.resolve(Quarry.pick(main.get_tree(), cursor, cat), cat))

	# Pressed and held: the strike goes, and what it closes on it keeps.
	cat.set_bite_held(true)
	_check(cat.request_bite(cursor), "the held click was refused")
	_tick_both(cat, prey, 20)
	_check(cat.is_bite_latched(), "the jaws closed with the button down and let go")
	# ...and it goes on holding while the button is down and nothing has asked
	# anything of it. Deliberately short of the first chew: how long a hold
	# survives being chewed and hauled on is the feeding claim, and CombatProbe
	# owns it. What is being pinned here is the button.
	_tick_both(cat, prey, 25)
	_check(cat.is_bite_latched(), "a held bite let go on its own")
	var fed: float = cat.maw.belly

	# Released: the same frame, no window, no ceremony.
	cat.set_bite_held(false)
	_check(not cat.is_bite_latched(), "releasing the button did not let go")
	_check(not cat.bite_held, "the body still thinks the button is down")

	# ...and a click with the button up bites without keeping anything.
	_settle(cat, prey, Vector2(12.0, 0.0), 0.0, Vector2(118.0, -28.0), PI / 2.0)
	prey.toggle_collapsed()
	prey.simulate(1.5)
	mouth = prey.contour.locate(cat.maw.jaw_point())
	cat.aim_at(Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(mouth["at"]), cat), cat))
	var whole: float = prey.corpus.integrity()
	cat.request_bite(Vector2(mouth["at"].x, mouth["at"].y))
	_tick_both(cat, prey, 30)
	_check(prey.corpus.integrity() < whole, "the unheld bite took no flesh")
	_check(not cat.is_bite_latched(), "a bite taken with the button up latched anyway")
	notes.append("grip: held closes and keeps (fed %.1f), released lets go on the frame; unheld bites and comes away"
		% fed)


# ------------------------------------------------------------------ helpers ----

## Points the animal at a world place — the whole of what the lab's cursor does
## to the body. INF is the pointer saying nothing at all.
func _point(c: Creature2, at: Vector2) -> void:
	c.command.aim_active = at.x < INF
	c.command.aim_world = at if at.x < INF else Vector2.ZERO
	if at.x >= INF:
		c.aim_at(null)


func _head_bearing(c: Creature2) -> float:
	var a: Armature = c.armature
	return (a.plan(a.head_index()) - a.plan(a.nape_index())).angle()


func _stand(at: Vector2, heading: float) -> Creature2:
	var c := Creature2.new()
	c.name = "Sparring"
	c.spawn_position = at
	c.spawn_heading = heading
	main.add_child(c)
	return c


func _settle_one(cat: Creature2) -> void:
	main.terrain.clear()
	_point(cat, Vector2.INF)
	cat.command.throttle = 0.0
	cat.command.turn = 0.0
	cat.command.sprint = false
	cat.command.jump = false
	cat.set_bite_held(false)
	if cat.armature.collapsed:
		cat.toggle_collapsed()
	cat.build(Vector2.ZERO, 0.0)
	_tick(cat, 20)


func _settle(cat: Creature2, prey: Creature2,
		cat_at: Vector2 = Vector2.ZERO, cat_heading: float = 0.0,
		prey_at: Vector2 = Vector2(115.0, -25.0),
		prey_heading: float = PI / 2.0) -> void:
	main.terrain.clear()
	_point(cat, Vector2.INF)
	cat.command.throttle = 0.0
	cat.command.turn = 0.0
	cat.command.sprint = false
	cat.command.jump = false
	cat.set_bite_held(false)
	if cat.armature.collapsed:
		cat.toggle_collapsed()
	if prey.armature.collapsed:
		prey.toggle_collapsed()
	cat.build(cat_at, cat_heading)
	prey.build(prey_at, prey_heading)
	cat.maw.release()
	_tick_both(cat, prey, 10)


func _tick(c: Creature2, n: int) -> void:
	for i in n:
		c._physics_process(TICK)
	_measure(c)


func _tick_both(a: Creature2, b: Creature2, n: int) -> void:
	for i in n:
		a._physics_process(TICK)
		b._physics_process(TICK)
	_measure(a)
	_measure(b)


func _measure(c: Creature2) -> void:
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())


func _check(ok: bool, complaint: String) -> void:
	if not ok:
		failures.append(complaint)


func _finish() -> void:
	print("")
	print("=== AimProbe ===")
	for note in notes:
		print("  · ", note)
	if failures.is_empty():
		print("AimProbe: all claims hold")
		quit(0)
		return
	print("AimProbe: %d FAILED" % failures.size())
	for f in failures:
		print("  FAIL — ", f)
	quit(1)
