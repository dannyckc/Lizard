## The Anatomy tab's drawer: a specimen you can walk around, what the animal is
## built out of, and what its organs are still doing.
##
## Every readout here is taken live off the selected creature's own anatomy —
## `TissueGrid` for what is still standing, `BodyState` for what the two supply
## networks are delivering — so the panel cannot drift out of step with the body
## it is describing. There is no anatomy model behind this file; there is the
## creature's, read from.
##
## Two rules about how it says things, and both are about scanning rather than
## about taste. Anything that is a *proportion* is drawn as a bar, because the eye
## reads a length faster than it reads a number and a row of bars can be taken in
## at once; and nothing is printed that reads "100%" on a healthy animal, because
## a panel full of hundreds is a panel that has to be searched for the one number
## that moved. What is printed instead is what the reading *means* — a share of
## the body's weight, a count of cut runs, a word for the state an organ is in.
class_name AnatomyPanel
extends PanelContainer

const PAPER := CreatureView.PAPER
const INK := CreatureView.INK

## The depth stack, plus the two networks laid through it, in the order a bite
## goes down through them. `layer` is -1 for the networks, which are not part of
## the stack and are toggled on the view instead.
const ROWS: Array[Dictionary] = [
	{"name": "Skin", "layer": TissueGrid.SKIN, "ink": AnatomyView.COL_HIDE},
	{"name": "Fat", "layer": TissueGrid.FAT, "ink": CreatureView.COL_FAT},
	{"name": "Muscle", "layer": TissueGrid.MUSCLE, "ink": CreatureView.COL_MUSCLE},
	{"name": "Skeleton", "layer": TissueGrid.BONE, "ink": CreatureView.COL_BONE},
	{"name": "Vessels", "layer": -1, "ink": CreatureView.COL_DBG_VESSEL},
	{"name": "Nerves", "layer": -1, "ink": CreatureView.COL_DBG_NERVE},
]
const VESSELS_ROW: int = 4
const NERVES_ROW: int = 5

## Every tissue of the cell lattice, in the order it is striped across the
## composition bar. The organ layer has no row of its own — an organ cannot be
## peeled off the specimen — but organs, nerves and vessels are all cells and
## all part of what the animal weighs, so the bar carries the lot and the shares
## add up to the body rather than to the four toggles.
const COMPOSITION: Array[int] = [
	AnatomyLattice.SKIN, AnatomyLattice.FAT, AnatomyLattice.MUSCLE,
	AnatomyLattice.BONE, AnatomyLattice.ORGAN, AnatomyLattice.NERVE,
	AnatomyLattice.VESSEL,
]
## Not a `const`: a packed array is built by a constructor, which is one step more
## than a constant expression is allowed to be.
static var COMPOSITION_INKS := PackedColorArray([
	AnatomyView.COL_HIDE,
	CreatureView.COL_FAT,
	CreatureView.COL_MUSCLE,
	CreatureView.COL_BONE,
	CreatureView.COL_ORGAN,
	CreatureView.COL_DBG_NERVE,
	CreatureView.COL_DBG_VESSEL,
])
## The section chips, in canonical-axis order with OFF in front.
const SLICES: Array[Dictionary] = [
	{"label": "OFF", "axis": AnatomyView.SLICE_OFF},
	{"label": "LONG", "axis": AnatomyView.SLICE_LONG},
	{"label": "SIDE", "axis": AnatomyView.SLICE_SIDE},
	{"label": "FLAT", "axis": AnatomyView.SLICE_FLAT},
]

const BRAIN_VITAL: int = 0
const HEART_VITAL: int = 1
const BLOOD_VITAL: int = 2

## Reading below which a body has visibly given ground. Above it an organ is
## described as sound rather than by how many hundredths of it are missing.
const DIM: float = 0.98
## Consciousness at which an animal is no longer meaningfully awake.
const FAINT: float = 0.35
## Circulation at which the heart is losing the body rather than merely labouring.
const FAILING: float = 0.5
## Tip of the specimen's own length off vertical below which the readout treats it
## as standing straight. A degree either way is the drag not having been perfectly
## level, and naming it would be reporting the hand rather than the view.
const LEVEL: float = 0.017

const WIDTH: float = 378.0
const INSET: float = 44.0
## What the stage would like, and what it will shrink to on a short window.
const STAGE_HEIGHT: float = 326.0
const STAGE_MIN_HEIGHT: float = 120.0

