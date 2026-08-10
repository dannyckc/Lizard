## The 3D anatomy lattice: that the body is a solid of constant-sized cells in
## three real axes, that every tissue occupies its own cells in the right order
## — skin outside fat outside muscle around an *internal* skeleton, organs and
## conduits in volumes of their own — and that the census the physique weighs,
## the panel prints and the specimen draws are all these same cells.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/LatticeTest.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.get_node("Creature")
	_check_census_is_the_simulation(player)
	_check_cells_are_a_constant_grid(player)
	_check_the_hull_is_skin(player)
	_check_the_skeleton_is_internal(player)
	_check_tissues_stack_outside_in(player)
	_check_organs_are_volumes(player)
	_check_conduits_are_threads(player)
	_check_fat_is_a_layer_of_cells(player)
	_check_muscle_lands_on_its_own_limb(player)
	_check_damage_eats_cells_outside_in(player)
	_check_a_bite_lands_where_the_teeth_were(player)
	_finish()
	return false


func _lattice(player: Creature) -> AnatomyLattice:
	return player.anatomy.tissue.lattice


func _apply(player: Creature, tweak: Callable = Callable()) -> void:
	player.params.apply_preset("Lizard")
	if tweak.is_valid():
		tweak.call(player.params)
	player.command = MovementInput.Command.new()
	player.reset(Vector2.ZERO, 0.0)
	for _t in 4:
		player._physics_process(TICK)


## The physique's numbers and the lattice's numbers are one census: what the
## panel prints beside the specimen is what the scales weighed.
func _check_census_is_the_simulation(player: Creature) -> void:
	_apply(player)
	var lat: AnatomyLattice = _lattice(player)
	_check(lat != null and lat.count > 0, "the creature has no cell lattice")
	if lat == null:
		return
	_check(int(player.physique.cells) == lat.standing_total,
		"the physique counted %d cells and the lattice holds %d"
			% [int(player.physique.cells), lat.standing_total])
	_check(int(player.physique.muscle_cells) == lat.tissue_cells(AnatomyLattice.MUSCLE),
		"the physique's muscle is not the lattice's muscle cells")
	var regions: int = 0
	for region in BodyPlan.REGIONS:
		regions += int(player.physique.cells_of(region))
	_check(regions == lat.standing_total, "the region censuses do not add up to the lattice")
	var shares: float = 0.0
	for t in AnatomyLattice.TISSUES:
		shares += lat.mass_share(t)
	_check(absf(shares - 1.0) < 0.0001, "the tissue shares do not account for the body")
	notes.append("%d cells, one census" % lat.standing_total)


## Constant cell size: every cell sits on the one grid, and the volume is the
## count times the one cell volume — anatomy changes counts, never sizes.
func _check_cells_are_a_constant_grid(player: Creature) -> void:
	var lat: AnatomyLattice = _lattice(player)
	var off_grid: int = 0
	for i in lat.count:
		var p: Vector3 = lat.pos[i] / AnatomyLattice.CELL - Vector3(0.5, 0.5, 0.5)
		if absf(p.x - roundf(p.x)) > 0.01 or absf(p.y - roundf(p.y)) > 0.01 \
				or absf(p.z - roundf(p.z)) > 0.01:
			off_grid += 1
	_check(off_grid == 0, "%d cells sit off the constant grid" % off_grid)
	_check(is_equal_approx(lat.volume(),
		float(lat.standing_total) * AnatomyLattice.CELL_VOLUME),
		"the volume is not the cell count times the cell size")


