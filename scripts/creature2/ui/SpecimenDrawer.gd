## The Anatomy drawer: a specimen you can walk around, what the animal is built
## out of, and what state the build is in — AnatomyPanel ported onto the v2
## census (docs/V2_DESIGN.md §8).
##
## Every readout is taken live off `Corpus`, which is the animal's one census, so
## the panel cannot drift out of step with the body it describes. There is no
## anatomy model behind this file; there is the creature's, read from. What
## changed in the port is only where the numbers come from: v1 counted cells of a
## lattice, and this sums the census's own wedge-shell volumes — the same two
## questions per tissue, asked of the thing that now answers them.
##
## v1's two rules about how it says things are kept, and both are about scanning
## rather than taste. Anything that is a *proportion* is drawn as a bar, because
## the eye reads a length faster than a number and a row of bars can be taken in
## at once; and nothing is printed that reads "100%" on a healthy animal, because
## a panel full of hundreds is a panel that has to be searched for the one number
## that moved. What is printed instead is what the reading *means* — a share of
## the body's weight, a word for the state the frame is in.
##
## It is a drawer, not a page: it stands in the shared right-hand dock at its own
## width, so the field and the moving animal stay visible beside it, and the
## camera pays for the column it takes — see HudDock and LabHUD.field_shift.
class_name SpecimenDrawer
extends PanelContainer

const PAPER := Color("f3f1ec")
const INK := Color("14140f")

## The depth stack, plus the two networks laid through it, in the order a bite
## goes down through them. `layer` is -1 for the networks, which are not part of
## the stack and are toggled on the view instead.
const ROWS: Array[Dictionary] = [
	{"name": "Skin", "layer": BodySchema.Layer.SKIN, "ink": SpecimenStage.COL_HIDE},
	{"name": "Fat", "layer": BodySchema.Layer.FAT, "ink": SpecimenStage.COL_FAT},
	{"name": "Muscle", "layer": BodySchema.Layer.MUSCLE, "ink": SpecimenStage.COL_MUSCLE},
	{"name": "Skeleton", "layer": BodySchema.Layer.BONE, "ink": SpecimenStage.COL_BONE},
	{"name": "Vessels", "layer": -1, "ink": SpecimenStage.COL_VESSEL},
	{"name": "Nerves", "layer": -1, "ink": SpecimenStage.COL_NERVE},
]
const VESSELS_ROW: int = 4
const NERVES_ROW: int = 5

## The composition bar's stripes, outside-in — the order the peel lifts them off,
## so the bar and the rows under it read as one statement about a depth stack.
const COMPOSITION: Array[int] = [
	BodySchema.Layer.SKIN, BodySchema.Layer.FAT,
	BodySchema.Layer.MUSCLE, BodySchema.Layer.BONE,
]
## Not a `const`: a packed array is built by a constructor, which is one step
## more than a constant expression is allowed to be.
static var COMPOSITION_INKS := PackedColorArray([
	SpecimenStage.COL_HIDE, SpecimenStage.COL_FAT,
	SpecimenStage.COL_MUSCLE, SpecimenStage.COL_BONE,
])

## The section chips, in canonical-axis order with OFF in front.
const SLICES: Array[Dictionary] = [
	{"label": "OFF", "axis": SpecimenStage.SLICE_OFF},
	{"label": "LONG", "axis": SpecimenStage.SLICE_LONG},
	{"label": "SIDE", "axis": SpecimenStage.SLICE_SIDE},
	{"label": "FLAT", "axis": SpecimenStage.SLICE_FLAT},
]

const MUSCLE_ROW: int = 0
const FRAME_ROW: int = 1
const WEIGHT_ROW: int = 2

## Reading below which a body has visibly given ground.
const DIM: float = 0.98
## Stick error past which the solver is not holding the skeleton it was given.
## The armature's own tolerance, quoted as the thing it is a tolerance on.
const SLACK: float = 0.05

const WIDTH: float = 378.0
## What the stage would like, and what it will shrink to on a short window. A
## floor and not a ceiling: the stage is the one section of the drawer that
## expands, so on a tall window everything the rest of the column does not want
## goes to the specimen.
const STAGE_HEIGHT: float = 326.0
const STAGE_MIN_HEIGHT: float = 120.0

const ROW_METER: float = 42.0
const HEAD_METER: float = 96.0
const VITAL_NAME: float = 58.0
const VITAL_WORD: float = 106.0