## Bars. A row meter is narrow enough to sit beside a name; the two full-width
## ones carry the whole animal.
const ROW_METER: float = 42.0
const HEAD_METER: float = 96.0
const VITAL_NAME: float = 58.0
const VITAL_WORD: float = 92.0


## A bar, and the only way this panel states a proportion.
##
## One segment for a health reading, several for a composition — the same control
## either way, because a stacked bar is a bar whose track happens to be shared.
## Nothing here knows what it is measuring: it is given fractions and inks.
class Meter extends Control:
	const TRACK := Color(CreatureView.INK, 0.10)
	## Hairline between neighbouring segments, so a stripe of skin between the fat
	## and the muscle is still legible as its own share.
	const GAP: float = 1.0

	var values: PackedFloat32Array = PackedFloat32Array([0.0])
	var inks: PackedColorArray = PackedColorArray([CreatureView.INK])
	var thickness: float = 3.0

	func _init(bar_width: float, bar_thickness: float = 3.0) -> void:
		thickness = bar_thickness
		custom_minimum_size = Vector2(bar_width, maxf(bar_thickness, 8.0))
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_bar(value: float, ink: Color) -> void:
		values = PackedFloat32Array([clampf(value, 0.0, 1.0)])
		inks = PackedColorArray([ink])
		queue_redraw()

	func set_segments(shares: PackedFloat32Array, segment_inks: PackedColorArray) -> void:
		values = shares
		inks = segment_inks
		queue_redraw()

	func _draw() -> void:
		var top: float = (size.y - thickness) * 0.5
		draw_rect(Rect2(0.0, top, size.x, thickness), TRACK)
		var at: float = 0.0
		var stacked: bool = values.size() > 1
		for i in values.size():
			var span: float = size.x * clampf(values[i], 0.0, 1.0)
			if span > 0.0:
				draw_rect(Rect2(at, top, maxf(span - (GAP if stacked else 0.0), 0.5), thickness),
					inks[i] if i < inks.size() else CreatureView.INK)
			at += span


var view: AnatomyView

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _specimens: Array = []
var _active: int = 0

var _status: Label
var _integrity: Meter
var _mass: Label
var _composition: Meter
var _note: Label
var _orbit: Label
var _readout: Label
var _stage: Control
var _chip_row: HBoxContainer
var _rows: Array[Dictionary] = []
var _vitals: Array[Dictionary] = []
var _chips: Array[Button] = []
var _slice_chips: Array[Dictionary] = []
var _slice_slider: HSlider
var _xray_chip: Control
## The mask the specimen wore before a tissue was isolated, so a second
## right-click puts the body back exactly as it stood.
var _before_solo: int = -1
var _solo_row: int = -1


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
	if _status == null:
		return
	var each: Creature = creature()
	var grid: TissueGrid = view.tissue() if view != null else null
	_orbit.text = _orbit_word()
	if each == null or grid == null:
		_blank()
		return

	var state: BodyState = each.anatomy.state
	var integrity: float = grid.integrity()
	_status.text = _status_word(each, state, integrity)
	_integrity.set_bar(integrity, INK if integrity >= DIM else CreatureView.COL_DBG_VESSEL)

	# The cell lattice is what the body *is* — the same cells the physique
	# weighed, printed rather than restated. Where it has not been built yet the
	# damage ledger's own counts stand in for one frame. Refreshed against the
	# ledger before anything is printed, so a wound bitten between ticks is
	# already counted out of the cells it took.
	var lat: AnatomyLattice = grid.lattice if grid.lattice != null \
		and grid.lattice.count > 0 else null
	if lat != null:
		lat.refresh_damage(grid)
	if lat != null:
		var gone: int = lat.built_total - lat.standing_total
		_note.text = "%d CELLS OUT OF %d" % [gone, lat.built_total] if gone > 0 \
			else "LATTICE %d CELLS" % lat.built_total
	else:
		_note.text = "LATTICE %d CELLS" % grid.cell_count()

	# What the animal is made of, and what that adds up to. Mass is quoted beside
	# the shares because a share is of something: a lean creature and a fat one can
	# read the same percentage of muscle and not be the same animal at all.
	var shares := PackedFloat32Array()
	for tissue_kind in COMPOSITION:
		shares.append(lat.mass_share(tissue_kind) if lat != null else 0.0)
	_composition.set_segments(shares, COMPOSITION_INKS)
	_mass.text = "MASS %.2f" % each.physique.mass

	for index in _rows.size():
		var row: Dictionary = ROWS[index]
		var layer: int = int(row["layer"])
		var meter: Meter = _rows[index]["meter"]
		var value: Label = _rows[index]["value"]
		if layer >= 0:
			# The bar is how many of that tissue's cells are still standing; the
			# number beside it is how much of the creature's weight that tissue
			# currently *is*. Two different questions about the same tissue, and
			# the panel is worth having because they come apart — a limb torn off
			# takes muscle and skin with it and leaves the body a larger fraction
			# bone than it started.
			if lat != null:
				meter.set_bar(float(lat.tissue_cells(layer)) \
					/ maxf(float(lat.tissue_built(layer)), 1.0), row["ink"])
				value.text = "%d%%" % int(round(lat.mass_share(layer) * 100.0))
			else:
				meter.set_bar(grid.layer_left(layer), row["ink"])
				value.text = "%d%%" % int(round(grid.layer_share(layer) * 100.0))
		else:
			var network: AnatomyNetwork = state.vessels if index == VESSELS_ROW \
				else state.nerves
			meter.set_bar(_mean_delivery(network), row["ink"])
			var cut: int = network.cut_off()
			value.text = "SOUND" if cut == 0 else "%d CUT" % cut

	var head: BodyState.Region = state.region(BodyPlan.HEAD)
	_set_vital(BRAIN_VITAL, state.consciousness,
		_brain_word(state, grid.organ(BodyPlan.BRAIN), head), CreatureView.COL_DBG_NERVE)
	_set_vital(HEART_VITAL, state.circulation,
		_heart_word(state, grid.organ(BodyPlan.HEART)), CreatureView.COL_DBG_VESSEL)
	_set_vital(BLOOD_VITAL, state.blood, _blood_word(state), CreatureView.COL_DBG_VESSEL)


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