## Skin forms the outer boundary: every cell with a face on open air is covered,
## either by being skin or by wearing a sheath.
##
## The second is the case the lattice cannot hold a cell for. Where the animal is
## thinner than the grid — a lizard's forearm, the last inch of a tail — the skin
## over it is a film under a pixel deep, and a cell given wholly to it would be a
## limb made entirely of hide with nothing inside. So the cell keeps the tissue it
## is mostly made of and is marked `sheathed`, and it is the mark that carries the
## covering: the specimen draws such a cell as skin while the skin is on. What may
## never happen is a cell facing air with neither, which would be a real hole in
## the animal, and that is what is checked here.
func _check_the_hull_is_skin(player: Creature) -> void:
	var lat: AnatomyLattice = _lattice(player)
	var bare: int = 0
	var sheathed: int = 0
	for i in lat.count:
		if lat.kind[i] == AnatomyLattice.SKIN:
			continue
		for k in 6:
			if lat.neighbor[i * 6 + k] < 0:
				if lat.sheathed[i] != 0:
					sheathed += 1
				else:
					bare += 1
				break
	_check(bare == 0, "%d cells of other tissue face open air uncovered" % bare)
	# ...and the sheath is the exception it claims to be, not the rule: the great
	# majority of the animal's boundary is still cells of real skin.
	var hide: int = lat.tissue_cells(AnatomyLattice.SKIN)
	_check(sheathed < hide,
		"%d sheathed boundary cells against only %d of skin" % [sheathed, hide])
	notes.append("%d of the boundary is sheathed, %d is skin" % [sheathed, hide])


## The skeleton is internal — no bone cell is left uncovered, on any build — and
## it is wrapped in flesh: nearly every bone cell has muscle or fat lying against
## it. On a limb or a tail tip the grid cannot hold a cell for the covering, and
## there the bone wears a sheath instead; what it may never do is lie open.
func _check_the_skeleton_is_internal(player: Creature) -> void:
	for preset in ["Lizard", "Elephant", "T. rex"]:
		player.params.apply_preset(preset)
		player.command = MovementInput.Command.new()
		player.reset(Vector2.ZERO, 0.0)
		for _t in 4:
			player._physics_process(TICK)
		var lat: AnatomyLattice = _lattice(player)
		var bones: int = 0
		var exposed: int = 0
		var fleshed: int = 0
		var parts: Dictionary = {}
		for i in lat.count:
			if lat.kind[i] != AnatomyLattice.BONE:
				continue
			bones += 1
			parts[int(lat.part[i])] = true
			var soft: bool = false
			for k in 6:
				var n: int = lat.neighbor[i * 6 + k]
				if n < 0:
					if lat.sheathed[i] == 0:
						exposed += 1
					break
				if lat.kind[n] == AnatomyLattice.MUSCLE or lat.kind[n] == AnatomyLattice.FAT:
					soft = true
			if soft:
				fleshed += 1
		_check(bones > 0, "a %s has no skeleton in its lattice" % preset)
		_check(exposed == 0,
			"a %s carries %d uncovered bone cells on its surface" % [preset, exposed])
		_check(fleshed > bones / 2,
			"a %s's skeleton is not wrapped in flesh (%d of %d cells touch muscle or fat)"
				% [preset, fleshed, bones])
		_check(parts.has(AnatomyLattice.PART_VERTEBRA) and parts.has(AnatomyLattice.PART_SKULL),
			"a %s's skeleton is missing its vertebrae or its skull" % preset)
		# Every animal in the file, and no longer only the ones with thick enough
		# legs to bury a bone in. A limb is a bone with flesh on it at any size,
		# and one carrying none was the census reporting a sock.
		_check(parts.has(AnatomyLattice.PART_LIMB_BONE),
			"a %s's legs have no bone in them" % preset)
	_apply(player)
	notes.append("the skeleton is internal on every build tried")


