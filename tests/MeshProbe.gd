## Prints the specimen mesh ring by ring: how many sectors of each band found a
## cell, the band's mean station and its mean reach. Throwaway scaffolding for
## the low-poly rework.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       --script tests/MeshProbe.gd -- --preset Lizard
extends SceneTree

var main: Node
var frames: int = 0
var preset: String = "Lizard"


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
	for _s in 8:
		view._settle(1.0)
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null:
		print("no lattice")
		return
	view._draw_key = 0
	view._refresh_stations(grid)
	view._refresh_draw_list(lat, grid)
	var mesh: SpecimenMesh = view._mesh
	print("=== %s: %d cells, surface %d, verts %d, facets %d ==="
		% [preset, lat.count, view._draw_list.size(), mesh.v_count, mesh.count])

	# Rebuild the buckets by hand, since the mesh keeps only the finished facets.
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(5)
	hi.resize(5)
	lo.fill(INF)
	hi.fill(-INF)
	for i in view._draw_list:
		var pk0: int = lat.patch_of[i]
		var u0: float = lat.pos[i].x if pk0 == 0 else -lat.pos[i].z
		lo[pk0] = minf(lo[pk0], u0)
		hi[pk0] = maxf(hi[pk0], u0)
	var per_band: Dictionary = {}
	for i in view._draw_list:
		var pk: int = lat.patch_of[i]
		var bands: int = SpecimenMesh.bands_of(pk)
		var sectors: int = SpecimenMesh.sectors_of(pk)
		var span: float = hi[pk] - lo[pk]
		var step: float = AnatomyLattice.CELL if span <= 0.0 \
			else maxf(AnatomyLattice.CELL, span / float(bands - 1))
		var u: float = lat.pos[i].x if pk == 0 else -lat.pos[i].z
		var band: int = clampi(int((u - lo[pk]) / step), 0, bands - 1)
		var ax: float = lat.lat[i]
		var ay: float = lat.lift[i] if pk == 0 else lat.fore[i]
		var r: float = sqrt(ax * ax + ay * ay)
		var sector: int = int(fposmod(atan2(ax, ay), TAU) / TAU * float(sectors)) % sectors
		var key: int = pk * 1000 + band
		var row = per_band.get(key)
		if row == null:
			row = {}
			per_band[key] = row
		row[sector] = maxf(row.get(sector, 0.0), r)

	for pk in AnatomyLattice.PATCH_KEYS.size():
		var sectors: int = SpecimenMesh.sectors_of(pk)
		print("--- patch %s (%d sectors) ---" % [AnatomyLattice.PATCH_KEYS[pk], sectors])
		for band in SpecimenMesh.bands_of(pk):
			var row = per_band.get(pk * 1000 + band)
			if row == null:
				continue
			var total: float = 0.0
			for s in row:
				total += row[s]
			print("  band %2d: %2d/%2d sectors, mean r %.2f"
				% [band, row.size(), sectors, total / float(row.size())])

	# Tissue mix of the surface, which is what the mesh takes its colour from.
	var kinds: Array = [0, 0, 0, 0, 0, 0, 0]
	for i in view._draw_list:
		kinds[lat.kind[i]] += 1
	var bits: PackedStringArray = PackedStringArray()
	for t in 7:
		if kinds[t] > 0:
			bits.append("%s %d" % [AnatomyLattice.TISSUE_NAMES[t], kinds[t]])
	print("surface tissues: %s" % " · ".join(bits))
	_sweep(view)


## Runs the pointer over the whole stage and reports how much of the specimen
## answers it — the check that matters after the hit test stopped being a box
## around a cell and became the facet's own polygon.
func _sweep(view: AnatomyView) -> void:
	view._place_marks(view.lattice())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in view._shown_count:
		lo = lo.min(view._cell_page[j])
		hi = hi.max(view._cell_page[j])
	var hits: int = 0
	var tried: int = 0
	var named: Dictionary = {}
	for ix in 60:
		for iy in 60:
			var at := Vector2(lerpf(lo.x, hi.x, float(ix) / 59.0),
				lerpf(lo.y, hi.y, float(iy) / 59.0))
			tried += 1
			view._hover_voxel = -1
			view._pick(at)
			if view._hover_voxel < 0:
				continue
			hits += 1
			var word: String = view._readout(view.lattice(), view.tissue(),
				view._hover_voxel).split(" · ")[0]
			named[word] = int(named.get(word, 0)) + 1
	print("hover: %d of %d points over the specimen's own box answered · reach %.1f px"
		% [hits, tried, view._pick_reach])
	var regions: PackedStringArray = PackedStringArray()
	for word in named:
		regions.append("%s %d" % [word, named[word]])
	print("  read out: %s" % " · ".join(regions))
