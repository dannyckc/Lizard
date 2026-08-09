## Monochrome editorial HUD based on the Evolution Game UI Design handoff.
class_name EvolutionHUD
extends Control

signal species_selected(preset_name: String)

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
const EDGE := Color(0.078, 0.078, 0.059, 0.13)

## The two things this HUD can be looking at. The field is the animal in its
## habitat; the anatomy is the same animal opened up. They are views of one
## creature rather than two screens, so the switch is a tab and not a mode.
const VIEW_FIELD: String = "Field"
const VIEW_ANATOMY: String = "Anatomy"
const VIEWS: Array[String] = [VIEW_FIELD, VIEW_ANATOMY]

var params: CreatureParams
var panel: TuningPanel
var anatomy: AnatomyPanel

var _sans_base: SystemFont
var _mono_base: Font
var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _stats: Dictionary = {}
var _species_buttons: Dictionary = {}
var _view_buttons: Dictionary = {}
var _active_species: String = "Lizard"
var _active_view: String = VIEW_FIELD
var _panel_open: bool = true
var _hint_target: float = 1.0

var _biomass_value: Label
var _food_value: Label
var _stage_value: Label
var _biomass_meter: BiomassMeter
var _move_hint: Label
var _tuning_button: Button
var _stats_grid: GridContainer
var _species_tabs: HBoxContainer
var _field_block: Control
var _anatomy_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_fonts()
	_build_frame()
	_build_identity_and_stats()
	_build_species_tabs()
	_build_biomass_and_legend()
	_build_tuning_panel()
	_build_tuning_button()
	_build_move_hint()
	_build_anatomy()
	_set_active_species(_active_species)
	set_view(_active_view)
	resized.connect(_fit_anatomy)
	_fit_anatomy()


func _process(delta: float) -> void:
	if anatomy != null and anatomy.visible:
		anatomy.refresh()
	if _move_hint == null:
		return
	_move_hint.modulate.a = lerpf(
		_move_hint.modulate.a,
		_hint_target,
		1.0 - exp(-3.0 * delta)
	)


## `integrity` is the fraction of the creature's own tissue it still has, 1.0
## intact. It reads out where the growth multiplier used to, because growth is
## gone for now and biomass you are losing is the live number this prototype
## actually has.
func update_metrics(
	state_name: String,
	speed: int,
	airborne: int,
	food: int,
	integrity: float,
	segments: int,
	mass: float = 1.0,
	height: float = 0.0
) -> void:
	if _stats.is_empty():
		return
	_stats["STATE"].text = state_name.to_upper()
	_stats["SPEED"].text = "%03d PX/S" % speed
	# How far off the ground plane the whole animal is. Reads zero for anything
	# standing on it, which is most of what is ever on screen — it is here for the
	# moments it is not.
	_stats["HEIGHT"].text = "%03d PX" % int(round(height))
	# Mass is derived, not set, so it belongs on the readout beside speed rather
	# than on a slider in the drawer — it is the number the silhouette, the
	# density and every bite taken out of the creature add up to.
	_stats["MASS"].text = "%.2f" % mass
	_stats["FEET"].text = "%d/4 UP" % airborne
	_stats["SEGMENTS"].text = str(segments)
	_biomass_value.text = "%03d%%" % int(round(clampf(integrity, 0.0, 1.0) * 100.0))
	_food_value.text = "FOOD %03d" % food
	_stage_value.text = "STAGE %02d" % (int(floor(float(food) / 12.0)) + 1)
	_biomass_meter.progress = float(food % 12) / 12.0
	if speed > 5:
		_hint_target = 0.0


func toggle_panel() -> void:
	set_panel_open(not _panel_open)


func set_panel_open(open: bool) -> void:
	_panel_open = open
	if panel == null:
		return
	panel.visible = open and _active_view == VIEW_FIELD
	_update_tuning_button()


