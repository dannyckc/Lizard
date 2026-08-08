## Focused contract test for the second SENSES layer.
##
## Checks the world's scent record and the creature's read of it separately, then
## the scene wiring, the species/full-reset integration, and the two claims the
## design rests on: that nothing is emitted from a source, and that the layer is
## an annotation over the habitat rather than a change to it.
##
##   godot --headless --path . --script tests/SmellTest.gd
extends SceneTree

var failures: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true

	var senses: CreatureSenses = main.senses
	var smell: SmellSense = senses.smell if senses != null else null
	var field: ScentField = main.scent_field
	_check(smell != null, "SENSES component did not register smell")
	_check(senses.layer(&"smell") == smell, "smell is not an independent perception layer")
	_check(senses.layer(&"sight") == senses.sight, "registering smell disturbed the sight layer")
	if smell == null or field == null:
		_finish()
		return false

	_check(smell.field == field, "smell is not reading the habitat's scent field")
	_check(smell.origin().is_equal_approx(main.creature.body.head.pos),
		"smell does not originate at the solved head")

	_persistence(field)
	_trails(field)
	_reading(smell, field)
	_perception_not_emission(smell, field)
	_world_untouched(field)
	_layering(senses, field)

	_finish()
	return false


## Scent outlives its source and then stops.
func _persistence(field: ScentField) -> void:
	field.clear()
	var here := Vector2(4000.0, 4000.0)
	field.deposit(here, ScentField.Kind.FORAGE)
	_check(field.traces.size() == 1, "a deposit did not leave a trace")
	_check(field.concentration_at(here) > 0.0, "a fresh trace is not detectable at its own place")
	_check(field.concentration_at(here + Vector2(600.0, 0.0)) == 0.0,
		"scent is detectable arbitrarily far from where it was left")

	# A second deposit inside the merge radius renews rather than accumulates: a
	# pellet sitting still is one smell, not one per tick it exists.
	field.deposit(here + Vector2(6.0, 0.0), ScentField.Kind.FORAGE)
	_check(field.traces.size() == 1, "a source renewing in place multiplied its traces")
	# A different kind in the same place is a different smell.
	field.deposit(here, ScentField.Kind.BLOOD)
	_check(field.traces.size() == 2, "two kinds of scent in one place merged into one")

	# Measured on a trace of its own, so a place saturated by several smells
	# cannot hide one of them weakening.
	var alone := Vector2(-9000.0, 9000.0)
	field.deposit(alone, ScentField.Kind.FORAGE)
	var full: float = field.concentration_at(alone)
	field._fade(ScentField.HOLD[ScentField.Kind.FORAGE] * 0.5)
	_check(field.concentration_at(alone) < full, "scent does not weaken with time")
	field._fade(ScentField.HOLD[ScentField.Kind.BLOOD])
	_check(field.traces.is_empty(), "scent does not disappear once it is spent")

	# Distinct sources, distinct kinds — a nose that cannot tell them apart is a
	# proximity meter.
	_check(ScentField.KIND_COUNT == 5 and ScentField.CARRY.size() == 5
		and ScentField.HOLD.size() == 5, "the scent kinds are not fully described")


## A moving source leaves the path it walked, ageing from the tail forward.
func _trails(field: ScentField) -> void:
	field.clear()
	var walker: int = 4242
	var start := Vector2(-4000.0, 0.0)
	var steps: int = 12
	for i in steps:
		field.deposit(start + Vector2(float(i) * ScentField.MERGE_RADIUS * 1.5, 0.0),
			ScentField.Kind.QUARRY, 1.0, walker)
		field._fade(0.2)
	_check(field.traces.size() >= steps - 1, "a moving source did not leave a trail behind it")
	var oldest: ScentField.Trace = field.traces[0]
	var newest: ScentField.Trace = field.traces[field.traces.size() - 1]
	_check(newest.strength > oldest.strength, "a trail is not freshest at its head")
	_check(newest.pos.x > oldest.pos.x, "a trail was not laid along the path walked")


