## Focused first-slice test for mouse aim, anatomy queries, the layered tissue
## lattice, procedural body/limb contacts and the click/hold bite contract.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/CombatTest.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	_run_checks()
	return false


func _run_checks() -> void:
	var player: Creature = main.creature
	var target: Creature = main.target_creature
	_check(player != null, "player creature was not instantiated")
	_check(target != null, "stationary target creature was not instantiated")
	if player == null or target == null:
		_finish()
		return

	# The body in the habitat is placed dead — see Creature.alive — so everything
	# below has to say which of the two things it is testing. Combat is a contest
	# between two living creatures, so this slice revives it and puts it back on
	# its mark; the carcass's own behaviour is RagdollTest's subject.
	_check(not target.alive, "the habitat's body was not placed as a carcass")
	target.alive = true
	target.reset(target.spawn_position, target.spawn_heading)

	_check(target.head_pos.is_equal_approx(Vector2(360.0, 0.0)),
		"target did not use its simulation-space spawn position")
	var stationary_mark: Vector2 = target.head_pos
	target._physics_process(TICK)
	_check(target.head_pos.distance_to(stationary_mark) < 0.001,
		"target moved without a command")

	# Each visible procedural primitive must map to the expected tissue family.
	var head_hit: AnatomyState.Hit = target.query_bite(target.body.head.pos, 1.0)
	_check(head_hit != null and head_hit.kind == AnatomyState.HEAD,
		"head circle did not resolve to head tissue")

	var torso_index: int = mini(4, target.body.last_index - 1)
	var torso_point: Vector2 = target.spine.points[torso_index] \
		+ target.spine.perps[torso_index] * target.body.widths[torso_index]
	var torso_hit: AnatomyState.Hit = target.query_bite(torso_point, 1.0)
	_check(torso_hit != null and torso_hit.kind == AnatomyState.TORSO,
		"body flank did not resolve to torso tissue")

	var test_limb: Limb = target.gait.limbs[0]
	var lower_midpoint: Vector2 = test_limb.joints[1].lerp(test_limb.joints[2], 0.5)
	var limb_hit: AnatomyState.Hit = target.query_bite(lower_midpoint, 1.0)
	_check(limb_hit != null and limb_hit.kind == AnatomyState.LIMB,
		"drawn limb capsule did not resolve to limb tissue")

	_check_skeleton(target)
	_check_tissue(target)
	_check_voids(target)

	# The mouse supplies an articulated-head target, never a locomotion turn or
	# point-and-go throttle. ControlsTest owns the detailed pose geometry.
	var mouse_input := MovementInput.new()
	var aimed: MovementInput.Command = mouse_input.read(Vector2.ZERO, 0.0, Vector2(0.0, 100.0))
	_check(absf(aimed.turn) < 0.001, "mouse aim still wrote the body's turn command")
	_check(absf(aimed.throttle) < 0.001, "mouse aim still applied point-and-go throttle")
	_check(aimed.aim_active and aimed.aim_world.is_equal_approx(Vector2(0.0, 100.0)),
		"enabled mouse look did not carry its aim target into the command")

	_check_dentition(player, target)
	_check_bite_contract(player, target)

	_check_contacts(player, target)

	_check_physique(player, target)
	_check_grip(player, target)

	main.queue_free()
	_finish()


## Mass, strength and bite force are read off the creature rather than set on it,
## so what has to hold is that they track the thing they are read from: the drawn
## silhouette, the head, and how much tissue is left.
func _check_physique(player: Creature, target: Creature) -> void:
	var lizard: float = _physique_of(player, "Lizard").mass
	var gecko: float = _physique_of(player, "Gecko").mass
	var komodo: Physique = _physique_of(player, "Komodo")
	var crocodile: Physique = _physique_of(player, "Crocodile")
	_check(gecko < lizard and lizard < komodo.mass and komodo.mass < crocodile.mass,
		"mass did not follow build (gecko %.2f, lizard %.2f, komodo %.2f, croc %.2f)"
			% [gecko, lizard, komodo.mass, crocodile.mass])
	_check(komodo.mass > lizard * 3.0,
		"a Komodo came out only %.1fx a Lizard — the silhouette is not reaching mass"
			% (komodo.mass / lizard))

	# Square-cube: the big one is stronger outright and weaker per unit of mass.
	# Without that a large creature would simply be a small one times a constant
	# and nothing about scale would matter.
	_check(crocodile.strength > komodo.strength,
		"the heavier creature was not the stronger one")
	_check(crocodile.strength / crocodile.mass < komodo.strength / komodo.mass,
		"strength scaled with mass rather than with cross-section")
	_check(crocodile.bite_force > komodo.bite_force * 3.0,
		"a Crocodile's jaws (%.1f) were not in a different league from a Komodo's (%.1f)"
			% [crocodile.bite_force, komodo.bite_force])

	# Widening the body has to be enough on its own, or mass is really a slider
	# that happens to be spelled differently.
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	var narrow: float = player.physique.mass
	player.params.chest_width *= 2.0
	player.params.waist_width *= 2.0
	player._physics_process(TICK)
	_check(player.physique.mass > narrow * 1.5,
		"doubling the torso's width barely changed its mass (%.2f -> %.2f)"
			% [narrow, player.physique.mass])

	# ...and damage has to take it back off again, along with the strength and the
	# bite force derived from it. A creature eaten hollow is not the creature that
	# walked in.
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	var whole: Physique = Physique.new()
	whole.update(player.body, player.spine, player.anatomy.tissue, player.params)
	var scraps: Array = []
	for i in 12:
		var station: int = clampi(2 + i, 2, player.body.last_index - 1)
		for _repeat in 8:
			player.anatomy.tissue.bite(_disc(player.spine.points[station], 12.0, 3.0), scraps)
	player._physics_process(TICK)
	_check(player.physique.mass < whole.mass * 0.9,
		"chewing a creature open did not make it lighter (%.2f -> %.2f)"
			% [whole.mass, player.physique.mass])
	_check(player.physique.strength < whole.strength,
		"a half-eaten creature was as strong as an intact one")
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)


