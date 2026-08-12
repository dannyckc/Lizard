## The lab's HUD: EvolutionHUD's shell, standing over the v2 creature.
##
## The chrome is v1's and deliberately unchanged — the identity block, the stats
## grid, the two dot tracks, the keycap legend, the view tabs top right and the
## right-hand dock the drawers open into are all the same furniture in the same
## places (docs/V2_DESIGN.md §8: "the HUD shell survives untouched"). What is new
## is only who it is reading. v1's HUD was handed its numbers by Main because the
## words came out of half a dozen subsystems Main was already holding; the v2 body
## answers for itself, so this asks it.
##
## Two views of one creature rather than two screens, so the switch is a tab and
## not a mode: the field is the animal in its habitat, and the anatomy is the same
## animal opened up. The anatomy opens a drawer in the dock, and the field pays for
## whatever is open in one place — `field_shift`, which the lab's camera reads and
## eases onto.
##
## What is not here is anything v1's HUD had that the v2 body cannot yet answer
## for. There is no creation menu (the authoring layer is a resource for now), no
## stamina track (blood and the aerobic engine arrive with Phase 5), and no gait
## view — the movers were taken out to be rewritten, so there is no walk to
## measure. All three were left out rather than mocked: a HUD that prints a number
## nothing measures is the one thing worse than a HUD that does not print it.
class_name LabHUD
extends Control

const PAPER := Color("f3f1ec")
const INK := Color("14140f")

const VIEW_FIELD: String = "Field"
const VIEW_ANATOMY: String = "Anatomy"
const VIEWS: Array[String] = [VIEW_FIELD, VIEW_ANATOMY]

## The keys the lab actually answers to — see V2Lab, which is where they are
## pumped. Two rows rather than v1's one, because the lab has the handling a probe
## cannot and every one of those is a key.
const LEGEND: Array[Array] = [
	[[["W", "A", "S", "D"], "MOVE"], [["⇧"], "SPRINT"], [["SPACE"], "JUMP"],
		[["LMB"], "DRAG NODE"]],
	[[["F3"], "ANATOMY"], [["V"], "SKELETON"], [["K"], "COLLAPSE"],
		[["F"], "DROP"], [["R"], "RESET"]],
]

var subject: Creature2
var anatomy: SpecimenDrawer

var _sans_base: SystemFont
var _mono_base: Font
var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _stats: Dictionary = {}
var _view_buttons: Dictionary = {}
## Every drawer that opens in the right-hand dock, in the order they were built.
## They are held as one list rather than named one at a time, because everything
## the HUD does with a drawer — size it to the window, ask what it costs the field
## — is the same for all of them and has to stay that way for the next one.
var _drawers: Array[Control] = []
var _active_view: String = VIEW_FIELD
var _hint_target: float = 1.0

var _health_value: Label
var _footing_value: Label
var _health_meter: PipMeter
var _footing_meter: PipMeter
var _census_value: Label
var _facet_value: Label
var _move_hint: Label
var _stats_grid: GridContainer
var _field_block: Control
var _anatomy_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_fonts()
	_build_frame()
	_build_identity_and_stats()
	_build_view_tabs()
	_build_condition_and_legend()
	_build_move_hint()
	_build_anatomy()
	set_view(_active_view)
	resized.connect(_fit_drawers)
	_fit_drawers()


func _process(delta: float) -> void:
	_read_subject()
	if anatomy != null and anatomy.visible:
		anatomy.refresh()
	if _move_hint == null:
		return
	_move_hint.modulate.a = lerpf(
		_move_hint.modulate.a, _hint_target, 1.0 - exp(-3.0 * delta))


## Whose creature this is. The drawers read the same animal, so a body swapped in
## the lab is swapped everywhere at once.
##
## The drawers are re-fitted afterwards, and that is not housekeeping: a drawer's
## fixed chrome depends on the animal — the anatomy drawer offers a chip per chain
## of the census — so how much height is left for the specimen cannot be worked out
## before the body is known.
func set_subject(each: Creature2) -> void:
	subject = each
	if anatomy != null:
		anatomy.set_subject(each)
	_fit_drawers()