## Walking inward from the top of the chest meets skin before fat before
## muscle, and never meets skin again once inside — the outside-to-inside
## order is the lattice's own geometry, not a drawing convention. Measured on a
## well-padded build so the fat layer is unmistakably cells of its own.
func _check_tissues_stack_outside_in(player: Creature) -> void:
	_apply(player, func(p: CreatureParams) -> void:
		p.fat_reserve = 2.5)
	var lat: AnatomyLattice = _lattice(player)
	# The dorsal column of cells nearest the chest's midline: thorax cells with
	# lateral offset within one cell of zero, sorted top down.
	var columns: Dictionary = {}
	for i in lat.count:
		if int(lat.region[i]) != BodyPlan.THORAX or lat.patch_of[i] != 0:
			continue
		if absf(lat.pos[i].y) > AnatomyLattice.CELL:
			continue
		var key: int = int(roundf(lat.pos[i].x / AnatomyLattice.CELL)) * 4096 \
			+ int(roundf(lat.pos[i].y / AnatomyLattice.CELL))
		if not columns.has(key):
			columns[key] = []
		columns[key].append(i)
	var stacked: int = 0
	var broken: int = 0
	for key in columns:
		var cells: Array = columns[key]
		cells.sort_custom(func(a: int, b: int) -> bool:
			return lat.pos[a].z > lat.pos[b].z)
		# Top half only: the ventral hull is skin again, legitimately.
		var first_muscle: int = -1
		var first_fat: int = -1
		var order_held: bool = true
		for j in cells.size():
			var i: int = cells[j]
			if lat.pos[i].z < 0.0:
				break
			# What the cell reads as from outside, which on a boundary cell the
			# grid could not spare for skin is skin — see AnatomyLattice.sheathed.
			var t: int = AnatomyLattice.SKIN if lat.sheathed[i] != 0 \
				else int(lat.kind[i])
			if j == 0 and t != AnatomyLattice.SKIN:
				order_held = false
			if t == AnatomyLattice.FAT and first_fat < 0:
				first_fat = j
			if t == AnatomyLattice.MUSCLE and first_muscle < 0:
				first_muscle = j
			if (t == AnatomyLattice.SKIN or t == AnatomyLattice.FAT) \
					and first_muscle >= 0:
				order_held = false
		if first_fat >= 0 and first_muscle >= 0 and first_fat > first_muscle:
			order_held = false
		if order_held:
			stacked += 1
		else:
			broken += 1
	_check(stacked > 0, "no dorsal column of the chest could be walked at all")
	_check(broken == 0,
		"%d of %d chest columns broke the skin-fat-muscle order" % [broken, stacked + broken])
	_apply(player)
	notes.append("skin over fat over muscle, walked cell by cell")


## Organs are distinct volumes with named parts, buried inside the body.
func _check_organs_are_volumes(player: Creature) -> void:
	var lat: AnatomyLattice = _lattice(player)
	var brain: int = 0
	var heart: int = 0
	var exposed: int = 0
	var parts: Dictionary = {}
	for i in lat.count:
		var organ: int = int(lat.organ_of[i])
		if organ == BodyPlan.NO_ORGAN:
			continue
		if organ == BodyPlan.BRAIN:
			brain += 1
		else:
			heart += 1
		parts[int(lat.part[i])] = true
		for k in 6:
			if lat.neighbor[i * 6 + k] < 0:
				exposed += 1
				break
		_check(int(lat.region[i]) == (BodyPlan.HEAD if organ == BodyPlan.BRAIN \
			else BodyPlan.THORAX), "an organ cell lies outside its own region")
	_check(brain > 0, "the creature has no brain cells")
	_check(heart > 0, "the creature has no heart cells")
	_check(exposed == 0, "%d organ cells face open air" % exposed)
	_check(parts.has(AnatomyLattice.PART_CEREBRUM) and parts.has(AnatomyLattice.PART_BRAINSTEM),
		"the brain has no substructure")
	_check(parts.has(AnatomyLattice.PART_ATRIUM) and parts.has(AnatomyLattice.PART_VENTRICLE),
		"the heart has no chambers")
	notes.append("brain %d cells, heart %d, all enclosed" % [brain, heart])


