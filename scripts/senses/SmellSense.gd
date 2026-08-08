## Gameplay-facing sense of smell for a creature.
##
## Perception, not emission. Nothing leaves the pellet, the carcass or the wound;
## what exists is a ScentField the world writes to, and this class resolving part
## of it from where one creature is standing. Marks appear in the air *around*
## whatever has already been detected, on a beat, and dissolve when the read
## lapses — which is why the habitat never appears to be pouring anything.
##
## It knows nothing about fonts, colours or the screen. A mark carries how sure
## the read was and a fixed seed; SmellRenderer turns that into a glyph, a size
## and a hue. Detection rules can therefore change without presentation becoming
## gameplay truth, exactly as SightSense is separate from SightRenderer.
class_name SmellSense
extends RefCounted

## Kind given to a mark that resolved nothing at all. Not a ScentField.Kind: the
## habitat never contains this, only the observer does.
const UNREAD: int = -1
## Certainty falls off faster than distance does, so the far half of the range is
## mostly hints rather than reads.
const ACUITY_GAMMA: float = 1.3
## A read this sure pulls its marks inward and clusters; below it the marks
## wander off the thing instead.
const GRIP_CONFIDENCE: float = 0.48
## Only every third beat may resolve into something legible.
const LEGIBLE_BEAT: int = 3
## Where a mark of nothing-yet is strewn: never underfoot, out to most of the
## range, and always drifting off whatever it failed to resolve.
const AMBIENT_NEAR: float = 140.0
const AMBIENT_SPAN: float = 0.75
const AMBIENT_PULL: float = -0.3
## Fraction of the mark budget released when the ceiling is hit.
const CULL_FRACTION: int = 12


## One thing this creature currently smells.
class Read extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var kind: int = 0
	var confidence: float = 0.0
	var phase: float = 0.0


## One impression of a read, hanging in the air until it dissolves.
class Mark extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	## Where the read it belongs to was. Marks close on this or lose it.
	var source: Vector2 = Vector2.ZERO
	var kind: int = UNREAD
	var confidence: float = 0.0
	var age: float = 0.0
	var life: float = 1.0
	## Fixed at spawn. Everything arbitrary about one mark is derived from it, so
	## a mark never changes its character between frames.
	var seed: float = 0.0
	## Positive closes on the source, negative drifts off it.
	var pull: float = 0.0
	var legible: bool = false


var creature: Creature
var profile: SmellProfile
var field: ScentField

var marks: Array[Mark] = []
## Shared clock for drift and flicker, so the renderer needs no second one.
var elapsed: float = 0.0

var _beat: int = 0
var _since_beat: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(owner: Creature, smell_profile: SmellProfile, scent_field: ScentField) -> void:
	creature = owner
	profile = smell_profile
	field = scent_field
	_rng.randomize()


func reset() -> void:
	# Everything the sense is holding is a read in progress. A creature that has
	# just been rebuilt or respawned has not smelled anything yet.
	marks.clear()
	elapsed = 0.0
	_beat = 0
	_since_beat = 0.0


func origin() -> Vector2:
	if creature == null:
		return Vector2.ZERO
	if creature.body != null:
		return creature.body.head.pos
	return creature.head_pos


## The muzzle points where the head does. Smell is not aimed the way sight is,
## but a nose still leads, and this is what tilts a read toward what the creature
## is turned toward.
func direction() -> Vector2:
	if creature == null:
		return Vector2.RIGHT
	var look: Vector2 = creature.head_look_dir
	return look.normalized() if look.length_squared() > 0.0001 else Vector2.RIGHT.rotated(creature.heading)


## Driven by CreatureSenses. Sight can be answered on demand because it is a
## field; smell accumulates a read over time and so has to be ticked.
func advance(delta: float) -> void:
	if profile == null:
		return
	elapsed += delta
	_since_beat += delta
	if _since_beat >= profile.beat_interval:
		_since_beat -= profile.beat_interval
		_beat += 1
		_resolve()
	_drift(delta)


## Everything this creature currently smells, strongest first. Live rather than
## cached on the beat: the beat governs how the read is *presented*, while a
## gameplay query asking what is in the air right now should get an answer that
## is right now.
func reads() -> Array[Read]:
	var found: Array[Read] = []
	if field == null or profile == null:
		return found
	var own_id: int = creature.get_instance_id() if creature != null else 0
	for trace in field.traces:
		# A creature does not track itself, or it would spend its life reading its
		# own footprints back to where it came from.
		if trace.source_id == own_id and own_id != 0:
			continue
		var confidence: float = trace.strength \
			* _acuity(trace.pos, profile.reach * ScentField.CARRY[trace.kind])
		if confidence < profile.min_confidence:
			continue
		var read := Read.new()
		read.pos = trace.pos
		read.kind = trace.kind
		read.confidence = minf(confidence, 1.0)
		read.phase = trace.phase
		found.append(read)
	found.sort_custom(func(a: Read, b: Read) -> bool: return a.confidence > b.confidence)
	return found