## Which view the HUD is on. The field's own furniture stands down while the
## specimen is out, because the anatomy drawer occupies the same right-hand column
## the rest of the chrome does — and because a dissection should have the page to
## itself.
func set_view(view_name: String) -> void:
	if not VIEWS.has(view_name):
		return
	_active_view = view_name
	_apply_chrome()
	for name in _view_buttons:
		var button: Button = _view_buttons[name]
		var selected: bool = str(name) == view_name
		button.text = ("•  " if selected else "   ") + str(name).to_upper()
		button.add_theme_color_override("font_color", INK if selected else Color(INK, 0.42))
		button.add_theme_color_override("font_hover_color", INK if selected else Color(INK, 0.72))
		button.add_theme_stylebox_override("normal", _tab_style(selected))


## Steps to the next view, round the loop: field, anatomy, field.
func toggle_view() -> void:
	set_view(VIEWS[(VIEWS.find(_active_view) + 1) % VIEWS.size()])


func active_view() -> String:
	return _active_view


## How far the field's own picture stands off the middle of the window, in screen
## pixels, while a drawer is open: half the column that drawer has taken, so the
## animal ends up in the middle of the paper left to its left. Zero with nothing
## open. The lab reads this and eases the camera onto it — see
## V2Lab._camera_focus; nothing here moves a camera.
func field_shift() -> float:
	for drawer in _drawers:
		if drawer.visible:
			return HudDock.reserved(drawer.dock_width()) * 0.5
	return 0.0


func reset_hint() -> void:
	_hint_target = 1.0
	if _move_hint != null:
		_move_hint.modulate.a = 1.0


## What is on screen, decided in one place from the one thing that decides it:
## which view is up.
func _apply_chrome() -> void:
	var field: bool = _active_view == VIEW_FIELD
	if _stats_grid != null:
		_stats_grid.visible = field
	if _field_block != null:
		_field_block.visible = field
	if _move_hint != null:
		_move_hint.visible = field
	if _anatomy_note != null:
		_anatomy_note.visible = _active_view == VIEW_ANATOMY
	if anatomy != null:
		anatomy.visible = _active_view == VIEW_ANATOMY
		if anatomy.visible:
			anatomy.refresh()


## Every drawer is sized to the window rather than to a fixed rect: they all stand
## in the same dock and are all as tall as it, and what each does with that height
## is its own business — the anatomy drawer spends it on the specimen, and has its
## own thing to give up when the window is short.
func _fit_drawers() -> void:
	var tall: float = HudDock.height(size.y)
	for drawer in _drawers:
		drawer.fit_to_height(tall)


# ------------------------------------------------------------- the readings ----

## What the animal is doing, in one word, off its own state and nothing else.
##
## The order is a precedence and each step of it outranks the one under it for the
## same reason: what the body is doing is the most committing thing it is doing. A
## leap outranks the walk it took off from; a body that has been put down outranks
## everything.
func _state_word() -> String:
	if subject.armature.collapsed:
		return "collapsed"
	if subject.armature.fall.is_airborne():
		return "airborne"
	if subject.speed_norm > 0.05:
		if subject.command.sprint and subject.speed_norm > 0.7:
			return "running"
		return "walking"
	if absf(subject.ang_vel) > 0.6:
		return "turning"
	return "idle"


