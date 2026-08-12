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
##     and it comes home when the pointer stops saying anything.
##   * **the neck is the field** — the pointer drives the head inside the radius
##     the cervical joints deliver and not one degree outside it, where the head
##     keeps the bearing it was left on rather than straining after something it
##     cannot see.
##   * **the eye never steers** — the mouse moves the head and nothing else,
##     standing or walking, whatever it is pointed at and however long for. A and
##     D are the only thing that writes the heading.
##   * **the purse holds still** — what the mark draws and what the strike is
##     priced against is a property of the stance, so it does not breathe at the
##     stride's frequency while the player is aiming inside it.
##   * **the zone is the reach** — the arc the player is shown is the neck's own
##     rotation and the lunge's own distance, and everything inside it can
##     genuinely be bitten: swept round the animal at every bearing and out to
##     every distance, what the drawing promises and what the jaws deliver agree.
##   * **leaving the zone drops the target** — a cursor outside the arc selects
##     nothing at all, so there is no highlight and no line to anything; the
##     click still throws a lunge, along the head.
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
	_check_the_field_bounds_the_look(cat)
	_check_the_purse_holds_still(cat)
	_check_the_neck_alone_does_the_looking(cat)
	_check_the_look_never_steers(cat, prey)
	_check_the_hand_is_the_only_steer(cat, prey)
	_check_the_zone_is_the_reach(cat, prey)
	_check_leaving_the_zone_drops_the_target(cat, prey)
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


## The aiming radius: the cursor has the head inside the animal's own field and
## has nothing to say about it outside, where the neck simply keeps the bearing
## it was left on.
##
## The failure this pins is a specific one. Clamp the ask to the limit instead
## and the head goes on following a cursor it cannot reach, pinned at the edge of
## its range — until the pointer crosses the line dead astern, where the ask
## flips sign and the head whips from one shoulder to the other for a pixel of
## mouse movement. So the sweep below goes all the way round.
func _check_the_field_bounds_the_look(cat: Creature2) -> void:
	_settle_one(cat)
	var most: float = cat.gaze.radius()
	_check(most > deg_to_rad(20.0) and most <= Gaze.MAX_ANGLE + 0.001,
		"the aiming radius came back as %.0f°" % rad_to_deg(most))
	_check(most <= cat.armature.neck_sweep() + 0.001,
		"the field is wider than the neck that has to deliver it")

	# Well inside: the head is on the cursor, and on it accurately.
	_bearing(cat, most * 0.7)
	_tick(cat, 60)
	_check(cat.gaze.tracking, "a pointer well inside the field was not tracked")
	_check(absf(absf(cat.gaze.craned) - most * 0.7) < deg_to_rad(3.0),
		"the head sat %.0f° off a cursor %.0f° out"
			% [rad_to_deg(cat.gaze.craned), rad_to_deg(most * 0.7)])

	# ...and now round the back of the animal, a couple of degrees at a time. The
	# head must leave the cursor at the edge of the field, must not move again
	# while the body is still, and must never jump.
	var left_at: float = 0.0
	var worst: float = 0.0
	var held: float = cat.gaze.angle
	var after: float = INF
	for step in 100:
		_bearing(cat, most * 0.7 + deg_to_rad(2.0 * float(step + 1)))
		cat._physics_process(TICK)
		worst = maxf(worst, absf(wrapf(cat.gaze.angle - held, -PI, PI)))
		held = cat.gaze.angle
		if not cat.gaze.tracking and left_at == 0.0:
			left_at = absf(cat.gaze.craned)
			after = cat.gaze.angle
	_measure(cat)
	_check(not cat.gaze.tracking,
		"a cursor swept two hundred degrees round the animal was still driving its head")
	_check(left_at > most - deg_to_rad(6.0),
		"the head let go of the cursor at %.0f°, well inside its %.0f° field"
			% [rad_to_deg(left_at), rad_to_deg(most)])
	_check(absf(wrapf(cat.gaze.angle - after, -PI, PI)) < deg_to_rad(2.0),
		"a head left off the cursor drifted %.1f° while the body stood still"
			% rad_to_deg(wrapf(cat.gaze.angle - after, -PI, PI)))
	_check(worst <= Gaze.SWEEP_RATE * TICK + 0.001,
		"the head moved %.1f° in one tick — that is a snap, not a look"
			% rad_to_deg(worst))
	_check(absf(cat.gaze.craned) <= most + 0.001,
		"the head was carried %.0f° past a %.0f° neck"
			% [rad_to_deg(cat.gaze.craned), rad_to_deg(most)])
	# ...and the neck is still being held there rather than handed back: a head
	# holding a bearing is very much being held on it.
	_check(not is_nan(cat.armature.look),
		"the neck was given back while the head was still holding a bearing")
	notes.append("field: %.0f° either way; the head tracks inside it, lets go at %.0f° and holds, worst tick %.1f°"
		% [rad_to_deg(most), rad_to_deg(left_at), rad_to_deg(worst)])
	_point(cat, Vector2.INF)


