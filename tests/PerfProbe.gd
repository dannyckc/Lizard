## Scenario profiler and behaviour digest for the simulation tick. Temporary
## diagnostic harness.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/PerfProbe.gd          # timings
##   ... --script tests/PerfProbe.gd -- --digest       # bit-exact state digest
##
## Drives the real habitat by hand rather than letting the engine tick it: a
## physics callback timed in place reports the 60 Hz interval it was called on,
## not the work it did. The scene is disabled, the nodes are walked in tree order
## and each one's `_physics_process` is called directly, so what comes out is the
## cost of the tick and nothing else.
##
## The digest mode runs the identical scenarios and folds every solved number of
## both bodies — head, spine, widths, limb poses, foot surfaces, stature — into
## one hash per scenario. It is what makes "no behaviour change" checkable rather
## than asserted: an optimisation that alters the simulation by one float in the
## fourth decimal moves the hash.
##
## Written to compile on either side of the terrain commit — anything that only
## exists on one side is reached through `load()` rather than by class name.
extends SceneTree

const TICK: float = 1.0 / 60.0
const WARMUP: int = 90
const SAMPLE: int = 400

var main: Node
var player: Node
var target: Node
var ticked: Array[Node] = []
var reticle_script: Script = null
var digest_mode: bool = false
var strip_terrain: bool = false
var digest: PackedFloat64Array = PackedFloat64Array()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	digest_mode = "--digest" in args
	strip_terrain = "--no-terrain" in args
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


## One idle frame later, so the scene is fully in the tree and every `_ready` has
## run — the habitat builds its terrain there, and a probe that measured before
## it would be timing an empty world.
func _process(_delta: float) -> bool:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	# Sensitivity control: with the obstacles taken out, any scenario whose digest
	# still matches never touched the terrain and is not evidence about it.
	var field: Node = main.get_node_or_null("Terrain")
	if strip_terrain and field != null:
		field.obstacles.clear()
	player = main.get_node("Creature")
	target = main.get_node("TargetCreature")
	if ResourceLoader.exists("res://scripts/world/Reticle.gd"):
		reticle_script = load("res://scripts/world/Reticle.gd")
	_collect(main)

	print("nodes ticked: %d" % ticked.size())
	print("terrain obstacles: %d" % _obstacle_count())
	print("")
	if digest_mode:
		print("%-26s %22s %12s" % ["scenario", "digest", "samples"])
	else:
		print("%-26s %8s %8s %8s %8s" % ["scenario", "mean ms", "med ms", "p95 ms", "max ms"])
	# Open floor, then the creature-to-creature cases, then one case per verdict
	# `Traversal` can return — the start positions walk the body straight at the
	# slab, the ledge, the boulder and the branch the habitat builds.
	_run("apart", 4000.0, false, false)
	_run("apart + aim", 4000.0, true, false)
	_run("contact", 150.0, false, false)
	_run("contact + aim", 150.0, true, false)
	_run("contact + aim + bite", 150.0, true, true)
	_run("over slab", 4000.0, false, false, Vector2(-400.0, 120.0))
	_run("mount ledge", 4000.0, false, false, Vector2(-380.0, -320.0))
	_run("into boulder", 4000.0, false, false, Vector2(200.0, 260.0))
	_run("under branch", 4000.0, false, false, Vector2(-760.0, 300.0))
	_run("terrain + contact", 150.0, true, false, Vector2(-380.0, -320.0))
	quit(0)
	return true


func _obstacle_count() -> int:
	var field: Node = main.get_node_or_null("Terrain")
	return 0 if field == null else int(field.obstacles.size())


## Tree order, parent before child, which is the order the engine would use.
func _collect(node: Node) -> void:
	if node.has_method("_physics_process") and node != main:
		ticked.append(node)
	for child in node.get_children():
		_collect(child)


func _run(label: String, separation: float, aim: bool, bite: bool,
		start: Vector2 = Vector2.ZERO) -> void:
	player.reset(start, 0.0)
	target.reset(start + Vector2(separation, 0.0), PI)
	digest = PackedFloat64Array()
	var samples: PackedFloat64Array = PackedFloat64Array()
	for i in range(WARMUP + SAMPLE):
		var started: int = Time.get_ticks_usec()
		_tick(aim, bite, i)
		var elapsed: float = float(Time.get_ticks_usec() - started) / 1000.0
		if digest_mode:
			_capture(player)
			_capture(target)
		elif i >= WARMUP:
			samples.append(elapsed)
	if digest_mode:
		print("%-26s %22d %12d" % [label, hash(digest), digest.size()])
	else:
		_report(label, samples)


func _tick(aim: bool, bite: bool, frame: int) -> void:
	player.command.throttle = 1.0
	player.command.turn = 0.0
	player.command.sprint = false
	if aim and reticle_script != null:
		player.aim_at(reticle_script.pick(self, target.bounds_center,
			reticle_script.SLACK, player))
	if bite and frame % 40 == 0:
		player.set_bite_held(true)
		player.request_bite(target.bounds_center)
	for node in ticked:
		node._physics_process(TICK)


## Everything the solver decided this tick, in the order it decided it.
func _capture(creature: Node) -> void:
	digest.append(creature.head_pos.x)
	digest.append(creature.head_pos.y)
	digest.append(creature.heading)
	digest.append(creature.speed)
	digest.append(creature.ang_vel)
	digest.append(creature.bounds_radius)
	for p in creature.spine.points:
		digest.append(p.x)
		digest.append(p.y)
	for w in creature.body.widths:
		digest.append(w)
	for limb in creature.gait.limbs:
		for point in limb.plan:
			digest.append(point.x)
			digest.append(point.y)
		digest.append(limb.surface if "surface" in limb else 0.0)
		digest.append(1.0 if limb.stepping else 0.0)
	digest.append(creature.stature.trunk.x)
	digest.append(creature.stature.trunk.y)
	digest.append(creature.stature.elevation)
	digest.append(creature.physique.mass)
	digest.append(creature.anatomy.tissue.integrity())


func _report(label: String, samples: PackedFloat64Array) -> void:
	var sorted: Array = Array(samples)
	sorted.sort()
	var total: float = 0.0
	for s in sorted:
		total += s
	var n: int = sorted.size()
	print("%-26s %8.3f %8.3f %8.3f %8.3f" % [label, total / float(n),
		sorted[n / 2], sorted[int(float(n) * 0.95)], sorted[n - 1]])
