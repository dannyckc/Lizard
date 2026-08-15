## Phase-5 gate for v2 damage & combat — see docs/V2_DESIGN.md §11.2.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/CombatProbe.gd
##
## The CombatTest / BiteReachTest / FeedingTest claims, re-expressed against
## the one census — behaviours, not constants:
##
##   * **what is hit is what is displayed** — the hit test resolves world
##     points on the same posed rings every view draws: a surface point
##     round-trips to its own column, a point over the animal's back is air
##     where the same plan point at flank height is flesh, and a bitten ring
##     is thinner by exactly the flesh the census lost.
##   * **contacts are 2.5D flesh, not silhouettes** — two standing bodies
##     press apart to their real girths, both of them moving by their mass
##     shares; the same two overlapping in *plan* never touch while one is
##     airborne above the other, because capsule distance is taken in three
##     dimensions off the posed sticks.
##   * **the bite is one 3D contact point** — anchored at the jaws even from
##     inside the body (the underbody lesson); verticals gate before
##     horizontals (a back too tall is refused as height, never chased); the
##     neck is an arc, so the same horizontal gap connects at mouth level and
##     is refused onto the floor.
##   * **the lunge is the body moving** — a strike carries the pelvis, not a
##     stretched neck, and the throw is capped by the support.
##   * **wound depth is the tooth/layer math** — a wound spends skin, then
##     fat, then muscle, then bone, exactly as deep as it is; the surface
##     dents by exactly what was taken; the next bite lands deeper.
##   * **anatomy kills, not rules** — a throat bite breaches the carotid and
##     the animal bleeds out to arrest; the heart is safe behind the ribs
##     until repeated bites are through them, and the hit that reaches it
##     stops it. Death is a stopped heart, and a stopped heart is a collapse.
##   * **a cut nerve is a dead leg** — severing the sciatic drops the planted
##     grip without touching the flesh.
##   * **feeding is possession** — a latched hold follows the flesh as a body
##     address, tows the carcass when the holder walks, feeds the belly by
##     exactly the mass the carcass census lost, and tears free through the
##     flesh when pulled past what flesh holds.
##   * **anatomy holds throughout** — every stick, bend and bone exact after
##     all of it, on both bodies.
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

	_check_hit_test_is_the_drawn_body(prey)
	_check_contacts_press_flesh_apart(cat, prey)
	_check_airborne_clears_what_plan_overlaps(cat, prey)
	_check_bite_anchors_at_the_jaws(cat, prey)
	_check_verticals_gate_before_horizontals(cat, prey)
	_check_the_lunge_is_the_body_moving(cat, prey)
	_check_wound_depth_is_layer_math(prey)
	_check_a_bite_dents_what_it_bit(cat, prey)
	_check_throat_bite_bleeds_out(cat, prey)
	_check_ribs_guard_the_heart_until_they_do_not(cat, prey)
	_check_a_cut_nerve_is_a_dead_leg(cat, prey)
	_check_feeding_is_possession(cat, prey)

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


# ------------------------------------------------------------------ helpers ----

func _stand(at: Vector2, heading: float) -> Creature2:
	var c := Creature2.new()
	c.name = "Sparring"
	c.spawn_position = at
	c.spawn_heading = heading
	main.add_child(c)
	return c


## Both bodies rebuilt standing where the scenario wants them, settled a beat.
func _settle(cat: Creature2, prey: Creature2,
		cat_at: Vector2 = Vector2.ZERO, cat_heading: float = 0.0,
		prey_at: Vector2 = Vector2.INF,
		prey_heading: float = PI / 2.0) -> void:
	main.terrain.clear()
	cat.command.throttle = 0.0
	cat.command.turn = 0.0
	cat.command.sprint = false
	cat.command.jump = false
	if cat.armature.collapsed:
		cat.toggle_collapsed()
	if prey.armature.collapsed:
		prey.toggle_collapsed()
	cat.build(cat_at, cat_heading)
	if prey_at.x == INF:
		# A strike's-length stand-off, quoted off this cat's own jaw rather
		# than pinned: these scenarios once stood the prey at 115 px, which
		# was really "the old neck's jaw plus a lunge" — scaffolding that went
		# red the day the neck was re-authored to real anatomy.
		prey_at = Vector2(cat.maw.jaw_point().x + 24.0, cat_at.y - 25.0)
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


