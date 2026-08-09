## The Creature Creation menu: where a species is chosen, its body is tuned, and
## the animal that comes out of both is stood on a slab and looked at.
##
## It replaces two separate pieces of furniture — a tuning drawer down the right
## edge and a row of species tabs across the top — which between them made
## picking an animal and adjusting one feel like different activities happening
## in different places. They are the same activity. A preset *is* a set of these
## sliders written down, and the only honest way to show that is to put the
## sliders, the species and the creature they describe on one page.
##
## Three columns, and each of them is one question.
##
## Left — which animal is this. Every species is quoted by the same three
## readings so they can be compared rather than merely listed, and each of those
## is read out of the preset itself.
##
## Middle — what that animal is and what it can do: the live specimen, turnable
## and peelable, over the numbers its own body reports. Not one of those numbers
## is authored here. Mass, strength and bite force come off `Physique`; how tall
## it stands off `Stature`; its acceleration, turn rate and how many legs it walks
## on off `Locomotion`; and the name of the gait off `Footfall`, which works it out
## from the proportions rather than being told. Tune the legs and the readout
## moves because the animal moved.
##
## Right — every parameter the species is made of, in `CreatureParams.SCHEMA`
## order, with the species' own value notched on each track. That notch is the
## whole reason the two halves belong together: how far a creature has been
## carried from its species is then visible on the control that carried it, and
## putting it back is one button.
##
## Nothing in this file models a creature. Everything it prints is read off the
## live `Creature`, and everything it writes goes onto the one `CreatureParams`
## the simulation is already reading. It is a view of the animal, in both
## directions.
class_name CreatureCreator
extends Control

## A species has been chosen. The world rebuilds the body and re-points its
## senses; the menu does neither, because whose creature this is is not its
## business.
signal preset_selected(preset_name: String)
## One parameter has been moved. `structural` is true for the ones a body is
## *built* out of rather than solved with — see STRUCTURAL — so the world knows
## when a slider needs the animal grown again rather than merely read again.
signal param_changed(prop: String, structural: bool)

const PAPER := Color("f3f1ec")
const INK := Color("14140f")

## Parameters that are read once, when the body is built, and never again.
##
## Everything else on this panel is consulted fresh each tick — a width, a speed,
## a bite depth — so moving it shows up on the specimen immediately. These do not:
## a stance is turned into a `Posture`, a girdle position into columns of the
## tissue lattice and a joint angle into an `Articulation` at rebuild time, and
## until the animal is grown again the slider is describing a body that does not
## exist yet. The menu cannot rebuild it — the creature belongs to the world — so
## it says which kind of change this was and lets the world do it.
const STRUCTURAL: Array[String] = [
	"posture",
	"front_limb_t", "rear_limb_t",
	"fore_flex_deg", "hind_flex_deg",
	"fore_fold_range", "hind_fold_range",
	"fore_upper_share", "hind_upper_share",
	"fore_swing_deg", "hind_swing_deg",
]

## The three readings every species is quoted by on the rail. Chosen because they
## are the three that are *not* implied by each other: how fast it goes, how
## strong it is for its size, and how solidly it is built.
const RAIL_METERS: Array[Dictionary] = [
	{"prop": "move_speed", "label": "SPD"},
	{"prop": "muscle_power", "label": "PWR"},
	{"prop": "density", "label": "BLK"},
]

const RAIL_WIDTH: float = 250.0
const TUNE_WIDTH: float = 384.0
const STAGE_MIN_HEIGHT: float = 190.0
const RAIL_METER: float = 40.0

## The stat tiles under the specimen, in two rows of six. `key` is what the tile
## is called; the value is filled in by `_read_body` off the creature itself.
const TILES: Array[Array] = [
	["MASS", "STRENGTH", "BITE FORCE", "STANDS", "LENGTH", "TOP SPEED"],
	["STANCE", "BEARING", "GAIT", "ACCELERATION", "TURN RATE", "LEAP"],
]
## Share of the row each column takes. Even but for the third, which carries the
## name of the gait — the one reading here that is a phrase rather than a number,
## and the only one that cannot be shortened without saying less.
const TILE_RATIOS: Array[float] = [1.0, 1.0, 1.9, 1.1, 1.0, 1.0]

var params: CreatureParams
## The animal on the slab. The player's creature — a creation menu is about the
## body you are wearing — and the panel only ever reads it.
var subject: Creature
var view: AnatomyView

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _active: String = "Lizard"
## The species as written down, kept beside the species as edited. Every notch,
## every edit mark and the revert button are the difference between the two.
var _baseline: CreatureParams = CreatureParams.new()
var _updating: bool = false

