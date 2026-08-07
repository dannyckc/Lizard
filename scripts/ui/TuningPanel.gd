## Runtime parameter drawer generated from CreatureParams.SCHEMA.
## Its controls are deliberately quiet so the simulation remains the focal
## point: hairline rules, tiny ink handles and a compact editorial type scale.
class_name TuningPanel
extends PanelContainer

signal preset_applied(preset_name: String)

const PAPER := Color("f3f1ec")
const INK := Color("14140f")

var params: CreatureParams

var _sliders: Dictionary = {}      ## property name -> MinimalSlider
var _value_labels: Dictionary = {} ## property name -> Label
var _checks: Dictionary = {}       ## property name -> InkToggle
var _updating: bool = false
var _current_preset: String = "Lizard"

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font
var _species_label: Label


func set_ui_fonts(sans: Font, sans_tracked: Font, mono: Font, mono_tracked: Font) -> void:
	_sans = sans
	_sans_tracked = sans_tracked
	_mono = mono
	_mono_tracked = mono_tracked


func _ready() -> void:
	_ensure_fonts()
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_bottom = 1.0
	offset_left = -368.0
	offset_right = -32.0
	offset_top = 76.0
	offset_bottom = -82.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER, 0.91)
	style.border_color = Color(INK, 0.13)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(INK, 0.12)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 10.0)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.name = "ParameterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_theme_stylebox_override("panel", _empty_style())
	root.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	margin.add_child(list)

	for row in CreatureParams.SCHEMA:
		if row.has("group"):
			list.add_child(_build_group_header(str(row["group"])))
		elif row.get("bool", false):
			list.add_child(_build_check_row(row))
		else:
			list.add_child(_build_slider_row(row))

	root.add_child(_build_footer())
	_style_scrollbar(scroll.get_v_scroll_bar())
	refresh()


