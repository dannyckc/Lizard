## Gameplay-facing sight model for a creature.
##
## This class knows where the eyes are looking and can answer perception queries,
## but it has no dependency on shaders, cameras or the viewport. SightRenderer is
## a separate consumer of the same pose/profile, so detection rules can evolve
## without turning screen presentation into gameplay truth.
class_name SightSense
extends RefCounted

var creature: Creature
var profile: SightProfile


func setup(owner: Creature, sight_profile: SightProfile) -> void:
	creature = owner
	profile = sight_profile


func reset() -> void:
	# Sight is stateless today. This hook is intentional: adaptation, temporary
	# blindness and sensory fatigue can later clear with the creature without the
	# reset flow needing to know how sight stores them.
	pass


func origin() -> Vector2:
	if creature == null:
		return Vector2.ZERO
	if creature.body != null:
		return creature.body.head.pos
	return creature.head_pos


func direction() -> Vector2:
	if creature == null:
		return Vector2.RIGHT
	var look: Vector2 = creature.head_look_dir
	return look.normalized() if look.length_squared() > 0.0001 else Vector2.RIGHT.rotated(creature.heading)


## Continuous 0..1 visual/perceptual confidence at a world point. This is not a
## target detector: occlusion, camouflage and recognition belong to future
## gameplay systems, which can use this field as one input alongside hearing and
## smell instead of borrowing pixels from the sight shader.
func clarity_at(world_point: Vector2) -> float:
	if profile == null:
		return 0.0
	var delta: Vector2 = world_point - origin()
	var forward: Vector2 = direction()
	var along: float = delta.dot(forward)
	var across: float = absf(delta.cross(forward))
	var clear: float = _field_strength(along, across,
		profile.clear_reach, profile.clear_width, profile.clear_near_radius)
	var peripheral: float = _field_strength(along, across,
		profile.peripheral_reach, profile.peripheral_width, profile.peripheral_near_radius)
	return clampf(maxf(clear, peripheral * 0.55), 0.0, 1.0)


func clearly_sees(world_point: Vector2, threshold: float = 0.62) -> bool:
	return clarity_at(world_point) >= threshold


## A soft union of a near-eye circle and a forward organic envelope. There is no
## cone boundary: confidence falls continuously in every direction and retains a
## modest near field behind the eyes.
func _field_strength(along: float, across: float, reach: float, width: float,
		near_radius: float) -> float:
	var near_distance: float = Vector2(along, across).length()
	var near_strength: float = 1.0 - smoothstep(near_radius * 0.45, near_radius, near_distance)
	if along <= 0.0 or along >= reach:
		return near_strength
	var t: float = clampf(along / reach, 0.0, 1.0)
	var envelope: float = width * (0.34 + 0.78 * pow(sin(PI * (0.12 + 0.88 * t)), 0.75))
	var lateral: float = 1.0 - smoothstep(envelope * 0.45, envelope, across)
	var tail: float = 1.0 - smoothstep(0.72, 1.0, t)
	return maxf(near_strength, lateral * tail)