var _sliders: Dictionary = {}        ## prop -> MinimalSlider
var _checks: Dictionary = {}         ## prop -> InkToggle
var _values: Dictionary = {}         ## prop -> Label
var _marks: Dictionary = {}          ## prop -> Panel
var _species_rows: Dictionary = {}   ## preset name -> Dictionary
var _group_anchors: Dictionary = {}  ## group name -> Control
var _group_chips: Dictionary = {}    ## group name -> Button
var _tiles: Dictionary = {}          ## tile key -> Label
var _layer_chips: Array[Dictionary] = []

var _scroll: ScrollContainer
var _edited_note: Label
var _revert: Button
var _species_note: Label
var _hover: Label
var _orbit: Label
## Which group the tuning column is currently looking at, so the chips are
## restyled when that changes rather than on every pixel of every scroll.
var _looking_at: String = ""
## The edit mark's two appearances, made once. `_refresh_edits` runs on every
## frame of every drag and there are sixty rows of them.
var _dot_on: StyleBoxFlat
var _dot_off: StyleBoxFlat


func set_ui_fonts(sans: Font, sans_tracked: Font, mono: Font, mono_tracked: Font) -> void:
	_sans = sans
	_sans_tracked = sans_tracked
	_mono = mono
	_mono_tracked = mono_tracked
	if view != null:
		view.set_ui_font(mono)


func _ready() -> void:
	_ensure_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The menu takes the whole window and the pointer with it: the field behind is
	# still running and still being drawn, but a click in here is not a bite.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)

	_dot_on = StyleBoxFlat.new()
	_dot_on.bg_color = INK
	_dot_on.set_corner_radius_all(2)
	_dot_off = StyleBoxFlat.new()
	_dot_off.bg_color = Color.TRANSPARENT

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(PAPER, 0.955)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var frame := Panel.new()
	frame.name = "InsetFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 14.0
	frame.offset_top = 14.0
	frame.offset_right = -14.0
	frame.offset_bottom = -14.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color.TRANSPARENT
	frame_style.border_color = Color(INK, 0.10)
	frame_style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)
	root.add_child(_build_header())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 0)
	root.add_child(columns)
	columns.add_child(_build_species_rail())
	columns.add_child(_rule())
	columns.add_child(_build_specimen())
	columns.add_child(_rule())
	columns.add_child(_build_tuning())

	root.add_child(_build_footer())

	view.set_ui_font(_mono)
	_sync_layer_chips()
	# Adopted rather than applied: the creature arrives already built, and a menu
	# that stamped a preset over it on the way up would be editing the animal
	# before anybody had asked it to.
	adopt_species(_active)


func _process(_delta: float) -> void:
	if not visible:
		return
	_read_body()
	_orbit.text = _orbit_word()


## Whether the menu is out. The creature is not paused behind it — the specimen is
## the animal as it stands, and standing is something it is doing.
func set_open(open: bool) -> void:
	visible = open
	set_process(open)
	if not open:
		return
	if view != null:
		view.creature = subject
		# A menu that has just been opened frames the animal rather than easing
		# across from wherever the last one was left.
		view.reset_fit()
	_refresh_edits()
	_read_body()


func toggle() -> void:
	set_open(not visible)


## The creature this menu is describing. Handed over by the world, because whose
## body this is is the world's business.
func set_subject(each: Creature) -> void:
	subject = each
	if view != null:
		view.creature = each
		view.reset_fit()
	_read_body()


## Makes the creature this species: the preset goes onto the parameters and every
## track is re-notched against it.
func set_species(preset_name: String) -> void:
	if not CreatureParams.PRESETS.has(preset_name):
		return
	if params != null:
		params.apply_preset(preset_name)
	adopt_species(preset_name)
	preset_selected.emit(preset_name)
	# After the emit, never before it. The report is of the animal, and until the
	# world has heard about the new species the animal is still the old one — so
	# reading it any earlier prints the creature that has just been replaced.
	_read_body()


## Names the species this creature is understood to be, without touching it.
##
## The difference from `set_species` matters exactly once — on the way up, where
## the animal already exists and the menu is joining it rather than making it —
## and it is the difference between a notch that says what the species carries
## and a preset stamped over a body nobody asked to change.
func adopt_species(preset_name: String) -> void:
	if not CreatureParams.PRESETS.has(preset_name):
		return
	_active = preset_name
	_baseline = CreatureParams.new()
	_baseline.apply_preset(preset_name)
	_style_species_rows()
	refresh()


