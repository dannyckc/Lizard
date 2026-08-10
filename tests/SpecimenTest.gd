## The Anatomy tab's specimen mesh, checked as the claim it makes rather than as
## a picture: that the low-poly surface is skinned off the creature's own cell
## lattice, that every facet on it names a real standing cell, that peeling a
## tissue drops the surface onto the layer underneath, that a bite is a dent in
## the geometry and a severed limb is missing from it, that the mesh costs the
## same on an elephant as on a lizard, and that the pointer still reads a cell.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/SpecimenTest.gd
extends SceneTree

var failures: Array[String] = []
var main: Node
var checked: bool = false
var summary: String = "not reached"


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var view: AnatomyView = (main.hud as EvolutionHUD).anatomy.view
	view.creature = main.creature
	view.size = Vector2(340.0, 326.0)
	_settled(view)

	var lizard: int = _check_skin(view)
	var small: int = main.creature.anatomy.tissue.lattice.built_total
	_check_layers(view)
	_check_peel(view)
	_check_flare(view)
	_check_wounds(view)
	var elephant: int = _check_cost(view, lizard)
	var large: int = main.creature.anatomy.tissue.lattice.built_total
	_check_hover(view)
	summary = "%d facets over a lizard's %d cells, %d over an elephant's %d" % [
		lizard, small, elephant, large]
	_finish()
	return false


## The mesh is the animal: it covers every region the creature has, and every
## facet on it stands on a cell that is really there and really being shown.
func _check_skin(view: AnatomyView) -> int:
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	_check(lat != null and grid != null, "the specimen had no lattice to skin")
	if lat == null:
		return 0
	_rebuild(view, lat, grid)
	var mesh: SpecimenMesh = view._mesh
	_check(mesh.count > 0, "the specimen skinned no facets at all")

	var honest: bool = true
	var hidden: bool = false
	var seen: Dictionary = {}
	for q in mesh.count:
		var cell: int = mesh.f_cell[q]
		if cell < 0 or cell >= lat.count:
			honest = false
			continue
		if lat.gone[cell] != 0 or not view.tissue_shown(lat.kind[cell]):
			hidden = true
		seen[int(lat.region[cell])] = true
	_check(honest, "a facet named a cell the lattice does not have")
	_check(not hidden, "a facet was skinned off flesh that is gone or not being shown")
	# Every region of a whole animal is on its own surface. A mesh that has lost
	# a leg or a head is the failure this catches, and it is the failure a ring
	# skin is most prone to.
	for reg in BodyPlan.REGIONS:
		if lat.region_cells(reg) > 0:
			_check(seen.has(reg), "the mesh had no facet anywhere on the %s"
				% grid.plan.region_name(reg))

	# Four corners apiece, and every one of them a vertex that exists.
	var wired: bool = mesh.f_v.size() == mesh.count * 4
	for v in mesh.f_v:
		wired = wired and v >= 0 and v < mesh.v_count
	_check(wired, "a facet pointed at a vertex the mesh does not have")
	return mesh.count


## What a toggle promises, asked of every tissue in turn: everything the layer is
## showing is on the slab, and nothing else is.
##
## The half that used to fail is the first one. A ring skin can only make a
## surface out of a tissue that goes most of the way round the body, and the
## skeleton, the fat on a lean animal and the two supply networks do not — so a
## specimen showing them alone came up empty or nearly so, which is a panel
## saying the animal has no bones in it. Every representation the specimen has —
## the mesh, the chains' own tubes, the loose cells — is asked here at once,
## because which of the three a tissue is drawn by is this file's business and
## not the player's.
##
## The second half is the older promise and still worth holding: a tissue that is
## off is off. Not dimmed, not behind something — absent.
func _check_layers(view: AnatomyView) -> void:
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null or grid == null:
		return
	for t in AnatomyLattice.TISSUES:
		view.layers = 0
		view.show_vessels = t == AnatomyLattice.VESSEL
		view.show_nerves = t == AnatomyLattice.NERVE
		if t < AnatomyLattice.NERVE:
			view.layers = 1 << t
		_rebuild(view, lat, grid)
		view._place_marks(lat)
		var mine: int = 0
		var strays: Dictionary = {}
		for j in view._shown_count:
			# What the cell is being shown *as*. Where the animal is too thin for
			# the lattice to hold a cell of skin, the outermost cell wears its skin
			# as a sheath and is drawn as skin while the skin is on — so with the
			# skin isolated it is one of the skin's own cells, and with anything
			# else isolated it is the tissue underneath. Either way it is the
			# tissue asked for, and neither reading is a stray.
			var cell: int = view._shown[j]
			var kind: int = AnatomyLattice.SKIN \
				if t == AnatomyLattice.SKIN and lat.sheathed[cell] != 0 \
				else int(lat.kind[cell])
			if kind == t:
				mine += 1
			else:
				strays[kind] = true
		var name: String = AnatomyLattice.TISSUE_NAMES[t]
		if lat.tissue_cells(t) > 0:
			_check(mine > 0, "the specimen was showing %s alone and drew none of it: %d cells"
				% [name, lat.tissue_cells(t)])
		for kind in strays:
			_check(false, "the specimen was showing %s alone and drew %s as well"
				% [name, AnatomyLattice.TISSUE_NAMES[kind]])

	# ...and the two networks over a body with its hide on, which is the whole of
	# what makes them overlays rather than another layer of the depth stack.
	view.layers = AnatomyView.ALL_LAYERS
	view.show_vessels = true
	view.show_nerves = true
	_rebuild(view, lat, grid)
	view._place_marks(lat)
	var supply: int = 0
	for j in view._shown_count:
		var kind: int = int(lat.kind[view._shown[j]])
		if kind == AnatomyLattice.NERVE or kind == AnatomyLattice.VESSEL:
			supply += 1
	_check(supply > 0, "the supply networks were switched on and nothing of them was drawn")


