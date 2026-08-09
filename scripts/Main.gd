## Game root: wires input to the creature, follows it with the camera, keeps the
## food field topped up and owns the HUD and the creature creation menu.
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

## The habitat starts bare: one animal, one carcass, and an empty floor to read
## them against. Both fields below are still live and still answer every query —
## anything handed to `terrain.add` or dropped into `food_field.pellets` behaves
## exactly as it always did, which is how the tests populate them.
@onready var terrain: Terrain = $Terrain
@onready var food_field: FoodField = $FoodField
@onready var scrap_field: ScrapField = $ScrapField
@onready var carrion: CarrionField = $CarrionField
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
var hud: EvolutionHUD
var creator: CreatureCreator
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
		each.tissue_shed.connect(_on_tissue_shed.bind(each))
		each.part_severed.connect(_on_part_severed.bind(each))
		each.swallowed.connect(_on_swallowed.bind(each))
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
	creator = hud.creator
	# Whose body the creation menu is making. The player's, because that is the
	# animal being worn; the anatomy tab below can be pointed at either.
	hud.set_subject(creature)
	hud.species_selected.connect(_on_species_selected)
	hud.param_changed.connect(_on_param_changed)
	# Which bodies the anatomy tab can be pointed at. Named here because which
	# creature is whose is the world's business — the HUD only opens them up.
	hud.set_specimens([
		{"name": "Self", "creature": creature},
		{"name": "Target", "creature": target_creature},
	])


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
	_aim_cursor()

	food_field.refresh(creature.head_pos)
	# The mouse can articulate the visible head around the neck without moving
	# the locomotion anchor, so mouth interactions use the solved head itself.
	var eaten: int = food_field.consume(creature.body.head.pos, creature.mouth_radius(),
		creature.stature.bite)
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
			scavenger.body.head.pos, scavenger.mouth_radius(), scavenger,
			scavenger.stature.bite)
		if scavenged > 0:
			scavenger.feed(scavenged)
			sound_field.emit_sound(scavenger.body.head.pos,
				0.42 * scavenger.size_scale, SoundField.Kind.FEED, scavenger)


## Resolves the cursor into one target and hands it to the player's creature.
##
## Every tick rather than on the click, and that is what makes it a *target*
## rather than a mouse coordinate: the body starts reaching for whatever is under
## the pointer before any button is pressed — lowering itself toward something on
## the floor, holding its height for something at chest level — so the strike,
## when it comes, is thrown from a body already in position. Which is what an
## animal does, and the reason none of it needed an animation.
##
## Owned here rather than by the creature for the same reason the bite resolver
## is: which of the several things under one pixel was meant is a question about
## the world, and only the world can see all of them.
##
## Which is exactly why it takes two calls. `pick` is that question and is
## answered without reference to anybody — what is under the pointer. `resolve` is
## the other one, and it is about a single body: which surface of the thing *this*
## animal's jaws would meet, and whether the marker has to stop short of it
## because the animal cannot get that far. Both are needed here because the world
## is the only place holding one of each.
func _aim_cursor() -> void:
	if not input.mouse_look:
		creature.aim_at(null)
		return
	creature.aim_at(Reticle.resolve(Reticle.pick(get_tree(),
		get_global_mouse_position(), Reticle.SLACK, creature), creature))


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
	# Close control outranks the walk it is a walk of, because it is what the
	# player has asked the animal to be doing. Named for the posture rather than
	# for the key: what a body creeping along with its belly down is doing is
	# stalking, whether or not there is anything in front of it.
	if creature.is_stalking():
		state = "stalking" if creature.speed_norm > 0.02 else "crouched"
	# Off the ground outranks anything it was doing on it: what the creature is
	# doing is leaping, gliding or flying, and the name comes from the elevation
	# itself rather than from a second reading of the same facts here.
	if creature.elevation.is_airborne():
		state = creature.elevation.state_name()
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
		creature.physique.mass,
		creature.elevation.height
	)
	hud.update_target(_target_readout())