## Which view the HUD is on. The field's own furniture stands down while the
## specimen is out, because the anatomy drawer occupies the same right-hand
## column the species tabs and the tuning drawer do — and because a dissection
## should have the page to itself.
func set_view(view_name: String) -> void:
	if not VIEWS.has(view_name):
		return
	_active_view = view_name
	var field: bool = view_name == VIEW_FIELD
	if _stats_grid != null:
		_stats_grid.visible = field
	if _species_tabs != null:
		_species_tabs.visible = field
	if _field_block != null:
		_field_block.visible = field
	if _tuning_button != null:
		_tuning_button.visible = field
	if _move_hint != null:
		_move_hint.visible = field
	if _anatomy_note != null:
		_anatomy_note.visible = not field
	if anatomy != null:
		anatomy.visible = not field
		if not field:
			anatomy.refresh()
	if panel != null:
		panel.visible = _panel_open and field
	_update_tuning_button()
	for name in _view_buttons:
		var button: Button = _view_buttons[name]
		var selected: bool = str(name) == view_name
		button.text = ("•  " if selected else "   ") + str(name).to_upper()
		button.add_theme_color_override("font_color", INK if selected else Color(INK, 0.42))
		button.add_theme_color_override("font_hover_color", INK if selected else Color(INK, 0.72))
		button.add_theme_stylebox_override("normal", _tab_style(selected))


func toggle_view() -> void:
	set_view(VIEW_FIELD if _active_view == VIEW_ANATOMY else VIEW_ANATOMY)


func active_view() -> String:
	return _active_view


## The creatures the anatomy tab can be pointed at. Named by the world, because
## which body is whose is the world's business and not the HUD's.
func set_specimens(list: Array) -> void:
	if anatomy != null:
		anatomy.set_specimens(list)


func _fit_anatomy() -> void:
	if anatomy != null:
		anatomy.fit_to_height(size.y - 96.0)


func reset_hint() -> void:
	_hint_target = 1.0
	if _move_hint != null:
		_move_hint.modulate.a = 1.0


func select_species(preset_name: String) -> void:
	if not CreatureParams.PRESETS.has(preset_name):
		return
	_on_species_pressed(preset_name)


func _build_fonts() -> void:
	_sans_base = SystemFont.new()
	_sans_base.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
	_sans_base.font_weight = 500

	_mono_base = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if _mono_base == null:
		var mono_fallback := SystemFont.new()
		mono_fallback.font_names = PackedStringArray(["IBM Plex Mono", "SF Mono", "Menlo", "PT Mono", "monospace"])
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

	var title := _label("EVOLUTION", 11, _sans_tracked, INK)
	identity.add_child(title)

	var rule_wrap := CenterContainer.new()
	rule_wrap.custom_minimum_size = Vector2(22.0, 7.0)
	rule_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.22)
	rule.custom_minimum_size = Vector2(22.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_wrap.add_child(rule)
	identity.add_child(rule_wrap)

	var proto := _label("PROTO  0.1", 10, _mono_tracked, Color(INK, 0.42))
	identity.add_child(proto)

	var views := HBoxContainer.new()
	views.name = "ViewTabs"
	views.add_theme_constant_override("separation", 4)
	block.add_child(views)
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

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 22)
	_stats_grid.add_theme_constant_override("v_separation", 4)
	_stats_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_stats_grid)
	for key in ["STATE", "SPEED", "MASS", "HEIGHT", "FEET", "SEGMENTS"]:
		var key_label := _label(key, 10, _mono_tracked, Color(INK, 0.40))
		key_label.custom_minimum_size.x = 74.0
		_stats_grid.add_child(key_label)
		var value := _label("—", 10, _mono_tracked, INK)
		_stats[key] = value
		_stats_grid.add_child(value)