## Puts the creature back to the species it says it is, without changing species.
func revert_to_preset() -> void:
	if params == null:
		return
	params.copy_from(_baseline)
	refresh()
	preset_selected.emit(_active)
	_read_body()


func active_species() -> String:
	return _active


## How many parameters this creature has been carried away from its species by.
func edited_count() -> int:
	var count: int = 0
	if params == null:
		return 0
	for row in CreatureParams.SCHEMA:
		if row.has("prop") and _is_edited(str(row["prop"])):
			count += 1
	return count


## Pushes the live resource back into every control, and re-reads the body.
func refresh() -> void:
	if params == null:
		return
	_updating = true
	for prop in _sliders:
		var slider: MinimalSlider = _sliders[prop]
		var value: float = float(params.get(prop))
		slider.set_value_silent(value)
		slider.reference = float(_baseline.get(prop))
		_update_value_label(str(prop), value)
	for prop in _checks:
		var pressed: bool = bool(params.get(prop))
		(_checks[prop] as InkToggle).button_pressed = pressed
		(_values[prop] as Label).text = "ON" if pressed else "OFF"
	_updating = false
	_refresh_edits()
	_read_body()


# ----------------------------------------------------------------- header ----

func _build_header() -> Control:
	var section := _band(0.0, 0.0, 14.0, SIDE_BOTTOM)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 26.0
	row.add_theme_constant_override("separation", 10)
	section.add_child(row)

	row.add_child(_mark(6.0))
	row.add_child(_label("CREATURE CREATION", 11, _sans_tracked, INK))

	var rule_wrap := CenterContainer.new()
	rule_wrap.custom_minimum_size = Vector2(26.0, 7.0)
	rule_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.22)
	rule.custom_minimum_size = Vector2(26.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_wrap.add_child(rule)
	row.add_child(rule_wrap)

	_species_note = _label("—", 10, _mono_tracked, Color(INK, 0.46))
	_species_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_species_note)
	row.add_child(_spacer())

	_edited_note = _label("", 9, _mono_tracked, Color(INK, 0.46))
	_edited_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_edited_note)

	_revert = _flat_button("REVERT TO SPECIES", 9, revert_to_preset)
	row.add_child(_revert)

	var close := Button.new()
	close.text = "CLOSE   F1"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(104.0, 28.0)
	close.add_theme_font_override("font", _sans_tracked)
	close.add_theme_font_size_override("font_size", 10)
	close.add_theme_color_override("font_color", INK)
	close.add_theme_color_override("font_hover_color", INK)
	close.add_theme_stylebox_override("normal", _box_style(0.16))
	close.add_theme_stylebox_override("hover", _box_style(0.34))
	close.add_theme_stylebox_override("pressed", _box_style(0.5))
	close.pressed.connect(set_open.bind(false))
	row.add_child(close)
	return section


# ------------------------------------------------------------------ rail ----

## The species, each quoted by what separates it from the others.
##
## The subtitle and the three bars are read out of the preset rather than written
## beside it: the stance is the stance it carries, and whether it walks on four
## legs or two is `Locomotion`'s own test put to the numbers — the same test the
## simulation will apply to the body once it is grown, so the rail cannot promise
## an animal the world then declines to build.
func _build_species_rail() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = RAIL_WIDTH
	column.size_flags_horizontal = Control.SIZE_FILL
	column.add_theme_constant_override("separation", 0)

	var head := MarginContainer.new()
	head.add_theme_constant_override("margin_top", 16)
	head.add_theme_constant_override("margin_bottom", 10)
	head.add_theme_constant_override("margin_right", 18)
	head.add_child(_label("SPECIES", 9, _sans_tracked, Color(INK, 0.40)))
	column.add_child(head)

	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 18)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(list)
	column.add_child(pad)

	var peaks: Dictionary = _rail_peaks()
	for preset_name in CreatureParams.PRESETS:
		list.add_child(_build_species_row(str(preset_name), peaks))
	return column