## Deepest trunk-against-trunk overlap between two bodies, px — the honest
## interpenetration reading, off the same capsules Clash presses with.
func _trunk_overlap(a: Creature2, b: Creature2) -> float:
	var deepest: float = -INF
	var ta: Armature.Chain = a.armature.chain(BodySchema.TRUNK)
	var tb: Armature.Chain = b.armature.chain(BodySchema.TRUNK)
	for s in ta.sticks:
		var ra: float = (a.armature.flesh_r[a.armature.stick_a[s]]
			+ a.armature.flesh_r[a.armature.stick_b[s]]) * 0.5
		for z in tb.sticks:
			var rb: float = (b.armature.flesh_r[b.armature.stick_a[z]]
				+ b.armature.flesh_r[b.armature.stick_b[z]]) * 0.5
			var near: Array = Clash._segment_gap(
				a.armature.pos[a.armature.stick_a[s]],
				a.armature.pos[a.armature.stick_b[s]],
				b.armature.pos[b.armature.stick_a[z]],
				b.armature.pos[b.armature.stick_b[z]])
			deepest = maxf(deepest, ra + rb - float(near[0]))
	return deepest


func _check(ok: bool, complaint: String) -> void:
	if not ok:
		failures.append(complaint)


func _finish() -> void:
	print("")
	print("=== CombatProbe ===")
	for note in notes:
		print("  · ", note)
	if failures.is_empty():
		print("CombatProbe: all claims hold")
		quit(0)
		return
	print("CombatProbe: %d FAILED" % failures.size())
	for f in failures:
		print("  FAIL — ", f)
	quit(1)


# ------------------------------------------------------------------- claims ----

## The hit test reads the same rings the painter does: a drawn surface point
## resolves to its own column at depth ~0, air above the back is air, and the
## address goes back out to the same world point.
func _check_hit_test_is_the_drawn_body(prey: Creature2) -> void:
	var skin: Contour = prey.contour
	var band: Contour.Band = skin.band(BodySchema.TRUNK)
	var r: int = band.first + band.count / 2
	var s: int = band.right
	var point: Vector3 = skin.surface[skin.ring_base[r] + s]
	var found: Dictionary = skin.locate(point)
	_check(not found.is_empty() and found["band"] == BodySchema.TRUNK,
		"a trunk surface point resolved off the trunk")
	if found.is_empty():
		return
	_check(absf(float(found["depth"])) < 0.4,
		"a drawn surface point sat %.2f px off its own surface" % float(found["depth"]))
	_check(found["sector"] == s,
		"sector round-trip: put in %d, got %d" % [s, found["sector"]])
	_check(absi(int(found["station"]) - skin.ring_station[r]) <= 1,
		"station round-trip strayed: ring says %d, locate says %d"
			% [skin.ring_station[r], found["station"]])
	var back: Vector3 = skin.place(BodySchema.TRUNK, found["t"], found["theta"])
	_check(back.distance_to(point) < 0.6,
		"place() put the address %.2f px from where locate() read it"
			% back.distance_to(point))
	# The third dimension: the same plan point, 30 px higher, is air.
	var high: Dictionary = skin.locate(point + Vector3(0.0, 0.0, 30.0))
	_check(float(high["depth"]) < -15.0,
		"a point 30 px over the back still read as flesh (depth %.1f)"
			% float(high["depth"]))
	notes.append("hit test: round-trip %.3f px, depth on-surface %.3f, air above is air"
		% [back.distance_to(point), absf(float(found["depth"]))])


