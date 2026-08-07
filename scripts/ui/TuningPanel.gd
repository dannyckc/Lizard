## Runtime tuning UI, generated entirely from CreatureParams.SCHEMA.
##
## Nothing here knows what any individual parameter means — add a row to the
## schema and a slider appears, wired to the live resource. Every change takes
## effect on the next physics tick because the systems read the resource fresh
## each frame.
class_name TuningPanel
extends PanelContainer

signal preset_applied(preset_name: String)

var params: CreatureParams

var _sliders: Dictionary = {}      ## property name -> HSlider
var _value_labels: Dictionary = {} ## property name -> Label
var _checks: Dictionary = {}       ## property name -> CheckBox
var _updating: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_top = 0.0
	anchor_bottom = 1.0
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -336.0
	offset_right = -14.0
	offset_top = 14.0
	offset_bottom = -14.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.13, 0.93)
	style.border_color = Color(1, 1, 1, 0.10)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "TUNING"
	title.add_theme_color_override("font_color", Color(0.62, 0.85, 0.70))
	root.add_child(title)

	root.add_child(_build_preset_row())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)

	for row in CreatureParams.SCHEMA:
		if row.has("group"):
			list.add_child(_build_group_header(row["group"]))
		elif row.get("bool", false):
			list.add_child(_build_check_row(row))
		else:
			list.add_child(_build_slider_row(row))

	var hint := Label.new()
	hint.text = "F1 panel · F2 debug · R reset"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	root.add_child(hint)

	refresh()


func _build_preset_row() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for preset_name in CreatureParams.PRESETS:
		var button := Button.new()
		button.text = str(preset_name)
		button.add_theme_font_size_override("font_size", 11)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_preset_pressed.bind(str(preset_name)))
		box.add_child(button)
	return box


func _build_group_header(text: String) -> Control:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0, 0.85))
	label.custom_minimum_size = Vector2(0, 22)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


func _build_slider_row(row: Dictionary) -> Control:
	var prop: String = row["prop"]
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = row["label"]
	name_label.custom_minimum_size = Vector2(118, 0)
	name_label.add_theme_font_size_override("font_size", 11)
	box.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = row["min"]
	slider.max_value = row["max"]
	slider.step = row["step"]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 18)
	slider.value_changed.connect(_on_slider_changed.bind(prop))
	box.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	box.add_child(value_label)

	_sliders[prop] = slider
	_value_labels[prop] = value_label
	return box


func _build_check_row(row: Dictionary) -> Control:
	var prop: String = row["prop"]
	var check := CheckBox.new()
	check.text = row["label"]
	check.add_theme_font_size_override("font_size", 11)
	check.toggled.connect(_on_check_toggled.bind(prop))
	_checks[prop] = check
	return check


func _on_slider_changed(value: float, prop: String) -> void:
	if _updating or params == null:
		return
	params.set(prop, value)
	_update_value_label(prop, value)


func _on_check_toggled(pressed: bool, prop: String) -> void:
	if _updating or params == null:
		return
	params.set(prop, pressed)


func _on_preset_pressed(preset_name: String) -> void:
	if params == null:
		return
	params.apply_preset(preset_name)
	refresh()
	preset_applied.emit(preset_name)


func _update_value_label(prop: String, value: float) -> void:
	var label: Label = _value_labels.get(prop)
	if label == null:
		return
	var slider: HSlider = _sliders[prop]
	label.text = str(int(round(value))) if slider.step >= 1.0 else ("%.2f" % value)


## Pushes the resource's current values back into every control. Called after a
## preset swap, or any time the parameters change from outside the panel.
func refresh() -> void:
	if params == null:
		return
	_updating = true
	for prop in _sliders:
		var value: float = float(params.get(prop))
		_sliders[prop].value = value
		_update_value_label(prop, value)
	for prop in _checks:
		_checks[prop].button_pressed = bool(params.get(prop))
	_updating = false