func _build_species_row(preset_name: String, peaks: Dictionary) -> Control:
	var each := CreatureParams.new()
	each.apply_preset(preset_name)

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 62.0
	button.pressed.connect(set_species.bind(preset_name))
	button.add_theme_stylebox_override("normal", _row_style(false))
	button.add_theme_stylebox_override("hover", _row_style(false, 0.05))
	button.add_theme_stylebox_override("pressed", _row_style(true))

	# The button is the hit area and nothing else; everything legible sits on top
	# of it and lets the pointer through, which is how a row can carry a name, a
	# description and three bars and still be one thing to click.
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 12.0
	body.offset_right = -10.0
	body.offset_top = 9.0
	body.offset_bottom = -9.0
	body.add_theme_constant_override("separation", 3)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(body)

	var title := _label(preset_name.to_upper(), 12, _sans, INK)
	body.add_child(title)

	var legs: String = "FOUR LEGS" if Locomotion.bears_on_forelimbs(each) else "TWO LEGS"
	var caption := _label("%s · %s" % [Posture.NAMES[each.posture].to_upper(), legs],
		8, _mono_tracked, Color(INK, 0.42))
	body.add_child(caption)

	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 9)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(bars)
	for entry in RAIL_METERS:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(_label(str(entry["label"]), 7, _mono_tracked, Color(INK, 0.32)))
		var meter := AnatomyPanel.Meter.new(RAIL_METER, 2.0)
		var prop: String = entry["prop"]
		meter.set_bar(float(each.get(prop)) / maxf(float(peaks[prop]), 0.0001), Color(INK, 0.55))
		pair.add_child(meter)
		bars.add_child(pair)

	_species_rows[preset_name] = {
		"button": button, "title": title, "caption": caption, "bars": bars,
	}
	return button


## The largest each rail reading reaches across the whole roster, so a bar is a
## species' share of the fastest, strongest or heaviest thing on the list rather
## than of an arbitrary ceiling nothing ever touches.
func _rail_peaks() -> Dictionary:
	var peaks: Dictionary = {}
	for entry in RAIL_METERS:
		peaks[entry["prop"]] = 0.0001
	for preset_name in CreatureParams.PRESETS:
		var each := CreatureParams.new()
		each.apply_preset(str(preset_name))
		for entry in RAIL_METERS:
			var prop: String = entry["prop"]
			peaks[prop] = maxf(float(peaks[prop]), float(each.get(prop)))
	return peaks


func _style_species_rows() -> void:
	for preset_name in _species_rows:
		var row: Dictionary = _species_rows[preset_name]
		var selected: bool = str(preset_name) == _active
		(row["button"] as Button).add_theme_stylebox_override("normal", _row_style(selected))
		(row["button"] as Button).add_theme_stylebox_override("hover",
			_row_style(selected, 0.05))
		(row["title"] as Label).add_theme_color_override("font_color",
			INK if selected else Color(INK, 0.62))
		(row["caption"] as Label).add_theme_color_override("font_color",
			Color(INK, 0.52 if selected else 0.34))
		(row["bars"] as Control).modulate = Color(1.0, 1.0, 1.0, 1.0 if selected else 0.6)


# -------------------------------------------------------------- specimen ----

func _build_specimen() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)

	var head := MarginContainer.new()
	head.add_theme_constant_override("margin_left", 20)
	head.add_theme_constant_override("margin_right", 20)
	head.add_theme_constant_override("margin_top", 16)
	head.add_theme_constant_override("margin_bottom", 9)
	column.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	head.add_child(head_row)
	head_row.add_child(_label("SPECIMEN", 9, _sans_tracked, Color(INK, 0.40)))
	head_row.add_child(_spacer())
	head_row.add_child(_build_layer_chips())

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(300.0, STAGE_MIN_HEIGHT)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	var stage_pad := MarginContainer.new()
	stage_pad.add_theme_constant_override("margin_left", 20)
	stage_pad.add_theme_constant_override("margin_right", 20)
	stage_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_pad.add_child(stage)
	column.add_child(stage_pad)

	view = AnatomyView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.cell_hovered.connect(_on_cell_hovered)
	stage.add_child(view)

	_orbit = _label("", 8, _mono_tracked, Color(INK, 0.30))
	_orbit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_orbit.offset_left = 2.0
	_orbit.offset_top = -18.0
	_orbit.offset_bottom = -6.0
	stage.add_child(_orbit)

	_hover = _label("HOVER A CELL", 9, _mono, Color(INK, 0.34))
	_hover.position = Vector2(2.0, 3.0)
	stage.add_child(_hover)

	column.add_child(_build_report())
	return column


