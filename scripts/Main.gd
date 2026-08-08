## Game root: wires input to the creature, follows it with the camera, keeps the
## food field topped up and owns the HUD / tuning panel.
##
## Node order in the scene matters — Main ticks before its children, so the
## movement command written here is the one the creature consumes this tick.
extends Node2D

const GRID_SPACING: float = 90.0
## The design mockup presents the default 200 px body close to actual size.
const DEFAULT_ZOOM: float = 1.0
## 4× MSAA is comfortably inside budget through 1440p after the sense renderer
## optimisations. Beyond that, target pixel count dominates again; 2× at 4K has
## both better frame time and comparable edge density to 4× at 1440p.
const MSAA_4X_PIXEL_BUDGET: int = 2560 * 1440
const PAPER := Color("f3f1ec")
const INK := Color("14140f")
const COL_GRID := Color(INK, 0.13)

@onready var food_field: FoodField = $FoodField
@onready var scrap_field: ScrapField = $ScrapField
@onready var scent_field: ScentField = $ScentField
@onready var sound_field: SoundField = $SoundField
@onready var creature: Creature = $Creature
@onready var senses: CreatureSenses = $Creature/Senses
@onready var view: CreatureView = $Creature/View
@onready var target_creature: Creature = $TargetCreature
@onready var target_view: CreatureView = $TargetCreature/View
@onready var bite_cue: BiteCue = $BiteCue
@onready var camera: Camera2D = $Camera2D
@onready var sight_renderer: SightRenderer = $SightRenderer
@onready var smell_renderer: SmellRenderer = $SmellRenderer
@onready var hearing_renderer: HearingRenderer = $HearingRenderer

var input := MovementInput.new()
var panel: TuningPanel
var hud: EvolutionHUD
## Paired feet often land on the same gait beat. Register every other contact so
## locomotion stays quiet and rhythmic rather than becoming a constant ripple.
var _footfall_counts: Dictionary = {}


func _ready() -> void:
	get_viewport().size_changed.connect(_update_output_msaa)
	_update_output_msaa()
	camera.make_current()
	camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	camera.global_position = creature.head_pos
	# Any creature can be bitten, so any creature can bite and any creature can
	# shed. Children are ready before their parent, so the group is already
	# populated here. The biter is bound rather than assumed, because a latched
	# bite now emits again every time its jaws come round to chew.
	for node in get_tree().get_nodes_in_group("creatures"):
		var each := node as Creature
		each.bite_started.connect(_on_creature_bite_started.bind(each))
		each.tissue_shed.connect(_on_tissue_shed.bind(node))
		each.foot_landed.connect(_on_foot_landed.bind(each))
	food_field.refresh(creature.head_pos)
	_build_ui()


func _update_output_msaa() -> void:
	var viewport := get_viewport()
	viewport.msaa_2d = _msaa_for_output_size(viewport.size)


func _msaa_for_output_size(output_size: Vector2i) -> Viewport.MSAA:
	var pixels: int = output_size.x * output_size.y
	return Viewport.MSAA_4X if pixels <= MSAA_4X_PIXEL_BUDGET else Viewport.MSAA_2X


func _build_ui() -> void:
	_build_backdrop()

	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 20
	add_child(layer)

	hud = EvolutionHUD.new()
	hud.params = creature.params
	layer.add_child(hud)
	panel = hud.panel
	hud.species_selected.connect(_on_species_selected)


func _build_backdrop() -> void:
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.name = "PaperBackdrop"
	backdrop_layer.layer = -20
	add_child(backdrop_layer)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