## The cord and the great vessel are threads of their own cells running the
## length of the trunk, inside everything else.
func _check_conduits_are_threads(player: Creature) -> void:
	var lat: AnatomyLattice = _lattice(player)
	var body_lo: float = INF
	var body_hi: float = -INF
	var cord_lo: float = INF
	var cord_hi: float = -INF
	var aorta_lo: float = INF
	var aorta_hi: float = -INF
	var cord: int = 0
	var aorta: int = 0
	var exposed: int = 0
	for i in lat.count:
		if lat.patch_of[i] != 0:
			continue
		var x: float = lat.pos[i].x
		body_lo = minf(body_lo, x)
		body_hi = maxf(body_hi, x)
		var named: int = int(lat.part[i])
		if named == AnatomyLattice.PART_CORD:
			cord += 1
			cord_lo = minf(cord_lo, x)
			cord_hi = maxf(cord_hi, x)
		elif named == AnatomyLattice.PART_AORTA:
			aorta += 1
			aorta_lo = minf(aorta_lo, x)
			aorta_hi = maxf(aorta_hi, x)
		else:
			continue
		for k in 6:
			if lat.neighbor[i * 6 + k] < 0:
				if lat.sheathed[i] == 0:
					exposed += 1
				break
	_check(cord > 0, "there is no spinal cord in the lattice")
	_check(aorta > 0, "there is no great vessel in the lattice")
	_check(exposed == 0, "%d conduit cells face open air uncovered" % exposed)
	var length: float = maxf(body_hi - body_lo, 1.0)
	# Not the whole length: the cord runs as far down the tail as there is body
	# deep enough to bury it, and on the smallest build that is about half —
	# the taper takes the cord's cells with everything else's.
	_check((cord_hi - cord_lo) / length > 0.42,
		"the cord runs only %.0f%% of the body" % (100.0 * (cord_hi - cord_lo) / length))
	_check((aorta_hi - aorta_lo) / length > 0.35,
		"the aorta runs only %.0f%% of the body" % (100.0 * (aorta_hi - aorta_lo) / length))
	notes.append("cord %d cells, aorta %d" % [cord, aorta])


## Fat is cells: a padded build carries more fat cells in a physically thicker
## layer, is a bigger animal for it, and weighs more — and a starved one keeps
## almost none.
func _check_fat_is_a_layer_of_cells(player: Creature) -> void:
	_apply(player, func(p: CreatureParams) -> void:
		p.fat_reserve = 0.0)
	var lat: AnatomyLattice = _lattice(player)
	var lean_fat: int = lat.tissue_cells(AnatomyLattice.FAT)
	var lean_cells: int = lat.standing_total
	var lean_mass: float = player.physique.mass
	_apply(player, func(p: CreatureParams) -> void:
		p.fat_reserve = 3.0)
	lat = _lattice(player)
	var fat: int = lat.tissue_cells(AnatomyLattice.FAT)
	_check(fat > lean_fat + 200,
		"three reserves of fat added only %d fat cells" % (fat - lean_fat))
	_check(lat.standing_total > lean_cells,
		"a fattened animal did not grow in cells (%d -> %d)"
			% [lean_cells, lat.standing_total])
	_check(player.physique.mass > lean_mass * 1.1,
		"the added fat cells weighed nothing (%.2f -> %.2f)"
			% [lean_mass, player.physique.mass])
	_apply(player)
	notes.append("fat 0 -> 3 reserves is %d -> %d cells" % [lean_fat, fat])


## More musculature on a body part is more muscle cells *on that part*: load
## the hindquarters and the hind legs thicken in muscle specifically.
func _check_muscle_lands_on_its_own_limb(player: Creature) -> void:
	_apply(player)
	var lat: AnatomyLattice = _lattice(player)
	var hind: int = lat.region_tissue(BodyPlan.RL, AnatomyLattice.MUSCLE) \
		+ lat.region_tissue(BodyPlan.RR, AnatomyLattice.MUSCLE)
	var head: int = lat.region_cells(BodyPlan.HEAD)
	_apply(player, func(p: CreatureParams) -> void:
		p.density = 3.0)
	lat = _lattice(player)
	var loaded: int = lat.region_tissue(BodyPlan.RL, AnatomyLattice.MUSCLE) \
		+ lat.region_tissue(BodyPlan.RR, AnatomyLattice.MUSCLE)
	_check(loaded > hind * 3 / 2,
		"legs sized to triple the load did not grow their own muscle cells (%d -> %d)"
			% [hind, loaded])
	_check(absf(float(lat.region_cells(BodyPlan.HEAD) - head)) < float(head) * 0.25,
		"loading the hindquarters rebuilt the head")
	_apply(player)
	notes.append("3x the load is %d -> %d hind-leg muscle cells" % [hind, loaded])