## Continuous 0..1 confidence that this creature smells something at a world
## point. The counterpart of SightSense.clarity_at, and the same contract: not a
## detector, one input among the senses.
##
## A point query cannot say *which* smell is being asked about, so it is answered
## on the creature's own reach; a read of one trace knows its kind and is answered
## on how far that kind of scent carries.
func confidence_at(world_point: Vector2) -> float:
	if field == null or profile == null:
		return 0.0
	return clampf(field.concentration_at(world_point) * _acuity(world_point, profile.reach),
		0.0, 1.0)


func smells(world_point: Vector2, threshold: float = 0.35) -> bool:
	return confidence_at(world_point) >= threshold


## How much of what is at a place can be resolved from where the creature stands:
## nearness within `reach`, plus a little for having the muzzle turned toward it.
func _acuity(at: Vector2, reach: float) -> float:
	if profile == null or reach <= 0.0:
		return 0.0
	var delta: Vector2 = at - origin()
	var distance: float = delta.length()
	if distance >= reach:
		return 0.0
	var facing: float = 0.0
	if distance > 0.001:
		facing = delta.normalized().dot(direction())
	var bias: float = (1.0 - profile.muzzle_bias) \
		+ profile.muzzle_bias * (0.5 + 0.5 * facing)
	return pow(clampf((1.0 - distance / reach) * bias, 0.0, 1.0), ACUITY_GAMMA)


## One beat of the sense.
func _resolve() -> void:
	var found: Array[Read] = reads()
	var budget: int = mini(found.size(), profile.reads_per_beat)
	for i in budget:
		var read: Read = found[i]
		# Each beat samples only part of the field, and each source breathes on its
		# own phase, so density rises and falls instead of streaming.
		var wave: float = 0.5 + 0.5 * sin(float(_beat) * 1.1 + read.phase)
		var count: int = roundi((1.0 + read.confidence * profile.marks_per_read) * (0.45 + wave))
		var spread: float = profile.cluster_radius \
			+ (1.0 - read.confidence) * profile.scatter_radius
		for _mark in count:
			_spawn(read, spread, false)
		if read.confidence > profile.legible_confidence and _beat % LEGIBLE_BEAT == 0 \
				and _rng.randf() < profile.legible_chance:
			_spawn(read, spread * 0.8 + 24.0, true)

	# The sense runs whether or not it finds anything: a thin grain of nothing-yet,
	# strewn out of arm's reach and always losing its grip.
	for _ambient in profile.ambient_marks:
		var away: float = AMBIENT_NEAR + _rng.randf() * profile.reach * AMBIENT_SPAN
		var blank := Read.new()
		blank.pos = origin()
		blank.kind = UNREAD
		blank.confidence = profile.min_confidence
		_spawn_at(blank, origin() + Vector2.RIGHT.rotated(_rng.randf() * TAU) * away,
			false, AMBIENT_PULL)


func _spawn(read: Read, spread: float, legible: bool) -> void:
	var angle: float = _rng.randf() * TAU
	var radius: float = spread * (0.3 + 0.7 * sqrt(_rng.randf()))
	var pull: float = 0.08
	if not legible:
		pull = (1.0 if read.confidence > GRIP_CONFIDENCE else -1.0) \
			* (0.22 + _rng.randf() * 0.5)
	_spawn_at(read, read.pos + Vector2.RIGHT.rotated(angle) * radius, legible, pull)


func _spawn_at(read: Read, at: Vector2, legible: bool, pull: float) -> void:
	if marks.size() >= profile.max_marks:
		# Drop the oldest block rather than one at a time, so the ceiling costs a
		# rare bulk removal instead of a shuffle on every spawn.
		marks = marks.slice(maxi(1, profile.max_marks / CULL_FRACTION))
	var mark := Mark.new()
	mark.pos = at
	mark.source = read.pos
	mark.kind = read.kind
	mark.confidence = read.confidence
	mark.life = profile.mark_life + _rng.randf() * profile.mark_life_spread \
		+ read.confidence * 0.9
	if legible:
		mark.life = 2.0 + _rng.randf()
	mark.seed = _rng.randf()
	mark.pull = pull
	mark.legible = legible
	marks.append(mark)


## Field-like, never a plume: a lazy curl, plus a pull toward the thing being
## read while the read holds, or away from it while it is losing its grip.
func _drift(delta: float) -> void:
	for i in range(marks.size() - 1, -1, -1):
		var mark: Mark = marks[i]
		mark.age += delta
		if mark.age >= mark.life:
			marks.remove_at(i)
			continue
		var curl := Vector2(
			sin(mark.pos.y * 0.006 + elapsed * 0.28 + mark.seed * TAU),
			cos(mark.pos.x * 0.006 - elapsed * 0.24 + mark.seed * TAU)) * profile.drift_curl
		var toward: Vector2 = mark.source - mark.pos
		var reach: float = maxf(1.0, toward.length())
		mark.pos += (curl + (toward / reach) * profile.drift_pull * mark.pull) * delta