## A bar, and the only way this panel states a proportion.
##
## One segment for a condition reading, several for a composition — the same
## control either way, because a stacked bar is a bar whose track happens to be
## shared. Nothing here knows what it is measuring: it is given fractions and
## inks.
class Meter extends Control:
	const TRACK := Color(SpecimenDrawer.INK, 0.10)
	## Hairline between neighbouring segments, so a stripe of skin between the
	## fat and the muscle is still legible as its own share.
	const GAP: float = 1.0

	var values: PackedFloat32Array = PackedFloat32Array([0.0])
	var inks: PackedColorArray = PackedColorArray([SpecimenDrawer.INK])
	var thickness: float = 3.0
	## A row that has no proportion to state draws no track at all. An empty bar
	## beside four full ones reads as a reading of zero, and a full one beside them
	## reads as a proportion — so a row whose answer is a count keeps its column and
	## leaves the ink to the rows that are measuring something.
	var blank: bool = false

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
		if blank:
			return
		var top: float = (size.y - thickness) * 0.5
		draw_rect(Rect2(0.0, top, size.x, thickness), TRACK)
		var at: float = 0.0
		var stacked: bool = values.size() > 1
		for i in values.size():
			var span: float = size.x * clampf(values[i], 0.0, 1.0)
			if span > 0.0:
				draw_rect(Rect2(at, top, maxf(span - (GAP if stacked else 0.0), 0.5), thickness),
					inks[i] if i < inks.size() else SpecimenDrawer.INK)
			at += span


var view: SpecimenStage
var subject: Creature2

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _status: Label
var _integrity: Meter
var _mass: Label
var _composition: Meter
var _note: Label
var _orbit: Label
var _readout: Label
var _stage: Control
var _chip_row: GridContainer
var _rows: Array[Dictionary] = []
var _vitals: Array[Dictionary] = []
var _chips: Array[Dictionary] = []
var _slice_chips: Array[Dictionary] = []
var _slice_slider: HSlider
var _xray_chip: Button
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
	root.add_child(_build_frame_block())
	root.add_child(_build_footer())
	view.set_ui_font(_mono)
	view.creature = subject
	_sync_toggles()
	_build_chips()
	refresh()


## Whose body is on the slab. There is one in the lab, and the panel still asks
## rather than assuming: a drawer that reached for a global would be a second
## opinion about which animal is being played.
##
## The chips are rebuilt here rather than only at `_ready`, because the drawer is
## built before it is told what it is looking at and the chains it offers to
## isolate are the census's — a body swapped in is a different set of them.
func set_subject(each: Creature2) -> void:
	subject = each
	if view != null:
		view.creature = each
		view.focus = &""
		view.reset_fit()
	if _chip_row != null:
		_build_chips()


## How wide a column the drawer takes in the dock — see HudDock, which is where
## every drawer's rect is decided and what the field asks how much of the window
## it has lost.
func dock_width() -> float:
	return WIDTH


## Told how tall the dock is. Shrinks the specimen stage to whatever a short
## window has left over, so the readouts under it are never pushed off the
## screen; on a window with room to spare there is nothing to do, because the
## stage is the drawer's one expanding section and already has it.
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
	_orbit.text = _orbit_word()
	if subject == null or subject.corpus == null or subject.corpus.columns == 0:
		_blank()
		return

	var corpus: Corpus = subject.corpus
	var integrity: float = corpus.integrity()
	_status.text = _status_word(integrity)
	_integrity.set_bar(integrity, INK if integrity >= DIM else SpecimenStage.COL_VESSEL)

	# What the census is, and what has been taken out of it. A cell count is the
	# resolution of the body rather than its size — it does not move with the
	# animal, which is the v2 claim worth being able to see on the drawer.
	if integrity < 0.999:
		_note.text = "%.1f%% OF TISSUE GONE" % ((1.0 - integrity) * 100.0)
	else:
		_note.text = "CENSUS %d COLUMNS · %d CELLS" % [corpus.columns, corpus.columns * 4]

	# What the animal is made of, and what that adds up to. Mass is quoted beside
	# the shares because a share is of something: a lean creature and a fat one
	# can read the same percentage of muscle and not be the same animal at all.
	var shares := PackedFloat32Array()
	for layer in COMPOSITION:
		shares.append(corpus.layer_mass_share(layer))
	_composition.set_segments(shares, COMPOSITION_INKS)
	_mass.text = "MASS %.0f" % corpus.mass()

	for index in _rows.size():
		var row: Dictionary = ROWS[index]
		var layer: int = int(row["layer"])
		var meter: Meter = _rows[index]["meter"]
		var value: Label = _rows[index]["value"]
		if layer >= 0:
			# The bar is how much of that tissue is still standing; the number
			# beside it is how much of the creature's weight that tissue
			# currently *is*. Two different questions about one tissue, and the
			# panel is worth having because they come apart — a limb chewed off
			# takes muscle and skin and leaves the body a larger fraction bone
			# than it started.
			meter.set_bar(corpus.layer_standing(layer), row["ink"])
			value.text = "%d%%" % int(round(corpus.layer_mass_share(layer) * 100.0))
		else:
			# The networks are authored geometry rather than cells (§6): nothing
			# is delivered along them until Phase 5 walks a wound into one, so
			# there is no proportion to state and the row states a count instead.
			# v1's bar here was mean delivery, and printing a full one in its
			# place would be inventing a reading rather than porting one.
			var runs: int = _count_features("vessel" if index == VESSELS_ROW else "nerve")
			value.text = "%d RUNS" % runs if runs != 1 else "1 RUN"

	# What the build is doing, under the tissue: whether the muscle is answering,
	# whether the solver is holding the skeleton it was given, and where the
	# weight has ended up. Three different failures, and none of them is visible
	# in a silhouette.
	var muscle: float = corpus.layer_standing(BodySchema.Layer.MUSCLE)
	_set_vital(MUSCLE_ROW, muscle,
		"ANSWERING" if muscle >= DIM else "%d%% SPENT" % int(round((1.0 - muscle) * 100.0)),
		SpecimenStage.COL_MUSCLE)

	var slack: float = subject.armature.worst_bone_error()
	_set_vital(FRAME_ROW, clampf(1.0 - slack / maxf(SLACK * 4.0, 0.001), 0.0, 1.0),
		"EXACT" if slack <= SLACK else "%.2f PX OUT" % slack,
		SpecimenStage.COL_VESSEL)

	var along: float = corpus.along()
	_set_vital(WEIGHT_ROW, clampf(along, 0.0, 1.0),
		"%d%% ALONG · %d PX UP" % [int(round(along * 100.0)), int(round(corpus.com().z))],
		Color(INK, 0.55))


