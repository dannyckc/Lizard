## The Phase-4 cost comparison: what one creature's view costs a frame, v1
## against v2 — see docs/V2_DESIGN.md §11.2, "RenderBenchmark comparison".
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/SkinBench.gd
##
## RenderBenchmark itself measures the whole game scene and cannot see v2 at
## all until the Phase-7 cutover, so what is compared here is the thing that
## actually changed: the geometry a creature's view produces every frame, and
## the CPU time it takes to produce it. Both sides are driven by hand rather
## than by the engine's callbacks (the PerfProbe lesson: timing a physics
## callback measures the 60 Hz interval, not the work), and both sides are run
## whole and then chewed, because the v1 claim under test is that cost scales
## with volume in cells and the v2 claim is that it does not.
##
## Deterministic and headless on purpose: the printed draw count of a real
## frame swings by an order of magnitude run to run (v1 lesson), so nothing
## here is a GPU measurement pretending to be one.
extends SceneTree

const TICK: float = 1.0 / 60.0
const RUNS: int = 200

var main: Node
var lab: Node
var stage: int = 0
var v1_quads: int = 0
var v1_us: float = 0.0
var v1_chewed_quads: int = 0
var v1_chewed_us: float = 0.0
## What the same two animals cost v1's census, which is the half of the old cost
## that grew without limit: an elephant carried fifteen times a cat's cells.
var v1_cat_cells: int = 0
var v1_elephant_cells: int = 0


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	match stage:
		0:
			_measure_v1()
			main.queue_free()
			lab = load("res://scenes/V2Lab.tscn").instantiate()
			root.add_child(lab)
			stage = 1
		1:
			_measure_v2()
			quit(0)
	return false


# ------------------------------------------------------------------- v1 ----

## v1's CreatureView emits one quad per surviving cell of the lattice, every
## frame, per structure — the mesh the whole draw is built out of.
func _measure_v1() -> void:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.terrain.clear()
	var player: Creature = main.get_node("Creature")
	player.params.apply_preset("Cat")
	player.rebuild()
	player.reset(Vector2.ZERO, 0.0)
	var ticked: Array[Node] = []
	_collect(main, ticked)
	for _i in 60:
		player.command.throttle = 1.0
		for node in ticked:
			node._physics_process(TICK)

	var view: CreatureView = player.get_node("View")
	v1_quads = _v1_build(player, view)
	v1_us = _best(func() -> void: _v1_build(player, view))

	# ...and the same animal with a good deal bitten out of it. Fewer cells is
	# less geometry in v1, which is the shape of the old cost: it is a function
	# of how much animal there is.
	var tissue: TissueGrid = player.anatomy.tissue
	var torso: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	for cell in range(0, torso.gone.size(), 3):
		if torso.gone[cell] == 0:
			torso.gone[cell] = 1
			torso.gone_count += 1
	v1_chewed_quads = _v1_build(player, view)
	v1_chewed_us = _best(func() -> void: _v1_build(player, view))

	# The census behind that mesh, for a cat and for an elephant. This is the
	# half of v1's cost that grew with the animal.
	v1_cat_cells = player.anatomy.tissue.lattice.count
	player.params.apply_preset("Elephant")
	player.rebuild()
	player.reset(Vector2.ZERO, 0.0)
	v1_elephant_cells = player.anatomy.tissue.lattice.count


func _v1_build(player: Creature, view: CreatureView) -> int:
	var tissue: TissueGrid = player.anatomy.tissue
	var quads: int = view._build(tissue.patch(TissueGrid.BODY_KEY), 0, TissueGrid.BODY_COLS)
	for limb in player.gait.limbs:
		quads += view._build(tissue.patch(limb.key), 0, TissueGrid.LIMB_COLS)
	return quads


## Microseconds a frame, best of three batches — one run of anything on a
## machine with other work on it is noise, and the fastest batch is the one
## least contaminated by that work.
func _best(work: Callable) -> float:
	var best: float = INF
	for _batch in 3:
		var started: int = Time.get_ticks_usec()
		for _i in RUNS:
			work.call()
		best = minf(best, float(Time.get_ticks_usec() - started) / float(RUNS))
	return best


func _collect(node: Node, into: Array[Node]) -> void:
	if node.has_method("_physics_process") and node != main:
		into.append(node)
	for child in node.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
		_collect(child, into)


# ------------------------------------------------------------------- v2 ----

func _measure_v2() -> void:
	lab.terrain.clear()
	var creature: Creature2 = lab.creature
	creature.command.throttle = 1.0
	for _i in 60:
		creature._physics_process(TICK)

	var skin: Contour = creature.contour
	var likeness: Likeness = lab.get_node("Creature2/Likeness")
	var frame: Callable = func() -> void:
		skin.pose()
		likeness._project(skin)
		likeness._shade(skin)
	var posed: float = _best(frame)

	for st in range(0, 10):
		for sec in range(0, 6):
			creature.corpus.gouge(BodySchema.TRUNK, st, sec, 14.0)
	skin.refresh()
	var chewed: float = _best(frame)

	# v1's figure is its mesh build alone — its shadows, its per-station raise
	# and its tissue grain are all extra, and left out to be generous to it.
	print("v1 view : %d quads rebuilt and recoloured every frame, %.0f us · chewed %d quads, %.0f us"
		% [v1_quads, v1_us, v1_chewed_quads, v1_chewed_us])
	print("v2 view : %d facets posed and projected every frame, %.0f us · chewed %d facets, %.0f us"
		% [skin.facet_count(), posed, skin.facet_count(), chewed])
	print("        %.1fx the geometry at %.1fx the cost — and the ink is re-read only when"
		% [float(skin.facet_count()) / maxf(float(v1_quads), 1.0),
			posed / maxf(v1_us, 0.001)])
	print("        a wound moves the census, where v1 recoloured every cell every frame")
	print("v1 census: %d cells for a cat, %d for an elephant — cost with volume"
		% [v1_cat_cells, v1_elephant_cells])
	print("v2 census: %d columns / %d cells for either, and %d facets over them — cost with surface"
		% [creature.corpus.columns, creature.corpus.columns * 4, skin.facet_count()])
