## Gameplay-facing hearing model for one creature.
##
## SoundField owns travelling events and physical occlusion. This class owns how
## one creature resolves them: range, sensitivity, memory and the strength lost
## behind cover. It has no renderer, camera or particle dependency.
class_name HearingSense
extends RefCounted


class HeardSound extends RefCounted:
	var wave_id: int = 0
	var origin: Vector2 = Vector2.ZERO
	var kind: int = SoundField.Kind.IMPACT
	var strength: float = 0.0
	## Unit vector from the listener toward the source at arrival.
	var direction: Vector2 = Vector2.ZERO
	var occluded: bool = false
	var age: float = 0.0


var creature: Creature
var profile: HearingProfile
var field: SoundField
var heard_sounds: Array[HeardSound] = []

var _resolved: Dictionary = {}
## Last wavefront radius observed per event. Detection happens at the crossing,
## so moving inside an old ring cannot make a creature hear it retroactively.
var _previous_front: Dictionary = {}


func setup(owner: Creature, hearing_profile: HearingProfile,
		sound_field: SoundField) -> void:
	creature = owner
	profile = hearing_profile
	field = sound_field


func reset() -> void:
	heard_sounds.clear()
	_resolved.clear()
	_previous_front.clear()
	# A new creature/species does not retroactively hear waves already in flight.
	if field != null:
		for wave in field.waves:
			_resolved[wave.id] = true
			_previous_front[wave.id] = field.radius(wave)


func origin() -> Vector2:
	if creature == null:
		return Vector2.ZERO
	if creature.body != null:
		return creature.body.head.pos
	return creature.head_pos


func advance(delta: float) -> void:
	if profile == null:
		return
	for i in range(heard_sounds.size() - 1, -1, -1):
		heard_sounds[i].age += delta
		if heard_sounds[i].age >= profile.memory_seconds:
			heard_sounds.remove_at(i)
	if field == null:
		return

	var live: Dictionary = {}
	for wave in field.waves:
		live[wave.id] = true
		var front: float = field.radius(wave)
		var previous: float = float(_previous_front.get(wave.id, 0.0))
		_previous_front[wave.id] = front
		if _resolved.has(wave.id):
			continue
		var distance: float = origin().distance_to(wave.origin)
		if distance > minf(profile.reach, wave.reach):
			continue
		# The listener must be on the annulus swept since its previous tick. This
		# works in world space, so motion can carry it into a wave but never makes
		# an already-passed sound arrive a second time.
		if distance + 0.001 < previous or front + 0.001 < distance:
			continue
		_resolved[wave.id] = true
		var blockers: int = field.occlusion_count(wave.origin, origin(),
			wave.source_id, creature.get_instance_id() if creature != null else 0)
		var strength: float = _strength(wave.amplitude, distance, wave.reach, blockers)
		if strength < profile.min_strength:
			continue
		var read := HeardSound.new()
		read.wave_id = wave.id
		read.origin = wave.origin
		read.kind = wave.kind
		read.strength = strength
		read.direction = (wave.origin - origin()).normalized()
		read.occluded = blockers > 0
		heard_sounds.append(read)
		if heard_sounds.size() > profile.max_heard_sounds:
			heard_sounds.pop_front()

	for wave_id in _resolved.keys():
		if not live.has(wave_id):
			_resolved.erase(wave_id)
	for wave_id in _previous_front.keys():
		if not live.has(wave_id):
			_previous_front.erase(wave_id)


## Continuous estimate for hypothetical gameplay/AI queries, independent of
## whether a matching visual ring is alive right now.
func strength_at(world_point: Vector2, source_amplitude: float = 1.0,
		source_id: int = 0) -> float:
	if profile == null:
		return 0.0
	var distance: float = origin().distance_to(world_point)
	if distance > profile.reach:
		return 0.0
	var blockers: int = 0
	if field != null:
		blockers = field.occlusion_count(world_point, origin(), source_id,
			creature.get_instance_id() if creature != null else 0)
	return _strength(source_amplitude, distance, profile.reach, blockers)


func hears(world_point: Vector2, source_amplitude: float = 1.0,
		source_id: int = 0) -> bool:
	return profile != null \
		and strength_at(world_point, source_amplitude, source_id) >= profile.min_strength


func reads() -> Array[HeardSound]:
	var result: Array[HeardSound] = heard_sounds.duplicate()
	result.sort_custom(func(a: HeardSound, b: HeardSound) -> bool:
		return a.strength > b.strength)
	return result


func _strength(amplitude: float, distance: float, physical_reach: float,
		blockers: int) -> float:
	if profile == null or physical_reach <= 0.0 or distance >= physical_reach:
		return 0.0
	var falloff: float = pow(clampf(1.0 - distance / physical_reach, 0.0, 1.0),
		profile.distance_falloff)
	var obstruction: float = pow(profile.occlusion_transmission, float(blockers))
	return clampf(amplitude * falloff * obstruction * profile.sensitivity, 0.0, 1.0)