## Two standing bodies pressed into each other separate to their real girths,
## and both of them move — the separation is shared by mass, not assigned.
## Built into each other and measured at the build, before either has had a
## tick to answer.
func _check_contacts_press_flesh_apart(cat: Creature2, prey: Creature2) -> void:
	main.terrain.clear()
	if prey.armature.collapsed:
		prey.toggle_collapsed()
	cat.build(Vector2.ZERO, 0.0)
	prey.build(Vector2(20.0, 12.0), 0.0)
	var was: float = _trunk_overlap(cat, prey)
	_check(was > 2.0, "the press scenario failed to overlap the bodies (%.1f px)" % was)
	var cat_start: Vector2 = cat.centre()
	var prey_start: Vector2 = prey.centre()
	_tick_both(cat, prey, 150)
	var left: float = _trunk_overlap(cat, prey)
	_check(left <= 0.8,
		"two standing trunks still interpenetrate %.2f px after 2.5 s" % left)
	_check(cat.centre().distance_to(cat_start) > 1.0
			and prey.centre().distance_to(prey_start) > 1.0,
		"the press moved only one of the two bodies")
	notes.append("press: %.1f px of trunk overlap resolved to %.2f, both bodies moved"
		% [was, left])


## The same two bodies overlapping in plan never touch while one is airborne
## above the other — the claim that contacts are not flat silhouettes.
func _check_airborne_clears_what_plan_overlaps(cat: Creature2,
		prey: Creature2) -> void:
	main.terrain.clear()
	prey.build(Vector2(60.0, 0.0), 0.0)
	cat.build(Vector2(68.0, 6.0), 0.0)
	cat.drop(140.0)
	# Two ticks first: a drop is a teleport, and the Z channel applies it a
	# stage after the contacts read it — the claim starts once the body is
	# honestly in the air.
	cat._physics_process(TICK)
	cat._physics_process(TICK)
	var plan_gap: float = cat.centre().distance_to(prey.centre())
	_check(plan_gap < 40.0, "the airborne scenario failed to overlap the plans")
	var start: Vector2 = cat.centre()
	var pushed: float = 0.0
	# Measured while even a fully dangled leg clears the other body's back —
	# lower than that the toes genuinely graze it, which is the same claim
	# from the other side.
	for i in 10:
		cat._physics_process(TICK)
		if cat.armature.fall.height > 70.0:
			pushed = maxf(pushed, cat.centre().distance_to(start))
	_check(pushed < 0.6,
		"an airborne body was pressed %.2f px sideways by flesh far below it"
			% pushed)
	# ...and the moment it is down among the other body's flesh, it is pressed.
	_tick_both(cat, prey, 150)
	var after: float = cat.centre().distance_to(prey.centre())
	_check(after > plan_gap + 3.0,
		"landing among another body's flesh did not press the two apart "
		+ "(%.1f → %.1f px)" % [plan_gap, after])
	notes.append("2.5D: airborne over a body, %.2f px of push; landed, pressed %.1f → %.1f px apart"
		% [pushed, plan_gap, after])


## A mouth inside the body's envelope anchors its contact at the mouth — the
## underbody lesson: the near flesh, never the far flank.
func _check_bite_anchors_at_the_jaws(cat: Creature2, prey: Creature2) -> void:
	main.terrain.clear()
	cat.build(Vector2.ZERO, 0.0)
	# The prey stands so its near flank covers the cat's jaw — placed off the
	# cat's own measured jaw point rather than at a pinned distance, so the
	# scenario is about the anchoring mechanism and survives a proportion
	# re-author (it was pinned at 97 px once, which was the *old* neck).
	prey.build(Vector2(cat.maw.jaw_point().x + 7.0, -25.0), PI / 2.0)
	# Carry the head down into the prey's height band, where its trunk is —
	# straight through the Z channel, with no tick for the bodies to press
	# each other back out of the overlap first.
	var trunk_z: float = prey.armature.pos[prey.armature.withers_index()].z
	cat.armature.head_reach_z = trunk_z
	cat.armature.carry(0.0)
	var jaw: Vector3 = cat.maw.jaw_point()
	var found: Dictionary = prey.contour.locate(jaw)
	_check(not found.is_empty() and float(found["depth"]) > 0.0,
		"the underbody scenario failed to put the jaw inside the flesh")
	if found.is_empty():
		return
	var near: Vector3 = found["at"]
	var far: Vector3 = (found["centre"] as Vector3) * 2.0 - near
	_check(jaw.distance_to(near) < jaw.distance_to(far),
		"a bite from inside the envelope anchored at the far flank")
	notes.append("underbody: jaw %.1f px inside, anchored %.1f px away (far flank %.1f)"
		% [float(found["depth"]), jaw.distance_to(near), jaw.distance_to(far)])