## Weight decides who yields. Both parties still resolve one full contact between
## them; what mass changes is how that one correction is divided, which is the
## whole of the difference between shoving and being shoved.
func _check_weight(player: Creature, target: Creature) -> void:
	# Equal builds must behave exactly as they did before mass existed: half each.
	player.params.apply_preset("Lizard")
	target.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)
	player._physics_process(TICK)
	target._physics_process(TICK)
	_check(absf(player._contact_share(target) - 0.5) < 0.02,
		"two identical creatures no longer split a contact down the middle (%.3f)"
			% player._contact_share(target))

	var light_gain: float = _shove(player, target, "Gecko", "Crocodile")
	var heavy_gain: float = _shove(player, target, "Crocodile", "Gecko")
	_check(heavy_gain > light_gain * 3.0,
		"weight bought nothing in a shove: a Crocodile moved a Gecko %.0f px and a Gecko moved a Crocodile %.0f px"
			% [heavy_gain, light_gain])
	_check(light_gain < 40.0,
		"a Gecko walked a Crocodile %.0f px across the world" % light_gain)
	_check(heavy_gain > 60.0,
		"a Crocodile leaning on a Gecko only moved it %.0f px — nothing is being shoved at all"
			% heavy_gain)

	player.params.apply_preset("Lizard")
	target.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)


## How far a creature of `pusher_name` shoves a stationary one of `pushee_name`
## by walking into it for two seconds.
func _shove(pusher: Creature, pushee: Creature, pusher_name: String, pushee_name: String) -> float:
	pusher.params.apply_preset(pusher_name)
	pushee.params.apply_preset(pushee_name)
	pusher.reset(Vector2.ZERO, 0.0)
	pushee.reset(Vector2(150.0, 0.0), PI)
	var start: Vector2 = pushee.head_pos
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _i in 240:
		pusher.command = drive
		pusher._physics_process(TICK)
		pushee._physics_process(TICK)
	return start.distance_to(pushee.head_pos)


## The grip: a latch that can be dragged with, struggled against, chewed through
## and torn off, with which of those happens decided by the three physical
## quantities and nothing else.
func _check_grip(player: Creature, target: Creature) -> void:
	_check_weight(player, target)

	# Jaws shut on a victim and left alone are jaws shut on a victim. Nothing about
	# a hold generates damage by itself — only chewing and pulling do.
	_hold(player, target, "Crocodile", "Gecko", "still", 0.0)
	var untouched: float = target.anatomy.tissue.integrity()
	_hold_on(player, target, "still", 3.0)
	_check(player.grip != null, "a Crocodile let go of a Gecko that did nothing at all")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), untouched),
		"three motionless seconds in a Crocodile's jaws chewed the victim anyway")

	# A heavy set of jaws on light prey: it goes where the biter goes. Towing is
	# quiet — the two travel together — so it is a drag and not a dismemberment.
	var towed: float = _hold(player, target, "Crocodile", "Gecko", "drag", 3.0)
	_check(player.grip != null,
		"a Crocodile lost its hold on a Gecko it was simply walking away with")
	_check(towed > 100.0,
		"prey held in a Crocodile's jaws was towed only %.0f px in three seconds" % towed)

	# The same jaws, with the victim thrashing: unshakeable, and now the load has
	# somewhere to go. The flesh is weaker than the jaws, so it is the flesh that
	# gives — a mouthful at a time, with the hold re-seating on what is left.
	var whole: float = target.anatomy.tissue.integrity()
	_hold(player, target, "Crocodile", "Gecko", "thrash", 3.0)
	_check(player.grip != null,
		"a thrashing Gecko shook a Crocodile off jaws worth %.1f"
			% player.physique.bite_force)
	var torn: float = target.anatomy.tissue.integrity()
	_check(torn < whole - 0.1,
		"a Gecko thrashing in a Crocodile's jaws had no meat pulled off it (%.2f -> %.2f)"
			% [whole, torn])
	_check(main.scrap_field.scraps.size() > 0, "tearing meat off a creature shed nothing")
	# Torn, not ground: a tear is a discrete failure of the tissue, so it has to
	# leave holes in the lattice rather than uniformly thin the whole victim.
	var opened: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	_check(opened.gone_count > 0,
		"three seconds of tearing never opened a hole in the victim")

	# ...and a victim that stops struggling stops being torn. Stress is spent as
	# fast as it is earned once the pull comes off, so the hold goes quiet — after
	# the moment it takes the pair to actually come to rest and whatever was
	# already most of the way to parting to finish doing so.
	_hold_on(player, target, "still", 0.75)
	var settled: float = target.anatomy.tissue.integrity()
	_hold_on(player, target, "still", 2.0)
	_check(is_equal_approx(target.anatomy.tissue.integrity(), settled),
		"a victim that stopped thrashing went on being torn apart")

	# Reverse the pair and the same rules produce the opposite outcome.
	_hold(player, target, "Gecko", "Crocodile", "drag", 2.0)
	_check(target.head_pos.distance_to(Vector2(60.0, 0.0)) < 60.0,
		"a Gecko dragged a Crocodile %.0f px" % target.head_pos.distance_to(Vector2(60.0, 0.0)))
	_check(absf(player.speed) < player.params.move_speed * 0.5,
		"a Gecko hauling a Crocodile kept %.0f px/s of its own top speed" % player.speed)

	# ...and light jaws on something that will not be held come off it.
	_hold(player, target, "Gecko", "Crocodile", "thrash", 3.0)
	_check(player.grip == null,
		"a Gecko held a thrashing Crocodile with jaws it could never close on it")
	_check(not player.is_bite_latched(),
		"a torn-off grip still reported itself as latched")
	_check(player.bite_held,
		"tearing free let go of the button as well as of the victim")
	_check(target.anatomy.tissue.integrity() < 1.0,
		"jaws pulled off a victim came away clean")
	# The other half of that: which of the two gave is decided by nothing but
	# which was weaker. Jaws that lost come off a body still in one piece, where
	# the same struggle against jaws that held would have opened it up.
	_check(target.anatomy.tissue.patch(TissueGrid.BODY_KEY).gone_count == 0,
		"a Crocodile that shook a Gecko off had meat torn out of it anyway")

	# Depth is what is left of the jaws' force after holding on, so the same bite
	# cuts deeper into something that has stopped fighting.
	_hold(player, target, "Crocodile", "Komodo", "thrash", 1.5)
	var strained: float = player.bite_depth()
	_check(player.grip != null, "the strained-chew case lost its grip before measuring")
	if player.grip != null:
		_check(player.grip.load > 0.0, "a thrashing victim put no load on the jaws at all")
		_check(strained < player.params.bite_damage,
			"jaws holding a struggling victim bit as deep as free ones (%.2f of %.2f)"
				% [strained, player.params.bite_damage])
	player.set_bite_held(false)
	for _i in int(ceil(Creature.GRIP_REGRASP_WINDOW / TICK)) + 2:
		player._physics_process(TICK)
	_check(player.grip == null, "the strained-chew hold outlived its parting window")
	_check(is_equal_approx(player.bite_depth(), player.params.bite_damage),
		"a free bite did not go in at its full configured depth")

	player.params.apply_preset("Lizard")
	target.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)


