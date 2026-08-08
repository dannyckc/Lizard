## The Anatomy tab's drawer: a specimen, the depth stack that made it, and the
## four numbers that say whether it is still working.
##
## Every readout here is taken live off the selected creature's own anatomy —
## `TissueGrid` for what is still standing, `BodyState` for what the two supply
## networks are delivering — so the panel cannot drift out of step with the body
## it is describing. There is no anatomy model behind this file; there is the
## creature's, read from.
class_name AnatomyPanel
extends PanelContainer

const PAPER := CreatureView.PAPER
const INK := CreatureView.INK

## The depth stack, plus the two networks laid through it, in the order a bite
## goes down through them. `layer` is -1 for the networks, which are not part of
## the stack and are toggled on the view instead.
const ROWS: Array[Dictionary] = [
	{"name": "Skin", "layer": TissueGrid.SKIN, "ink": CreatureView.COL_BODY_HEAD},
	{"name": "Fat", "layer": TissueGrid.FAT, "ink": CreatureView.COL_FAT},
	{"name": "Muscle", "layer": TissueGrid.MUSCLE, "ink": CreatureView.COL_MUSCLE},
	{"name": "Skeleton", "layer": TissueGrid.BONE, "ink": CreatureView.COL_BONE},
	{"name": "Vessels", "layer": -1, "ink": CreatureView.COL_DBG_VESSEL},
	{"name": "Nerves", "layer": -1, "ink": CreatureView.COL_DBG_NERVE},
]
const VESSELS_ROW: int = 4
const NERVES_ROW: int = 5

const WIDTH: float = 378.0
const INSET: float = 44.0
## What the stage would like, and what it will shrink to on a short window.
const STAGE_HEIGHT: float = 326.0
const STAGE_MIN_HEIGHT: float = 120.0

var view: AnatomyView

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _specimens: Array = []
var _active: int = 0

var _status: Label
var _integrity: Label
var _note: Label
var _readout: Label
var _stage: Control
var _chip_row: HBoxContainer
var _rows: Array[Dictionary] = []
var _vitals: Array[Label] = []
var _chips: Array[Button] = []


func set_ui_fonts(sans: Font, sans_tracked: Font, mono: Font, mono_tracked: Font) -> void:
	_sans = sans
	_sans_tracked = sans_tracked
	_mono = mono
	_mono_tracked = mono_tracked
	if view != null:
		view.set_ui_font(mono)


func _ready() -> void:
	_ensure_fonts()
	_place()

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_stage())
	root.add_child(_build_layers())
	root.add_child(_build_vitals())
	root.add_child(_build_footer())
	view.set_ui_font(_mono)
	_sync_toggles()
	_build_chips()
	_apply_specimen()


## The creature currently on the slab.
func creature() -> Creature:
	if _active < 0 or _active >= _specimens.size():
		return null
	var each: Creature = _specimens[_active]["creature"]
	return each if is_instance_valid(each) else null


## `list` is `[{"name": String, "creature": Creature}, ...]` — whatever the world
## has that can be opened up. The panel names none of them itself.
func set_specimens(list: Array) -> void:
	_specimens = list
	_active = clampi(_active, 0, maxi(list.size() - 1, 0))
	_build_chips()
	_apply_specimen()


func select_specimen(index: int) -> void:
	if index < 0 or index >= _specimens.size():
		return
	_active = index
	_apply_specimen()


## Shrinks the specimen stage to whatever a short window has left over, so the
## readouts under it are never pushed off the screen.
func fit_to_height(available: float) -> void:
	if _stage == null:
		return
	var chrome: float = get_combined_minimum_size().y - _stage.custom_minimum_size.y
	_stage.custom_minimum_size.y = clampf(
		available - chrome, STAGE_MIN_HEIGHT, STAGE_HEIGHT)