## Wounds are missing cells, taken outermost-first: after a bite the census
## drops by the cells the specimen no longer shows, and no tissue group has an
## outer cell standing over a deeper one already gone.
func _check_damage_eats_cells_outside_in(player: Creature) -> void:
	_apply(player)
	var lat: AnatomyLattice = _lattice(player)
	var whole: int = lat.standing_total
	var scraps: Array = []
	var at: Vector2 = player.spine.points[5]
	for _bite in 6:
		player.anatomy.tissue.bite(BiteMark.mouthful(at, Vector2.RIGHT, 10.0, 3.0), scraps)
	player._physics_process(TICK)
	_check(lat.standing_total < whole,
		"six bites in one place cost the lattice nothing")
	_check(int(player.physique.cells) == lat.standing_total,
		"the wounded census and the physique disagree")

	# Outside-in, per (ledger cell, tissue) group: anything gone must be the
	# outermost of what its group had.
	var inverted: int = 0
	var groups: Dictionary = {}
	for i in lat.count:
		var g: int = (int(lat.patch_of[i]) << 28) | (lat.cell_of[i] << 3) | int(lat.kind[i])
		if not groups.has(g):
			groups[g] = [1.0, 0.0]
		var span: Array = groups[g]
		if lat.gone[i] == 0:
			span[0] = minf(span[0], lat.rank[i])
		else:
			span[1] = maxf(span[1], lat.rank[i])
	for g in groups:
		var span: Array = groups[g]
		if span[1] > span[0] + 0.0001 and span[1] > 0.0:
			inverted += 1
	_check(inverted == 0,
		"%d tissue groups lost a deep cell while an outer one still stands" % inverted)
	notes.append("a wound is %d missing cells" % (whole - lat.standing_total))
	_apply(player)


## Jaws that can only reach the top of a back take the top of it.
##
## The claim the whole spatial layer exists for, and the one a column-wide ledger
## cannot make on its own: two bites of identical depth on identical flesh, one
## along the spine and one under the belly, are different wounds. What is checked
## is that the cells which went are the cells the teeth could get to — measured
## against the same posed heights the specimen draws them at — and that the flesh
## outside the jaws' reach in the *same columns* is still standing.
func _check_a_bite_lands_where_the_teeth_were(player: Creature) -> void:
	_apply(player)
	var lat: AnatomyLattice = _lattice(player)
	var grid: TissueGrid = player.anatomy.tissue
	var body: TissueGrid.Patch = grid.patch(TissueGrid.BODY_KEY)
	var whole: Vector2 = grid.whole_band()
	# The upper third of the animal, and nothing below it.
	var high := Vector2(lerpf(whole.x, whole.y, 0.66), whole.y + 20.0)
	var at: Vector2 = player.spine.points[5]
	var mark: BiteMark = BiteMark.mouthful(at, Vector2.RIGHT, 12.0, 4.0)
	mark.reach = high
	var scraps: Array = []
	for _bite in 5:
		grid.bite(mark, scraps)
	player._physics_process(TICK)

	var eaten: int = 0
	var eaten_high: int = 0
	var spared_low: int = 0
	var threads: int = 0
	for i in lat.count:
		if int(lat.patch_of[i]) != 0:
			continue
		if body.touched[lat.cell_of[i]] == 0:
			continue
		var reached: bool = Stature.overlaps(high, lat.cell_band(body, i))
		if lat.gone[i] == 0:
			if not reached:
				spared_low += 1
			continue
		# A conduit is exempt and has to be: it is a thread rather than a volume,
		# so cutting it anywhere takes the run, and the cells that go are along
		# its length rather than at the teeth. Everything solid is answerable.
		var t: int = int(lat.kind[i])
		if t == AnatomyLattice.NERVE or t == AnatomyLattice.VESSEL:
			threads += 1
			continue
		eaten += 1
		eaten_high += 1 if reached else 0
	_check(eaten > 0, "a bite along the back cost the lattice nothing")
	_check(eaten_high == eaten,
		"%d of %d solid cells a high bite destroyed stood below the jaws"
			% [eaten - eaten_high, eaten])
	_check(spared_low > 0,
		"a bite the height of the back left nothing standing under it")
	notes.append("a high bite took %d cells (%d threads) and left %d under it standing"
		% [eaten, threads, spared_low])
	_apply(player)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("lattice OK — one body of constant cells, counted once: %s"
			% " · ".join(notes))
		quit(0)
		return
	for failure in failures:
		print("LATTICE FAIL — %s" % failure)
	quit(1)
