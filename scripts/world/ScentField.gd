## Every smell in the habitat, held as marks left on the ground rather than as
## anything the objects themselves do.
##
## Nothing here draws. A pellet, a carcass, a scrap and a walking animal all look
## exactly as they did before this file existed; what they gain is a record in
## this field saying *something of this kind was at this place, this recently*.
## That indirection is the whole point: scent has to outlive its source (a pellet
## is eaten and its smell hangs about), it has to be laid down where the source
## *was* rather than where it is (a trail), and it has to fade on its own clock.
##
## One mechanism produces all three. A source that is still present renews the
## trace under it every tick, so it stays fresh while it exists and starts dying
## the moment it stops. A source that moves further than `MERGE_RADIUS` renews
## nothing and lays a new trace instead, so the path it walked is left behind as
## a chain of traces ageing from the tail forward. Take the source away and the
## chain simply runs out.
##
## The world owns this rather than any creature: a smell is not the property of
## the nose that finds it, and SmellSense reads this field without being able to
## change it.
class_name ScentField
extends Node

## What a trace smells of. Distinct kinds rather than one intensity, because a
## nose that cannot tell meat from fruit is not a sense, it is a proximity meter.
enum Kind { FORAGE, QUARRY, CARRION, BLOOD, SCRAP }
const KIND_COUNT: int = 5

## How far each kind carries, as a multiple of the reach of whatever is smelling
## it. Carrion and spilled blood travel; a seed is a whisper you have to be on
## top of. Kinds differ in the distance they announce themselves from rather than
## in how certain you are once you are there — you always know what is under your
## own nose.
const CARRY: Array[float] = [0.72, 0.95, 1.30, 1.15, 0.85]
## Seconds a fresh trace of each kind takes to fade to nothing once nothing is
## renewing it. This is also the length of a trail, measured in time.
const HOLD: Array[float] = [20.0, 12.0, 120.0, 55.0, 40.0]

## World tick. Scent moves at the speed of things being somewhere, not at the
## speed of the frame rate, so it is deliberately far coarser than the physics.
const TICK: float = 0.1
## A deposit this close to a live trace of the same kind renews it instead of
## adding another. Doubles as the spacing of a trail.
const MERGE_RADIUS: float = 26.0
## Ceiling on live traces. Reached only in a habitat saturated with meat; the
## weakest are dropped first, so what survives pressure is the freshest news.
const MAX_TRACES: int = 400
## A creature leaks blood once it is hurt past this, scaled by how badly.
const BLEED_THRESHOLD: float = 0.04
const BLEED_GAIN: float = 2.2


## One place that smells of one thing.
class Trace extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var kind: int = Kind.FORAGE
	## Freshness, 1 at deposit and falling to 0 over HOLD[kind] seconds.
	var strength: float = 1.0
	## Stable per-trace phase, so separate sources are read out of step with each
	## other instead of pulsing as one.
	var phase: float = 0.0
	## Instance id of whatever laid this, or 0 for scent that belongs to the
	## ground. A creature does not track itself.
	var source_id: int = 0


@export var food_field_path: NodePath = NodePath("../FoodField")
@export var scrap_field_path: NodePath = NodePath("../ScrapField")

var traces: Array[Trace] = []

var _food_field: FoodField
var _scrap_field: ScrapField
var _since_tick: float = 0.0
var _rng := RandomNumberGenerator.new()
## Rebuilt once per tick and used only inside it: a live index would have to be
## maintained through every removal for no gain.
var _bins: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	if not food_field_path.is_empty():
		_food_field = get_node_or_null(food_field_path) as FoodField
	if not scrap_field_path.is_empty():
		_scrap_field = get_node_or_null(scrap_field_path) as ScrapField


func _physics_process(delta: float) -> void:
	_since_tick += delta
	if _since_tick < TICK:
		return
	var step: float = _since_tick
	_since_tick = 0.0
	_fade(step)
	_index()
	_gather()