## What the brain is doing, and — when it is not doing it — which of the two ways
## it can fail is the one happening.
##
## An organ torn open and an organ perfectly intact in a head with no blood
## reaching it produce the same fall in consciousness out of the same brain, and
## they are not remotely the same injury. The whole reason this panel says
## STARVED rather than a number is that the number cannot tell them apart.
static func _brain_word(state: BodyState, brain: float, head: BodyState.Region) -> String:
	if state.collapsed:
		return "OUT"
	if state.consciousness < FAINT:
		return "FAINT"
	if brain < DIM:
		return "TORN"
	if head != null and head.vitality < DIM:
		return "STARVED"
	return "DULLED" if state.consciousness < BodyState.NOMINAL else "ALERT"


static func _heart_word(state: BodyState, heart: float) -> String:
	if state.circulation <= BodyState.COLLAPSE:
		return "STOPPED"
	if heart < DIM:
		return "TORN"
	if state.circulation < FAILING:
		return "FAILING"
	return "WEAK" if state.circulation < BodyState.NOMINAL else "STEADY"


## Blood is the one place a rate is worth more than a state, because it is the
## reading that says what is about to happen rather than what has happened: a
## creature at full reserve losing it fast is in more trouble than one sitting at
## half and holding.
static func _blood_word(state: BodyState) -> String:
	if state.bleeding > BodyState.CLOT_THRESHOLD:
		return "LOSING %.2f/S" % state.bleeding
	return "SEALED" if state.blood < 0.999 else "FULL"


## Where the eye has got to. Roll is only named once there is some — it is the one
## of the three that cannot be asked for, so on a specimen nobody has turned over
## it would be a reading of nothing.
func _orbit_word() -> String:
	if view == null:
		return ""
	var roll: float = view.roll
	if not view.orbited() and absf(roll) < LEVEL:
		return "TOP DOWN · DRAG TO TURN"
	var word: String = "SPIN %d° · TILT %+d°" % [
		int(round(rad_to_deg(view.spin))), int(round(rad_to_deg(view.tilt)))]
	if absf(roll) >= LEVEL:
		word += " · ROLL %+d°" % int(round(rad_to_deg(roll)))
	return word + " · DOUBLE-CLICK RESETS"