## What the cursor has hold of, in words: which structure of which thing, how far
## off the ground it is, and why the jaws cannot be got onto it when they cannot.
##
## The marker in the field says where; this says what. Both are needed and
## neither replaces the other — a ring on a shin and a ring on the flank behind it
## are two pixels apart in a top-down picture, and which of them the click meant
## is the whole question this game's third axis asks.
func _target_readout() -> String:
	var pick: Reticle.Pick = creature.aim
	if pick == null:
		return "—"
	var selected: Reticle.Pick = pick.selected()
	var text: String = "%s %d PX" % [selected.name_of().to_upper(),
		int(round(selected.height))]
	if selected != pick:
		return "%s · BEYOND REACH" % text
	var reach: Reach = creature.aim_reach
	if reach != null and not reach.possible:
		return "%s · %s" % [text, reach.refusal.to_upper()]
	return text


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				hud.toggle_creator()
			KEY_ESCAPE:
				hud.set_creator_open(false)
			KEY_F2:
				view.debug = not view.debug
				target_view.debug = view.debug
			KEY_F3:
				hud.toggle_view()
			KEY_R:
				creature.reset()
				senses.reset_for_species(senses.active_species)
				target_creature.reset(target_creature.spawn_position, target_creature.spawn_heading)
				food_field.pellets.clear()
				food_field.refresh(creature.head_pos)
				scrap_field.clear()
				carrion.clear()
				bite_cue.clear()
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
	# as responsive as the sliders and the species rail look.
	creature.rebuild()
	senses.reset_for_species(preset_name)
	sight_renderer.refresh_profile()
	smell_renderer.refresh_profile()
	hearing_renderer.refresh_profile()


## One slider moved in the creation menu.
##
## Nearly all of them need nothing done: the parameters are read fresh every tick,
## so a width or a bite depth is already in effect by the time the handle stops
## moving. The handful that are *built into* the body rather than read off it —
## the stance, where the girdles sit, what each joint does — are laid down once at
## rebuild time and would otherwise sit there describing an animal that does not
## exist until something else happened to grow it. Which is the world's job, and
## this is the world.
func _on_param_changed(_prop: String, structural: bool) -> void:
	if structural:
		creature.rebuild()


## Resolves one closing of a set of jaws: the apex of a lunge, a chew from jaws
## already latched, or the mouthful a grip takes with it when it is torn off.
##
## The hit test picks a single victim — the body overlapped most deeply — and
## only then does the mark erode that creature's tissue, by position, across
## whatever structures of it the jaws actually cover. Owned by the world rather
## than by either participant so creature update order cannot turn one strike
## into several hits as more creatures are introduced, and so all three cases go
## down exactly one path.
##
## The mark carries its own penetration, tooth by tooth, because how a bite is
## spent is a property of the mouth that made it — a set of jaws already holding
## something has less force to cut with, and a keen dentition concentrates what
## it does have. Neither is anything the world needs to know: it is handed one
## footprint and stamps it.
## Jaws already holding meat are resolved against that meat and nothing else, for
## the same reason a chew on a living victim never re-targets: what these jaws are
## closing on is what is in them.
func _on_creature_bite_started(mark: BiteMark, biter: Creature) -> void:
	bite_cue.show_mark(mark)
	if biter.mouthful != null:
		_chew_mouthful(mark, biter)
		return

	var best_target: Creature = null
	var best_hit: AnatomyState.Hit = null
	for node in get_tree().get_nodes_in_group("creatures"):
		var candidate := node as Creature
		if candidate == null or candidate == biter:
			continue
		var hit: AnatomyState.Hit = candidate.query_bite(mark.center, mark.radius, mark.reach)
		if hit != null and (best_hit == null or hit.score < best_hit.score):
			best_target = candidate
			best_hit = hit

	# Meat on the ground competes for the same bite on the same terms, and can win
	# it: a leg lying across a body is what the jaws reached furthest into, so a
	# leg is what they close on. Scored in the same currency by the same rule,
	# which is the only reason the comparison means anything.
	var meat: CarrionField.Part = carrion.reach_of(mark.center, mark.radius, mark.reach)
	if meat != null and best_hit != null \
			and carrion.depth_into(meat, mark.center) >= best_hit.score:
		meat = null
	if meat != null:
		best_target = null
		best_hit = null

	var connected: bool = false
	if meat != null:
		connected = _bite_meat(meat, mark, biter)
		# A piece bitten clean through is two pieces, whether or not anything was
		# holding it. What the jaws are over stays the piece they then take.
		if connected:
			carrion.split(meat, meat.to_local(mark.center))
	elif best_target != null:
		connected = best_target.apply_bite(mark) > 0.0
	if connected:
		# Spilled blood is left at the place it was spilled and belongs to nobody
		# after that — including the creature it came out of, which is why it is
		# deposited unowned while a wound's slow drip is not.
		scent_field.deposit(mark.center, ScentField.Kind.BLOOD)
	sound_field.emit_sound(mark.center, (0.52 if connected else 0.34) * biter.size_scale,
		SoundField.Kind.BITE, biter)
	biter.resolve_bite(connected, best_target if connected else null, best_hit,
		meat if connected else null)