## Verticals gate before horizontals, and the neck is an arc: a back too tall
## is refused as height at close plan range, and the same horizontal gap that
## connects at mouth level is refused onto the floor.
func _check_verticals_gate_before_horizontals(cat: Creature2,
		prey: Creature2) -> void:
	# The tall back: the prey on a platform, flank higher than the carry.
	main.terrain.clear()
	main.terrain.add(Vector2(420.0, 300.0), 50.0, 70.0, 0.0, "perch")
	prey.build(Vector2(420.0, 300.0), PI / 2.0)
	cat.build(Vector2(300.0, 290.0), 0.0)
	_tick_both(cat, prey, 8)
	var flank: Dictionary = prey.contour.locate(
		Vector3(420.0, 290.0, cat.maw.jaw_point().z))
	var seen: Dictionary = cat.maw.aim(prey, Vector2(420.0, 290.0))
	_check(not bool(seen["ok"]) and String(seen["why"]) == "height",
		"a flank %.0f px up was answered '%s', not 'height'"
			% [float(flank["at"].z), String(seen.get("why", "ok"))])
	var tall_z: float = float(flank["at"].z)

	# The purse: pick a plan gap the arm covers level but not down the
	# vertical — the band between R and sqrt(R² − dz²) that only exists
	# because the reach is one 3D radius. Placed off the measured purse, so
	# the claim is about the mechanism and not about any pinned number.
	_settle(cat, prey)
	var arm: float = cat.body.neck_length + cat.body.head_offset
	var purse: float = arm + cat.maw.throw_cap() \
		+ cat.maw.muzzle_reach() * Maw.GRAB
	var gap_x: float = purse - 2.6
	var withers: Vector3 = cat.armature.pos[cat.armature.withers_index()]
	# One placement, one correction: put the prey's near flank at the wanted
	# plan gap by measuring where the first try actually landed.
	var axis_x: float = withers.x + gap_x + 10.6
	prey.build(Vector2(axis_x, -25.0), PI / 2.0)
	var probe := Vector2(axis_x, withers.y + 5.0)
	var level: Dictionary = cat.maw.aim(prey, probe)
	if not bool(level["ok"]) and String(level.get("why", "")) == "far":
		var off: float = float(level.get("gap", purse)) - gap_x
		prey.build(Vector2(axis_x - off, -25.0), PI / 2.0)
		probe = Vector2(axis_x - off, withers.y + 5.0)
		level = cat.maw.aim(prey, probe)
	_check(bool(level["ok"]),
		"a level flank %.1f px inside the purse was refused (%s)"
			% [gap_x, String(level.get("why", ""))])
	var level_gap: float = float(level.get("gap", 0.0))

	# ...and the same flesh, lying on the floor at the same plan gap, is past
	# it: the vertical spends what the horizontal was living on.
	prey.build(Vector2(probe.x, -28.0), PI / 2.0)
	prey.toggle_collapsed()
	prey.simulate(1.0)
	var down: Dictionary = cat.maw.aim(prey, probe)
	_check(not bool(down["ok"]),
		"the purse paid for a floor bite at the same plan gap it covers level "
		+ "(level %.1f, floor %.1f, purse %.1f)"
			% [level_gap, float(down.get("gap", 0.0)), purse])
	prey.toggle_collapsed()
	notes.append(("reach: tall back at z %.0f refused as height; %.1f px connects "
		+ "level (purse %.1f) and is refused onto the floor (%.1f)")
		% [tall_z, level_gap, purse, float(down.get("gap", 0.0))])