func _read_subject() -> void:
	if _stats.is_empty() or subject == null or subject.corpus == null \
			or subject.corpus.columns == 0:
		return
	var a: Armature = subject.armature
	_stats["STATE"].text = _state_word().to_upper()
	_stats["SPEED"].text = "%03d PX/S" % int(absf(subject.speed))
	# Mass is derived, not set, so it belongs on the readout beside speed rather
	# than on a slider — it is the number the silhouette, the tissue knots and
	# every bite taken out of the creature add up to.
	_stats["MASS"].text = "%.0f" % subject.corpus.mass()
	# How far off the ground the whole animal is. Reads zero for anything standing
	# on it, which is most of what is ever on screen — it is here for the moments
	# it is not.
	_stats["HEIGHT"].text = "%03d PX" % int(round(
		maxf(a.fall.height - a.fall.floor_height, 0.0)))
	# How many toes are on the ground. Poise's own plant test rather than a count
	# kept by a gait, so it stays a measurement of the body while there is no gait
	# to ask — and it is the same count the support hull below is built from.
	_stats["FEET"].text = "%d/%d DOWN" % [subject.poise.feet, a.limbs.size()]
	_stats["NODES"].text = "%d / %d" % [a.node_count(), a.stick_count()]
	_stats["STANCE"].text = subject.attitude.describe().to_upper()

	var health: float = subject.corpus.integrity()
	# Footing without a balance system to ask: how far inside its own support the
	# plumb line is sitting, against the margin a stance is expected to keep
	# (`Poise.KEEP`). Full is a body squarely over its feet, zero is one out past
	# them — the same fact the balance system reduced to a hold, one step earlier.
	var hold: float = 0.0
	if subject.poise.posed and subject.poise.feet > 0:
		hold = clampf(subject.poise.clearance
			/ maxf(subject.poise.span * Poise.KEEP, 0.001), 0.0, 1.0)
	_health_value.text = "%03d%%" % int(round(health * 100.0))
	_footing_value.text = "%03d%%" % int(round(hold * 100.0))
	_health_meter.progress = health
	_footing_meter.progress = hold
	_census_value.text = "CELLS %d" % (subject.corpus.columns * 4)
	_facet_value.text = "FACETS %d" % subject.contour.facet_count()
	if absf(subject.speed) > 5.0:
		_hint_target = 0.0


# ------------------------------------------------------------------ the parts ----

func _build_fonts() -> void:
	_sans_base = SystemFont.new()
	_sans_base.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
	_sans_base.font_weight = 500

	_mono_base = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if _mono_base == null:
		var mono_fallback := SystemFont.new()
		mono_fallback.font_names = PackedStringArray(
			["IBM Plex Mono", "SF Mono", "Menlo", "PT Mono", "monospace"])
		mono_fallback.font_weight = 400
		_mono_base = mono_fallback

	_sans = _font_variant(_sans_base, 0)
	_sans_tracked = _font_variant(_sans_base, 2)
	_mono = _font_variant(_mono_base, 0)
	_mono_tracked = _font_variant(_mono_base, 1)


func _font_variant(base: Font, glyph_spacing: int) -> Font:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.set_spacing(TextServer.SPACING_GLYPH, glyph_spacing)
	return variation


func _build_frame() -> void:
	var frame := Panel.new()
	frame.name = "InsetFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 14.0
	frame.offset_top = 14.0
	frame.offset_right = -14.0
	frame.offset_bottom = -14.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, 0.10)
	style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)


func _build_identity_and_stats() -> void:
	var block := VBoxContainer.new()
	block.name = "IdentityAndStats"
	block.position = Vector2(32.0, 30.0)
	block.add_theme_constant_override("separation", 16)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 11)
	identity.alignment = BoxContainer.ALIGNMENT_BEGIN
	block.add_child(identity)

	var dot_wrap := CenterContainer.new()
	dot_wrap.custom_minimum_size = Vector2(7.0, 7.0)
	dot_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_wrap.add_child(_ink_mark(7.0, true))
	identity.add_child(dot_wrap)

	identity.add_child(_label("EVOLUTION", 11, _sans_tracked, INK))

	var rule_wrap := CenterContainer.new()
	rule_wrap.custom_minimum_size = Vector2(22.0, 7.0)
	rule_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.22)
	rule.custom_minimum_size = Vector2(22.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_wrap.add_child(rule)
	identity.add_child(rule_wrap)

	identity.add_child(_label("V2  LAB", 10, _mono_tracked, Color(INK, 0.42)))

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 22)
	_stats_grid.add_theme_constant_override("v_separation", 4)
	_stats_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_stats_grid)
	for key in ["STATE", "SPEED", "MASS", "HEIGHT", "FEET", "NODES", "STANCE"]:
		var key_label := _label(key, 10, _mono_tracked, Color(INK, 0.40))
		key_label.custom_minimum_size.x = 74.0
		_stats_grid.add_child(key_label)
		var value := _label("—", 10, _mono_tracked, INK)
		_stats[key] = value
		_stats_grid.add_child(value)