## The depth stack as a row of chips: click one and it comes off the specimen.
## The same six layers the anatomy drawer peels, driven the same way, because it
## is the same view of the same lattice — plus the lattice itself, which is what
## the whole body is drawn out of and so is worth being able to switch off.
func _build_layer_chips() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for index in AnatomyPanel.ROWS.size():
		row.add_child(_layer_chip(index, str(AnatomyPanel.ROWS[index]["name"]),
			AnatomyPanel.ROWS[index]["ink"]))
	row.add_child(_layer_chip(AnatomyPanel.ROWS.size(), "Lattice", Color(INK, 0.45)))
	return row


func _layer_chip(index: int, text: String, ink: Color) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.gui_input.connect(_on_layer_chip_input.bind(index))

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(inner)

	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(7.0, 7.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(7.0, 7.0)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(swatch)
	inner.add_child(wrap)
	inner.add_child(_label(text.to_upper(), 8, _mono_tracked, INK))

	_layer_chips.append({"chip": chip, "swatch": swatch, "ink": ink, "index": index})
	return chip


func _on_layer_chip_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if index == AnatomyPanel.ROWS.size():
		view.show_lattice = not view.show_lattice
	elif index == AnatomyPanel.VESSELS_ROW:
		view.show_vessels = not view.show_vessels
	elif index == AnatomyPanel.NERVES_ROW:
		view.show_nerves = not view.show_nerves
	else:
		var layer: int = int(AnatomyPanel.ROWS[index]["layer"])
		view.set_layer_shown(layer, not view.layer_shown(layer))
	_sync_layer_chips()
	accept_event()


func _layer_on(index: int) -> bool:
	if index == AnatomyPanel.ROWS.size():
		return view.show_lattice
	if index == AnatomyPanel.VESSELS_ROW:
		return view.show_vessels
	if index == AnatomyPanel.NERVES_ROW:
		return view.show_nerves
	return view.layer_shown(int(AnatomyPanel.ROWS[index]["layer"]))


## A layer that has been lifted off reads as lifted off: the swatch empties and
## the chip goes quiet, so the row of chips is a picture of what is on the
## specimen rather than a list of what could be.
func _sync_layer_chips() -> void:
	for entry in _layer_chips:
		var on: bool = _layer_on(int(entry["index"]))
		var ink: Color = entry["ink"]
		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = ink if on else Color.TRANSPARENT
		swatch_style.border_color = ink if on else Color(INK, 0.28)
		swatch_style.set_border_width_all(1)
		(entry["swatch"] as Panel).add_theme_stylebox_override("panel", swatch_style)
		var chip: PanelContainer = entry["chip"]
		chip.add_theme_stylebox_override("panel", _chip_style(0.26 if on else 0.10))
		chip.modulate = Color(1.0, 1.0, 1.0, 1.0 if on else 0.5)


## What the body reports about itself, under the picture of it.
func _build_report() -> Control:
	var section := _band(20.0, 13.0, 9.0, SIDE_TOP)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	section.add_child(column)

	for line in TILES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)
		for index in line.size():
			var tile := VBoxContainer.new()
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# The same ratios on both rows, so the two lines of the report stay in
			# columns even though one of them needs a wider third.
			tile.size_flags_stretch_ratio = TILE_RATIOS[index]
			tile.add_theme_constant_override("separation", 4)
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(_label(str(line[index]), 8, _sans_tracked, Color(INK, 0.36)))
			var value := _label("—", 11, _mono, INK)
			value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			tile.add_child(value)
			_tiles[str(line[index])] = value
			row.add_child(tile)
	return section


## Every tile, off the creature. Nothing is cached and nothing is computed here:
## each of these is a property some system already publishes about the body it
## has just solved, which is why tuning a leg moves half of them at once.
func _read_body() -> void:
	if _tiles.is_empty():
		return
	if params == null or subject == null or not is_instance_valid(subject) \
			or subject.body == null or subject.gait == null:
		for key in _tiles:
			(_tiles[key] as Label).text = "—"
		return

	var physique: Physique = subject.physique
	var stature: Stature = subject.stature
	var loco: Locomotion = subject.locomotion
	_tiles["MASS"].text = "%.2f" % physique.mass
	_tiles["STRENGTH"].text = "%.2f" % physique.strength
	_tiles["BITE FORCE"].text = "%.2f" % physique.bite_force
	_tiles["STANDS"].text = "%d PX" % int(round(stature.stand_height()))
	_tiles["LENGTH"].text = "%d PX" % int(round(subject.body_length()))
	_tiles["TOP SPEED"].text = "%d PX/S" % int(round(params.move_speed))
	_tiles["STANCE"].text = subject.posture.name().to_upper()
	_tiles["BEARING"].text = "%d LEGS" % loco.bearing_limbs
	_tiles["GAIT"].text = subject.gait.footfall.describe().to_upper()
	_tiles["ACCELERATION"].text = "%d PX/S²" % int(round(loco.accel))
	_tiles["TURN RATE"].text = "%d°/S" % int(round(rad_to_deg(loco.turn_rate)))
	# Against the animal's own height, which is the only unit a leap means anything
	# in: three of its own heights is a cat and none of them is an elephant, and
	# both of those are the same number of pixels on differently sized bodies.
	var leap: float = params.leap_height * stature.stand_height()
	_tiles["LEAP"].text = "NONE" if leap < 1.0 else "%d PX" % int(round(leap))