float paper_noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 paper = vec3(0.953, 0.945, 0.925);
	vec3 ink = vec3(0.078, 0.078, 0.059);
	vec2 centred = (UV - vec2(0.5)) * vec2(1.50, 1.85);
	float vignette = smoothstep(0.45, 1.13, length(centred)) * 0.048;
	float grain = (paper_noise(FRAGCOORD.xy) - 0.5) * 0.018;
	float amount = clamp(vignette + grain, 0.0, 0.07);
	COLOR = vec4(mix(paper, ink, amount), 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	backdrop.material = material
	backdrop.color = PAPER
	backdrop_layer.add_child(backdrop)


func _physics_process(_delta: float) -> void:
	# Let the head settle forward while the cursor is operating a slider. Mouse
	# look is purely cosmetic/gameplay aim and never changes the body command.
	input.mouse_look = get_viewport().gui_get_hovered_control() == null
	creature.command = input.read(creature.head_pos, creature.heading, get_global_mouse_position())

	food_field.refresh(creature.head_pos)
	# The mouse can articulate the visible head around the neck without moving
	# the locomotion anchor, so mouth interactions use the solved head itself.
	var eaten: int = food_field.consume(creature.body.head.pos, creature.mouth_radius())
	if eaten > 0:
		creature.feed(eaten)
		sound_field.emit_sound(creature.body.head.pos, 0.42 * creature.size_scale,
			SoundField.Kind.FEED, creature)

	# Torn-off tissue is meat, and meat belongs to whoever's jaws reach it — so
	# this is resolved over every creature rather than only the player's.
	for node in get_tree().get_nodes_in_group("creatures"):
		var scavenger := node as Creature
		# A dead mouth is not a mouth. Meat coming to rest against a carcass would
		# otherwise quietly disappear into it.
		if scavenger == null or scavenger.body == null or not scavenger.alive:
			continue
		var scavenged: int = scrap_field.consume(
			scavenger.body.head.pos, scavenger.mouth_radius(), scavenger)
		if scavenged > 0:
			scavenger.feed(scavenged)
			sound_field.emit_sound(scavenger.body.head.pos,
				0.42 * scavenger.size_scale, SoundField.Kind.FEED, scavenger)


func _process(delta: float) -> void:
	# The editorial HUD treats the creature as a specimen: keep it centred while
	# easing away the tiny high-frequency motion from the procedural head.
	camera.global_position = camera.global_position.lerp(creature.head_pos, 1.0 - exp(-3.2 * delta))

	_update_hud()
	queue_redraw()


func _update_hud() -> void:
	var stepping: int = 0
	for limb in creature.gait.limbs:
		if limb.stepping:
			stepping += 1
	var state: String = "idle"
	if creature.speed_norm > 0.05:
		state = "walking"
	if absf(creature.ang_vel) > 0.6 and creature.speed_norm < 0.35:
		state = "turning"
	if creature.command.sprint and creature.speed_norm > 0.7:
		state = "running"
	if creature.is_lunging():
		state = "biting"
	# A hold outranks the lunge that started it: once the jaws are on something,
	# what the creature is doing is holding on, not striking.
	if creature.is_bite_latched():
		state = "gripping"
	elif creature.is_being_gripped():
		state = "held"

	hud.update_metrics(
		state,
		int(absf(creature.speed)),
		stepping,
		creature.food_eaten,
		creature.anatomy.tissue.integrity(),
		creature.spine.size(),
		creature.physique.mass
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				hud.toggle_panel()
			KEY_F2:
				view.debug = not view.debug
				target_view.debug = view.debug
			KEY_R:
				creature.reset()
				senses.reset_for_species(senses.active_species)
				target_creature.reset(target_creature.spawn_position, target_creature.spawn_heading)
				food_field.pellets.clear()
				food_field.refresh(creature.head_pos)
				scrap_field.clear()
				scent_field.clear()
				sound_field.clear()
				_footfall_counts.clear()
				camera.global_position = creature.head_pos
				hud.reset_hint()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			creature.set_bite_held(event.pressed)
			if event.pressed:
				creature.request_bite(get_global_mouse_position())


## A bite may begin only from unhandled world input, but its release must be
## observed even if the cursor moves over the tuning UI while the jaws are
## clamped. `_input` runs before GUI dispatch, so handling only the release here
## preserves both rules.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		creature.set_bite_held(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(creature):
		creature.set_bite_held(false)


func _zoom_by(factor: float) -> void:
	var z: float = clampf(camera.zoom.x * factor, 0.35, 3.0)
	camera.zoom = Vector2(z, z)


func _on_species_selected(preset_name: String) -> void:
	# Rebuild immediately so structural changes (especially segment count) feel
	# as responsive as the sliders and tabs look.
	creature.rebuild()
	senses.reset_for_species(preset_name)
	sight_renderer.refresh_profile()
	smell_renderer.refresh_profile()
	hearing_renderer.refresh_profile()


## Resolves one closing of a set of jaws: the apex of a lunge, a chew from jaws
## already latched, or the mouthful a grip takes with it when it is torn off.
##
## The hit test picks a single victim — the body overlapped most deeply — and
## only then does the bite erode that creature's tissue, by position, across
## whatever structures of it the jaws actually cover. Owned by the world rather
## than by either participant so creature update order cannot turn one strike
## into several hits as more creatures are introduced, and so all three cases go
## down exactly one path.
##
## Depth is asked of the biter rather than read off its params: a set of jaws
## already holding something spends part of its force staying shut, and only what
## is left over cuts.
func _on_creature_bite_started(center: Vector2, radius: float, biter: Creature) -> void:
	bite_cue.show_at(center)
	var best_target: Creature = null
	var best_hit: AnatomyState.Hit = null
	for node in get_tree().get_nodes_in_group("creatures"):
		var candidate := node as Creature
		if candidate == null or candidate == biter:
			continue
		var hit: AnatomyState.Hit = candidate.query_bite(center, radius)
		if hit != null and (best_hit == null or hit.score < best_hit.score):
			best_target = candidate
			best_hit = hit

	var connected: bool = false
	if best_target != null:
		var removed: float = best_target.apply_bite(center, radius, biter.bite_depth())
		connected = removed > 0.0
	if connected:
		# Spilled blood is left at the place it was spilled and belongs to nobody
		# after that — including the creature it came out of, which is why it is
		# deposited unowned while a wound's slow drip is not.
		scent_field.deposit(center, ScentField.Kind.BLOOD)
	sound_field.emit_sound(center, (0.52 if connected else 0.34) * biter.size_scale,
		SoundField.Kind.BITE, biter)
	biter.resolve_bite(connected, best_target if connected else null, best_hit)


func _on_foot_landed(at: Vector2, intensity: float, source: Creature) -> void:
	var source_id: int = source.get_instance_id()
	var count: int = int(_footfall_counts.get(source_id, 0)) + 1
	_footfall_counts[source_id] = count
	if count % 2 == 0:
		sound_field.emit_sound(at, intensity, SoundField.Kind.STEP, source)


func _on_tissue_shed(chunks: Array, origin: Vector2, source: Creature) -> void:
	scrap_field.scatter(chunks, origin, source)


## Sparse one-pixel registration dots from the design's specimen-sheet field.
func _draw() -> void:
	var half: Vector2 = get_viewport_rect().size * 0.5 / camera.zoom
	var centre: Vector2 = camera.global_position
	var min_x: float = floor((centre.x - half.x) / GRID_SPACING) * GRID_SPACING
	var max_x: float = centre.x + half.x
	var min_y: float = floor((centre.y - half.y) / GRID_SPACING) * GRID_SPACING
	var max_y: float = centre.y + half.y

	var x: float = min_x
	while x <= max_x:
		var y: float = min_y
		while y <= max_y:
			draw_circle(Vector2(x, y), 1.0 / camera.zoom.x, COL_GRID)
			y += GRID_SPACING
		x += GRID_SPACING