## Latches `biter_name`'s jaws onto `victim_name` and runs the pair for
## `seconds`. Returns how far the victim moved.
func _hold(biter: Creature, victim: Creature, biter_name: String, victim_name: String,
		mode: String, seconds: float) -> float:
	biter.set_bite_held(false)
	biter.params.apply_preset(biter_name)
	victim.params.apply_preset(victim_name)
	biter.reset(Vector2.ZERO, 0.0)
	# A bite lands where the mouth is, so engagement distance is a lunge plus a
	# snout rather than a bite volume thrown out in front of one. This is inside
	# every pair's reach and outside every pair's silhouette, which is what a
	# grip fixture has to be.
	victim.reset(Vector2(52.0, 0.0), PI)
	for _i in 20:
		biter._physics_process(TICK)
		victim._physics_process(TICK)

	biter.set_bite_held(true)
	biter.request_bite(Vector2(200.0, 0.0))
	for _i in 20:
		biter._physics_process(TICK)
		victim._physics_process(TICK)
	if biter.grip == null:
		failures.append("%s never got hold of %s to begin with" % [biter_name, victim_name])
		return 0.0
	return _hold_on(biter, victim, mode, seconds)


## Runs an established hold on for `seconds`. `mode` is what the two do about it:
## the biter walks off with its prey, the victim spins on the spot trying to shake
## the jaws, or neither of them does anything at all — which is the case that
## proves a hold is a hold rather than a slow bite. Returns the victim's travel.
func _hold_on(biter: Creature, victim: Creature, mode: String, seconds: float) -> float:
	var biter_cmd := MovementInput.Command.new()
	var victim_cmd := MovementInput.Command.new()
	if mode == "drag":
		biter_cmd.throttle = 1.0
	elif mode == "thrash":
		victim_cmd.turn = 1.0
	var start: Vector2 = victim.head_pos
	for _i in int(round(seconds / TICK)):
		biter.command = biter_cmd
		victim.command = victim_cmd
		biter._physics_process(TICK)
		victim._physics_process(TICK)
	return start.distance_to(victim.head_pos)


## The physique a preset settles at, measured on a real creature so it comes off
## the solved silhouette rather than off the numbers that produced it.
func _physique_of(creature: Creature, preset_name: String) -> Physique:
	creature.params.apply_preset(preset_name)
	creature.reset(Vector2.ZERO, 0.0)
	for _i in 4:
		creature._physics_process(TICK)
	var measured := Physique.new()
	measured.update(creature.body, creature.spine, creature.anatomy.tissue, creature.params)
	return measured


## A press starts one strike. If that strike connects while the button remains
## down, it stays clamped at the hit frame without becoming repeated damage;
## release resumes the original recovery. Misses and quick clicks never clamp.
func _check_bite_contract(player: Creature, target: Creature) -> void:
	const APEX: float = Creature.LUNGE_WINDUP + Creature.LUNGE_STRIKE
	var apex_ticks: int = int(ceil(APEX / TICK)) + 2

	# Connected hold: exercise the same synchronous signal/world resolver path as
	# a real left-button press, then keep it held well past every ordinary timer.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(50.0, 0.0), PI)
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected a held bite request")
	var stand: Vector2 = player.head_pos
	player._physics_process(TICK)
	_check(player.is_lunging(), "an accepted held bite did not start a lunge")
	_check(player.lunge_offset < 0.0, "the held lunge skipped its wind-up")
	_check(not main.bite_cue.is_showing(), "the Bite cue appeared before impact")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), 1.0),
		"the held bite landed before the lunge had extended")

	var extension: float = 0.0
	for _i in apex_ticks:
		player._physics_process(TICK)
		extension = maxf(extension, player.body.head.pos.distance_to(player.head_pos))
	var latched_integrity: float = target.anatomy.tissue.integrity()
	_check(latched_integrity < 1.0,
		"the held lunge never resolved into a bite on the nearby target")
	_check(extension > player.params.bite_reach * 0.5,
		"the head was never thrown appreciably forward (%.1f px)" % extension)
	_check(main.bite_cue.is_showing(),
		"the bite impact did not show its world-space Bite cue")
	_check(player.head_pos.is_equal_approx(stand),
		"lunging displaced the creature itself")
	_check(player.bite_connected, "landed held bite was reported as a miss")
	_check(player.is_bite_latched(), "holding a connected bite did not latch it")
	_check(is_equal_approx(player.bite_time, APEX),
		"a connected latch did not hold at the bite apex")
	_check(player.bite_cooldown_remaining > 0.0, "bite did not start its cooldown")

	var held_ticks: int = int(ceil(
		(maxf(player.params.bite_cooldown, Creature.LUNGE_TOTAL) + 0.25) / TICK))
	for _i in held_ticks:
		player._physics_process(TICK)
	_check(player.is_bite_latched(), "connected bite released itself while click stayed held")
	_check(player.is_lunging() and is_equal_approx(player.bite_time, APEX),
		"held bite drifted away from full extension")
	# A hold is a hold. Neither of the two things that damage a victim is the
	# button being down: a chew is an action taken, and a tear is force over time.
	# Neither party is moving here, so a full second of clamped jaws must leave the
	# creature exactly as the strike left it — and one press must still mean one
	# lunge, one cooldown and one hit frame however long it is held.
	_check(is_equal_approx(target.anatomy.tissue.integrity(), latched_integrity),
		"jaws merely held shut on a motionless victim went on damaging it")
	_check(is_equal_approx(player.bite_time, APEX),
		"holding restarted the strike animation")
	_check(player.bite_cooldown_remaining <= 0.0,
		"latch test did not actually outlast the cooldown")
	_check(not player.request_bite(Vector2(100.0, 0.0)),
		"a second strike was accepted while the first was latched")

	# Chewing is the button being *worked*. Jaws part rather than spring open, and
	# a press taken while they are parting shuts them again on the same flesh: it
	# bites, and it keeps the hold.
	player.set_bite_held(false)
	_check(player.is_bite_latched(),
		"jaws sprang open the instant the button rose instead of parting")
	player._physics_process(TICK)
	player.set_bite_held(true)
	for _i in 3:
		player._physics_process(TICK)
	var chewed: float = target.anatomy.tissue.integrity()
	_check(chewed < latched_integrity, "a chew inside the parting window bit nothing")
	_check(player.is_bite_latched(), "chewing let go of the hold it was chewing with")
	_check(is_equal_approx(player.bite_time, APEX),
		"a chew restarted the strike animation instead of working the jaws")
	_check(main.scrap_field.scraps.size() > 0,
		"a bite through skin and muscle shed nothing edible into the world")

	# ...and one press is one closing of the jaws here too. Mashing the button
	# cannot beat the interval the species can actually work them at.
	for _i in 4:
		player.set_bite_held(false)
		player._physics_process(TICK)
		player.set_bite_held(true)
		player._physics_process(TICK)
	_check(is_equal_approx(target.anatomy.tissue.integrity(), chewed),
		"mashing the button chewed faster than chew_interval allows")
	_check(player.is_bite_latched(), "mashing the button shook the hold loose")

	# Held past the parting window, the jaws actually open — then the original
	# recovery finishes as it always did.
	player.set_bite_held(false)
	for _i in int(ceil(Creature.GRIP_REGRASP_WINDOW / TICK)) + 2:
		player._physics_process(TICK)
	_check(not player.is_bite_latched(), "the parting window never let go")
	_check(player.grip == null, "jaws that had opened kept their hold")
	for _i in int(ceil(Creature.LUNGE_RECOVER / TICK)) + 2:
		player._physics_process(TICK)
	_check(not player.is_lunging(), "released latch never finished its recovery")
	_check(is_equal_approx(player.lunge_offset, 0.0),
		"released latch did not return the head to rest")
	_check(player.can_bite(), "released bite did not become ready after recovery")

	# Holding empty air is still one ordinary bite: it must never manufacture a
	# latch, retry automatically, or remain at full extension.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), PI)
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected a held miss request")
	var miss_latched: bool = false
	for _i in int(ceil(Creature.LUNGE_TOTAL / TICK)) + 4:
		player._physics_process(TICK)
		miss_latched = miss_latched or player.is_bite_latched()
	_check(not miss_latched, "a held miss latched without a target")
	_check(not player.bite_connected, "a bite into empty space reported a connection")
	_check(not player.is_lunging(), "holding a miss prevented normal recovery")
	_check(is_equal_approx(player.lunge_offset, 0.0),
		"held miss did not return the head to rest")
	player.set_bite_held(false)

	# Reset is authoritative even in the middle of a live clamp.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(50.0, 0.0), PI)
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected the reset latch precondition")
	for _i in apex_ticks:
		player._physics_process(TICK)
	_check(player.is_bite_latched(), "reset case never reached its latch precondition")
	player.reset(Vector2.ZERO, 0.0)
	_check(not player.bite_held and not player.bite_latched,
		"reset retained held or latched bite state")
	_check(not player.is_lunging() and is_equal_approx(player.lunge_offset, 0.0),
		"reset retained an active lunge")
	_check(player.can_bite(), "reset did not make the bite immediately ready")

	# A quick press/release before the next physics tick still performs one bite.
	# A deliberately coarse step must stop at its apex rather than skipping damage.
	target.reset(Vector2(50.0, 0.0), PI)
	var quick_before: float = target.anatomy.tissue.integrity()
	player.set_bite_held(true)
	_check(player.request_bite(Vector2(100.0, 0.0)),
		"ready player rejected a quick bite request")
	player.set_bite_held(false)
	player._physics_process(Creature.LUNGE_TOTAL * 2.0)
	var quick_impact: float = target.anatomy.tissue.integrity()
	_check(quick_impact < quick_before,
		"a coarse tick stepped over the quick bite's hit frame")
	_check(player.bite_connected, "quick released bite was reported as a miss")
	_check(not player.is_bite_latched(), "quick released bite latched after release")
	player._physics_process(Creature.LUNGE_TOTAL * 2.0)
	_check(not player.is_lunging(), "quick released bite never completed recovery")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), quick_impact),
		"one quick click resolved more than one bite")