## What one creature makes of the field from where it is standing.
func _reading(smell: SmellSense, field: ScentField) -> void:
	field.clear()
	var origin: Vector2 = smell.origin()
	var forward: Vector2 = smell.direction()
	var reach: float = smell.profile.reach

	var near_ahead: Vector2 = origin + forward * 90.0
	field.deposit(near_ahead, ScentField.Kind.CARRION)
	field.deposit(origin + forward * (reach * 0.9), ScentField.Kind.CARRION)
	field.deposit(origin - forward * 90.0, ScentField.Kind.CARRION)
	_check(smell.confidence_at(near_ahead) > smell.confidence_at(origin + forward * (reach * 0.9)),
		"smell does not resolve with distance")
	_check(smell.confidence_at(near_ahead) > smell.confidence_at(origin - forward * 90.0),
		"smell does not favour the direction the muzzle is pointed")
	_check(smell.confidence_at(origin + forward * (reach * 2.0)) == 0.0,
		"smell reads past its own reach")
	_check(smell.confidence_at(near_ahead + Vector2(3000.0, 0.0)) == 0.0,
		"smell reads a place nothing has ever been")

	var carrion: Array = smell.reads()
	_check(carrion.size() == 3, "a read did not find every trace in range")
	_check(carrion[0].confidence >= carrion[carrion.size() - 1].confidence,
		"reads are not ordered by how sure they are")
	_check(carrion[0].kind == ScentField.Kind.CARRION, "a read lost the kind of scent it found")

	# Kinds are told apart by how far they carry, not by being muffled up close:
	# a carcass announces itself from a distance a seed never would, and either
	# one under the muzzle is read for certain.
	field.clear()
	var far: Vector2 = origin + forward * (reach * 0.85)
	field.deposit(far, ScentField.Kind.CARRION)
	var carrion_far: Array = smell.reads()
	field.clear()
	field.deposit(far, ScentField.Kind.FORAGE)
	_check(not carrion_far.is_empty() and smell.reads().is_empty(),
		"every kind of scent carries exactly as far as every other")
	field.clear()
	var under_nose: Vector2 = origin + forward * 12.0
	field.deposit(under_nose, ScentField.Kind.FORAGE)
	_check(smell.reads()[0].confidence > 0.85, "a smell under the muzzle is not read for certain")

	# A creature does not track itself: its own musk is not news.
	field.clear()
	field.deposit(origin + forward * 40.0, ScentField.Kind.QUARRY, 1.0,
		main.creature.get_instance_id())
	_check(smell.reads().is_empty(), "a creature reads its own trail back to itself")


## The design's claim: nothing leaves the source. Marks are the observer's, they
## appear around what has already been found, and they dissolve.
func _perception_not_emission(smell: SmellSense, field: ScentField) -> void:
	field.clear()
	smell.reset()
	var origin: Vector2 = smell.origin()
	var source: Vector2 = origin + smell.direction() * 120.0
	field.deposit(source, ScentField.Kind.CARRION)

	smell.advance(smell.profile.beat_interval * 1.01)
	_check(not smell.marks.is_empty(), "a beat of the sense resolved nothing at all")

	var on_source: int = 0
	var spread: float = 0.0
	var found: int = 0
	for mark in smell.marks:
		if mark.kind != ScentField.Kind.CARRION:
			continue
		found += 1
		var away: float = mark.pos.distance_to(source)
		spread = maxf(spread, away)
		if away < 1.0:
			on_source += 1
	_check(found > 0, "a strong nearby source produced no marks")
	_check(on_source == 0, "marks are spawned on top of their source rather than around it")
	_check(spread > smell.profile.cluster_radius * 0.5,
		"marks do not occupy the air around what is being read")
	_check(spread < smell.profile.cluster_radius + smell.profile.scatter_radius + 1.0,
		"marks stream away from their source instead of hanging near it")

	# The sense runs whether or not it finds anything.
	field.clear()
	smell.reset()
	smell.advance(smell.profile.beat_interval * 1.01)
	var unread: int = 0
	for mark in smell.marks:
		if mark.kind == SmellSense.UNREAD:
			unread += 1
	_check(unread == smell.profile.ambient_marks,
		"the sense stops running when there is nothing to find")

	# Marks are impressions, not objects: they go out on their own. Asked of the
	# marks that exist now, because advancing far enough to kill them also beats
	# the sense again and makes new ones.
	var struck: Array = smell.marks.duplicate()
	var life: float = 0.0
	for mark in struck:
		life = maxf(life, mark.life)
	smell.advance(life + 0.1)
	for mark in struck:
		if smell.marks.has(mark):
			_check(false, "marks never dissolve")
			break

	# A saturated field cannot grow the read without bound.
	field.clear()
	smell.reset()
	for i in 200:
		field.deposit(origin + Vector2.RIGHT.rotated(float(i) * 0.31)
			* (60.0 + float(i % 7) * 40.0), ScentField.Kind.SCRAP)
	for _beat in 24:
		smell.advance(smell.profile.beat_interval * 1.01)
	_check(smell.marks.size() <= smell.profile.max_marks,
		"the read has no ceiling on how much it holds at once")
	_check(field.traces.size() <= ScentField.MAX_TRACES,
		"the scent field has no ceiling on how much it holds at once")


