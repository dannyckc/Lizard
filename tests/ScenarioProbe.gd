## Scenario profiler for the costs that once made the game hitch: a Cheetah at
## full sprint, jaws closing on empty air, a body being bitten to shreds, and a
## structural rebuild. PerfProbe times the steady tick; this times the events.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/ScenarioProbe.gd
##
## Drives the habitat by hand exactly as PerfProbe does — the scene is disabled
## and each node's `_physics_process` is called directly — so what is reported
## is the cost of the work and not the interval it was scheduled on. The
## rebuild section is the one place the numbers are expected to stay large:
## carving the cell lattice is the most expensive single operation a creature
## owns, and what these figures guard is that it happens only when the body's
## description genuinely changed.
extends SceneTree

const TICK: float = 1.0 / 60.0

var main: Node
var player: Node
var target: Node
var ticked: Array[Node] = []


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	player = main.get_node("Creature")
	target = main.get_node("TargetCreature")
	_collect(main)

	print("=== default build, walk ===")
	_run_walk(false)
	print("=== Cheetah, sprint ===")
	player.params.apply_preset("Cheetah")
	player.rebuild()
	_run_walk(true)
	print("")
	print("=== per-node cost during cheetah sprint (mean over 300) ===")
	_run_walk_per_node(true)
	print("")
	print("=== bite empty space (Cheetah): each phase ===")
	_time_bite_empty()
	print("")
	print("=== bite target repeatedly to shreds (default target) ===")
	_time_shred()
	print("")
	print("=== rebuild cost ===")
	_time_rebuild()
	quit(0)
	return true


func _collect(node: Node) -> void:
	if node.has_method("_physics_process") and node != main:
		ticked.append(node)
	for child in node.get_children():
		_collect(child)


func _tick_all() -> void:
	for node in ticked:
		node._physics_process(TICK)


func _run_walk(sprint: bool) -> void:
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(4000.0, 0.0), PI)
	var samples: PackedFloat64Array = PackedFloat64Array()
	for i in 400:
		player.command.throttle = 1.0
		player.command.turn = 0.0
		player.command.sprint = sprint
		var started: int = Time.get_ticks_usec()
		_tick_all()
		if i >= 100:
			samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	_report("tick", samples)
	print("  speed reached: %.0f px/s" % player.speed)


func _run_walk_per_node(sprint: bool) -> void:
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(4000.0, 0.0), PI)
	var totals: Dictionary = {}
	for i in 400:
		player.command.throttle = 1.0
		player.command.sprint = sprint
		for node in ticked:
			var started: int = Time.get_ticks_usec()
			node._physics_process(TICK)
			if i >= 100:
				totals[node.name] = totals.get(node.name, 0.0) \
					+ float(Time.get_ticks_usec() - started) / 1000.0
	for key in totals:
		print("  %-18s %8.4f ms" % [key, totals[key] / 300.0])


func _time_bite_empty() -> void:
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(4000.0, 0.0), PI)
	for i in 60:
		_tick_all()
	# Warm dentition.
	player.bite_mark(player.jaw_point(), player.bite_depth())
	var t0: int = Time.get_ticks_usec()
	var mark = null
	for i in 50:
		mark = player.bite_mark(player.jaw_point(), player.bite_depth())
	print("  bite_mark x50:        %8.3f ms  (%d impressions)" % [
		float(Time.get_ticks_usec() - t0) / 1000.0, mark.impressions.size()])
	t0 = Time.get_ticks_usec()
	for i in 50:
		player.query_bite(mark.center, mark.radius, mark.reach)
	print("  hit_test self x50:    %8.3f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	# Full bite path through the world resolver, on empty space.
	var samples: PackedFloat64Array = PackedFloat64Array()
	for i in 30:
		var started: int = Time.get_ticks_usec()
		player.set_bite_held(true)
		player.request_bite(player.head_pos + Vector2(80.0, 0.0))
		# run the strike frame
		for k in 12:
			_tick_all()
		player.set_bite_held(false)
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		for k in 30:
			_tick_all()
	_report("full lunge cycle (12 ticks incl strike)", samples)
	# Isolate tissue.bite on empty overlap: mark far from any patch
	var far_mark = player.bite_mark(Vector2(9999.0, 9999.0), player.bite_depth())
	var shed: Array = []
	t0 = Time.get_ticks_usec()
	for i in 200:
		target.anatomy.tissue.bite(far_mark, shed)
	print("  tissue.bite far x200: %8.3f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))


func _time_shred() -> void:
	player.reset(Vector2.ZERO, 0.0)
	target.reset(Vector2(150.0, 0.0), PI)
	for i in 60:
		_tick_all()
	var carrion = main.get_node("CarrionField")
	var scraps = main.get_node("ScrapField")
	var worst: float = 0.0
	var total: float = 0.0
	var bites: int = 0
	for i in 400:
		player.command.throttle = 0.6
		player.command.sprint = false
		if i % 20 == 0:
			player.set_bite_held(true)
			player.request_bite(target.bounds_center)
		if i % 20 == 10:
			player.set_bite_held(false)
		var started: int = Time.get_ticks_usec()
		_tick_all()
		var ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		total += ms
		if ms > worst:
			worst = ms
		bites += 1
	print("  400 ticks with a bite every 20: mean %.3f  worst %.3f ms" % [total / 400.0, worst])
	print("  target integrity: %.2f | parts %d | scraps %d | detached pieces seen" % [
		target.anatomy.tissue.integrity(), carrion.parts.size(), scraps.scraps.size()])
	# keep chewing the pieces
	var samples: PackedFloat64Array = PackedFloat64Array()
	for i in 400:
		if i % 15 == 0 and not carrion.parts.is_empty():
			var part = carrion.parts[0]
			player.set_bite_held(true)
			player.request_bite(part.center())
		if i % 15 == 8:
			player.set_bite_held(false)
		var started: int = Time.get_ticks_usec()
		_tick_all()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	_report("chewing carrion", samples)
	print("  parts %d | scraps %d | scent %d" % [carrion.parts.size(),
		scraps.scraps.size(), main.get_node("ScentField").traces.size()])


func _time_rebuild() -> void:
	player.reset(Vector2.ZERO, 0.0)
	for i in 30:
		_tick_all()
	var t0: int = Time.get_ticks_usec()
	for i in 20:
		player.rebuild()
	print("  rebuild x20 (same params):    %8.3f ms total, %.3f each" % [
		float(Time.get_ticks_usec() - t0) / 1000.0,
		float(Time.get_ticks_usec() - t0) / 20000.0])
	# Structural change: nudge limb length back and forth (lattice re-carve)
	t0 = Time.get_ticks_usec()
	for i in 20:
		player.params.leg_length += 1.0 if i % 2 == 0 else -1.0
		player.rebuild()
	print("  rebuild x20 (leg_length +/-): %8.3f ms total, %.3f each" % [
		float(Time.get_ticks_usec() - t0) / 1000.0,
		float(Time.get_ticks_usec() - t0) / 20000.0])


func _report(label: String, samples: PackedFloat64Array) -> void:
	var sorted: Array = Array(samples)
	sorted.sort()
	var total: float = 0.0
	for s in sorted:
		total += s
	var n: int = sorted.size()
	print("  %-38s mean %7.3f  med %7.3f  p95 %7.3f  max %7.3f ms" % [label,
		total / float(n), sorted[n / 2], sorted[int(float(n) * 0.95)], sorted[n - 1]])