## Records `kind` at `at`. `freshness` below 1 lays a fainter mark — a slow drip
## rather than a spill. Renewal never weakens what is already there.
func deposit(at: Vector2, kind: int, freshness: float = 1.0, source_id: int = 0) -> void:
	if freshness <= 0.0 or kind < 0 or kind >= KIND_COUNT:
		return
	var found: Trace = _renewable(at, kind)
	if found != null:
		found.strength = maxf(found.strength, freshness)
		# Ground both creatures have walked belongs to neither of them.
		if found.source_id != source_id:
			found.source_id = 0
		return
	var trace := Trace.new()
	trace.pos = at
	trace.kind = kind
	trace.strength = freshness
	trace.phase = _rng.randf() * TAU
	trace.source_id = source_id
	traces.append(trace)
	_bin_of(at).append(trace)
	if traces.size() > MAX_TRACES:
		_thin()


## How saturated a place is with scent, 0..1, before any nose is involved. Kinds
## are not weighted against each other here: this is how much is lying about,
## which is world truth, while what it is worth to a particular creature standing
## a particular distance away is SmellSense's business.
func concentration_at(at: Vector2, radius: float = 90.0) -> float:
	var total: float = 0.0
	var limit: float = radius * radius
	for trace in traces:
		var d2: float = trace.pos.distance_squared_to(at)
		if d2 > limit:
			continue
		total += trace.strength * (1.0 - sqrt(d2) / radius)
	return clampf(total, 0.0, 1.0)


func clear() -> void:
	traces.clear()
	_bins.clear()
	_since_tick = 0.0


func _fade(delta: float) -> void:
	for i in range(traces.size() - 1, -1, -1):
		var trace: Trace = traces[i]
		trace.strength -= delta / HOLD[trace.kind]
		if trace.strength <= 0.0:
			traces.remove_at(i)


## Everything in the habitat that smells, asked where it is now. Sources are read
## rather than notified, so no object in the world has to know this field exists.
func _gather() -> void:
	if _food_field != null:
		for pellet in _food_field.pellets:
			deposit(pellet, Kind.FORAGE)
	if _scrap_field != null:
		for scrap in _scrap_field.scraps:
			deposit(scrap.pos, Kind.SCRAP)
	for node in get_tree().get_nodes_in_group("creatures"):
		var each := node as Creature
		if each == null or each.body == null:
			continue
		if not each.alive:
			# A carcass is a place, not a path: it smells from the mass lying there.
			deposit(each.bounds_center, Kind.CARRION)
			continue
		# The muzzle traces the route actually walked, which is what makes the
		# chain of renewals behind a moving animal read as a trail.
		var owner_id: int = each.get_instance_id()
		deposit(each.body.head.pos, Kind.QUARRY, 1.0, owner_id)
		var hurt: float = 1.0 - each.anatomy.tissue.integrity()
		if hurt > BLEED_THRESHOLD:
			deposit(each.bounds_center, Kind.BLOOD, minf(1.0, hurt * BLEED_GAIN), owner_id)


func _renewable(at: Vector2, kind: int) -> Trace:
	var limit: float = MERGE_RADIUS * MERGE_RADIUS
	var best: Trace = null
	var best_d2: float = limit
	var cell: Vector2i = _cell(at)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var bin: Array = _bins.get(cell + Vector2i(dx, dy), []) as Array
			for entry in bin:
				var trace := entry as Trace
				if trace.kind != kind:
					continue
				var d2: float = trace.pos.distance_squared_to(at)
				if d2 < best_d2:
					best = trace
					best_d2 = d2
	return best


func _index() -> void:
	_bins.clear()
	for trace in traces:
		_bin_of(trace.pos).append(trace)


func _bin_of(at: Vector2) -> Array:
	var cell: Vector2i = _cell(at)
	var bin: Array = _bins.get(cell, []) as Array
	if bin.is_empty():
		_bins[cell] = bin
	return bin


func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / MERGE_RADIUS), floori(at.y / MERGE_RADIUS))


## Under pressure the faintest traces go first, so a crowded habitat loses its
## oldest history rather than its freshest.
func _thin() -> void:
	traces.sort_custom(func(a: Trace, b: Trace) -> bool: return a.strength > b.strength)
	traces.resize(MAX_TRACES)
	_index()