## The lunge is the body moving: a committed strike carries the pelvis toward
## the flesh — a rigid shift, not a stretched neck — and it is capped by the
## support.
func _check_the_lunge_is_the_body_moving(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey)
	var pelvis_was: Vector2 = cat.armature.plan(cat.armature.pelvis_index())
	var neck_before: float = _neck_span(cat)
	var went: bool = cat.bite(prey, Vector2(prey.centre().x, 5.0))
	_check(went, "a committed strike inside the purse refused to go")
	var throw: float = cat.maw._throw
	_check(throw > 2.0, "the lunge scenario asked for no body at all (%.1f px)" % throw)
	_check(throw <= cat.maw.throw_cap() + 0.001,
		"the throw (%.1f) outran the support's cap (%.1f)"
			% [throw, cat.maw.throw_cap()])
	_tick_both(cat, prey, 14)
	var carried: float = cat.armature.plan(cat.armature.pelvis_index()) \
		.distance_to(pelvis_was)
	_check(carried > throw * 0.45,
		"the strike moved the pelvis %.1f px of a %.1f px throw — the body did not go"
			% [carried, throw])
	var neck_after: float = _neck_span(cat)
	_check(absf(neck_after - neck_before) < 1.0,
		"the neck stretched %.2f px to deliver the strike"
			% absf(neck_after - neck_before))
	_check(prey.corpus.integrity() < 1.0, "the delivered strike took no flesh")
	notes.append("lunge: %.1f px thrown, pelvis carried %.1f px, neck ±%.2f px, flesh taken"
		% [throw, carried, absf(neck_after - neck_before)])


func _neck_span(c: Creature2) -> float:
	var a: Armature = c.armature
	return a.pos[a.head_index()].distance_to(a.pos[a.withers_index()])


## The wound is the layer walk: skin first, exactly as deep as it is, the
## surface thinner by exactly what was taken, the next wound deeper.
func _check_wound_depth_is_layer_math(prey: Creature2) -> void:
	if prey.armature.collapsed:
		prey.toggle_collapsed()
	prey.build(Vector2(115.0, -25.0), PI / 2.0)
	var corpus: Corpus = prey.corpus
	var st: int = 8
	var sec: int = 2
	var col: int = corpus.column(BodySchema.TRUNK, st, sec) * 4
	var skin_t: float = corpus.thickness[col + BodySchema.Layer.SKIN]
	var fat_t: float = corpus.thickness[col + BodySchema.Layer.FAT]
	var r_was: float = corpus.surface_radius(BodySchema.TRUNK, st, sec)

	var first: float = skin_t + fat_t * 0.5
	var report: Dictionary = corpus.wound(BodySchema.TRUNK, st, sec, first)
	_check(absf(float(report["taken"]) - first) < 0.001,
		"a %.2f px wound into deep flesh took %.3f px" % [first, float(report["taken"])])
	_check(corpus.hp[col + BodySchema.Layer.SKIN] == 0.0,
		"the skin survived a wound deeper than the skin")
	_check(absf(corpus.hp[col + BodySchema.Layer.FAT] - 0.5) < 0.01,
		"the fat under a half-fat wound stands at %.2f of itself, not half"
			% corpus.hp[col + BodySchema.Layer.FAT])
	_check(corpus.hp[col + BodySchema.Layer.MUSCLE] == 1.0,
		"a wound that ends in the fat reached the muscle")
	var dent: float = r_was - corpus.surface_radius(BodySchema.TRUNK, st, sec)
	_check(absf(dent - first) < 0.001,
		"the surface dented %.3f px under a %.3f px wound" % [dent, first])

	# The next wound starts where this one stopped.
	corpus.wound(BodySchema.TRUNK, st, sec, 2.0)
	_check(corpus.hp[col + BodySchema.Layer.FAT] == 0.0
			and corpus.hp[col + BodySchema.Layer.MUSCLE] < 1.0,
		"the second wound did not land deeper than the first")
	notes.append("wound math: %.2f px = skin + half the fat exactly; dent %.3f px; second bite hit muscle"
		% [first, dent])