## The skeleton has to stay a frame rather than spread into a plate. If bone
## covers most of the body there is no such thing as eating through it: every
## wound bottoms out on the same pale surface, nothing ever opens onto the
## ground, and the skull, ribs and vertebrae stop being distinguishable.
func _check_skeleton(target: Creature) -> void:
	var body: TissueGrid.Patch = target.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var boned: int = 0
	for cell in body.cells:
		boned += body.bone[cell]
	var covered: float = float(boned) / float(body.cells)
	_check(covered < 0.5,
		"bone covers %.0f%% of the body — that is a plate, not a skeleton" % (covered * 100.0))

	# Bone per column, so the *shape* can be asserted rather than just the total.
	# A column carrying only the vertebral column counts 1.
	var per_column: PackedInt32Array = PackedInt32Array()
	per_column.resize(body.cols)
	for c in body.cols:
		var n: int = 0
		for r in body.rows:
			n += body.bone[c * body.rows + r]
		per_column[c] = n

	# Every crossbar over the torso — girdle or rib — must have a flesh-only
	# column either side of it, or the chest is one continuous shell and a bite
	# can never land between two ribs.
	var freestanding: int = 0
	for c in range(TissueGrid.HEAD_COLS, TissueGrid.HEAD_COLS + TissueGrid.TORSO_COLS):
		if per_column[c] > 1 and per_column[c - 1] == 1 and per_column[c + 1] == 1:
			freestanding += 1
	_check(freestanding >= 3,
		"only %d free-standing crossbars over the torso — the ribcage is not a cage" % freestanding)

	# Behind the hips there is nothing but vertebrae.
	var tail_clear: bool = true
	for c in range(TissueGrid.HEAD_COLS + TissueGrid.TORSO_COLS, body.cols):
		tail_clear = tail_clear and per_column[c] == 1
	_check(tail_clear, "the tail carries more than a vertebral column")

	# The frame has to be one piece, joined bone to bone. Flesh is what a bite
	# takes first, so a skeleton whose parts only meet through muscle falls into
	# floating fragments exactly when a creature has been chewed down to it —
	# which is the one time the skeleton is the whole of what you are looking at.
	var reached: Dictionary = {}
	var stack: Array[int] = []
	for r in body.rows:
		if body.bone[r] == 1:  # seed from the snout column, at the far end of it
			reached[r] = true
			stack.append(r)
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		var c: int = cell / body.rows
		var r2: int = cell % body.rows
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: int = c + step.x
			var nr: int = r2 + step.y
			if nc < 0 or nc >= body.cols or nr < 0 or nr >= body.rows:
				continue
			var n: int = nc * body.rows + nr
			if body.bone[n] == 1 and not reached.has(n):
				reached[n] = true
				stack.append(n)
	_check(reached.size() == boned,
		"%d bone cells are not joined to the skull — the skeleton is in pieces"
			% (boned - reached.size()))

	# ...and the limbs hang off it. A socket over flesh means a limb bone tied to
	# the axial skeleton by nothing but the meat around it.
	for limb in target.gait.limbs:
		_check(body.bone[_nearest_cell(body, limb.joints[0])] == 1,
			"the %s socket sits over flesh, not over a girdle" % limb.key)