## Wording taken from the body rather than from a flag. v2 has no death yet —
## Phase 5 owns arrest — so the one state above the tissue reading is the one the
## armature genuinely has: a body that has been put down.
func _status_word(integrity: float) -> String:
	if subject.armature.collapsed:
		return "Collapsed"
	if integrity >= 0.95:
		return "Intact"
	if integrity >= 0.82:
		return "Wounded"
	return "Impaired" if integrity >= 0.6 else "Critical"


func _count_features(kind: String) -> int:
	var n: int = 0
	for f: Dictionary in subject.body.features:
		if str(f.get("feature", "")) == kind:
			n += 1
	return n


## Where the eye has got to. It reads as an instruction until the specimen has
## been turned once and as a coordinate afterwards, which is the only moment
## either of those is the useful thing to say.
func _orbit_word() -> String:
	if view == null:
		return ""
	if view.at_default_orbit():
		return "THREE-QUARTER · DRAG TO TURN · WHEEL TO ZOOM"
	var word: String = "BEARING %d° · ELEVATION %+d°" % [
		int(round(rad_to_deg(view.bearing()))), int(round(rad_to_deg(view.elevation())))]
	# Only once the wheel has been turned. On a specimen sitting at its own fit
	# "1.0×" would be a reading of nothing.
	if not is_equal_approx(view.zoom, 1.0):
		word += " · %.1f×" % view.zoom
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


# ---------------------------------------------------------------- layout ----

func _place() -> void:
	HudDock.place(self, WIDTH)
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
	# The whole animal's condition, as a length.
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

	view = SpecimenStage.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.cell_hovered.connect(_on_cell_hovered)
	_stage.add_child(view)

	_note = _label("CENSUS", 8, _mono_tracked, Color(INK, 0.34))
	_note.position = Vector2(13.0, 11.0)
	_stage.add_child(_note)

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
		var layer: int = int(row["layer"])
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
		# The networks are not a proportion of anything the census can weigh — see
		# `refresh` — so they keep the column and draw no track in it.
		meter.blank = layer < 0
		line.add_child(meter)
		var value := _label("—", 9, _mono, Color(INK, 0.58))
		value.custom_minimum_size.x = 44.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)

		_rows.append({"line": line, "swatch": swatch, "meter": meter, "value": value})

	column.add_child(_build_inspect())
	return section


## The ways inside the specimen that are not a peel: the section plane that
## carves the body on one of its own axes, and the X-ray that thins every facet
## to a film. Both are subtractions from the same cells, so what they show is
## always what is genuinely there.
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