func _build_species_tabs() -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "SpeciesTabs"
	tabs.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tabs.offset_left = -520.0
	tabs.offset_top = 30.0
	tabs.offset_right = -32.0
	tabs.offset_bottom = 65.0
	tabs.alignment = BoxContainer.ALIGNMENT_END
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	_species_tabs = tabs

	for preset_name in CreatureParams.PRESETS:
		var name := str(preset_name)
		var button := Button.new()
		button.text = "   " + name.to_upper()
		button.flat = true
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(82.0, 32.0)
		button.add_theme_font_override("font", _sans_tracked)
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_stylebox_override("normal", _tab_style(false))
		button.add_theme_stylebox_override("hover", _tab_style(false, 0.28))
		button.add_theme_stylebox_override("pressed", _tab_style(true))
		button.add_theme_stylebox_override("focus", _tab_style(false, 0.28))
		button.pressed.connect(_on_species_pressed.bind(name))
		tabs.add_child(button)
		_species_buttons[name] = button


func _build_biomass_and_legend() -> void:
	var block := Control.new()
	block.name = "BiomassAndControls"
	block.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	block.offset_left = 32.0
	block.offset_top = -132.0
	block.offset_right = 620.0
	block.offset_bottom = -30.0
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)
	_field_block = block

	var biomass := VBoxContainer.new()
	biomass.custom_minimum_size.x = 300.0
	biomass.position = Vector2.ZERO
	biomass.size = Vector2(300.0, 55.0)
	biomass.add_theme_constant_override("separation", 6)
	biomass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(biomass)

	var biomass_header := HBoxContainer.new()
	biomass_header.custom_minimum_size.x = 300.0
	biomass_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	biomass.add_child(biomass_header)
	biomass_header.add_child(_label("BIOMASS", 10, _mono_tracked, Color(INK, 0.40)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	biomass_header.add_child(spacer)
	_biomass_value = _label("100%", 10, _mono_tracked, INK)
	biomass_header.add_child(_biomass_value)

	_biomass_meter = BiomassMeter.new()
	_biomass_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biomass.add_child(_biomass_meter)

	var biomass_footer := HBoxContainer.new()
	biomass_footer.custom_minimum_size.x = 300.0
	biomass_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	biomass.add_child(biomass_footer)
	_food_value = _label("FOOD 000", 10, _mono_tracked, Color(INK, 0.40))
	biomass_footer.add_child(_food_value)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	biomass_footer.add_child(footer_spacer)
	_stage_value = _label("STAGE 01", 10, _mono_tracked, Color(INK, 0.40))
	biomass_footer.add_child(_stage_value)

	var legend := HBoxContainer.new()
	legend.position = Vector2(0.0, 78.0)
	legend.add_theme_constant_override("separation", 22)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(legend)
	legend.add_child(_legend_item(["W", "A", "S", "D"], "MOVE"))
	legend.add_child(_legend_item(["LMB"], "BITE / LATCH"))
	legend.add_child(_legend_item(["⇧"], "SPRINT"))
	legend.add_child(_legend_item(["F1"], "TUNING"))
	legend.add_child(_legend_item(["F2"], "DEBUG"))
	legend.add_child(_legend_item(["F3"], "ANATOMY"))
	legend.add_child(_legend_item(["R"], "RESET"))


func _legend_item(keys: Array[String], caption: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_group := HBoxContainer.new()
	key_group.add_theme_constant_override("separation", 3)
	key_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key_group)
	for key in keys:
		var keycap := Label.new()
		keycap.text = key
		keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keycap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		keycap.custom_minimum_size = Vector2(19.0 if key.length() == 1 else 31.0, 19.0)
		keycap.add_theme_font_override("font", _mono)
		keycap.add_theme_font_size_override("font_size", 9)
		keycap.add_theme_color_override("font_color", INK)
		keycap.add_theme_stylebox_override("normal", _keycap_style())
		keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_group.add_child(keycap)
	row.add_child(_label(caption, 10, _sans_tracked, Color(INK, 0.48)))
	return row


func _build_tuning_panel() -> void:
	panel = TuningPanel.new()
	panel.params = params
	panel.set_ui_fonts(_sans, _sans_tracked, _mono, _mono_tracked)
	panel.preset_applied.connect(_on_panel_reset)
	add_child(panel)


func _build_tuning_button() -> void:
	_tuning_button = Button.new()
	_tuning_button.name = "TuningToggle"
	_tuning_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_tuning_button.offset_left = -150.0
	_tuning_button.offset_top = -66.0
	_tuning_button.offset_right = -32.0
	_tuning_button.offset_bottom = -30.0
	_tuning_button.add_theme_font_override("font", _sans_tracked)
	_tuning_button.add_theme_font_size_override("font_size", 10)
	_tuning_button.add_theme_color_override("font_color", INK)
	_tuning_button.add_theme_color_override("font_hover_color", INK)
	_tuning_button.add_theme_stylebox_override("normal", _button_style(0.13))
	_tuning_button.add_theme_stylebox_override("hover", _button_style(0.30))
	_tuning_button.add_theme_stylebox_override("pressed", _button_style(0.45))
	_tuning_button.add_theme_stylebox_override("focus", _button_style(0.30))
	_tuning_button.pressed.connect(toggle_panel)
	add_child(_tuning_button)
	_update_tuning_button()


func _build_anatomy() -> void:
	anatomy = AnatomyPanel.new()
	anatomy.set_ui_fonts(_sans, _sans_tracked, _mono, _mono_tracked)
	add_child(anatomy)

	# The one caption the anatomy view needs, in the field's own footnote voice:
	# it names the two rules the whole picture is drawn by, so the layer list and
	# the two networks read as a description of a body rather than as legend keys.
	_anatomy_note = _label(
		"DEPTH STACK · SKIN OVER FAT OVER MUSCLE OVER BONE OVER ORGAN.\n"
		+ "NERVES RUN THE CORD INSIDE THE VERTEBRAE; VESSELS RUN BESIDE THEM.",
		9, _mono_tracked, Color(INK, 0.30))
	_anatomy_note.name = "AnatomyNote"
	_anatomy_note.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_anatomy_note.offset_left = 32.0
	_anatomy_note.offset_top = -48.0
	_anatomy_note.offset_right = 452.0
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


func _on_species_pressed(preset_name: String) -> void:
	_active_species = preset_name
	if params != null:
		params.apply_preset(preset_name)
	if panel != null:
		panel.set_current_preset(preset_name)
		panel.refresh()
	_set_active_species(preset_name)
	species_selected.emit(preset_name)


func _on_panel_reset(preset_name: String) -> void:
	_active_species = preset_name
	_set_active_species(preset_name)
	species_selected.emit(preset_name)


func _set_active_species(preset_name: String) -> void:
	_active_species = preset_name
	for name in _species_buttons:
		var button: Button = _species_buttons[name]
		var selected: bool = str(name) == preset_name
		button.text = ("•  " if selected else "   ") + str(name).to_upper()
		button.add_theme_color_override("font_color", INK if selected else Color(INK, 0.38))
		button.add_theme_color_override("font_hover_color", INK if selected else Color(INK, 0.72))
		button.add_theme_stylebox_override("normal", _tab_style(selected))
	if panel != null:
		panel.set_current_preset(preset_name)


func _update_tuning_button() -> void:
	if _tuning_button == null:
		return
	_tuning_button.text = ("•" if _panel_open else "·") + "  TUNING   F1"
	_tuning_button.add_theme_color_override("font_color", INK if _panel_open else Color(INK, 0.58))


func _label(text: String, size_px: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _ink_mark(mark_size: float, round: bool) -> Panel:
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(mark_size, mark_size)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	if round:
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


func _button_style(border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER, 0.84)
	style.border_color = Color(INK, border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(INK, 0.08)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	return style