## The purse a player aims inside holds still.
##
## `Maw.plan_reach` is what the mark draws its arc at and what the strike is
## priced against, so a purse that breathes is a target that breathes. It used to
## be read off `Poise.clearance` — the plumb line's margin inside the polygon its
## planted toes make — and that polygon collapses to a line every time the gait
## has two feet off the ground, which is most of a walk: the drawn arc swung
## better than two to one, twice a second, while nothing about the animal's
## ability to lunge had changed at all.
func _check_the_purse_holds_still(cat: Creature2) -> void:
	_settle_one(cat)
	var standing: float = cat.maw.plan_reach(0.0)
	_check(standing > 10.0, "a standing animal's purse measured %.1f px" % standing)

	cat.command.throttle = 1.0
	var lo: float = INF
	var hi: float = -INF
	for i in 300:
		cat._physics_process(TICK)
		# Past the settle from standing to walking, which is a real change and
		# not a flicker: what is being pinned is the ripple, not the level.
		if i >= 120:
			var r: float = cat.maw.plan_reach(0.0)
			lo = minf(lo, r)
			hi = maxf(hi, r)
	_measure(cat)
	cat.command.throttle = 0.0
	var ripple: float = (hi - lo) / maxf((hi + lo) * 0.5, 1.0)
	_check(ripple < 0.15,
		"the drawn purse swung %.0f%% (%.1f–%.1f px) over a steady walk"
			% [ripple * 100.0, lo, hi])
	notes.append("purse: %.1f px standing, %.1f–%.1f px through a walk — %.0f%% ripple"
		% [standing, lo, hi, ripple * 100.0])
	_settle_one(cat)


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


## The mouse aims the head. It does not steer, rotate or move the body — not
## standing, not walking, not held on one bearing for four seconds, and not when
## it is pointed at something the neck cannot even see.
##
## This is the claim the whole control scheme rests on, and it is stated as a
## *walking* one because standing is the easy half: an animal that is not going
## anywhere has nothing for a stray demand to spoil. The old failure was
## deliberate and still worth pinning against — `Gaze.lead` used to hand the
## turn a proportional demand, so a player crossing the lab and glancing at
## something off to one side had their walk quietly re-aimed under them by the
## look. Whatever `heading` does here now, the cursor has to have had no part in
## it, so the cursor is swung right round the animal while it walks and the
## heading is required not to notice.
func _check_the_look_never_steers(cat: Creature2, prey: Creature2) -> void:
	# Walking straight ahead, with the pointer swept all the way round the
	# animal: through its own field, out the far side and back astern.
	#
	# The other body is parked well out of the way first, and that is not
	# housekeeping — a walking animal that runs into another one is yawed by the
	# contact (`Clash`), which is a real turn the mouse had nothing to do with and
	# would be read here as the look steering.
	_park(cat, prey)
	var faced: float = cat.heading
	var went: float = 0.0
	var worst: float = 0.0
	cat.command.throttle = 1.0
	for i in 240:
		_bearing(cat, deg_to_rad(-180.0 + 1.5 * float(i)))
		cat._physics_process(TICK)
		went += wrapf(cat.heading - faced, -PI, PI)
		faced = cat.heading
		worst = maxf(worst, absf(cat.ang_vel))
	_measure(cat)
	cat.command.throttle = 0.0
	_point(cat, Vector2.INF)
	_check(absf(went) < deg_to_rad(2.0),
		"a cursor swept right round a walking animal steered it %.1f°"
			% rad_to_deg(went))
	_check(worst < 0.01,
		"looking about put %.3f rad/s of turn into a walking body" % worst)

	# ...and the same, standing, held on one bearing well outside the field so the
	# head has given up on it. That is precisely where the old lead was loudest:
	# the head off the cursor was the signal to turn the *body* after it.
	_park(cat, prey)
	var stood: Vector2 = cat.centre()
	faced = cat.heading
	var astern: Vector2 = cat.head_pos - Vector2.RIGHT.rotated(cat.heading) * 300.0
	for i in 240:
		_point(cat, astern)
		cat._physics_process(TICK)
	_measure(cat)
	var idle: float = absf(wrapf(cat.heading - faced, -PI, PI))
	var drifted: float = cat.centre().distance_to(stood)
	_check(not cat.gaze.tracking,
		"the head was still tracking a cursor dead astern of the animal")
	_check(idle < deg_to_rad(2.0),
		"a standing animal turned %.1f° toward something behind it" % rad_to_deg(idle))
	_check(drifted < 4.0,
		"a standing animal was towed %.1f px by looking behind itself" % drifted)
	notes.append("steering: a cursor swept 360° round a walking animal moves the heading %.1f°; held astern of a standing one, %.1f° and %.1f px"
		% [rad_to_deg(absf(went)), rad_to_deg(idle), drifted])
	_point(cat, Vector2.INF)