func _build_header() -> Control:
	var margin := MarginContainer.new()
	margin.custom_minimum_size.y = 49.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_theme_stylebox_override("panel", _rule_style(SIDE_BOTTOM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var dot_wrap := CenterContainer.new()
	dot_wrap.custom_minimum_size = Vector2(5.0, 5.0)
	dot_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(5.0, 5.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = INK
	dot.add_theme_stylebox_override("panel", dot_style)
	dot_wrap.add_child(dot)
	row.add_child(dot_wrap)
	var title := _make_label("TUNING", 10, _sans_tracked, INK)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_species_label = _make_label(_current_preset.to_upper(), 9, _mono_tracked, Color(INK, 0.38))
	row.add_child(_species_label)
	return margin


func _build_footer() -> Control:
	var margin := MarginContainer.new()
	margin.custom_minimum_size.y = 43.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 9)
	margin.add_theme_stylebox_override("panel", _rule_style(SIDE_TOP))

	var row := HBoxContainer.new()
	margin.add_child(row)
	var count: int = 0
	for item in CreatureParams.SCHEMA:
		if item.has("prop"):
			count += 1
	row.add_child(_make_label("SCHEMA · %d ROWS" % count, 9, _mono_tracked, Color(INK, 0.34)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var reset := Button.new()
	reset.text = "RESET"
	reset.flat = true
	reset.add_theme_font_override("font", _mono_tracked)
	reset.add_theme_font_size_override("font_size", 9)
	reset.add_theme_color_override("font_color", Color(INK, 0.55))
	reset.add_theme_color_override("font_hover_color", INK)
	reset.add_theme_stylebox_override("normal", _reset_style(0.22))
	reset.add_theme_stylebox_override("hover", _reset_style(0.6))
	reset.add_theme_stylebox_override("pressed", _reset_style(1.0))
	reset.add_theme_stylebox_override("focus", _reset_style(0.6))
	reset.pressed.connect(_on_reset_pressed)
	row.add_child(reset)
	return margin


func _build_group_header(text: String) -> Control:
	var box := HBoxContainer.new()
	box.custom_minimum_size.y = 39.0
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_label(text.to_upper(), 9, _sans_tracked, Color(INK, 0.40))
	label.size_flags_vertical = Control.SIZE_SHRINK_END
	label.custom_minimum_size.y = 30.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	box.add_child(label)
	var rule_wrap := CenterContainer.new()
	rule_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
	rule_wrap.custom_minimum_size.y = 13.0
	rule_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.11)
	rule.custom_minimum_size = Vector2(1.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_wrap.add_child(rule)
	box.add_child(rule_wrap)
	return box


func _build_slider_row(row: Dictionary) -> Control:
	var prop: String = row["prop"]
	var box := HBoxContainer.new()
	box.custom_minimum_size.y = 26.0
	box.add_theme_constant_override("separation", 9)

	var name_label := _make_label(str(row["label"]), 11, _sans, Color(INK, 0.78))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	var slider := MinimalSlider.new()
	slider.min_value = float(row["min"])
	slider.max_value = float(row["max"])
	slider.step = float(row["step"])
	slider.custom_minimum_size = Vector2(76.0, 26.0)
	slider.value_changed.connect(_on_slider_changed.bind(prop))
	box.add_child(slider)

	var value_label := _make_label("", 10, _mono, Color(INK, 0.62))
	value_label.custom_minimum_size = Vector2(42.0, 26.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value_label)

	_sliders[prop] = slider
	_value_labels[prop] = value_label
	return box


func _build_check_row(row: Dictionary) -> Control:
	var prop: String = row["prop"]
	var box := HBoxContainer.new()
	box.custom_minimum_size.y = 26.0
	box.add_theme_constant_override("separation", 9)

	var name_label := _make_label(str(row["label"]), 11, _sans, Color(INK, 0.78))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)

	var check := InkToggle.new()
	check.toggled.connect(_on_check_toggled.bind(prop))
	box.add_child(check)

	var value_label := _make_label("ON", 10, _mono, Color(INK, 0.62))
	value_label.custom_minimum_size = Vector2(42.0, 26.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value_label)

	_checks[prop] = check
	_value_labels[prop] = value_label
	return box


func _on_slider_changed(value: float, prop: String) -> void:
	if _updating or params == null:
		return
	params.set(prop, value)
	_update_value_label(prop, value)


func _on_check_toggled(pressed: bool, prop: String) -> void:
	if _updating or params == null:
		return
	params.set(prop, pressed)
	var label: Label = _value_labels.get(prop)
	if label != null:
		label.text = "ON" if pressed else "OFF"


func _on_reset_pressed() -> void:
	if params == null:
		return
	params.apply_preset(_current_preset)
	refresh()
	preset_applied.emit(_current_preset)


func set_current_preset(preset_name: String) -> void:
	_current_preset = preset_name
	if _species_label != null:
		_species_label.text = preset_name.to_upper()


func _update_value_label(prop: String, value: float) -> void:
	var label: Label = _value_labels.get(prop)
	if label == null:
		return
	var slider: MinimalSlider = _sliders[prop]
	label.text = str(int(round(value))) if slider.step >= 1.0 else ("%.2f" % value)


## Push the live resource values back into each custom control.
func refresh() -> void:
	if params == null:
		return
	_updating = true
	for prop in _sliders:
		var value: float = float(params.get(prop))
		var slider: MinimalSlider = _sliders[prop]
		slider.set_value_silent(value)
		_update_value_label(prop, value)
	for prop in _checks:
		var pressed: bool = bool(params.get(prop))
		var check: InkToggle = _checks[prop]
		check.button_pressed = pressed
		var label: Label = _value_labels.get(prop)
		if label != null:
			label.text = "ON" if pressed else "OFF"
	_updating = false


func _ensure_fonts() -> void:
	if _sans != null:
		return
	var sans_base := SystemFont.new()
	sans_base.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
	var mono_base: Font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if mono_base == null:
		var mono_fallback := SystemFont.new()
		mono_fallback.font_names = PackedStringArray(["IBM Plex Mono", "SF Mono", "Menlo", "PT Mono", "monospace"])
		mono_base = mono_fallback
	_sans = sans_base
	_sans_tracked = sans_base
	_mono = mono_base
	_mono_tracked = mono_base


func _make_label(text: String, size_px: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _rule_style(side: Side) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, 0.11)
	match side:
		SIDE_TOP:
			style.border_width_top = 1
		SIDE_BOTTOM:
			style.border_width_bottom = 1
	return style


func _reset_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, alpha)
	style.border_width_bottom = 1
	return style


func _style_scrollbar(bar: VScrollBar) -> void:
	bar.custom_minimum_size.x = 4.0
	bar.add_theme_icon_override("increment", ImageTexture.new())
	bar.add_theme_icon_override("decrement", ImageTexture.new())
	bar.add_theme_stylebox_override("scroll", _empty_style())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(INK, 0.22)
	grabber.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("grabber", grabber)
	var hover := grabber.duplicate() as StyleBoxFlat
	hover.bg_color = Color(INK, 0.38)
	bar.add_theme_stylebox_override("grabber_highlight", hover)
	bar.add_theme_stylebox_override("grabber_pressed", hover)