func _blank() -> void:
	_status.text = "—"
	_note.text = "NO SPECIMEN"
	_mass.text = "—"
	_integrity.set_bar(0.0, Color(INK, 0.30))
	_composition.set_segments(PackedFloat32Array(), PackedColorArray())
	for row in _rows:
		(row["meter"] as Meter).set_bar(0.0, Color(INK, 0.30))
		(row["value"] as Label).text = "—"
	for index in _vitals.size():
		_set_vital(index, 0.0, "—", Color(INK, 0.30))


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
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_status)
	# The whole animal's condition, as a length. It was a number here for as long
	# as there was only one of them; there are eleven now, and eleven numbers is a
	# table to be read rather than a body to be glanced at.
	_integrity = Meter.new(HEAD_METER, 4.0)
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

	# Where the eye is, and how to move it. It reads as an instruction until the
	# specimen has been turned once and as a coordinate afterwards, which is the
	# only moment either of those is the useful thing to say.
	_orbit = _label("", 8, _mono_tracked, Color(INK, 0.30))
	_orbit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_orbit.offset_left = 13.0
	_orbit.offset_top = -21.0
	_orbit.offset_bottom = -9.0
	_stage.add_child(_orbit)
	return section


func _build_layers() -> Control:
	var section := _section(17.0, 11.0, 12.0, true)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	section.add_child(column)

	var caption := HBoxContainer.new()
	caption.add_theme_constant_override("separation", 8)
	caption.add_child(_label("TISSUE · SHARE OF BODY MASS", 8, _sans_tracked, Color(INK, 0.38)))
	caption.add_child(_spacer())
	_mass = _label("—", 9, _mono, Color(INK, 0.58))
	caption.add_child(_mass)
	column.add_child(caption)

	# The body's whole composition in one length, striped in the same inks the
	# rows and the specimen are drawn in, so a build reads before any number does.
	_composition = Meter.new(0.0, 5.0)
	_composition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_composition)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)

	for index in ROWS.size():
		var row: Dictionary = ROWS[index]
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = 21.0
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_constant_override("separation", 7)
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
		var meter := Meter.new(ROW_METER, 3.0)
		line.add_child(meter)
		var value := _label("—", 9, _mono, Color(INK, 0.58))
		value.custom_minimum_size.x = 40.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)

		_rows.append({"line": line, "swatch": swatch, "meter": meter, "value": value})

	column.add_child(_build_inspect())
	return section


## The ways inside the specimen that are not a peel: the section plane that
## carves the lattice along one of its own axes, and the X-ray that thins every
## cell to a film. Both are subtractions from the same cells, so what they show
## is always what is genuinely there.
func _build_inspect() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 22.0
	row.add_theme_constant_override("separation", 6)

	row.add_child(_label("SECTION", 8, _sans_tracked, Color(INK, 0.38)))
	for entry in SLICES:
		var chip := Button.new()
		chip.text = str(entry["label"])
		chip.flat = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_override("font", _mono_tracked)
		chip.add_theme_font_size_override("font_size", 8)
		chip.pressed.connect(_on_slice_pressed.bind(int(entry["axis"])))
		row.add_child(chip)
		_slice_chips.append({"chip": chip, "axis": int(entry["axis"])})

	_slice_slider = HSlider.new()
	_slice_slider.min_value = 0.0
	_slice_slider.max_value = 1.0
	_slice_slider.step = 0.01
	_slice_slider.value = 1.0
	_slice_slider.custom_minimum_size = Vector2(52.0, 14.0)
	_slice_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slice_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slice_slider.focus_mode = Control.FOCUS_NONE
	_slice_slider.value_changed.connect(_on_slice_moved)
	row.add_child(_slice_slider)

	var xray := Button.new()
	xray.text = "X-RAY"
	xray.flat = true
	xray.focus_mode = Control.FOCUS_NONE
	xray.add_theme_font_override("font", _mono_tracked)
	xray.add_theme_font_size_override("font_size", 8)
	xray.pressed.connect(_on_xray_pressed)
	row.add_child(xray)
	_xray_chip = xray

	_style_inspect()
	return row


func _on_slice_pressed(axis: int) -> void:
	view.slice_axis = axis if view.slice_axis != axis or axis < 0 else AnatomyView.SLICE_OFF
	if view.slice_axis >= 0 and view.slice_at >= 0.999:
		# A plane parked past the end of the animal sections nothing; arriving on
		# a fresh axis, start midway through the body so the click shows a cut.
		view.slice_at = 0.5
		_slice_slider.set_value_no_signal(0.5)
	_style_inspect()


func _on_slice_moved(value: float) -> void:
	view.slice_at = clampf(value, 0.0, 1.0)