## A and D are the whole of the steering, and they are deliberate about it: the
## body comes round at a rate an animal could plausibly turn at, it builds and
## decays rather than switching on and off, and the heading it writes is one the
## body itself can keep up with.
##
## The last of those is the one that was wrong rather than merely fast. `heading`
## is an open-loop integral and the trunk follows it only as fast as the feet
## will walk it round, so asking for 264°/s on the spot gave a logical facing
## that had run away from the drawn animal — every contact, gait and aim in the
## game quoting a direction the creature was visibly not pointing. The rate is
## bounded here by what the *back* actually does, which is why this is a claim
## about the body and not about a constant.
func _check_the_hand_is_the_only_steer(cat: Creature2, prey: Creature2) -> void:
	for throttle in [0.0, 1.0]:
		_park(cat, prey)
		cat.command.throttle = throttle
		_tick(cat, 60)
		var faced: float = cat.heading
		var back_was: float = _back_bearing(cat)
		# Accumulated rather than differenced: a turn held for two seconds can go
		# past a half circle, and the wrapped difference would report that as
		# having gone the other way.
		var went: float = 0.0
		var body: float = 0.0
		var jerk: float = 0.0
		var was_rate: float = cat.ang_vel
		cat.command.turn = 1.0
		for i in 120:
			cat._physics_process(TICK)
			went += wrapf(cat.heading - faced, -PI, PI)
			faced = cat.heading
			body += wrapf(_back_bearing(cat) - back_was, -PI, PI)
			back_was = _back_bearing(cat)
			jerk = maxf(jerk, absf(cat.ang_vel - was_rate) / TICK)
			was_rate = cat.ang_vel
		_measure(cat)
		cat.command.turn = 0.0
		var rate: float = rad_to_deg(absf(went) / 2.0)
		var label: String = "standing" if throttle == 0.0 else "walking"
		_check(rate > 30.0,
			"%s, two seconds of hard turn came to %.0f°/s — the animal cannot steer"
				% [label, rate])
		_check(rate < 130.0,
			"%s, A and D spun the body at %.0f°/s" % [label, rate])
		# The body kept up: whatever is left between the heading and the back has
		# to be the *steer* — the front of the animal ahead of the back of it —
		# and not the heading running away from the whole creature.
		var lag: float = rad_to_deg(absf(went) - absf(body))
		_check(lag < 25.0,
			"%s, the heading ran %.0f° ahead of the back it is supposed to describe"
				% [label, lag])
		# ...and it got there gradually. A rate that can change by more than its
		# own ceiling in a second is a switch, not a body with any weight in it.
		_check(jerk < deg_to_rad(cat.body.turn_speed_deg) * 8.0,
			"%s, the turn rate jumped %.0f°/s² — that is a switch, not a body"
				% [label, rad_to_deg(jerk)])
		notes.append("%s turn: %.0f°/s, back within %.0f° of it, worst ramp %.0f°/s²"
			% [label, rate, lag, rad_to_deg(jerk)])

	# Letting go settles out rather than stopping dead — the other half of the
	# same weight, and what stops a tap on the key reading as a twitch.
	_park(cat, prey)
	cat.command.turn = 1.0
	_tick(cat, 60)
	var spinning: float = absf(cat.ang_vel)
	cat.command.turn = 0.0
	cat._physics_process(TICK)
	_measure(cat)
	_check(absf(cat.ang_vel) > spinning * 0.5,
		"the turn stopped dead the frame the key came up")
	_tick(cat, 60)
	_check(absf(cat.ang_vel) < deg_to_rad(2.0),
		"a second after the key came up the body was still turning at %.1f°/s"
			% rad_to_deg(absf(cat.ang_vel)))


