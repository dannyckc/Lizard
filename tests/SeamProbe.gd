## Measures the posed tear at each limb-trunk seam: every lattice cell of a limb
## patch that canonically touches a body-patch cell is posed through its own
## patch affine, its neighbour through the body's, and the gap between the two
## posed points is reported. Contiguous flesh should come out about one cell
## apart; anything more is the seam the side view shows. Throwaway scaffolding.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       --script tests/SeamProbe.gd -- --preset Cat
extends SceneTree

var main: Node
var frames: int = 0
var preset: String = "Cat"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--preset" and i + 1 < args.size():
			preset = args[i + 1]
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		var player: Creature = main.get_node("Creature")
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		main.hud.set_view(EvolutionHUD.VIEW_ANATOMY)
		return false
	if frames < 20:
		return false
	_report()
	quit(0)
	return false


func _report() -> void:
	var view: AnatomyView = main.hud.anatomy.view
	view.size = Vector2(340.0, 326.0)
	# Side-on, so the vertical part of any tear is in the page too.
	view.spin = 0.0
	view.tilt = 1.45
	for _s in 8:
		view._settle(1.0)
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null:
		print("no lattice")
		return
	view._refresh_stations(grid)
	var cell_px: float = AnatomyLattice.CELL * view._scale
	print("=== %s: cell on page %.2f px ===" % [preset, cell_px])
	for pk in range(1, AnatomyLattice.PATCH_KEYS.size()):
		var worst: float = 0.0
		var total: float = 0.0
		var pairs: int = 0
		var worst_i: int = -1
		var worst_n: int = -1
		for i in lat.count:
			if lat.patch_of[i] != pk:
				continue
			var base: int = i * 6
			for k in 6:
				var n: int = lat.neighbor[base + k]
				if n < 0 or lat.patch_of[n] != 0:
					continue
				var a: Vector3 = view._cell_at(lat, i)
				var b: Vector3 = view._cell_at(lat, n)
				var gap: float = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))
				total += gap
				pairs += 1
				if gap > worst:
					worst = gap
					worst_i = i
					worst_n = n
		if pairs == 0:
			print("%s: no seam pairs at all — the limb never touches the trunk"
				% AnatomyLattice.PATCH_KEYS[pk])
			continue
		print("%s: %d seam pairs · mean gap %.2f px (%.1f cells) · worst %.2f px (%.1f cells)"
			% [AnatomyLattice.PATCH_KEYS[pk], pairs, total / float(pairs),
				total / float(pairs) / cell_px, worst, worst / cell_px])
		if worst_i >= 0:
			print("    worst: limb cell canon %s station %.2f · body cell canon %s station %.2f"
				% [lat.pos[worst_i], lat.station[worst_i], lat.pos[worst_n],
					lat.station[worst_n]])