## Tissue eaten through every layer has to be genuinely gone, not painted the
## colour of the ground. Ground-coloured cells look right only against an empty
## background: they still hide whatever is behind the creature, and — the part
## that actually matters — the body still collides and hit-tests as though the
## tissue were there, so a creature can be eaten hollow and still be a wall.
##
## So three things have to agree that a hole is a hole: the lattice retires the
## cell, the body stops colliding where it used to be, and the bite query stops
## finding anything to bite there.
## The teeth, and the mark they leave.
##
## The point of generating a dentition rather than drawing one is that nothing
## about a wound is authored after it: the mouth decides the shape, the depth
## and the place, one description carries all three, and the same description is
## what erodes the tissue and what is printed on it. So these checks are about
## consequences — that a keener mouth cuts deeper because it has less tooth
## touching the flesh, that a crowded blunt one spreads the same jaws over more
## of it, and that neither of those was written down anywhere.
func _check_dentition(player: Creature, target: Creature) -> void:
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	var mouth: Dentition = player.dentition
	_check(mouth != null and mouth.teeth.size() == player.params.tooth_count * 2,
		"a mouth did not come out with a tooth in every slot of both arches")

	# Both arches, with the lower nested inside the upper — which is the whole
	# reason a bite mark is two rows of punctures rather than one, and why the
	# rows mesh instead of meeting point to point.
	var upper_seat: float = 0.0
	var lower_seat: float = 0.0
	var facing: int = 0
	for tooth in mouth.teeth:
		if tooth.jaw != Dentition.UPPER:
			lower_seat = maxf(lower_seat, tooth.seat)
			continue
		upper_seat = maxf(upper_seat, tooth.seat)
		for other in mouth.teeth:
			if other.jaw == Dentition.LOWER and absf(tooth.angle - other.angle) < 0.0001:
				facing += 1
	_check(lower_seat < upper_seat,
		"the lower arch was not set inside the upper one (%.2f vs %.2f)"
			% [lower_seat, upper_seat])
	# Both arches are symmetric about the snout, so an odd count leaves one pair
	# meeting at the midline exactly as a mouthful of incisors does. Every other
	# tooth has to fall in the gap opposite it.
	_check(facing <= 1,
		"%d teeth met their opposite number head on instead of meshing" % facing)

	# Type is read off position and keenness, never listed. A keen mouth carries
	# fangs and blades; a blunt one is cusps and crushers and has no canines at
	# all, because nothing here should invent a fang for a mouth without one.
	_check(mouth.count_of(Dentition.CANINE) > 0 and mouth.count_of(Dentition.CARNASSIAL) > 0,
		"a keen dentition grew neither canines nor blades")
	var blunt_params := CreatureParams.new()
	blunt_params.tooth_sharpness = 0.0
	var blunt: Dentition = Dentition.grow(blunt_params)
	_check(blunt.count_of(Dentition.CANINE) == 0,
		"a mouth of blunt cusps was given fangs anyway")
	_check(blunt.count_of(Dentition.MOLAR) > mouth.count_of(Dentition.MOLAR),
		"blunting a mouth did not push its crushing teeth further forward")

	# Teeth are structural the way the spine's segment count is: a slider regrows
	# them, and only a slider that actually changed anything.
	var same: Dentition = player.dentition
	player._physics_process(TICK)
	_check(player.dentition == same, "an unchanged mouth was regrown anyway")
	player.params.tooth_count += 3
	player._physics_process(TICK)
	_check(player.dentition != same
			and player.dentition.teeth.size() == player.params.tooth_count * 2,
		"changing the tooth count did not regrow the mouth")
	player.params.apply_preset("Lizard")
	player._physics_process(TICK)

	# Force over area, and nothing else. Fewer, keener teeth have less touching
	# the flesh, so the same jaws drive further into it.
	var few := CreatureParams.new()
	few.tooth_count = 5
	few.tooth_sharpness = 1.0
	var many := CreatureParams.new()
	many.tooth_count = 20
	many.tooth_sharpness = 0.0
	var keen: Dentition = Dentition.grow(few)
	var crowded: Dentition = Dentition.grow(many)
	_check(keen.contact_area < crowded.contact_area,
		"five needles met more flesh than twenty cusps (%.3f vs %.3f)"
			% [keen.contact_area, crowded.contact_area])
	_check(keen.pressure() > crowded.pressure(),
		"concentrating a bite into fewer keener teeth did not raise its pressure")

	_check_mark_is_the_damage(player, target)


## The mark is the damage: what the teeth cover is what is eaten, and a bite is
## a row of punctures rather than a stamped disc.
func _check_mark_is_the_damage(player: Creature, target: Creature) -> void:
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	target.params.apply_preset("Lizard")
	target.reset(Vector2(400.0, 0.0), 0.0)
	target._physics_process(TICK)

	# The jaws are on the head. Nothing about a bite may sit out in front of the
	# snout any more, which is the whole of what "the mouth is where the damage
	# is" means — so every tooth has to land inside the creature's own gape.
	var mark: BiteMark = player.bite_mark(player.jaw_point(), player.params.bite_damage)
	var mouth_reach: float = player.jaw_axes().x
	var furthest: float = 0.0
	for imp in mark.impressions:
		furthest = maxf(furthest, imp.pos.distance_to(player.body.head.pos))
	_check(furthest <= mouth_reach + 0.001,
		"a tooth landed %.1f px from the head, past its own %.1f px gape"
			% [furthest, mouth_reach])
	_check(player.jaw_point().distance_to(player.body.head.pos) < mouth_reach,
		"the jaws still hold from a point out in front of the face")

	# Damage lands where the teeth are and nowhere else. Sampled against the
	# mark itself, so this is not "a bite damages things" but "the print and the
	# wound are one description read twice".
	var flank_station: int = mini(6, target.body.last_index - 1)
	var flank: Vector2 = target.spine.points[flank_station] \
		+ target.spine.perps[flank_station] * (target.body.widths[flank_station] * 0.5)
	var lattice := TissueGrid.new()
	lattice.update(target)
	var stamp: BiteMark = player.bite_mark(flank, player.params.bite_damage)
	var shed: Array = []
	_check(lattice.bite(stamp, shed) > 0.0, "a mouthful of flank removed nothing at all")
	var patch: TissueGrid.Patch = lattice.patch(TissueGrid.BODY_KEY)
	var covered: int = 0
	var stray: int = 0
	for cell in patch.damaged:
		var at: Vector2 = patch.centre_of(cell)
		if stamp.depth_at(at) > 0.0 or at.distance_to(stamp.center) <= stamp.radius:
			covered += 1
		else:
			stray += 1
	_check(covered > 0 and stray == 0,
		"%d cells were eaten outside the mark that supposedly ate them" % stray)

	# ...and a keen mouth reaches through the hide where a crowded blunt one only
	# grazes a wider patch of it, at exactly the same jaw force. Neither result
	# is written anywhere: both are the same bite spread differently.
	var deep: Array = _stamp_with(player, target, flank, 5, 1.0)
	var broad: Array = _stamp_with(player, target, flank, 20, 0.0)
	_check(deep[1] > broad[1],
		"five needles did not go deeper than twenty cusps (%.2f vs %.2f hp)"
			% [deep[1], broad[1]])
	_check(broad[0] > deep[0],
		"twenty cusps did not cover more flesh than five needles (%d vs %d cells)"
			% [broad[0], deep[0]])
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)


