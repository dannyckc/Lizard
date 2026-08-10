## Calibration probe for the 3D anatomy lattice: builds each preset's lattice
## and prints its census, build cost and the physique read off it. Not a test —
## this is where Physique.REFERENCE_LATTICE_UNITS / _MUSCLE were measured, and
## the tool to re-measure them if the default build or the carve rules change.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/LatticeProbe.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

var main: Node
var done: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if done:
		return false
	done = true
	_run()
	quit(0)
	return true


func _run() -> void:
	var player: Creature = main.get_node("Creature")
	for preset in ["Lizard", "Cat", "Elephant", "Camel", "Cheetah", "T. rex", "Kangaroo"]:
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		var t0: int = Time.get_ticks_usec()
		player._physics_process(TICK)
		var first_tick: float = float(Time.get_ticks_usec() - t0) / 1000.0
		player._physics_process(TICK)
		var lat: AnatomyLattice = player.anatomy.tissue.lattice
		if lat == null:
			print("%s: NO LATTICE" % preset)
			continue
		var counts: PackedStringArray = PackedStringArray()
		for t in AnatomyLattice.TISSUES:
			counts.append("%s %d" % [AnatomyLattice.TISSUE_NAMES[t], lat.tissue_cells(t)])
		var regions: PackedStringArray = PackedStringArray()
		for r in BodyPlan.REGIONS:
			regions.append("%s %d" % [BodyPlan.REGION_NAMES[r], lat.region_cells(r)])
		print("%s: cells %d  units %.1f  axial %.1f  muscle %d  (built in %.1f ms)"
			% [preset, lat.standing_total, lat.standing_units, lat.axial_units,
				lat.tissue_cells(AnatomyLattice.MUSCLE), first_tick])
		print("    tissues: %s" % " · ".join(counts))
		print("    regions: %s" % " · ".join(regions))
		print("    physique: mass %.3f  strength %.3f  volume(cells) %.0f  limb_load %s"
			% [player.physique.mass, player.physique.strength, lat.volume(),
				player.physique.limb_load])