func _on_cell_hovered(readout: String, alarm: bool) -> void:
	if readout.is_empty():
		_hover.text = "HOVER A CELL"
		_hover.add_theme_color_override("font_color", Color(INK, 0.34))
		return
	_hover.text = readout
	_hover.add_theme_color_override("font_color",
		CreatureView.COL_DBG_VESSEL if alarm else Color(INK, 0.58))


## Where the eye has got to, in the same words the anatomy drawer uses — it is the
## same trackball on the same specimen, so it should not be described twice.
func _orbit_word() -> String:
	if view == null:
		return ""
	if not view.orbited() and absf(view.roll) < 0.017:
		return "DRAG TO TURN THE SPECIMEN"
	var word: String = "SPIN %d° · TILT %+d°" % [
		int(round(rad_to_deg(view.spin))), int(round(rad_to_deg(view.tilt)))]
	if absf(view.roll) >= 0.017:
		word += " · ROLL %+d°" % int(round(rad_to_deg(view.roll)))
	return word + " · DOUBLE-CLICK RESETS"


# ---------------------------------------------------------------- tuning ----

func _build_tuning() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = TUNE_WIDTH
	column.size_flags_horizontal = Control.SIZE_FILL
	column.add_theme_constant_override("separation", 0)

	var head := MarginContainer.new()
	head.add_theme_constant_override("margin_left", 20)
	head.add_theme_constant_override("margin_top", 16)
	head.add_theme_constant_override("margin_bottom", 9)
	column.add_child(head)
	head.add_child(_label("ATTRIBUTES", 9, _sans_tracked, Color(INK, 0.40)))

	# Jump chips. Sixty-odd parameters in eleven groups is a long column whichever
	# way it is cut, and the alternative — showing one group at a time — hides the
	# fact that the animal is all of them at once.
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	var chip_pad := MarginContainer.new()
	chip_pad.add_theme_constant_override("margin_left", 20)
	chip_pad.add_theme_constant_override("margin_bottom", 12)
	chip_pad.add_child(chips)
	column.add_child(chip_pad)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.add_child(_scroll)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pad)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	pad.add_child(list)

	for row in CreatureParams.SCHEMA:
		if row.has("group"):
			var group: String = str(row["group"])
			var anchor: Control = _build_group_header(group)
			list.add_child(anchor)
			_group_anchors[group] = anchor
			chips.add_child(_build_group_chip(group))
		elif row.get("bool", false):
			list.add_child(_build_check_row(row))
		else:
			list.add_child(_build_slider_row(row))

	_style_scrollbar(_scroll.get_v_scroll_bar())
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	return column


func _build_group_chip(group: String) -> Button:
	var chip := Button.new()
	chip.text = group.to_upper()
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size.y = 20.0
	chip.add_theme_font_override("font", _mono_tracked)
	chip.add_theme_font_size_override("font_size", 8)
	chip.pressed.connect(_jump_to_group.bind(group))
	_group_chips[group] = chip
	_style_group_chip(group, false)
	return chip


func _style_group_chip(group: String, active: bool) -> void:
	var chip: Button = _group_chips[group]
	chip.add_theme_color_override("font_color", INK if active else Color(INK, 0.40))
	chip.add_theme_color_override("font_hover_color", INK)
	chip.add_theme_stylebox_override("normal", _chip_style(0.40 if active else 0.12))
	chip.add_theme_stylebox_override("hover", _chip_style(0.40))
	chip.add_theme_stylebox_override("pressed", _chip_style(0.55))


## Where a group's header sits in the scrolled column. Measured through the two
## controls' own positions on the screen rather than by adding up the containers
## between them, so nothing here has to know how the column is nested.
func _group_offset(group: String) -> int:
	var anchor: Control = _group_anchors.get(group)
	if anchor == null or _scroll == null:
		return 0
	return int(anchor.global_position.y - _scroll.global_position.y) + _scroll.scroll_vertical