## Bites `target` at `at` with a mouth of `count` teeth of the given keenness,
## on a fresh lattice. Returns [cells damaged, deepest single cell].
func _stamp_with(player: Creature, target: Creature, at: Vector2,
		count: int, keenness: float) -> Array:
	player.params.tooth_count = count
	player.params.tooth_sharpness = keenness
	player._physics_process(TICK)
	var lattice := TissueGrid.new()
	lattice.update(target)
	lattice.bite(player.bite_mark(at, player.params.bite_damage), [])
	var patch: TissueGrid.Patch = lattice.patch(TissueGrid.BODY_KEY)
	var deepest: float = 0.0
	for cell in patch.damaged:
		var base: int = cell * TissueGrid.LAYERS
		deepest = maxf(deepest, TissueGrid.SKIN_HP + TissueGrid.MUSCLE_HP
			- patch.hp[base + TissueGrid.SKIN] - patch.hp[base + TissueGrid.MUSCLE])
	return [patch.damaged.size(), deepest]


func _check_voids(target: Creature) -> void:
	target.anatomy.reset()
	target._physics_process(TICK)
	var tissue: TissueGrid = target.anatomy.tissue
	var body: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	var last: int = target.body.last_index
	_check(body.gone_count == 0, "an untouched creature already had holes in it")

	# Well behind the ribcage, so this is flesh over a single vertebra rather
	# than over a crossbar, and a bite can reach every layer of it.
	var station: int = clampi(int(round(float(last) * 0.75)), 2, last - 2)
	var t: float = float(station) / float(last)
	var perp: Vector2 = target.spine.perps[station]
	var axis: Vector2 = target.spine.points[station]
	var flank: Vector2 = axis + perp * (target.body.widths[station] * 0.7)

	_check(is_equal_approx(tissue.body_solid(t, 1.0), 1.0),
		"an intact flank did not report its full width")
	_check(target.push_out_of_body(flank, 1.0) != Vector2.ZERO,
		"the intact flank collided with nothing — the probe proves nothing")
	_check(target.query_bite(flank, 1.0) != null, "the intact flank was not hit-testable")

	# One flank first: eating into a body from one side must not thin the other.
	var shed: Array = []
	for _i in 10:
		tissue.bite(_disc(flank, 7.0, 3.0), shed)
	_check(body.gone_count > 0, "cells stripped of every layer were never retired")
	_check(body.gone[_nearest_cell(body, flank)] == 1,
		"the cell under a bite that ate skin, muscle and all was still reported as tissue")
	_check(tissue.body_solid(t, 1.0) < 1.0,
		"eating a flank open did not narrow the body there")
	_check(is_equal_approx(tissue.body_solid(t, -1.0), 1.0),
		"eating one flank thinned the other one too")

	# Now the whole cross-section, three stations wide so the neighbouring
	# capsules cannot reach the probe and answer for the piece that is gone.
	for s in range(station - 1, station + 2):
		for _i in 16:
			tissue.bite(_disc(target.spine.points[s], 13.0, 3.0), shed)
	_check(is_equal_approx(tissue.body_solid(t, 1.0), 0.0)
			and is_equal_approx(tissue.body_solid(t, -1.0), 0.0),
		"a station eaten clean through still reported tissue standing on it")
	_check(target.push_out_of_body(axis, 1.0) == Vector2.ZERO,
		"a hole eaten clean through the body is still solid to walk into")
	_check(target.query_bite(axis, 1.0) == null,
		"jaws closing on a hole still found tissue to bite")

	# Both halves of a contact have to know about the hole, not just the body
	# being walked into: a creature eaten open must also stop shoving others
	# away at the width it no longer has.
	_check(is_equal_approx(target._solid_at(station, last), 0.0),
		"an eaten-through station still probed other bodies at its old width")
	_check(target._solid_at(1, last) > 0.0,
		"an intact station stopped probing other bodies at all")

	# The rest of the creature is untouched by any of that — the void is local,
	# not a body that has quietly stopped colliding altogether.
	var intact: Vector2 = target.spine.points[1]
	_check(target.push_out_of_body(intact, 1.0) != Vector2.ZERO,
		"opening a hole in the tail stopped the whole body colliding")
	_check(target.query_bite(intact, 1.0) != null,
		"opening a hole in the tail made the whole body un-biteable")