## Re-reads the specimen. Every number below is a query, never a stored copy.
func refresh() -> void:
	var each: Creature = creature()
	var grid: TissueGrid = view.tissue() if view != null else null
	if each == null or grid == null:
		_status.text = "—"
		_integrity.text = "—"
		_note.text = "NO SPECIMEN"
		return

	var state: BodyState = each.anatomy.state
	var integrity: float = grid.integrity()
	_integrity.text = "%.1f" % (integrity * 100.0)
	_status.text = _status_word(each, state, integrity)

	var gone: int = grid.gone_count()
	var cells: int = grid.cell_count()
	_note.text = "%d CELLS OUT OF %d" % [gone, cells] if gone > 0 \
		else "LATTICE %d CELLS" % cells

	for index in _rows.size():
		var row: Dictionary = ROWS[index]
		var layer: int = int(row["layer"])
		var value: float = grid.layer_left(layer) if layer >= 0 \
			else _mean_delivery(state.vessels if index == VESSELS_ROW else state.nerves)
		(_rows[index]["pct"] as Label).text = "%d%%" % int(round(value * 100.0))

	var brain: float = grid.organ(BodyPlan.BRAIN)
	var heart: float = grid.organ(BodyPlan.HEART)
	var cut_off: int = state.vessels.cut_off() + state.nerves.cut_off()
	_set_vital(0, "%d%%" % int(round(brain * 100.0)),
		CreatureView.COL_DBG_NERVE if brain < 0.99 else INK)
	_set_vital(1, "%d%%" % int(round(heart * 100.0)),
		CreatureView.COL_DBG_VESSEL if heart < 0.99 else INK)
	_set_vital(2, "%.2f" % state.bleeding,
		CreatureView.COL_DBG_VESSEL if state.bleeding > 0.4 else INK)
	_set_vital(3, "%d / %d" % [cut_off, BodyPlan.REGIONS * 2],
		CreatureView.COL_DBG_VESSEL if cut_off > 0 else INK)


## Wording taken from the body rather than from the tissue alone: an animal that
## has stopped is not merely a percentage, and saying so is the point of having a
## functional layer at all.
func _status_word(each: Creature, state: BodyState, integrity: float) -> String:
	if not each.alive:
		return "Dead"
	if state.collapsed:
		return "Collapsed"
	if integrity >= 0.95 and not state.impaired:
		return "Intact"
	if integrity >= 0.82:
		return "Wounded"
	return "Impaired" if integrity >= 0.6 else "Critical"


static func _mean_delivery(network: AnatomyNetwork) -> float:
	if network.delivery.is_empty():
		return 1.0
	var total: float = 0.0
	for value in network.delivery:
		total += value
	return total / float(network.delivery.size())


# ---------------------------------------------------------------- layout ----

func _place() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -(WIDTH + INSET)
	offset_right = -INSET
	offset_top = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER, 0.86)
	style.border_color = Color(INK, 0.13)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(INK, 0.14)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0.0, 10.0)
	add_theme_stylebox_override("panel", style)