## One closing of a set of jaws on a severed part.
##
## This is the only place a part turns into meat, and it does it by being bitten —
## the same erosion, the same shed chunks, the same scatter. What comes off is
## owned by the animal the part came off rather than by whoever is chewing it, so
## a creature still cannot be fed by its own tissue however many mouths it has
## passed through.
func _bite_meat(meat: CarrionField.Part, mark: BiteMark, biter: Creature) -> bool:
	var chunks: Array = []
	var removed: float = carrion.bite(meat, mark, chunks)
	if not chunks.is_empty():
		scrap_field.scatter(chunks, mark.center, meat.source_id)
	sound_field.emit_sound(mark.center, 0.30 * biter.size_scale,
		SoundField.Kind.FEED, biter)
	return removed > 0.0


## A chew on the piece already in the jaws. Split afterwards, because a piece bitten
## through the middle is two pieces — the same rule that made it in the first place,
## applied to it.
func _chew_mouthful(mark: BiteMark, biter: Creature) -> void:
	var meat: CarrionField.Part = biter.mouthful.part
	var connected: bool = _bite_meat(meat, mark, biter)
	if connected:
		scent_field.deposit(mark.center, ScentField.Kind.BLOOD)
		carrion.split(meat, biter.mouthful.hold)
	biter.resolve_bite(connected, null, null, null)


func _on_foot_landed(at: Vector2, intensity: float, source: Creature) -> void:
	var source_id: int = source.get_instance_id()
	var count: int = int(_footfall_counts.get(source_id, 0)) + 1
	_footfall_counts[source_id] = count
	if count % 2 == 0:
		sound_field.emit_sound(at, intensity, SoundField.Kind.STEP, source)


func _on_tissue_shed(chunks: Array, origin: Vector2, source: Creature) -> void:
	scrap_field.scatter(chunks, origin, source.get_instance_id())


## A creature has come apart. The pieces enter the world as anatomy, not as meat —
## see CarrionField — and the only thing that happens to them here is that they
## start lying somewhere and smelling of blood.
func _on_part_severed(pieces: Array, source: Creature) -> void:
	carrion.receive(pieces, source)
	scent_field.deposit(source.bounds_center, ScentField.Kind.BLOOD)


func _on_swallowed(part: CarrionField.Part, eater: Creature) -> void:
	eater.feed(carrion.swallow(part))
	sound_field.emit_sound(eater.body.head.pos, 0.42 * eater.size_scale,
		SoundField.Kind.FEED, eater)


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

	_draw_reticle()


