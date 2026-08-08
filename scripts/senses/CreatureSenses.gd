## Reusable sensory component attached to a creature.
##
## Each sense owns an independent perception layer. Only sight exists now;
## hearing and smell can later register beside it without either depending on
## SightSense or SightRenderer.
class_name CreatureSenses
extends Node

signal sight_profile_changed(profile: SightProfile)

@export var sight_profile: SightProfile

var sight: SightSense
var active_species: String = "Lizard"
var _layers: Dictionary = {}


func _ready() -> void:
	var owner := get_parent() as Creature
	if owner == null:
		push_error("CreatureSenses must be a direct child of a Creature")
		return
	if sight_profile == null:
		sight_profile = SightProfile.new()
	sight = SightSense.new()
	sight.setup(owner, sight_profile)
	register_layer(&"sight", sight)
	reset_for_species(active_species)


func register_layer(layer_name: StringName, layer: RefCounted) -> void:
	_layers[layer_name] = layer


func layer(layer_name: StringName) -> RefCounted:
	return _layers.get(layer_name) as RefCounted


## Runtime seam for a future species table. The renderer observes the component,
## while gameplay queries immediately read the same replacement profile.
func set_sight_profile(profile: SightProfile) -> void:
	if profile == null:
		return
	sight_profile = profile
	if sight != null:
		sight.profile = profile
	sight_profile_changed.emit(profile)


## Species changes and full creature resets both enter here. There is one default
## profile for now; the species name is retained so profile lookup can be added
## later without changing Main's reset contract or any renderer wiring.
func reset_for_species(species_name: String = "") -> void:
	active_species = species_name
	for sense_layer in _layers.values():
		if sense_layer.has_method("reset"):
			sense_layer.reset()