## Peeling is a subtraction from the same cells: what the surface is *made of*
## changes, because the surface has dropped onto what was underneath.
func _check_peel(view: AnatomyView) -> void:
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	var whole: Dictionary = _tissues_on(view, lat, grid)
	_check(whole.has(AnatomyLattice.SKIN),
		"an intact specimen's surface was not made of skin")

	view.set_layer_shown(AnatomyLattice.SKIN, false)
	view.set_layer_shown(AnatomyLattice.FAT, false)
	var peeled: Dictionary = _tissues_on(view, lat, grid)
	_check(not peeled.has(AnatomyLattice.SKIN),
		"the skin was lifted off and the surface was still skin")
	_check(peeled.has(AnatomyLattice.MUSCLE) or peeled.has(AnatomyLattice.BONE),
		"peeling the skin and fat off did not reach the layer under them")
	view.set_layer_shown(AnatomyLattice.SKIN, true)
	view.set_layer_shown(AnatomyLattice.FAT, true)


## The flare: the one cue on the specimen that is about *when* rather than about
## what. A region that is losing cells right now lights up and settles again, so
## damage is legible as it lands rather than only afterwards — and a body that is
## merely sitting there wounded does not go on flashing about it.
func _check_flare(view: AnatomyView) -> void:
	var creature: Creature = main.creature
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null or grid == null:
		return
	# Twice, so the census has a reading to be compared against.
	view._refresh_flares(lat, 0.016)
	view._refresh_flares(lat, 0.016)
	_check(_lit_regions(view) == 0, "an animal nobody had touched was already flaring")

	for _repeat in 8:
		creature.apply_bite(BiteMark.mouthful(
			creature.body.head.pos, Vector2.RIGHT, 12.0, 5.0))
	creature.anatomy.update(creature)
	lat.refresh_damage(grid)
	view._refresh_flares(lat, 0.016)
	_check(view._flare[BodyPlan.HEAD] > 0.9,
		"the head lost cells and did not flare: %.2f" % view._flare[BodyPlan.HEAD])
	_check(view._flare[BodyPlan.TAIL] == 0.0,
		"biting the head flared the tail as well")

	# ...and it settles. A wound that goes on flashing is a wound the eye stops
	# reading as news.
	view._refresh_flares(lat, AnatomyView.FLARE_FOR * 1.1)
	_check(_lit_regions(view) == 0,
		"the flare did not settle after %.1fs" % AnatomyView.FLARE_FOR)


func _lit_regions(view: AnatomyView) -> int:
	var lit: int = 0
	for reg in view._flare.size():
		if view._flare[reg] > 0.0:
			lit += 1
	return lit