## The layered lattice: bites eat strictly outside-in, land only where they
## land, cost far more through bone, and survive the pose being rebuilt — and
## the spine being restructured — underneath them.
func _check_tissue(target: Creature) -> void:
	var tissue: TissueGrid = target.anatomy.tissue
	var body: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	_check(body != null and body.live, "the body tissue lattice was never posed")
	if body == null or not body.live:
		return

	# Behind the ribcage and well off the midline, so this column is pure flesh
	# and can be eaten clean through.
	var station: int = clampi(int(round(float(target.body.last_index) * 0.75)),
		1, target.body.last_index - 1)
	var flank: Vector2 = target.spine.points[station] \
		+ target.spine.perps[station] * (target.body.widths[station] * 0.75)
	var cell: int = _nearest_cell(body, flank)
	var base: int = cell * TissueGrid.LAYERS
	_check(body.bone[cell] == 0, "the flank sample sits over bone, not flesh")

	# The damage solver stays cell-precise, but neighbouring cells destroyed by
	# one tear must leave as fewer, larger pieces rather than one scrap each.
	var cohort := TissueGrid.new()
	cohort.update(target)
	var cohort_shed: Array = []
	cohort.bite(_disc(flank, 12.0, 8.0), cohort_shed)
	var cohort_body: TissueGrid.Patch = cohort.patch(TissueGrid.BODY_KEY)
	var destroyed_layers: int = 0
	for cohort_cell in cohort_body.cells:
		var cohort_base: int = cohort_cell * TissueGrid.LAYERS
		destroyed_layers += 1 if cohort_body.hp[cohort_base + TissueGrid.SKIN] <= 0.0 else 0
		destroyed_layers += 1 if cohort_body.hp[cohort_base + TissueGrid.MUSCLE] <= 0.0 else 0
	_check(destroyed_layers > cohort_shed.size(),
		"one bite still emitted one loose scrap per destroyed tissue cell")
	var reference_extent: float = cohort_body.extent_of(_nearest_cell(cohort_body, flank))
	var largest_piece: float = 0.0
	for piece in cohort_shed:
		largest_piece = maxf(largest_piece, piece.size)
	_check(largest_piece > reference_extent * 1.25,
		"adjacent destroyed cells did not form a visibly larger piece")

	var elsewhere: int = _nearest_cell(body, target.body.head.pos)
	var elsewhere_before: float = body.hp[elsewhere * TissueGrid.LAYERS]

	var shed: Array = []
	var removed: float = tissue.bite(_disc(flank, 10.0, TissueGrid.SKIN_HP * 0.5), shed)
	_check(removed > 0.0, "a bite on the flank removed no tissue")
	_check(not body.damaged.is_empty(), "damaged cells were not recorded for drawing")
	_check(body.hp[base + TissueGrid.SKIN] < TissueGrid.SKIN_HP,
		"skin directly under the bite was not eroded")
	_check(is_equal_approx(body.hp[base + TissueGrid.MUSCLE], TissueGrid.MUSCLE_HP),
		"muscle took damage before the skin over it was gone")
	_check(shed.is_empty(), "a bite that only grazed the skin still shed chunks")
	_check(is_equal_approx(body.hp[elsewhere * TissueGrid.LAYERS], elsewhere_before),
		"a bite damaged cells nowhere near where it landed")

	for _i in 6:
		tissue.bite(_disc(flank, 10.0, 2.0), shed)
	_check(body.hp[base + TissueGrid.MUSCLE] <= 0.0,
		"repeated bites never ate through skin and muscle")
	_check(shed.size() >= 2, "destroyed skin and muscle shed no edible chunks")
	var found_weighty_piece: bool = false
	for piece in shed:
		found_weighty_piece = found_weighty_piece or (piece.size > 3.0 and piece.mass > 9.0)
	_check(found_weighty_piece, "shed tissue still consisted only of cell-sized pixels")
	# Nothing under the flesh there, so eating it opens a hole clean through to
	# the ground rather than bottoming out on a skeleton.
	_check(body.hp[base + TissueGrid.BONE] <= 0.0,
		"a cell with no skeleton under it still had bone left to stop the bite")

	# Bone is not merely more tissue: it yields at half rate and stops the bite,
	# so a skeletal cell has to outlast the flesh beside it by a wide margin.
	var midline: Vector2 = target.spine.points[station]
	var bone_cell: int = _nearest_cell(body, midline)
	_check(body.bone[bone_cell] == 1, "the midline sample is not over the vertebral column")
	var bone_hp: int = bone_cell * TissueGrid.LAYERS + TissueGrid.BONE
	var bites: int = 0
	while body.hp[bone_hp] > 0.0 and bites < 40:
		tissue.bite(_disc(midline, 6.0, 2.6), shed)
		bites += 1
	_check(bites > 4, "bone broke in %d bites — no harder to get through than flesh" % bites)

	# Damage is held in body space precisely so neither of these can wash it off.
	var scars: int = body.damaged.size()
	var integrity: float = tissue.integrity()
	_check(integrity < 1.0, "eating through the body did not reduce its integrity")
	target.rebuild()
	_check(is_equal_approx(tissue.integrity(), integrity),
		"a procedural rebuild restored lost tissue")
	_check(tissue.patch(TissueGrid.BODY_KEY).damaged.size() == scars,
		"a procedural rebuild erased the lattice's damage")

	target.params.segment_count = target.params.segment_count + 6
	target._physics_process(TICK)
	_check(target.spine.size() == target.params.segment_count,
		"changing segment count did not restructure the spine")
	_check(is_equal_approx(tissue.integrity(), integrity),
		"restructuring the spine remapped or erased existing damage")