# ------------------------------------------------------------------ the bite ----

## The bite zone the player is shown is the bite the animal has.
##
## Two numbers make the arc — `Maw.window` for its sweep and `Maw.plan_reach` for
## its radius — and the whole claim is that they are not a picture *of* the reach
## test but the reach test itself, so anything drawn inside can be bitten and
## anything that cannot be bitten is drawn outside. Checked in both directions,
## because the two failures are quite different: an arc that promises too much
## makes every refusal feel like a bug, and one that promises too little hides
## reach the animal actually has.
##
## The sweep is checked against the anatomy rather than against a constant. It
## used to be drawn at `ADDRESS_CONE` — the frontal cone, 100° a side — while the
## thing that actually has to deliver the bite is the neck, which on this animal
## gives 82°: eighteen degrees a side of arc that was never reachable.
func _check_the_zone_is_the_reach(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey)
	var span: Vector2 = cat.maw.window()
	var half: float = (span.y - span.x) * 0.5
	var field: float = cat.gaze.radius()
	_check(half <= field + 0.001,
		"the zone sweeps %.0f° a side off a neck that turns %.0f°"
			% [rad_to_deg(half), rad_to_deg(field)])
	_check(half > field - deg_to_rad(2.0),
		"the zone gave away %.0f° of a neck that turns %.0f°"
			% [rad_to_deg(field - half), rad_to_deg(field)])
	_check(half <= Maw.ADDRESS_CONE + 0.001,
		"the zone reaches past the cone a body can face")
	# The radius is the animal's own three terms and not a number: arm, lunge and
	# gape, which is exactly what `reach` adds up.
	var reach: float = cat.maw.reach()
	var arm: float = cat.body.neck_length + cat.body.head_offset
	_check(absf(reach - (arm + cat.maw.throw_cap()
		+ cat.maw.muzzle_reach() * Maw.GRAB)) < 0.001,
		"the drawn radius is not the arm, the lunge and the gape")
	_check(cat.maw.throw_cap() > 1.0,
		"the zone was drawn with no lunge in it at all")

	# ...and now the two directions, swept round the animal. The prey is stood at
	# a bearing and a distance, and what the drawing says about the flesh under
	# the cursor has to be what the jaws say about it.
	var root: Vector2 = cat.maw.purse_root()
	var promised: int = 0
	var tested: int = 0
	var lied: int = 0
	var hid: int = 0
	for step in 24:
		var bearing: float = cat.heading + deg_to_rad(-180.0 + 15.0 * float(step))
		# Rings from just clear of the animal's own flesh out to half again past
		# what it can reach, so the boundary is crossed at every bearing. Nothing
		# nearer, because two bodies inside one another are being shoved apart by
		# the contact solver and the pose under the cursor is not a settled one.
		for out in [0.85, 1.0, 1.15, 1.5]:
			_settle(cat, prey, Vector2.ZERO, 0.0,
				root + Vector2.RIGHT.rotated(bearing) * (reach * out), bearing + PI)
			# Where the jaws would actually meet it, which is the point both the
			# mark and the strike are asked about.
			var seat: Dictionary = prey.contour.locate(cat.maw.jaw_point())
			if seat.is_empty():
				continue
			var flesh: Vector3 = seat["at"]
			var at := Vector2(flesh.x, flesh.y)
			var toward: Vector2 = at - cat.maw.purse_root()
			# Inside the drawing: inside the sweep, inside the radius at its
			# height. Exactly the two things `AimMark` strokes.
			var drawn: bool = cat.maw.addressable(toward.angle()) \
				and toward.length() <= cat.maw.plan_reach(flesh.z)
			var takeable: bool = bool(cat.maw.aim(prey, at).get("ok", false))
			tested += 1
			if drawn:
				promised += 1
			# A hair inside the boundary either way is not a lie, it is a float:
			# only disagreements with room in them are counted.
			var margin: float = absf(toward.length() - cat.maw.plan_reach(flesh.z))
			if drawn and not takeable and margin > 1.0:
				lied += 1
			if takeable and not drawn and margin > 1.0:
				hid += 1
	_check(promised > 8,
		"only %d of %d places round the animal were drawn as reachable at all"
			% [promised, tested])
	_check(lied == 0,
		"%d places were drawn inside the zone that the jaws then refused" % lied)
	_check(hid == 0,
		"%d places the jaws would take were drawn outside the zone" % hid)
	notes.append("zone: %.0f° a side off an %.0f° neck, %.1f px of arm + lunge + gape; %d of %d places round the animal inside it, 0 promised and refused, 0 reachable and hidden"
		% [rad_to_deg(half), rad_to_deg(field), reach, promised, tested])
	_settle(cat, prey)