## Environmental objects are unchanged by having a smell.
func _world_untouched(field: ScentField) -> void:
	field.clear()
	var pellets_before: int = main.food_field.pellets.size()
	var scraps_before: int = main.scrap_field.scraps.size()
	var integrity_before: float = main.target_creature.anatomy.tissue.integrity()
	for _tick in 30:
		field._fade(ScentField.TICK)
		field._index()
		field._gather()
	_check(main.food_field.pellets.size() == pellets_before
		and main.scrap_field.scraps.size() == scraps_before
		and is_equal_approx(main.target_creature.anatomy.tissue.integrity(), integrity_before),
		"gathering scent changed the habitat it was reading")
	_check(not field.traces.is_empty(), "the habitat's own bodies do not smell of anything")

	var kinds: Dictionary = {}
	for trace in field.traces:
		kinds[trace.kind] = true
	_check(kinds.has(ScentField.Kind.FORAGE), "food does not smell")
	_check(kinds.has(ScentField.Kind.QUARRY), "a living creature does not smell")
	_check(kinds.has(ScentField.Kind.CARRION), "a carcass does not smell")


## Where the layer sits, and what a reset does to it.
func _layering(senses: CreatureSenses, field: ScentField) -> void:
	var renderer: SmellRenderer = main.smell_renderer
	_check(renderer.senses == senses, "SmellRenderer is not consuming the creature component")
	_check(main.sight_renderer.z_index < renderer.z_index,
		"smell is resolved under the sight treatment instead of over it")
	_check(renderer.z_index < main.view.z_index,
		"the controlled creature is not kept above its own perception layer")
	var pigment := renderer.material as ShaderMaterial
	_check(pigment != null and pigment.shader != null
		and pigment.shader.code.contains("blend_mul"),
		"marks are laid over the habitat as light rather than struck into it as pigment")
	# The same blend without the glyph's coverage folded in renders every mark as a
	# solid quad, which is the one way this layer can fail while still drawing.
	_check(pigment != null and pigment.shader != null
		and pigment.shader.code.contains("COLOR.a"),
		"the multiply blend ignores glyph coverage and will stamp solid blocks")

	var species_profile := SmellProfile.new()
	species_profile.reach = 333.0
	senses.set_smell_profile(species_profile)
	_check(senses.smell.profile == species_profile and senses.smell.profile.reach == 333.0,
		"a species-specific smell profile cannot replace the default")
	senses.set_smell_profile(SmellProfile.new())

	senses.smell.advance(senses.smell.profile.beat_interval * 1.01)
	main.hud.select_species("Gecko")
	_check(senses.active_species == "Gecko", "species change did not reset SENSES")
	_check(senses.smell.marks.is_empty(), "a species change kept the old creature's read")

	field.deposit(main.creature.head_pos + Vector2(50.0, 0.0), ScentField.Kind.BLOOD)
	senses.smell.advance(senses.smell.profile.beat_interval * 1.01)
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	main._unhandled_input(reset)
	_check(field.traces.is_empty(), "a full reset left the old habitat's scent behind")
	_check(senses.smell.marks.is_empty(), "a full reset left the old read behind")
	_check(senses.active_species == "Gecko", "full reset lost the active species")
	_check(senses.smell.origin().is_equal_approx(main.creature.body.head.pos),
		"smell did not follow the head after reset")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("smell OK — scent persists, trails, fades, and is read rather than emitted")
		quit(0)
	else:
		for failure in failures:
			print("SMELL FAIL — ", failure)
		quit(1)
