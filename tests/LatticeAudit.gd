## Structural audit of the anatomy lattice: where the cells actually go, whether
## the skin closes, whether anything is hollow that should not be, and what the
## specimen pass costs. Diagnostic scaffolding, not a test.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/LatticeAudit.gd
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
	for preset in ["Lizard", "Cat", "Elephant", "Cheetah", "T. rex", "Kangaroo"]:
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		player._physics_process(TICK)
		player._physics_process(TICK)
		var lat: AnatomyLattice = player.anatomy.tissue.lattice
		if lat == null:
			print("%s: NO LATTICE" % preset)
			continue
		print("--- %s: %d cells" % [preset, lat.count])
		_drive(lat, player)
		_tissue_by_region(lat)
		_exposure(lat)
		_voids(lat)
		_surface(lat)


## Where the muscle that moves the animal actually stands: behind the shoulders,
## or behind the hips. What Physique.girdle_muscle is measured off.
func _drive(lat: AnatomyLattice, player: Creature) -> void:
	var fore: int = lat.region_tissue(BodyPlan.THORAX, AnatomyLattice.MUSCLE)
	var hind: int = lat.region_tissue(BodyPlan.PELVIS, AnatomyLattice.MUSCLE)
	for key in BodyPlan.LIMB_KEYS:
		var reg: int = int(player.anatomy.plan.limb_region[key])
		var m: int = lat.region_tissue(reg, AnatomyLattice.MUSCLE)
		if key.begins_with("F"):
			fore += m
		else:
			hind += m
	var total: float = float(maxi(fore + hind, 1))
	print("    drive   fore %d (%.4f)  hind %d (%.4f)  of %d locomotor muscle"
		% [fore, float(fore) / total, hind, float(hind) / total, fore + hind])


## Per-region tissue split, so "does this leg have muscle" is answerable.
func _tissue_by_region(lat: AnatomyLattice) -> void:
	for r in BodyPlan.REGIONS:
		var total: int = lat.region_cells(r)
		if total == 0:
			continue
		var bits: PackedStringArray = PackedStringArray()
		for t in AnatomyLattice.TISSUES:
			var c: int = lat.region_tissue(r, t)
			if c > 0:
				bits.append("%s %d (%d%%)" % [AnatomyLattice.TISSUE_NAMES[t], c,
					int(round(100.0 * float(c) / float(total)))])
		print("    %-7s %5d : %s" % [BodyPlan.REGION_NAMES[r], total, " · ".join(bits)])


## Which tissues face open air. Skin should be the only one.
func _exposure(lat: AnatomyLattice) -> void:
	var exposed: PackedInt32Array = PackedInt32Array()
	exposed.resize(AnatomyLattice.TISSUES)
	var surface: int = 0
	for i in lat.count:
		var open: bool = false
		for k in 6:
			if lat.neighbor[i * 6 + k] < 0:
				open = true
				break
		if not open:
			continue
		surface += 1
		exposed[int(lat.kind[i])] += 1
	var bits: PackedStringArray = PackedStringArray()
	for t in AnatomyLattice.TISSUES:
		if exposed[t] > 0:
			bits.append("%s %d" % [AnatomyLattice.TISSUE_NAMES[t], exposed[t]])
	print("    hull    %5d : %s" % [surface, " · ".join(bits)])


## Enclosed empty grid sites: a void inside the animal that no cell stands in.
## Flooded from a box around the body, so anything the flood cannot reach is
## surrounded by tissue on every side.
func _voids(lat: AnatomyLattice) -> void:
	if lat.count == 0:
		return
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	var filled: Dictionary = {}
	for i in lat.count:
		var p: Vector3 = lat.pos[i]
		var at := Vector3i(floori(p.x / AnatomyLattice.CELL),
			floori(p.y / AnatomyLattice.CELL), floori(p.z / AnatomyLattice.CELL))
		filled[at] = i
		lo = Vector3i(mini(lo.x, at.x), mini(lo.y, at.y), mini(lo.z, at.z))
		hi = Vector3i(maxi(hi.x, at.x), maxi(hi.y, at.y), maxi(hi.z, at.z))
	lo -= Vector3i.ONE
	hi += Vector3i.ONE
	var seen: Dictionary = {}
	var queue: Array[Vector3i] = [lo]
	seen[lo] = true
	var offsets: Array[Vector3i] = [
		Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0),
		Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]
	var head: int = 0
	while head < queue.size():
		var at: Vector3i = queue[head]
		head += 1
		for o in offsets:
			var n: Vector3i = at + o
			if n.x < lo.x or n.y < lo.y or n.z < lo.z \
					or n.x > hi.x or n.y > hi.y or n.z > hi.z:
				continue
			if seen.has(n) or filled.has(n):
				continue
			seen[n] = true
			queue.append(n)
	var box: int = (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1)
	var holes: int = box - lat.count - seen.size()
	print("    voids   %5d enclosed empty sites (box %d, outside %d)"
		% [holes, box, seen.size()])


## What the specimen pass would actually draw: cells with any face exposed to
## something that is not there.
func _surface(lat: AnatomyLattice) -> void:
	var t0: int = Time.get_ticks_usec()
	var drawn: int = 0
	for i in lat.count:
		for k in 6:
			if lat.neighbor[i * 6 + k] < 0:
				drawn += 1
				break
	print("    draw    %5d surface cells (%.2f ms to select)"
		% [drawn, float(Time.get_ticks_usec() - t0) / 1000.0])