## What the cursor has selected, drawn so the third axis is legible.
##
## Two marks and a line between them, because that is exactly what the pick is: a
## ring where the target is in the picture, a tick where it stands on the ground
## plane, and the drop between the two, which is its height. Nothing else in a
## top-down view can show that a click landed on a shoulder rather than on the
## floor a shoulder's height behind it, and the whole feature is unreadable
## without it.
##
## Hollow when the jaws cannot be got onto it, filled when they can — so "out of
## reach" is something the player sees before pressing the button rather than
## something they infer from a bite that did nothing.
##
## Two more marks, now that the pick knows what it is on. The structure itself is
## traced — the actual bone, the actual span of flank — because a ring alone
## cannot say *which* of the four legs overlapping one another in a top-down
## picture the click has hold of. And when the marker has had to stop short of
## what was selected, a faint line runs on to it: the ring is where this animal's
## mouth gets to, and the far end of that line is what it was pointed at.
func _draw_reticle() -> void:
	var pick: Reticle.Pick = creature.aim
	if pick == null:
		return
	var reachable: bool = creature.can_reach_aim()
	var tint := Color(INK, 0.75 if reachable else 0.30)
	var scale: float = 1.0 / camera.zoom.x
	var selected: Reticle.Pick = pick.selected()
	if selected != pick:
		draw_dashed_line(pick.drawn, selected.drawn, Color(INK, 0.20),
			scale, 5.0 * scale, true)
	_draw_target_shape(selected, scale)
	if pick.drawn.distance_squared_to(pick.at) > 1.0:
		draw_line(pick.at, pick.drawn, Color(INK, 0.18), scale, true)
		draw_line(pick.at + Vector2(-4.0, 0.0) * scale, pick.at + Vector2(4.0, 0.0) * scale,
			Color(INK, 0.18), scale, true)
	if reachable:
		draw_circle(pick.drawn, 3.0 * scale, tint)
	draw_arc(pick.drawn, 7.0 * scale, 0.0, TAU, 20, tint, scale, true)


## The outline of whatever is targeted, traced over the thing itself.
##
## Off the same primitives the hit test scored and the view drew, so what is
## highlighted is exactly what a bite would name: the bone between two joints,
## the circle of the head, the width of the body at the station picked. Anything
## that had to reconstruct its own idea of where a leg is would eventually
## disagree with the one that decides the damage, and the highlight would start
## lying at precisely the moments it matters.
func _draw_target_shape(pick: Reticle.Pick, scale: float) -> void:
	var mark := Color(INK, 0.34)
	if pick.obstacle != null:
		draw_arc(pick.obstacle.drawn(pick.height), pick.obstacle.girth(),
			0.0, TAU, 28, mark, scale, true)
		return
	var target := pick.creature as Creature
	if target == null or pick.hit == null or target.body == null:
		return
	match pick.hit.kind:
		AnatomyState.HEAD:
			draw_arc(target.body.head.pos, target.body.head_radius + 2.0 * scale,
				0.0, TAU, 24, mark, scale, true)
		AnatomyState.LIMB:
			var limb: Limb = target._limb_by_key(pick.hit.limb_key)
			if limb == null:
				return
			if pick.hit.limb_segment >= 2:
				draw_arc(limb.joints[2], limb.foot_radius(target.size_scale) + 2.0 * scale,
					0.0, TAU, 18, mark, scale, true)
			else:
				# The drawn chain rather than the plan one: this is the leg as the
				# player sees it, hanging below the body, and it is the thing that has
				# to be picked out from the three others crossing it.
				draw_line(limb.joints[pick.hit.limb_segment],
					limb.joints[pick.hit.limb_segment + 1], mark, 2.0 * scale, true)
		_:
			# The body's own width at the station picked, which is the span of flesh
			# one bite there would be taken out of.
			draw_line(target.body_point(Vector2(pick.hit.spine_t, -1.0)),
				target.body_point(Vector2(pick.hit.spine_t, 1.0)), mark, 2.0 * scale, true)