## The three views, in the top right corner — directly over the dock that two of
## them open a drawer into, because a tab and the thing it opens belong on the
## same edge of the page. The row hangs off the right margin rather than being
## laid across it, so it keeps its own width whatever the window is doing and the
## drawers under it line up with its outer end.
func _build_view_tabs() -> void:
	var views := HBoxContainer.new()
	views.name = "ViewTabs"
	views.add_theme_constant_override("separation", 4)
	views.alignment = BoxContainer.ALIGNMENT_END
	views.anchor_left = 1.0
	views.anchor_right = 1.0
	views.anchor_top = 0.0
	views.anchor_bottom = 0.0
	views.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	views.grow_vertical = Control.GROW_DIRECTION_END
	views.offset_left = 0.0
	views.offset_right = -HudDock.INSET
	views.offset_top = 30.0
	views.offset_bottom = 58.0
	add_child(views)
	for view_name in VIEWS:
		var button := Button.new()
		button.text = "   " + view_name.to_upper()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 28.0)
		button.add_theme_font_override("font", _sans_tracked)
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_stylebox_override("hover", _tab_style(false, 0.28))
		button.add_theme_stylebox_override("pressed", _tab_style(true))
		button.pressed.connect(set_view.bind(view_name))
		views.add_child(button)
		_view_buttons[view_name] = button


## The corner that says what state the animal is in: how much of it is left, and
## how much of its own standing its legs are still answering for.
##
## Two tracks rather than one, because they are two different questions and they
## come apart — an intact animal whose legs have stopped holding it is about to go
## down, and a badly chewed one still standing squarely is not. They are drawn
## identically, in the same dots, one above the other, because the design already
## had a shape for a proportion in this corner and a second reading does not need
## a second one.
func _build_condition_and_legend() -> void:
	var block := Control.new()
	block.name = "ConditionAndControls"
	block.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	block.offset_left = 32.0
	block.offset_top = -184.0
	block.offset_right = 700.0
	block.offset_bottom = -30.0
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)
	_field_block = block

	var condition := VBoxContainer.new()
	condition.custom_minimum_size.x = 300.0
	condition.position = Vector2.ZERO
	condition.size = Vector2(300.0, 90.0)
	condition.add_theme_constant_override("separation", 6)
	condition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(condition)

	_health_value = _label("100%", 10, _mono_tracked, INK)
	condition.add_child(_reading_header("HEALTH", _health_value))
	_health_meter = PipMeter.new()
	_health_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition.add_child(_health_meter)

	# A caption sits over its own track rather than between two of them: with one
	# separation for the whole column the second title would be equidistant from
	# the bar above it and the bar below, and a reader would have to guess which
	# length it named.
	var split := Control.new()
	split.custom_minimum_size.y = 5.0
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	condition.add_child(split)

	_footing_value = _label("100%", 10, _mono_tracked, INK)
	condition.add_child(_reading_header("FOOTING", _footing_value))
	_footing_meter = PipMeter.new()
	_footing_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition.add_child(_footing_meter)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.x = 300.0
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	condition.add_child(footer)
	_census_value = _label("CELLS 0000", 10, _mono_tracked, Color(INK, 0.40))
	footer.add_child(_census_value)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(footer_spacer)
	_facet_value = _label("FACETS 000", 10, _mono_tracked, Color(INK, 0.40))
	footer.add_child(_facet_value)

	var y: float = 108.0
	for row in LEGEND:
		var legend := HBoxContainer.new()
		legend.position = Vector2(0.0, y)
		legend.add_theme_constant_override("separation", 22)
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(legend)
		for item in row:
			legend.add_child(_legend_item(item[0] as Array, str(item[1])))
		y += 25.0