## A cursor outside the zone has no target. Not a target drawn faintly, not a
## target with a line running off to it — none.
##
## The mark used to bring itself in to the edge of the purse and dot a line on to
## whatever had been pointed at, which read as a selection and was not one: the
## strike does not go to that flesh and the highlight was tracing a body the jaws
## could not touch. So the target is dropped, and what the player gets instead is
## the one honest thing left — a refusal where they are pointing.
##
## The click is not swallowed with it. An animal that has committed to a lunge
## lunges; it simply lunges where its head is, which is the only direction its
## jaws were ever going to arrive from.
func _check_leaving_the_zone_drops_the_target(cat: Creature2, prey: Creature2) -> void:
	# Inside first, so the difference is the cursor moving and nothing else.
	_settle(cat, prey, Vector2.ZERO, 0.0, Vector2(60.0, 0.0), PI)
	var near: Vector3 = prey.contour.locate(cat.maw.jaw_point())["at"]
	var inside: Quarry.Pick = Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(near), cat), cat)
	cat.aim_at(inside)
	_check(inside.creature == prey, "flesh at the jaws was not selected at all")
	_check(not inside.outside, "flesh at the jaws read as outside the zone")
	_check(cat.can_reach_aim(), "flesh at the jaws read as out of reach")

	# ...and now the sweep on its own, on bare floor, so nothing about distance or
	# height is involved: a place *behind* the animal and comfortably inside the
	# radius is refused for being behind it and for no other reason.
	var root: Vector2 = cat.maw.purse_root()
	var astern: Vector2 = root - Vector2.RIGHT.rotated(cat.heading) \
		* (cat.maw.plan_reach(0.0) * 0.5)
	_check(not cat.maw.addressable((astern - root).angle()),
		"a place dead astern was inside the bite zone's sweep")
	var floor_pick: Quarry.Pick = Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(Vector3(astern.x, astern.y, 0.0)), cat), cat)
	_check(floor_pick.outside,
		"floor half a reach behind the animal was offered as reachable")

	# The target itself, dropped. The other animal is put out past the radius so
	# the two bodies are not shoving each other while the claim is being made;
	# what is being pinned here is not which gate refused it but what is left of
	# the selection afterwards, which is nothing.
	_settle(cat, prey, Vector2.ZERO, 0.0, Vector2(300.0, 0.0), PI)
	var far_off: Vector3 = prey.contour.place(BodySchema.TRUNK, 0.5, PI * 0.5)
	var raw: Quarry.Pick = Quarry.pick(main.get_tree(), Contour.seen(far_off), cat)
	_check(raw.creature == prey, "the cursor was not on the far animal at all")
	var dropped: Quarry.Pick = Quarry.resolve(raw, cat)
	cat.aim_at(dropped)
	_check(dropped.creature == null,
		"flesh two body lengths off was kept as a selected target")
	_check(dropped.contact.is_empty(),
		"a dropped target kept the body address a highlight would be traced from")
	_check(dropped.outside, "a target outside the zone was not marked out of reach")
	_check(not cat.can_reach_aim(), "a cursor outside the zone read as reachable")
	_check(dropped.at.is_equal_approx(raw.at),
		"the marker wandered off the place the player is pointing at")

	# ...and the click still goes, along the head. Pointed hard astern, where the
	# neck has given up on the cursor: the body has to move the way it is facing
	# rather than sideways at something it cannot see.
	_park(cat, prey)
	var aimed: Vector2 = cat.maw.purse_root() \
		- Vector2.RIGHT.rotated(cat.heading) * 120.0
	_point(cat, aimed)
	_tick(cat, 30)
	cat.aim_at(Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(Vector3(aimed.x, aimed.y, 0.0)), cat), cat))
	_check(not cat.can_reach_aim(), "the floor dead astern read as reachable")
	var stood: Vector2 = cat.centre()
	var nose: Vector2 = cat.armature.fwd[cat.armature.head_index()]
	_check(cat.request_bite(aimed), "a click outside the zone was swallowed")
	_tick_both(cat, prey, 20)
	var carried: Vector2 = cat.centre() - stood
	_check(carried.length() > 2.0,
		"the lunge outside the zone moved the body %.1f px" % carried.length())
	_check(carried.normalized().dot(nose) > 0.7,
		"the lunge went %.0f° off the way the head was pointing"
			% rad_to_deg(absf(wrapf(carried.angle() - nose.angle(), -PI, PI))))
	notes.append("zone edge: flesh at the jaws is a target; floor half a reach astern is refused for being astern; flesh two lengths off is no target at all — no address, nothing for a line to reach; the click still throws %.1f px along the head"
		% carried.length())
	_point(cat, Vector2.INF)
	_settle(cat, prey)


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

	# ...and bare floor is asked the same question by the same zone: a place on
	# the ground inside the arc is a place the mouth can be put, and one outside
	# it is a refusal said where the player is pointing.
	_settle(cat, prey)
	var root: Vector2 = cat.maw.purse_root()
	var ahead: Vector2 = Vector2.RIGHT.rotated(cat.heading)
	var close: Quarry.Pick = Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(Vector3(root.x + ahead.x * 20.0, root.y + ahead.y * 20.0, 0.0)),
		cat), cat)
	_check(not close.outside, "floor under the animal's nose read as out of reach")
	var away: Vector2 = root + ahead * (cat.maw.plan_reach(0.0) + 60.0)
	var yonder: Quarry.Pick = Quarry.resolve(Quarry.pick(main.get_tree(),
		Contour.seen(Vector3(away.x, away.y, 0.0)), cat), cat)
	_check(yonder.outside, "floor well past the purse was offered as reachable")
	notes.append("pick: a cursor on the drawn flank names trunk t %.2f at z %.0f; open floor is ground, reachable under the nose and refused past the purse"
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


## Puts the cursor at a bearing `off` off the animal's own shoulders, which is
## the datum the field is measured from — so a sweep here is a sweep through the
## creature's frame rather than through the world's.
func _bearing(c: Creature2, off: float) -> void:
	var a: Armature = c.armature
	var datum: float = a.fwd[a.withers_index()].angle()
	_point(c, a.plan(a.nape_index()) + Vector2.RIGHT.rotated(datum + off) * 240.0)


func _head_bearing(c: Creature2) -> float:
	var a: Armature = c.armature
	return (a.plan(a.head_index()) - a.plan(a.nape_index())).angle()


## The way the animal's own back is pointing — hips to shoulders. What `heading`
## is a claim *about*, and the only honest thing to measure it against.
func _back_bearing(c: Creature2) -> float:
	var a: Armature = c.armature
	return (a.plan(a.withers_index()) - a.plan(a.pelvis_index())).angle()


func _stand(at: Vector2, heading: float) -> Creature2:
	var c := Creature2.new()
	c.name = "Sparring"
	c.spawn_position = at
	c.spawn_heading = heading
	main.add_child(c)
	return c


## The cat on its own, with the other body put somewhere it cannot be walked
## into. For the movement claims, where a contact with another animal is a
## genuine turn arriving from somewhere that is not the controls.
func _park(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey, Vector2.ZERO, 0.0, Vector2(0.0, 1200.0), 0.0)


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