func _on_xray_pressed() -> void:
	view.xray = not view.xray
	_style_inspect()


func _style_inspect() -> void:
	for entry in _slice_chips:
		var on: bool = view != null and view.slice_axis == int(entry["axis"]) \
			and int(entry["axis"]) >= 0
		var off_axis: bool = int(entry["axis"]) < 0 \
			and (view == null or view.slice_axis < 0)
		var chip: Button = entry["chip"]
		chip.add_theme_color_override("font_color",
			INK if on or off_axis else Color(INK, 0.40))
		chip.add_theme_color_override("font_hover_color", INK)
		chip.add_theme_stylebox_override("normal", _chip_style(0.40 if on else 0.13))
		chip.add_theme_stylebox_override("hover", _chip_style(0.40))
		chip.add_theme_stylebox_override("pressed", _chip_style(0.55))
	if _xray_chip != null:
		var lit: bool = view != null and view.xray
		(_xray_chip as Button).add_theme_color_override("font_color",
			INK if lit else Color(INK, 0.40))
		(_xray_chip as Button).add_theme_stylebox_override("normal",
			_chip_style(0.40 if lit else 0.13))


## The organs, and the blood that decides what either of them is worth.
##
## Each is one line: what it is, a bar of what it is actually *delivering*, and a
## word for the condition it is in. The bar and the word are deliberately about
## different things — an intact heart in an animal that has bled out reads STEADY
## on a bar that is nearly empty, and that pair is the whole story of that death.
func _build_vitals() -> Control:
	var section := _section(17.0, 12.0, 13.0, true)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	section.add_child(column)
	column.add_child(_label("ORGANS", 8, _sans_tracked, Color(INK, 0.38)))

	for title in ["Brain", "Heart", "Blood"]:
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = 15.0
		line.add_theme_constant_override("separation", 8)
		column.add_child(line)

		var name_label := _label(str(title), 11, _sans, INK)
		name_label.custom_minimum_size.x = VITAL_NAME
		line.add_child(name_label)
		var meter := Meter.new(0.0, 3.0)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(meter)
		var word := _label("—", 8, _mono_tracked, Color(INK, 0.42))
		word.custom_minimum_size.x = VITAL_WORD
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(word)

		_vitals.append({"meter": meter, "word": word})
	return section


func _build_footer() -> Control:
	var section := _section(17.0, 10.0, 11.0, false)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 22.0
	row.add_theme_constant_override("separation", 10)
	section.add_child(row)

	_readout = _label("HOVER A CELL · RIGHT-CLICK A TISSUE TO ISOLATE", 9, _mono, Color(INK, 0.34))
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
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_solo(index)
		_sync_toggles()
		accept_event()
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
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


## Right-click a tissue to see it alone — the skeleton by itself, the vessels
## by themselves — and right-click again to put the body back as it stood.
func _toggle_solo(index: int) -> void:
	if _solo_row == index:
		view.layers = _before_solo >> 2
		view.show_vessels = (_before_solo & 1) != 0
		view.show_nerves = (_before_solo & 2) != 0
		_solo_row = -1
		_before_solo = -1
		return
	if _solo_row < 0:
		_before_solo = (view.layers << 2) \
			| (2 if view.show_nerves else 0) | (1 if view.show_vessels else 0)
	_solo_row = index
	var layer: int = int(ROWS[index]["layer"])
	view.layers = (1 << layer) if layer >= 0 else 0
	view.show_vessels = layer < 0 and index == VESSELS_ROW
	view.show_nerves = layer < 0 and index == NERVES_ROW


func _on_cell_hovered(readout: String, alarm: bool) -> void:
	if readout.is_empty():
		_readout.text = "HOVER A CELL · RIGHT-CLICK A TISSUE TO ISOLATE"
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


## A vital reads nominal or it reads as itself: the bar and the word both go quiet
## while nothing is wrong, so anything coloured on this panel is something to look
## at rather than the panel's ordinary appearance.
func _set_vital(index: int, value: float, word: String, ink: Color) -> void:
	var vital: Dictionary = _vitals[index]
	var nominal: bool = value >= BodyState.NOMINAL
	(vital["meter"] as Meter).set_bar(value, Color(INK, 0.45) if nominal else ink)
	var label: Label = vital["word"]
	label.text = word
	label.add_theme_color_override("font_color", Color(INK, 0.42) if nominal else ink)


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