func _jump_to_group(group: String) -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = _group_offset(group)
	_on_scrolled(float(_scroll.scroll_vertical))


## Which group the column is currently looking at — the last one whose header has
## gone past the top of the window. Purely a reading of where the scroll is, so
## the chips answer a drag of the scrollbar exactly as they answer a click.
func _on_scrolled(value: float) -> void:
	var found: String = ""
	for group in _group_anchors:
		if float(_group_offset(str(group))) <= value + 12.0:
			found = str(group)
	if found == _looking_at:
		return
	_looking_at = found
	for group in _group_chips:
		_style_group_chip(str(group), str(group) == found)


func _build_group_header(text: String) -> Control:
	var box := HBoxContainer.new()
	box.custom_minimum_size.y = 38.0
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(text.to_upper(), 9, _sans_tracked, Color(INK, 0.42))
	label.size_flags_vertical = Control.SIZE_SHRINK_END
	label.custom_minimum_size.y = 29.0
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
	box.add_theme_constant_override("separation", 8)
	box.add_child(_edit_mark(prop))

	var name_label := _label(str(row["label"]), 11, _sans, Color(INK, 0.78))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	var slider := MinimalSlider.new()
	slider.min_value = float(row["min"])
	slider.max_value = float(row["max"])
	slider.step = float(row["step"])
	slider.custom_minimum_size = Vector2(88.0, 26.0)
	slider.value_changed.connect(_on_slider_changed.bind(prop))
	box.add_child(slider)

	var value_label := _label("", 10, _mono, Color(INK, 0.62))
	value_label.custom_minimum_size = Vector2(44.0, 26.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value_label)

	_sliders[prop] = slider
	_values[prop] = value_label
	return box


func _build_check_row(row: Dictionary) -> Control:
	var prop: String = row["prop"]
	var box := HBoxContainer.new()
	box.custom_minimum_size.y = 26.0
	box.add_theme_constant_override("separation", 8)
	box.add_child(_edit_mark(prop))

	var name_label := _label(str(row["label"]), 11, _sans, Color(INK, 0.78))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)

	var check := InkToggle.new()
	check.custom_minimum_size = Vector2(88.0, 26.0)
	check.toggled.connect(_on_check_toggled.bind(prop))
	box.add_child(check)

	var value_label := _label("ON", 10, _mono, Color(INK, 0.62))
	value_label.custom_minimum_size = Vector2(44.0, 26.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value_label)

	_checks[prop] = check
	_values[prop] = value_label
	return box