## The full pipeline, diffed against the picture: a bite on the flank wounds
## more than one column (a mouth, not a point), and the rendered ring over
## each is thinner by exactly what the census lost.
func _check_a_bite_dents_what_it_bit(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey, Vector2(-6.0, 0.0))
	var corpus: Corpus = prey.corpus
	var hp_was: PackedFloat32Array = corpus.hp.duplicate()
	var went: bool = cat.bite(prey, Vector2(prey.centre().x, 5.0))
	_check(went, "the flank bite refused to go")
	_tick_both(cat, prey, 40)

	var wounded: Array[int] = []
	for column in corpus.columns:
		for layer in 4:
			if corpus.hp[column * 4 + layer] < hp_was[column * 4 + layer]:
				wounded.append(column)
				break
	_check(wounded.size() >= 2,
		"one closing of a whole mouth wounded %d column(s)" % wounded.size())

	# The picture: the posed ring radius over a wounded column equals the
	# census's radius over it, freshly derived — one sum, no second surface.
	var trunk: Corpus.CensusChain = corpus.chain(BodySchema.TRUNK)
	var skin: Contour = prey.contour
	var band: Contour.Band = skin.band(BodySchema.TRUNK)
	var checked_ring: bool = false
	for column in wounded:
		if column < trunk.base or column >= trunk.base + trunk.stations * trunk.sectors:
			continue
		var st: int = (column - trunk.base) / trunk.sectors
		var sec: int = (column - trunk.base) % trunk.sectors
		for r in range(band.first, band.first + band.count):
			if skin.ring_station[r] != st:
				continue
			var drawn: float = skin.radius[skin.ring_base[r] + sec]
			var t: float = skin.ring_t[r]
			var counted: float = skin.radius_at(BodySchema.TRUNK, t, sec)
			_check(absf(drawn - counted) < 0.001,
				"the drawn ring reads %.4f where the census says %.4f" % [drawn, counted])
			checked_ring = true
	_check(checked_ring, "no rendered ring found over the wounded columns")
	notes.append("the mouth: %d columns wounded in one closing; drawn radius == census radius over each"
		% wounded.size())


## The throat: a bite where the carotid is shallow breaches it — geometry,
## not a rule — and the animal bleeds out to arrest, which is the collapse.
func _check_throat_bite_bleeds_out(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey)
	var corpus: Corpus = prey.corpus
	var st: int = corpus.station_of(BodySchema.NECK, 0.4)
	var sec: int = corpus.sector_of(BodySchema.NECK, 4.2)
	var report: Dictionary = corpus.wound(BodySchema.NECK, st, sec,
		cat.maw.fangs.close_depth(cat.corpus) * 1.5)
	var opened: Array = report["breached"]
	var carotid: bool = false
	for vessel: Dictionary in opened:
		if String(vessel["name"]).begins_with("carotid"):
			carotid = true
	_check(carotid, "a deep wound over the carotid did not breach it")
	prey.vitals.absorb(report)
	_check(not prey.vitals.bleeds.is_empty(), "a breached vessel is not bleeding")
	var seconds: float = 0.0
	while not prey.vitals.arrested and seconds < 60.0:
		prey.vitals.tick(0.25)
		seconds += 0.25
	_check(prey.vitals.arrested,
		"a torn carotid never emptied the animal (blood %.2f after %.0f s)"
			% [prey.vitals.blood, seconds])
	prey._physics_process(TICK)
	_check(prey.armature.collapsed and not prey.alive,
		"an arrested heart left the body standing")
	notes.append("throat: carotid breached by geometry, bled out to arrest in %.0f s, body down"
		% seconds)


## The heart: safe behind the rib bone layer until repeated bites are through
## it — the wound front is measured against the built column, so each bite
## starts where the last stopped — and the hit that reaches it stops it.
func _check_ribs_guard_the_heart_until_they_do_not(cat: Creature2,
		prey: Creature2) -> void:
	_settle(cat, prey)
	var corpus: Corpus = prey.corpus
	var st: int = corpus.station_of(BodySchema.TRUNK, 0.84)
	var sec: int = corpus.sector_of(BodySchema.TRUNK, PI)
	var depth: float = cat.maw.fangs.close_depth(cat.corpus) \
		* Fangs.MAX_REACH
	var first: Dictionary = corpus.wound(BodySchema.TRUNK, st, sec, depth)
	prey.vitals.absorb(first)
	var heart_first: bool = false
	for organ: Dictionary in first["organs"]:
		if organ["name"] == "heart":
			heart_first = true
	_check(not heart_first, "one bite reached the heart through intact ribs")
	var bites: int = 1
	while not prey.vitals.arrested and bites < 8:
		prey.vitals.absorb(corpus.wound(BodySchema.TRUNK, st, sec, depth))
		bites += 1
	_check(prey.vitals.arrested,
		"eight bites into the heart's own wedge never stopped it")
	prey._physics_process(TICK)
	_check(not prey.alive, "a stopped heart did not read as death")
	notes.append("heart: bite 1 stopped short of the ribs' keep; bite %d arrested it"
		% bites)


