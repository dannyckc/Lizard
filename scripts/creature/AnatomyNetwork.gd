## A branching supply network laid through the body: the nervous system, or the
## circulation. One class, because they are the same mechanism.
##
##     root organ -> trunk -> body region -> tissue
##
## What each region *gets* is what its parent got, times how intact its own run
## is. That single line is the whole of connectivity: a conduit cut anywhere
## delivers nothing past the cut, and everything downstream of it goes dark
## without any of it being written down as a rule about limbs or tails.
##
## Nothing here is stored between ticks and nothing is ever set by a bite. The
## integrity of a run is read off the lattice cells it passes through, so a
## severed nerve is a consequence of missing flesh rather than an injury state
## somebody remembered to flag — which is what keeps the two in agreement when a
## body is chewed in a way nobody anticipated.
##
## The two instances differ in exactly two ways, and both are the plan's business
## rather than this file's: where they are fed from, and whether their axial run
## is shielded by bone. Everything that follows from those — a broken neck
## silencing a body whose heart is fine, a opened chest starving a body whose
## brain is fine — falls out without being written anywhere.
class_name AnatomyNetwork
extends RefCounted

## Below this, a region is treated as cut off rather than merely poorly supplied.
## Only used for reporting; the continuous value is what everything consumes.
const CUTOFF: float = 0.05

var conduits: Array[BodyPlan.Conduit] = []
var root: int = 0

## How intact each region's own run is, before anything upstream is accounted
## for. Indexed by region.
var integrity: PackedFloat32Array = PackedFloat32Array()
## What actually arrives at each region, after every conduit between it and the
## root. This is the number the functional layer consumes.
var delivery: PackedFloat32Array = PackedFloat32Array()

## Regions in an order that always visits a parent before its children, so the
## solve below is a single pass rather than a search. Built once.
var _order: PackedInt32Array = PackedInt32Array()


func configure(p_conduits: Array[BodyPlan.Conduit], p_root: int) -> void:
	conduits = p_conduits
	root = p_root
	var count: int = conduits.size()
	integrity.resize(count)
	integrity.fill(1.0)
	delivery.resize(count)
	delivery.fill(1.0)
	_order = _topological_order(count)


## Breadth-first from the root, so every region is listed after whatever feeds
## it. A region the plan left unreachable is appended at the end and simply
## receives nothing, which is the honest answer for a structure with no supply
## rather than a reason to refuse to build the network.
func _topological_order(count: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(count)
	var queue: Array[int] = [root]
	seen[root] = 1
	while not queue.is_empty():
		var region: int = queue.pop_front()
		order.append(region)
		for candidate in count:
			if seen[candidate] == 0 and conduits[candidate].parent == region:
				seen[candidate] = 1
				queue.append(candidate)
	for candidate in count:
		if seen[candidate] == 0:
			order.append(candidate)
	return order


## Re-reads how intact every run is. This is the half that walks cells, and the
## only half that can change when a bite lands — so it is called on the ticks the
## lattice actually changed and not on the thousands where it did not.
func read(tissue: TissueGrid) -> void:
	for region in conduits.size():
		integrity[region] = tissue.conduit(conduits[region])


## Pushes what the root organ is putting out along the tree.
##
## `source` is the organ's own output — a brain still conscious, a heart still
## pumping. A network is therefore never better than its organ however sound its
## plumbing, and never better than its plumbing however sound its organ. Cheap
## enough to run every tick, which it has to be: the supply moves continuously
## even when no tissue does.
func propagate(source: float) -> void:
	var supply: float = clampf(source, 0.0, 1.0)
	for region in _order:
		var run: BodyPlan.Conduit = conduits[region]
		var upstream: float = supply if run.parent < 0 else delivery[run.parent]
		delivery[region] = upstream * integrity[region]


func solve(tissue: TissueGrid, source: float) -> void:
	read(tissue)
	propagate(source)


## How much of the network has been opened, 0 sound to 1 destroyed. What the
## circulation bleeds through, and a fair reading of how badly wired a nervous
## system is.
func openness() -> float:
	if integrity.is_empty():
		return 0.0
	var total: float = 0.0
	for value in integrity:
		total += 1.0 - value
	return total / float(integrity.size())


## Regions receiving effectively nothing — a readout for the debug overlay and
## the tests, never a thing the simulation branches on.
func cut_off() -> int:
	var count: int = 0
	for value in delivery:
		if value <= CUTOFF:
			count += 1
	return count
