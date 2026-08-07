## Focused first-slice test for mouse aim, anatomy queries, persistent tissue and
## the one-click/one-bite cooldown contract.
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

	var removed: float = target.apply_bite_hit(head_hit, 0.25, 8.0)
	_check(is_equal_approx(removed, 0.25), "bite did not remove the requested tissue")
	_check(is_equal_approx(target.anatomy.health_of("head"), 0.75),
		"head tissue health was not persisted")
	_check(target.anatomy.wounds.size() == 1, "successful bite did not record one wound")
	target.rebuild()
	_check(target.anatomy.wounds.size() == 1, "procedural rebuild erased persistent wounds")

	# Mouse aim turns without secretly applying forward throttle.
	var mouse_input := MovementInput.new()
	var aimed: MovementInput.Command = mouse_input.read(Vector2.ZERO, 0.0, Vector2(0.0, 100.0))
	_check(aimed.turn > 0.9, "always-on mouse aim did not steer toward the cursor")
	_check(absf(aimed.throttle) < 0.001, "mouse aim still applied point-and-go throttle")

	# Put the two heads inside bite range and exercise the real signal/world
	# resolver path used by a left click.
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(50.0, 0.0), PI)
	var accepted: bool = player.request_bite(Vector2(100.0, 0.0))
	_check(accepted, "ready player rejected a bite request")
	player._physics_process(TICK)
	_check(target.anatomy.wounds.size() == 1, "bite event did not damage the nearby target")
	_check(player.bite_connected, "landed bite was reported as a miss")
	_check(player.bite_cooldown_remaining > 0.0, "bite did not start its cooldown")
	_check(not player.request_bite(Vector2(100.0, 0.0)),
		"second click was accepted during bite cooldown")

	for _i in 32:
		player._physics_process(TICK)
	_check(player.can_bite(), "bite did not become ready after its cooldown")

	main.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("combat slice OK — target, anatomy, persistent wounds, aim and cooldown")
		quit(0)
	else:
		for failure in failures:
			print("COMBAT FAIL — ", failure)
		quit(1)