## A wound is geometry. What the teeth took is gone from the surface, the flesh
## still standing beside the hole is marked as an open wound, and a limb eaten
## off at the socket is missing from the mesh rather than merely discoloured.
func _check_wounds(view: AnatomyView) -> void:
	var target: Creature = main.target_creature
	view.creature = target
	view.reset_fit()
	_settled(view)
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null or grid == null:
		_check(false, "the second specimen had no lattice")
		return
	_rebuild(view, lat, grid)
	var before: int = view._mesh.count
	var raw_before: int = _raw_facets(view)
	_check(raw_before == 0, "a whole animal already had open wounds on it")

	for _repeat in 10:
		target.apply_bite(BiteMark.mouthful(
			target.body.head.pos, Vector2.RIGHT, 12.0, 5.0))
	target.anatomy.update(target)
	_rebuild(view, lat, grid)
	_check(_raw_facets(view) > 0,
		"the specimen was bitten open and no facet on it read as a wound")

	# ...and a limb eaten away entirely leaves the mesh, rather than hanging on it
	# recoloured. The surface is the flesh: no flesh, no facet.
	var leg: int = BodyPlan.RR
	var stood: int = _facets_in(view, lat, leg)
	_check(stood > 0, "the specimen had no facets on the hind leg to begin with")
	var patch: TissueGrid.Patch = grid.patch("RR")
	var shed: Array = []
	for cell in patch.cells:
		for _repeat in 6:
			grid.bite(BiteMark.mouthful(
				patch.centre_of(cell), Vector2.RIGHT, 1.2, 9.0), shed)
	target.anatomy.update(target)
	_rebuild(view, lat, grid)
	_check(lat.region_cells(leg) == 0,
		"the hind leg was eaten and the lattice still had %d cells of it"
			% lat.region_cells(leg))
	_check(_facets_in(view, lat, leg) == 0,
		"a leg with no flesh left in it was still carrying %d facets"
			% _facets_in(view, lat, leg))
	_check(view._mesh.count < before,
		"chewing a leg off the specimen did not shrink its mesh: %d then %d"
			% [before, view._mesh.count])


## The mesh is a statement about the surface rather than about the cells behind
## it, so a body sixteen times the cells does not cost sixteen times the facets.
## This is the whole performance claim and the one that silently rots.
func _check_cost(view: AnatomyView, lizard: int) -> int:
	var player: Creature = main.creature
	player.params.apply_preset("Elephant")
	player.reset(Vector2.ZERO, 0.0)
	view.creature = player
	view.reset_fit()
	_settled(view)
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null or grid == null:
		_check(false, "the elephant had no lattice")
		return 0
	_rebuild(view, lat, grid)
	var heavy: int = view._mesh.count
	_check(lat.count > 20000,
		"the elephant was not big enough to be a test of anything: %d cells" % lat.count)
	_check(heavy < lizard * 2,
		"an elephant carved far more mesh than a lizard: %d facets against %d"
			% [heavy, lizard])
	return heavy


## The pointer still reads a cell, over the whole animal rather than at one lucky
## point — and it reads the cell the facet under it was skinned off.
func _check_hover(view: AnatomyView) -> void:
	var lat: AnatomyLattice = view.lattice()
	if lat == null:
		return
	view._place_marks(lat)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in view._shown_count:
		lo = lo.min(view._cell_page[j])
		hi = hi.max(view._cell_page[j])
	var hits: int = 0
	var regions: Dictionary = {}
	for ix in 24:
		for iy in 24:
			view._hover_voxel = -1
			view._pick(Vector2(lerpf(lo.x, hi.x, float(ix) / 23.0),
				lerpf(lo.y, hi.y, float(iy) / 23.0)))
			if view._hover_voxel < 0:
				continue
			hits += 1
			regions[int(lat.region[view._hover_voxel])] = true
	_check(hits > 100, "the pointer found the specimen at only %d of 576 places" % hits)
	_check(regions.size() >= 4,
		"the whole specimen answered the pointer as %d regions" % regions.size())


func _tissues_on(view: AnatomyView, lat: AnatomyLattice, grid: TissueGrid) -> Dictionary:
	_rebuild(view, lat, grid)
	var seen: Dictionary = {}
	for q in view._mesh.count:
		seen[int(lat.kind[view._mesh.f_cell[q]])] = true
	return seen


func _raw_facets(view: AnatomyView) -> int:
	var raw: int = 0
	for q in view._mesh.count:
		if view._mesh.f_raw[q] != 0:
			raw += 1
	return raw


func _facets_in(view: AnatomyView, lat: AnatomyLattice, region: int) -> int:
	var here: int = 0
	for q in view._mesh.count:
		if int(lat.region[view._mesh.f_cell[q]]) == region:
			here += 1
	return here


## Re-skins from scratch, since nothing about a headless run advances the frame
## the view would otherwise notice a change on.
func _rebuild(view: AnatomyView, lat: AnatomyLattice, grid: TissueGrid) -> void:
	lat.refresh_damage(grid)
	view._draw_key = 0
	view._refresh_stations(grid)
	view._refresh_draw_list(lat, grid)


func _settled(view: AnatomyView) -> void:
	for _step in 8:
		view._settle(1.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("specimen OK — the mesh is the census, it dents where the teeth were,"
			+ " and it costs the same whatever is on the slab: " + summary)
		quit(0)
	else:
		for failure in failures:
			print("SPECIMEN FAIL — ", failure)
		quit(1)