## A caption on the left and its reading on the right, over the track it belongs
## to. Both bars are titled the same way, so the pair reads as one column.
func _reading_header(caption: String, value: Label) -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size.x = 300.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_label(caption, 10, _mono_tracked, Color(INK, 0.40)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	header.add_child(value)
	return header


func _legend_item(keys: Array, caption: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_group := HBoxContainer.new()
	key_group.add_theme_constant_override("separation", 3)
	key_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key_group)
	for key in keys:
		var keycap := Label.new()
		keycap.text = str(key)
		keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keycap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var letters: int = str(key).length()
		keycap.custom_minimum_size = Vector2(
			19.0 if letters == 1 else (31.0 if letters <= 3 else 44.0), 19.0)
		keycap.add_theme_font_override("font", _mono)
		keycap.add_theme_font_size_override("font_size", 9)
		keycap.add_theme_color_override("font_color", INK)
		keycap.add_theme_stylebox_override("normal", _keycap_style())
		keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_group.add_child(keycap)
	row.add_child(_label(caption, 10, _sans_tracked, Color(INK, 0.48)))
	return row


func _build_anatomy() -> void:
	anatomy = SpecimenDrawer.new()
	anatomy.set_ui_fonts(_sans, _sans_tracked, _mono, _mono_tracked)
	anatomy.set_subject(subject)
	add_child(anatomy)
	_drawers.append(anatomy)

	# The one caption the anatomy view needs, in the field's own footnote voice:
	# it names the two rules the whole picture is drawn by, so the layer list and
	# the two networks read as a description of a body rather than as legend keys.
	_anatomy_note = _label(
		"DEPTH STACK · SKIN OVER FAT OVER MUSCLE OVER BONE, PEELED OUTSIDE-IN.\n"
		+ "ORGANS, VESSELS AND NERVES ARE BODY COORDINATES, NOT CELLS — THEY MOVE WITH THE FLESH.",
		9, _mono_tracked, Color(INK, 0.30))
	_anatomy_note.name = "AnatomyNote"
	_anatomy_note.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_anatomy_note.offset_left = 32.0
	_anatomy_note.offset_top = -48.0
	_anatomy_note.offset_right = 620.0
	_anatomy_note.offset_bottom = -30.0
	_anatomy_note.add_theme_constant_override("line_spacing", 6)
	add_child(_anatomy_note)


func _build_move_hint() -> void:
	_move_hint = _label("MOVE TO BEGIN", 10, _sans_tracked, Color(INK, 0.34))
	_move_hint.name = "MoveHint"
	_move_hint.set_anchors_preset(Control.PRESET_CENTER)
	_move_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_move_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	_move_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_move_hint.custom_minimum_size = Vector2(180.0, 28.0)
	_move_hint.position -= _move_hint.custom_minimum_size * 0.5
	add_child(_move_hint)


func _label(text: String, size_px: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _ink_mark(mark_size: float, round_off: bool) -> Panel:
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(mark_size, mark_size)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	if round_off:
		style.set_corner_radius_all(int(ceil(mark_size * 0.5)))
	mark.add_theme_stylebox_override("panel", style)
	return mark


func _tab_style(selected: bool, hover_alpha: float = 0.12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = INK if selected else Color(INK, hover_alpha)
	style.border_width_bottom = 1
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	return style


func _keycap_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	return style