func _build_header() -> Control:
	var section := _section(17.0, 15.0, 12.0, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	section.add_child(row)

	row.add_child(_mark(5.0))
	row.add_child(_label("ANATOMY", 10, _sans_tracked, INK))
	row.add_child(_spacer())
	_status = _label("—", 9, _mono_tracked, Color(INK, 0.38))
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(_status)
	_integrity = _label("—", 15, _mono, INK)
	row.add_child(_integrity)
	return section


func _build_stage() -> Control:
	var section := _section(0.0, 0.0, 0.0, true)
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(0.0, STAGE_HEIGHT)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	section.add_child(_stage)

	view = AnatomyView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.cell_hovered.connect(_on_cell_hovered)
	_stage.add_child(view)

	_note = _label("LATTICE", 8, _mono_tracked, Color(INK, 0.34))
	_note.position = Vector2(13.0, 11.0)
	_stage.add_child(_note)
	return section


func _build_layers() -> Control:
	var section := _section(17.0, 10.0, 12.0, true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	section.add_child(grid)

	for index in ROWS.size():
		var row: Dictionary = ROWS[index]
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = 22.0
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		line.gui_input.connect(_on_row_input.bind(index))
		grid.add_child(line)

		var swatch := Panel.new()
		var wrap := CenterContainer.new()
		wrap.custom_minimum_size = Vector2(8.0, 8.0)
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.custom_minimum_size = Vector2(8.0, 8.0)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(swatch)
		line.add_child(wrap)

		var name_label := _label(str(row["name"]), 11, _sans, INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var pct := _label("100%", 10, _mono, Color(INK, 0.58))
		line.add_child(pct)

		_rows.append({"line": line, "swatch": swatch, "pct": pct})
	return section


func _build_vitals() -> Control:
	var section := _section(17.0, 13.0, 13.0, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	section.add_child(row)

	for title in ["Brain", "Heart", "Bleed", "Cut off"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 5)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_label(str(title).to_upper(), 8, _sans_tracked, Color(INK, 0.38)))
		var value := _label("—", 13, _mono, INK)
		column.add_child(value)
		_vitals.append(value)
		row.add_child(column)
	return section


func _build_footer() -> Control:
	var section := _section(17.0, 10.0, 11.0, false)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 22.0
	row.add_theme_constant_override("separation", 10)
	section.add_child(row)

	_readout = _label("HOVER A CELL", 9, _mono, Color(INK, 0.34))
	_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_readout.clip_text = true
	_readout.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_readout)

	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 3)
	row.add_child(_chip_row)
	return section


func _build_chips() -> void:
	if _chip_row == null:
		return
	for chip in _chips:
		_chip_row.remove_child(chip)
		chip.queue_free()
	_chips.clear()
	for index in _specimens.size():
		var chip := Button.new()
		chip.text = str(_specimens[index]["name"]).to_upper()
		chip.flat = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size.y = 20.0
		chip.add_theme_font_override("font", _mono_tracked)
		chip.add_theme_font_size_override("font_size", 8)
		chip.pressed.connect(select_specimen.bind(index))
		_chip_row.add_child(chip)
		_chips.append(chip)
	_style_chips()


# --------------------------------------------------------------- reaction ----

func _apply_specimen() -> void:
	if view == null:
		return
	view.creature = creature()
	view.reset_fit()
	_style_chips()
	_on_cell_hovered("", false)
	refresh()


func _on_row_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var layer: int = int(ROWS[index]["layer"])
	if layer >= 0:
		view.set_layer_shown(layer, not view.layer_shown(layer))
	elif index == VESSELS_ROW:
		view.show_vessels = not view.show_vessels
	else:
		view.show_nerves = not view.show_nerves
	_sync_toggles()
	accept_event()


func _on_cell_hovered(readout: String, alarm: bool) -> void:
	if readout.is_empty():
		_readout.text = "HOVER A CELL"
		_readout.add_theme_color_override("font_color", Color(INK, 0.34))
		return
	_readout.text = readout
	_readout.add_theme_color_override("font_color",
		CreatureView.COL_DBG_VESSEL if alarm else Color(INK, 0.58))


## An off layer is drawn as an empty swatch and a dimmed row — the specimen has
## had it lifted off, so the panel says so in the same two ways the design does.
func _sync_toggles() -> void:
	for index in _rows.size():
		var layer: int = int(ROWS[index]["layer"])
		var on: bool = view.layer_shown(layer) if layer >= 0 \
			else (view.show_vessels if index == VESSELS_ROW else view.show_nerves)
		var ink: Color = ROWS[index]["ink"]
		var swatch: Panel = _rows[index]["swatch"]
		var style := StyleBoxFlat.new()
		style.bg_color = ink if on else Color.TRANSPARENT
		style.border_color = ink if on else Color(INK, 0.28)
		style.set_border_width_all(1)
		swatch.add_theme_stylebox_override("panel", style)
		(_rows[index]["line"] as Control).modulate = Color(1.0, 1.0, 1.0, 1.0 if on else 0.44)


func _style_chips() -> void:
	for index in _chips.size():
		var chip: Button = _chips[index]
		var selected: bool = index == _active
		chip.add_theme_color_override("font_color", INK if selected else Color(INK, 0.40))
		chip.add_theme_color_override("font_hover_color", INK)
		chip.add_theme_stylebox_override("normal", _chip_style(0.40 if selected else 0.13))
		chip.add_theme_stylebox_override("hover", _chip_style(0.40))
		chip.add_theme_stylebox_override("pressed", _chip_style(0.55))


func _set_vital(index: int, text: String, ink: Color) -> void:
	var label: Label = _vitals[index]
	label.text = text
	label.add_theme_color_override("font_color", ink)


# ------------------------------------------------------------------ parts ----

## One horizontal band of the drawer, with the hairline that closes it off.
func _section(side: float, top: float, bottom: float, rule: bool) -> PanelContainer:
	var section := PanelContainer.new()
	section.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, 0.11)
	style.border_width_bottom = 1 if rule else 0
	style.content_margin_left = side
	style.content_margin_right = side
	style.content_margin_top = top
	style.content_margin_bottom = bottom
	section.add_theme_stylebox_override("panel", style)
	return section


func _chip_style(border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _mark(mark_size: float) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(mark_size, mark_size)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(mark_size, mark_size)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	mark.add_theme_stylebox_override("panel", style)
	wrap.add_child(mark)
	return wrap


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _label(text: String, size_px: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _ensure_fonts() -> void:
	if _sans != null:
		return
	var sans_base := SystemFont.new()
	sans_base.font_names = PackedStringArray(
		["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
	var mono_base: Font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if mono_base == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(
			["IBM Plex Mono", "SF Mono", "Menlo", "PT Mono", "monospace"])
		mono_base = fallback
	_sans = sans_base
	_sans_tracked = sans_base
	_mono = mono_base
	_mono_tracked = mono_base