## The sciatic: a deep wound on the back of the thigh cuts it, and the leg
## stops pressing — function loss with the flesh's own muscle untouched
## beyond the wound.
func _check_a_cut_nerve_is_a_dead_leg(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey)
	_tick_both(cat, prey, 30)
	var before: float = prey.travel.footwork.grip
	var corpus: Corpus = prey.corpus
	var st: int = corpus.station_of(&"HL", 0.2)
	var sec: int = corpus.sector_of(&"HL", PI)
	var report: Dictionary = corpus.wound(&"HL", st, sec, 3.2)
	var cut: bool = false
	for nerve: Dictionary in report["severed"]:
		if nerve["name"] == "sciatic_left":
			cut = true
	_check(cut, "a wound through the thigh to the sciatic's depth did not cut it")
	prey.vitals.absorb(report)
	_tick_both(cat, prey, 30)
	var after: float = prey.travel.footwork.grip
	_check(after < before - 0.1,
		"a cut sciatic left the grip at %.2f of %.2f" % [after, before])
	notes.append("nerve: sciatic cut, standing grip %.2f → %.2f" % [before, after])


## Feeding: a latched hold on a carcass follows the flesh as an address, tows
## the body when the holder walks, feeds the belly by exactly the census mass
## the carcass lost, and tears free when hauled past what flesh holds.
func _check_feeding_is_possession(cat: Creature2, prey: Creature2) -> void:
	_settle(cat, prey, Vector2(12.0, 0.0), 0.0, Vector2(118.0, -28.0), PI / 2.0)
	prey.toggle_collapsed()
	prey.simulate(1.5)
	_check(prey.vitals.arrested, "the carcass bay's body still has a beating heart")

	# The latch: aim at the nearest flesh the purse will pay for.
	var mouth: Dictionary = prey.contour.locate(cat.maw.jaw_point())
	var at: Vector3 = mouth["at"]
	var went: bool = cat.bite(prey, Vector2(at.x, at.y), true)
	_check(went, "the latch bite at a carcass in reach refused to go "
		+ "(gap withers→flesh %.1f)" % cat.armature.pos[cat.armature.withers_index()]
			.distance_to(at))
	_tick_both(cat, prey, 14)
	_check(not cat.maw.holding.is_empty(), "the latch did not hold")
	if cat.maw.holding.is_empty():
		return

	# The chew: mass moves from the carcass census to the belly, one scale.
	var carcass_was: float = prey.corpus.mass()
	var belly_was: float = cat.maw.belly
	_tick_both(cat, prey, 180)
	var eaten: float = cat.maw.belly - belly_was
	var lost: float = carcass_was - prey.corpus.mass()
	_check(eaten > 0.0, "three seconds of latched chewing fed nothing")
	_check(absf(eaten - lost) < 0.01,
		"the belly gained %.3f while the carcass lost %.3f" % [eaten, lost])

	# The tow: the holder walking drags the held body.
	var carcass_at: Vector2 = prey.centre()
	cat.command.throttle = -0.35
	_tick_both(cat, prey, 90)
	cat.command.throttle = 0.0
	var towed: float = prey.centre().distance_to(carcass_at)
	# The claim is that the carcass *follows* — a hold that towed nothing would
	# read a few tenths. The old 3.0 was calibrated to the long-necked build's
	# stand-off; the re-authored neck holds the pair closer, the contact press
	# eats more of each step, and the same mechanism tows a shorter distance.
	_check(towed > 1.2, "a held carcass was towed only %.1f px" % towed)

	# The tear: haul hard and the hold parts through the flesh.
	var still_held: bool = not cat.maw.holding.is_empty()
	var integrity_was: float = prey.corpus.integrity()
	cat.command.throttle = -1.0
	cat.command.sprint = true
	_tick_both(cat, prey, 150)
	cat.command.throttle = 0.0
	cat.command.sprint = false
	_check(cat.maw.holding.is_empty(),
		"a sprint straight away from a planted carcass never tore the hold")
	_check(not still_held or prey.corpus.integrity() < integrity_was,
		"the tear took no flesh on its way out")
	notes.append("feeding: latched, ate %.2f (carcass lost %.2f), towed %.1f px, tore free"
		% [eaten, lost, towed])
