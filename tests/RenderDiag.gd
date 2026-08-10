## Diagnoses the anatomy specimen's mark coverage: cross-sections of the lattice,
## draw-list composition per view, and the page-space extents of the marks.
## Throwaway scaffolding for the rendering rework.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/RenderDiag.gd -- --preset Lizard
extends SceneTree

var main: Node
var frames: int = 0
var preset: String = "Lizard"

const LETTER := "SFMBONV"


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
	if frames < 30:
		return false
	_report()
	quit(0)
	return false


func _view() -> AnatomyView:
	return main.hud.anatomy.view


func _report() -> void:
	var view: AnatomyView = _view()
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null or grid == null:
		print("no lattice")
		return

	print("=== %s: %d cells ===" % [preset, lat.count])
	var by_kind: Array = [0, 0, 0, 0, 0, 0, 0]
	for i in lat.count:
		by_kind[lat.kind[i]] += 1
	for t in 7:
		print("  %s: %d" % [AnatomyLattice.TISSUE_NAMES[t], by_kind[t]])

	# Cross sections of the trunk at several stations: tissue letter per (y,z).
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in lat.count:
		if lat.patch_of[i] != 0:
			continue
		lo = lo.min(lat.pos[i])
		hi = hi.max(lat.pos[i])
	for fx in [0.15, 0.35, 0.5, 0.75]:
		var x: float = lerpf(lo.x, hi.x, fx)
		var ix: int = floori(x / AnatomyLattice.CELL)
		print("--- section x=%.0f (fx %.2f) ---" % [x, fx])
		var rows: Dictionary = {}
		for i in lat.count:
			if lat.patch_of[i] != 0:
				continue
			if floori(lat.pos[i].x / AnatomyLattice.CELL) != ix:
				continue
			var iy: int = floori(lat.pos[i].y / AnatomyLattice.CELL)
			var iz: int = floori(lat.pos[i].z / AnatomyLattice.CELL)
			if not rows.has(iz):
				rows[iz] = {}
			rows[iz][iy] = LETTER[lat.kind[i]]
		var zs: Array = rows.keys()
		zs.sort()
		zs.reverse()
		for iz in zs:
			var cols: Dictionary = rows[iz]
			var ys: Array = cols.keys()
			ys.sort()
			var line: String = "z%3d  " % iz
			for iy in range(ys[0], ys[ys.size() - 1] + 1):
				line += cols.get(iy, ".")
			print(line)

	# Draw-list composition, intact and peeled, top-down.
	view.reset_orbit()
	for mode in 2:
		view.layers = AnatomyView.ALL_LAYERS
		if mode == 1:
			view.set_layer_shown(AnatomyLattice.SKIN, false)
			view.set_layer_shown(AnatomyLattice.FAT, false)
		view._draw_key = 0
		view._refresh_stations(grid)
		view._refresh_draw_list(lat, grid)
		var counts: Array = [0, 0, 0, 0, 0, 0, 0]
		for j in view._draw_list.size():
			counts[lat.kind[view._draw_list[j]]] += 1
		print("--- %s draw list: %d cells, lod %d ---"
			% ["peeled" if mode == 1 else "intact", view._draw_list.size(), view._lod])
		for t in 7:
			if counts[t] > 0:
				print("  %s: %d" % [AnatomyLattice.TISSUE_NAMES[t], counts[t]])
		# Facing survival and normal distribution for what is listed.
		var facing: int = 0
		var edge_on: int = 0
		for j in view._draw_list.size():
			var i: int = view._draw_list[j]
			var out: Vector3 = lat.normal[i]
			# Top-down: lit is effectively the z component blended through the
			# station frame; approximate with |z| here to classify.
			if out.z > -AnatomyView.FACING_CUT:
				facing += 1
			if absf(out.z) < 0.35:
				edge_on += 1
		print("  facing up: %d · near edge-on from above: %d" % [facing, edge_on])
		print("  scale %.2f · cell on page %.2f px"
			% [view._scale, AnatomyLattice.CELL * view._scale])

	# Chain visibility, peeled: is the skeleton showing as tubes?
	var vis: int = 0
	for s in view._sample_vis.size():
		if view._sample_vis[s] != 0:
			vis += 1
	print("--- chains: %d samples total, %d visible peeled ---"
		% [view._form.sample_total, vis])
	var kinds_of_chains: Dictionary = {}
	for c in view._form.chain_count:
		var t: int = int(view._form.chain_kind[c])
		kinds_of_chains[t] = kinds_of_chains.get(t, 0) + 1
	print("  chains by tissue: %s" % str(kinds_of_chains))

	# The quads actually drawn last frame, intact: how big did they come out, and
	# which are abnormally long on the page?
	view.layers = AnatomyView.ALL_LAYERS
	view._draw_key = 0
	view._refresh_stations(grid)
	view._refresh_draw_list(lat, grid)
	view._draw_cells(lat, grid)
	var n: int = view._shown_count
	print("--- drawn quads intact: %d ---" % n)
	var overlong: int = 0
	var biggest: Array = []
	for q in n:
		var v: int = q * 4
		var lo2: Vector2 = view._points[v]
		var hi2: Vector2 = view._points[v]
		for k in range(1, 4):
			lo2 = lo2.min(view._points[v + k])
			hi2 = hi2.max(view._points[v + k])
		var ext: float = (hi2 - lo2).length()
		if ext > 12.0:
			overlong += 1
			if biggest.size() < 12:
				var i2: int = view._shown[q]
				biggest.append("  quad %d ext %.1f  cell %d kind %s normal %s pos %s"
					% [q, ext, i2, AnatomyLattice.TISSUE_NAMES[lat.kind[i2]],
						str(lat.normal[i2]), str(lat.pos[i2])])
	print("  quads with page extent > 12px: %d" % overlong)
	for line in biggest:
		print(line)
