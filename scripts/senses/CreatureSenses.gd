## Reusable sensory component attached to a creature.
##
## Each sense owns an independent perception layer. Sight, smell and hearing do
## not know about each other. Layers that need a clock get one from `_process`
## without this component knowing what they do with it, and pure queries need no
## wiring at all.
class_name CreatureSenses
extends Node

signal sight_profile_changed(profile: SightProfile)
signal smell_profile_changed(profile: SmellProfile)
signal hearing_profile_changed(profile: HearingProfile)

@export var sight_profile: SightProfile
@export var smell_profile: SmellProfile
@export var hearing_profile: HearingProfile
## The habitat's scent record. Smell reads the world rather than being told about
## it, so the component needs to be pointed at the field once.
@export var scent_field_path: NodePath
## World-owned travelling sound events. Hearing reads these; it never asks its
## renderer what is on screen.
@export var sound_field_path: NodePath

var sight: SightSense
var smell: SmellSense
var hearing: HearingSense
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

	if smell_profile == null:
		smell_profile = SmellProfile.new()
	var scent_field: ScentField = null
	if not scent_field_path.is_empty():
		scent_field = get_node_or_null(scent_field_path) as ScentField
	smell = SmellSense.new()
	smell.setup(owner, smell_profile, scent_field)
	register_layer(&"smell", smell)

	if hearing_profile == null:
		hearing_profile = HearingProfile.new()
	var sound_field: SoundField = null
	if not sound_field_path.is_empty():
		sound_field = get_node_or_null(sound_field_path) as SoundField
	hearing = HearingSense.new()
	hearing.setup(owner, hearing_profile, sound_field)
	register_layer(&"hearing", hearing)

	reset_for_species(active_species)


## Senses that accumulate a read over time advance here. A sense that is a pure
## query — sight — simply has no `advance` and is skipped.
func _process(delta: float) -> void:
	for sense_layer in _layers.values():
		if sense_layer.has_method("advance"):
			sense_layer.advance(delta)


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


func set_smell_profile(profile: SmellProfile) -> void:
	if profile == null:
		return
	smell_profile = profile
	if smell != null:
		smell.profile = profile
	smell_profile_changed.emit(profile)


func set_hearing_profile(profile: HearingProfile) -> void:
	if profile == null:
		return
	hearing_profile = profile
	if hearing != null:
		hearing.profile = profile
		hearing.reset()
	hearing_profile_changed.emit(profile)


## Species changes and full creature resets both enter here. There is one default
## profile per sense for now; the species name is retained so profile lookup can
## be added later without changing Main's reset contract or any renderer wiring.
func reset_for_species(species_name: String = "") -> void:
	active_species = species_name
	for sense_layer in _layers.values():
		if sense_layer.has_method("reset"):
			sense_layer.reset()