## The mark that says this row is no longer what its species says. One dot, in the
## margin, so a creature that has been worked on reads as a column of dots down
## the edge and an untouched one reads as nothing at all.
func _edit_mark(prop: String) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(4.0, 4.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(4.0, 4.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(dot)
	_marks[prop] = dot
	return wrap


func _on_slider_changed(value: float, prop: String) -> void:
	if _updating or params == null:
		return
	params.set(prop, value)
	_update_value_label(prop, value)
	_refresh_edits()
	param_changed.emit(prop, STRUCTURAL.has(prop))


func _on_check_toggled(pressed: bool, prop: String) -> void:
	if _updating or params == null:
		return
	params.set(prop, pressed)
	(_values[prop] as Label).text = "ON" if pressed else "OFF"
	_refresh_edits()
	param_changed.emit(prop, STRUCTURAL.has(prop))


func _update_value_label(prop: String, value: float) -> void:
	var label: Label = _values.get(prop)
	if label == null:
		return
	var slider: MinimalSlider = _sliders[prop]
	label.text = str(int(round(value))) if slider.step >= 1.0 else ("%.2f" % value)


func _is_edited(prop: String) -> bool:
	if params == null:
		return false
	var mine: Variant = params.get(prop)
	var theirs: Variant = _baseline.get(prop)
	if typeof(mine) == TYPE_BOOL:
		return bool(mine) != bool(theirs)
	return not is_equal_approx(float(mine), float(theirs))


## Re-reads the whole panel against the species it claims to be. One pass, because
## the dots, the header count, the revert button and the value inks are four ways
## of saying the same thing and must never disagree.
func _refresh_edits() -> void:
	if _species_note == null:
		return
	var edited: int = 0
	for prop in _marks:
		var dirty: bool = _is_edited(str(prop))
		if dirty:
			edited += 1
		(_marks[prop] as Panel).add_theme_stylebox_override("panel",
			_dot_on if dirty else _dot_off)
		var label: Label = _values.get(prop)
		if label != null:
			label.add_theme_color_override("font_color", INK if dirty else Color(INK, 0.62))

	# The stance the creature is actually carrying rather than the one its species
	# writes down — they come apart the moment somebody moves that slider, and the
	# header should say what is standing on the slab.
	var stance: int = int(params.posture) if params != null else _baseline.posture
	_species_note.text = "%s · %s" % [_active.to_upper(), Posture.NAMES[stance].to_upper()]
	_edited_note.text = "" if edited == 0 else "%d EDITED" % edited
	_revert.visible = edited > 0


# ----------------------------------------------------------------- footer ----

func _build_footer() -> Control:
	var section := _band(0.0, 12.0, 0.0, SIDE_TOP)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 20.0
	row.add_theme_constant_override("separation", 24)
	section.add_child(row)
	row.add_child(_legend("F1", "CLOSE"))
	row.add_child(_legend("DRAG", "TURN THE SPECIMEN"))
	row.add_child(_legend("CLICK", "PEEL A LAYER"))
	row.add_child(_spacer())

	var count: int = 0
	for item in CreatureParams.SCHEMA:
		if item.has("prop"):
			count += 1
	var note := _label("%d PARAMETERS · %d SPECIES · THE NOTCH ON EACH TRACK IS THE SPECIES' OWN VALUE"
		% [count, CreatureParams.PRESETS.size()], 8, _mono_tracked, Color(INK, 0.30))
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)
	return section


func _legend(key: String, caption: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var keycap := Label.new()
	keycap.text = key
	keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keycap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keycap.custom_minimum_size = Vector2(19.0 if key.length() == 1 else 34.0, 19.0)
	keycap.add_theme_font_override("font", _mono)
	keycap.add_theme_font_size_override("font_size", 9)
	keycap.add_theme_color_override("font_color", INK)
	keycap.add_theme_stylebox_override("normal", _keycap_style())
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(keycap)
	row.add_child(_label(caption, 9, _sans_tracked, Color(INK, 0.44)))
	return row


# ------------------------------------------------------------------ parts ----

## One horizontal band of the page, with the hairline that closes it off.
func _band(side: float, top: float, bottom: float, rule: Side) -> PanelContainer:
	var section := PanelContainer.new()
	section.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, 0.11)
	match rule:
		SIDE_TOP:
			style.border_width_top = 1
		SIDE_BOTTOM:
			style.border_width_bottom = 1
	style.content_margin_left = side
	style.content_margin_right = side
	style.content_margin_top = top
	style.content_margin_bottom = bottom
	section.add_theme_stylebox_override("panel", style)
	return section


## A hairline between two columns. The rect itself, with no wrapper around it — a
## container that centres its children would hand this its minimum size and put a
## single pixel in the middle of the gap.
func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(INK, 0.11)
	line.custom_minimum_size = Vector2(1.0, 0.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _flat_button(text: String, size_px: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _mono_tracked)
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_color_override("font_color", Color(INK, 0.55))
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_stylebox_override("normal", _underline_style(0.22))
	button.add_theme_stylebox_override("hover", _underline_style(0.6))
	button.add_theme_stylebox_override("pressed", _underline_style(1.0))
	button.pressed.connect(action)
	return button


func _underline_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, alpha)
	style.border_width_bottom = 1
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _row_style(selected: bool, tint: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, maxf(tint, 0.035 if selected else 0.0))
	style.border_color = INK if selected else Color(INK, 0.10)
	style.border_width_left = 2 if selected else 1
	style.set_corner_radius_all(2)
	return style


func _chip_style(border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _box_style(border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER, 0.84)
	style.border_color = Color(INK, border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
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


func _style_scrollbar(bar: VScrollBar) -> void:
	bar.custom_minimum_size.x = 4.0
	bar.add_theme_icon_override("increment", ImageTexture.new())
	bar.add_theme_icon_override("decrement", ImageTexture.new())
	bar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(INK, 0.22)
	grabber.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("grabber", grabber)
	var hover := grabber.duplicate() as StyleBoxFlat
	hover.bg_color = Color(INK, 0.38)
	bar.add_theme_stylebox_override("grabber_highlight", hover)
	bar.add_theme_stylebox_override("grabber_pressed", hover)


func _mark(mark_size: float) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(mark_size, mark_size)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(mark_size, mark_size)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(int(ceil(mark_size * 0.5)))
	dot.add_theme_stylebox_override("panel", style)
	wrap.add_child(dot)
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