## Bodies are solid. A creature driven at another is stopped by it, two that
## start inside each other push apart without stretching either spine, and a
## creature with nobody near it is not displaced by the pass at all.
func _check_contacts(player: Creature, target: Creature) -> void:
	# Held at full throttle straight into a stationary body for four seconds —
	# twice as long as it takes to cover the gap.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(220.0, 0.0), PI)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _i in 240:
		player.command = drive
		player._physics_process(TICK)
		target._physics_process(TICK)
	var nose_to_nose: float = player.head_pos.distance_to(target.head_pos)
	_check(player.head_pos.x < target.head_pos.x,
		"a creature driven at another walked straight through it")
	_check(nose_to_nose < player.body.head_radius + target.body.head_radius + 6.0,
		"the driven creature stopped %.0f px short of anything to stop it" % nose_to_nose)
	_check(absf(player.speed) < player.params.move_speed * 0.25,
		"a creature pressed against another kept its walking speed (%.0f px/s)" % player.speed)
	_check(_deepest_overlap(player, target) < 1.0,
		"a creature driven at another came to rest inside it")
	_check(player._push_out_of_creature(target).length() < 1.0,
		"capsule contacts found a resting overlap that point probes missed")

	# Laid down alongside each other, deeply interpenetrating: the worst case for
	# a chain solve, since the correction has to survive the constraint pass that
	# runs immediately after it.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(-70.0, 5.0), 0.0)
	var overlap_before: float = _deepest_overlap(player, target)
	_check(overlap_before > 10.0,
		"the contact case did not start overlapping (%.1f px) — it proves nothing" % overlap_before)

	# A contact correction is a change in the creature's world position, not a
	# deformation. Every current and previous particle must receive exactly the
	# same shift or the constraint solver will turn separation into body flailing.
	var points_before: PackedVector2Array = player.spine.points.duplicate()
	var prev_before: PackedVector2Array = player.spine.prev.duplicate()
	var head_before: Vector2 = player.head_pos
	player._resolve_contacts()
	var rigid_shift: Vector2 = player.head_pos - head_before
	_check(rigid_shift.length() > 0.1, "deep contact produced no correction")
	var nonrigid_error: float = 0.0
	for i in player.spine.size():
		nonrigid_error = maxf(nonrigid_error,
			(player.spine.points[i] - points_before[i] - rigid_shift).length())
		nonrigid_error = maxf(nonrigid_error,
			(player.spine.prev[i] - prev_before[i] - rigid_shift).length())
	_check(nonrigid_error < 0.001,
		"contact bent the spine while separating it (%.3f px non-rigid shift)" % nonrigid_error)

	# Reset because the direct pass above intentionally stopped between the
	# contact phase and the normal spine/body rebuild.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(-70.0, 5.0), 0.0)

	for _i in 180:
		player._physics_process(TICK)
		target._physics_process(TICK)
	var overlap_after: float = _deepest_overlap(player, target)
	_check(overlap_after < 1.0,
		"two creatures inside each other never separated (%.1f px still overlapping)" % overlap_after)
	_check(_worst_segment_error(player) < 0.05 and _worst_segment_error(target) < 0.05,
		"contact pushes stretched a spine past its segment lengths")

	# Nothing near it, nothing done to it: the contact pass must be inert at range
	# or every creature in the world would drift.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)
	var undisturbed: Vector2 = player.head_pos
	for _i in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(player.head_pos.is_equal_approx(undisturbed),
		"a creature with nobody near it was displaced by the contact pass")

	# Put another creature's snout directly through a lower foreleg while the
	# two torsos remain clear. The procedural gait must route the chain around
	# that body, retain exact bone lengths, and persist the displaced plant
	# instead of drawing the same penetrating pose again on every tick.
	player.reset(Vector2.ZERO, 0.0)
	var contact_limb: Limb = player.gait.limbs[0]
	var obstacle_at: Vector2 = contact_limb.joints[1].lerp(contact_limb.joints[2], 0.55)
	var relative_knee_before: Vector2 = contact_limb.joints[1] - contact_limb.joints[0]
	target.reset(obstacle_at, -PI * 0.5)
	var torso_overlap: float = player._push_out_of_creature(target).length()
	var limb_overlap_before: float = _limb_body_overlap(player, contact_limb, target)
	_check(torso_overlap < 1.0,
		"limb collision case also overlapped the torsos (%.2f px)" % torso_overlap)
	_check(limb_overlap_before > 8.0,
		"limb collision case did not start deeply intersecting (%.2f px)" % limb_overlap_before)

	for _i in 12:
		player._physics_process(TICK)
	var limb_overlap_after: float = _limb_body_overlap(player, contact_limb, target)
	var relative_knee_after: Vector2 = contact_limb.joints[1] - contact_limb.joints[0]
	_check(limb_overlap_after < 1.0,
		"procedural limb stayed inside the other body (%.2f px)" % limb_overlap_after)
	_check(relative_knee_after.distance_to(relative_knee_before) > 2.0,
		"colliding limb did not change its bend around the obstacle")
	for bone in 2:
		var actual: float = contact_limb.joints[bone].distance_to(contact_limb.joints[bone + 1])
		_check(absf(actual - contact_limb.lengths[bone]) < 0.05,
			"limb collision changed bone %d length by %.2f px" \
				% [bone, absf(actual - contact_limb.lengths[bone])])

	# Sparse, narrow chains crossing halfway along two long segments. None of
	# their spine points is inside the other body, so the former point-probe
	# solver saw no collision at all even though the drawn capsules intersected.
	var saved_player := CreatureParams.new()
	var saved_target := CreatureParams.new()
	saved_player.copy_from(player.params)
	saved_target.copy_from(target.params)
	for p: CreatureParams in [player.params, target.params]:
		p.segment_count = 6
		p.segment_length = 40.0
		p.body_wave = 0.0
		p.head_width = 1.0
		p.chest_width = 1.0
		p.waist_width = 1.0
		p.hip_width = 1.0
		p.tail_tip_width = 1.0
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(-20.0, 20.0), PI * 0.5)
	var endpoint_overlap: float = maxf(
		_deepest_overlap(player, target), _deepest_overlap(target, player))
	var capsule_overlap: float = player._push_out_of_creature(target).length()
	_check(endpoint_overlap < 0.001,
		"mid-segment regression accidentally touched an endpoint (%.2f px)" % endpoint_overlap)
	_check(capsule_overlap > 1.5,
		"crossing capsule axes were missed (%.2f px overlap reported)" % capsule_overlap)

	for _i in 30:
		player._physics_process(TICK)
		target._physics_process(TICK)
	_check(player._push_out_of_creature(target).length() < 0.1,
		"crossing mid-segments remained interlocked after contact resolution")

	player.params.copy_from(saved_player)
	target.params.copy_from(saved_target)
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(900.0, 0.0), 0.0)


## Deepest interpenetration of `a`'s body into `b`'s, in pixels.
func _deepest_overlap(a: Creature, b: Creature) -> float:
	var worst: float = 0.0
	var last: int = mini(a.body.last_index, a.spine.size() - 1)
	for i in range(last + 1):
		worst = maxf(worst, b.push_out_of_body(a.spine.points[i], a.body.widths[i]).length())
	return worst


func _worst_segment_error(creature: Creature) -> float:
	var seg_len: float = creature.params.segment_length * creature.size_scale
	var worst: float = 0.0
	for i in range(1, creature.spine.size()):
		var d: float = creature.spine.points[i - 1].distance_to(creature.spine.points[i])
		worst = maxf(worst, absf(d - seg_len) / seg_len)
	return worst


## Deepest overlap of either bone or the foot with `obstacle`'s body.
func _limb_body_overlap(owner: Creature, limb: Limb, obstacle: Creature) -> float:
	var upper_radius: float = maxf(limb.total_length * 0.16, 2.5 * owner.size_scale) * 0.5
	var radii: Array[float] = [upper_radius, upper_radius * 0.72]
	var preferred: Vector2 = owner.bounds_center - obstacle.bounds_center
	var worst: float = 0.0
	for segment in 2:
		worst = maxf(worst, obstacle.push_capsule_out_of_body(
			limb.joints[segment], limb.joints[segment + 1], radii[segment], preferred).length())
	var foot_radius: float = maxf(limb.total_length * 0.10, 3.0 * owner.size_scale)
	worst = maxf(worst, obstacle.push_capsule_out_of_body(
		limb.joints[2], limb.joints[2], foot_radius, preferred).length())
	return worst


func _nearest_cell(patch: TissueGrid.Patch, at: Vector2) -> int:
	var best: int = 0
	var best_distance: float = INF
	for cell in patch.cells:
		var d: float = patch.centre_of(cell).distance_squared_to(at)
		if d < best_distance:
			best_distance = d
			best = cell
	return best


## A plain disc of damage, for the checks below that are about the lattice
## rather than about any particular mouth. The teeth get their own section.
func _disc(at: Vector2, radius: float, depth: float) -> BiteMark:
	return BiteMark.mouthful(at, Vector2.RIGHT, radius, depth)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("combat slice OK — target, anatomy, tissue, lunge, cooldown, body and limb contacts")
		quit(0)
	else:
		for failure in failures:
			print("COMBAT FAIL — ", failure)
		quit(1)