## What the tissue is standing on: the muscle that answers, the frame that holds
## it and the weight it ends up carrying.
##
## Each is one line — what it is, a bar of what it is delivering, and a word for
## the condition it is in — the shape v1's organ block had, because the question
## is the same shape: is this part of the body doing its job, and if not, which
## of the ways it can fail is the one happening.
func _build_frame_block() -> Control:
	var section := _section(17.0, 12.0, 13.0, true)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	section.add_child(column)
	column.add_child(_label("BUILD", 8, _sans_tracked, Color(INK, 0.38)))

	for title in ["Muscle", "Frame", "Weight"]:
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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	section.add_child(column)

	_readout = _label("HOVER A CELL · RIGHT-CLICK A TISSUE TO ISOLATE", 9, _mono, Color(INK, 0.34))
	_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_readout.custom_minimum_size.y = 16.0
	_readout.clip_text = true
	_readout.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_readout)

	# The chains of the census, so one of them can be held up on its own. The
	# rest of the body stays on the slab at a whisper rather than vanishing: a
	# tail with no cat around it is not a diagnosis of anything.
	_chip_row = GridContainer.new()
	_chip_row.columns = 4
	_chip_row.add_theme_constant_override("h_separation", 3)
	_chip_row.add_theme_constant_override("v_separation", 3)
	column.add_child(_chip_row)
	return section


func _build_chips() -> void:
	if _chip_row == null:
		return
	for entry in _chips:
		var old: Button = entry["chip"]
		_chip_row.remove_child(old)
		old.queue_free()
	_chips.clear()
	if subject == null or subject.corpus == null:
		return
	var names: Array[StringName] = [&""]
	for chain in subject.corpus.chains:
		names.append(chain.name)
	for name in names:
		var chip := Button.new()
		chip.text = "WHOLE" if name.is_empty() else str(name).to_upper()
		chip.flat = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size.y = 19.0
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_override("font", _mono_tracked)
		chip.add_theme_font_size_override("font_size", 8)
		chip.pressed.connect(_on_focus_pressed.bind(name))
		_chip_row.add_child(chip)
		_chips.append({"chip": chip, "name": name})
	_style_chips()


# --------------------------------------------------------------- reaction ----

func _on_focus_pressed(name: StringName) -> void:
	view.focus = &"" if view.focus == name else name
	_style_chips()


func _on_slice_pressed(axis: int) -> void:
	view.slice_axis = axis if view.slice_axis != axis or axis < 0 else SpecimenStage.SLICE_OFF
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


## The wheel anywhere on the drawer leans the specimen in and out.
##
## The stage takes it directly — see `SpecimenStage._gui_input` — and this is the
## rest of the panel doing the same, because a drawer whose animal only answers
## the wheel over some of its own surface is a drawer the player has to aim at.
## The section slider is the one thing that keeps its own wheel, since a control
## under the pointer is what the pointer is on.
func _gui_input(event: InputEvent) -> void:
	var turn := event as InputEventMouseButton
	if turn == null or not turn.pressed or view == null:
		return
	if turn.button_index != MOUSE_BUTTON_WHEEL_UP \
			and turn.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	view.set_zoom(view.zoom * (SpecimenStage.ZOOM_STEP
		if turn.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / SpecimenStage.ZOOM_STEP))
	accept_event()


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


## Right-click a tissue to see it alone — the skeleton by itself, the vessels by
## themselves — and right-click again to put the body back as it stood.
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
	# A peel is a stack, so isolating one tissue is showing everything under it
	# and nothing over it — the skeleton alone is the bone radius, not a bone
	# shell floating where the skin used to be.
	view.layers = ((1 << (layer + 1)) - 1) if layer >= 0 else 0
	view.show_vessels = layer < 0 and index == VESSELS_ROW
	view.show_nerves = layer < 0 and index == NERVES_ROW


func _on_cell_hovered(readout: String, alarm: bool) -> void:
	if readout.is_empty():
		_readout.text = "HOVER A CELL · RIGHT-CLICK A TISSUE TO ISOLATE"
		_readout.add_theme_color_override("font_color", Color(INK, 0.34))
		return
	_readout.text = readout
	_readout.add_theme_color_override("font_color",
		SpecimenStage.COL_VESSEL if alarm else Color(INK, 0.58))


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
		_xray_chip.add_theme_color_override("font_color", INK if lit else Color(INK, 0.40))
		_xray_chip.add_theme_stylebox_override("normal", _chip_style(0.40 if lit else 0.13))


func _style_chips() -> void:
	for entry in _chips:
		var chip: Button = entry["chip"]
		var selected: bool = view != null and view.focus == entry["name"]
		chip.add_theme_color_override("font_color", INK if selected else Color(INK, 0.40))
		chip.add_theme_color_override("font_hover_color", INK)
		chip.add_theme_stylebox_override("normal", _chip_style(0.40 if selected else 0.13))
		chip.add_theme_stylebox_override("hover", _chip_style(0.40))
		chip.add_theme_stylebox_override("pressed", _chip_style(0.55))


## A reading goes quiet while nothing is wrong, so anything coloured on this
## panel is something to look at rather than the panel's ordinary appearance.
func _set_vital(index: int, value: float, word: String, ink: Color) -> void:
	var vital: Dictionary = _vitals[index]
	var nominal: bool = value >= DIM
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
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
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
