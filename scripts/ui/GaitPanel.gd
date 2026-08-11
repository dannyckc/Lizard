## The Gait tab: the animal's walk, measured while it happens.
##
## Built from the "Gait HUD" design handoff, and connected the way the design
## asked to be implemented rather than the way it was mocked: the mock carries a
## table of six creatures and their gaits re-typed into JavaScript, and this
## panel carries none of it. Every readout is a measurement the simulation has
## just taken of the body being played — the footfall pattern off `Footfall`, the
## duty and the cycle off `Gait`, the joints and their levers off `Articulation`,
## the launch off `Leap` — so the panel cannot say anything the animal is not
## actually doing. Drive the creature and the numbers move; swap the species and
## the same readouts describe the new body.
##
## Three instruments, as the design lays them out:
##
##   * the figure — a true side elevation of the solved skeleton, across the top.
##     The limb chains are the actual `plan`/`heights` FABRIK just produced,
##     projected along the body's own axis, so a folding knee here is the knee
##     folding in the world and a leap here is the body genuinely off the floor;
##     nothing is re-animated for the panel. The wheel leans in on it, on the
##     anatomy drawer's own terms.
##   * the footfall chart — one cycle, one row per bearing limb, each bar at the
##     phase the pattern holds that foot to, red while the real foot is down.
##   * the readouts — the pattern in Hildebrand's numbers: Froude, girdle lag,
##     the two splits, duty, lift and cycle, plus the machine underneath them:
##     what angle each girdle carries its joint at and what its tendon lever
##     gears the muscle to.
##
## The panel is a column in the right-hand dock, under the view buttons and
## beside the anatomy drawer's own column — see HudDock, which is where both of
## their rects are decided. Everything on it is a length and the column is not,
## so the three instruments are stacked down it in the order they are read and
## each is given the whole width: the figure across the top, the chart of one
## cycle under the caption, and the two readout blocks side by side beneath that.
## It is a wider column than the anatomy drawer's, for the one reason a column is
## ever widened — an elevation of a long-tailed animal and a whole cycle laid out
## along an axis are both as wide as they are allowed to be, and neither can be
## folded.
##
## The figure takes the height the fixed bands do not want, which is the anatomy
## drawer's rule for its specimen stage and lands the animal on about the same
## half of the drawer. The field is still beside it with the walk happening in
## it — the world slides the animal into the middle of what the dock has left, so
## the thing being measured and the measurement of it are both in view.
class_name GaitPanel
extends Control

signal species_selected(preset_name: String)

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
const RED := Color("8e1b12")

## How long a footfall ring is left ringing, and how many are kept.
const RING_LIFE: float = 0.6
const RING_MAX: int = 40
## How many recent foot positions a trail keeps.
const TRAIL_MAX: int = 70
## World spacing of the ground ticks the figure scrolls against.
const TICK_SPACING: float = 56.0

## Below this share of flat out, the animal is standing and the cycle readouts
## say so rather than quoting the last walk it took.
const IDLE_PACE: float = 0.03

# --- the drawer's rect ---------------------------------------------------------
## The column the drawer takes in the dock. Wider than the anatomy drawer's,
## which is the one thing about this panel's rect that is its own rather than
## HudDock's: the figure and the chart are both lengths and a column is what they
## have least of.
const WIDTH: float = 500.0
const PAD: float = 18.0
## The gap between the two readout blocks, and how much of the pair the left one
## takes. Not down the middle: the pattern block's values are words and the
## machine block's are strings of numbers.
const GUTTER: float = 22.0
const PATTERN_SHARE: float = 0.52

## Vertical bands, top to bottom. Everything but the figure is fixed at what its
## own contents come to; the figure takes what is left, and it is the one that
## gives ground on a short window.
const HEADER_H: float = 26.0
## The species tabs, three across and two deep. Six of them, named and numbered,
## do not queue along a column this wide — they stacked this way the last time
## this panel was one.
const TAB_COLUMNS: int = 3
const TAB_H: float = 24.0
const TABS_H: float = TAB_H * 2.0
## What the figure will never be squeezed below, and the most of the drawer it may
## take when the fixed bands leave more than that.
const FIGURE_MIN: float = 96.0
const FIGURE_SHARE: float = 0.50
## Two caption lines between the ground line and the chart, and the gap under the
## chart.
const CAPTION_H: float = 24.0
const CHART_GAP: float = 12.0
## The readout rows at their pitch — the taller block is the 8 pattern rows under
## its own heading — and the footfall chart's own row pitch.
const ROW_PITCH: float = 12.0
const READOUT_ROWS: int = 8
const CHART_ROW: float = 17.0
## The legend, the note lines under it, and the paper left under them. Three
## lines rather than the band's two: the note is wrapped to a column now, and the
## longest of the sentences it composes runs to two lines on its own.
const FOOT_H: float = 57.0
const NOTE_LINES: int = 3
const TAIL: float = 5.0

# --- the figure's camera -------------------------------------------------------
## How much of the column's width the animal's own length may take, and how far
## the fit may magnify a small one. Both are margin: an elevation pressed to the
## edges of its frame is one whose nose and tail tip are the first things to go.
const FRAME_FILL: float = 0.82
const FIT_MAX: float = 1.35
## Paper kept over the top of whatever the figure needs, so a head at full height
## is not touching the tabs — and under the ground line, where the ground ticks
## and a planted toe's mark hang.
const FIG_AIR: float = 8.0
const GROUND_LIP: float = 11.0
## How much of its own leap the band stands ready for without moving.
const JUMP_ROOM: float = 0.35
## The wheel, on the anatomy drawer's terms — see AnatomyView, which owns these
## numbers; they are restated rather than imported only because a gait figure is
## not a specimen and the two could reasonably part company later.
const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 3.2
const ZOOM_STEP: float = 1.09

var subject: Creature

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _species_buttons: Dictionary = {}
var _tab_row: GridContainer
var _active_species: String = "Lizard"
var _time: float = 0.0
## Footfall rings: {at: Vector2 (world), t0: float}.
var _rings: Array[Dictionary] = []
## Per-limb trails of drawn foot positions, keyed as the limbs are.
var _trails: Dictionary = {}


var _style: StyleBoxFlat
var _stage: Stage
## How tall the figure band has come out: what the fixed bands left, capped at its
## share of the drawer. See `_span`.
var _figure_h: float = FIGURE_MIN
## How tall the dock last said it was, for the frames before the layout has caught
## up with it — see `fit_to_height`.
var _dock_h: float = 0.0


## The figure's own canvas. A child rather than a region of the panel's, and for
## the one reason a stage is ever its own node: leaning the wheel in has to be
## able to run the animal off the edges of its band without running it over the
## species tabs above and the chart below. Everything it draws it asks the panel
## for — see `_draw_stage` — so there is still one figure and one projection.
class Stage extends Control:
	var panel: GaitPanel

	func _init(owner_panel: GaitPanel) -> void:
		panel = owner_panel
		clip_contents = true
		# The wheel is the panel's, everywhere on the panel.
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		panel._draw_stage(self)


func _ready() -> void:
	_place()
	clip_contents = true
	_stage = Stage.new(self)
	_stage.name = "Figure"
	add_child(_stage)
	_build_species_tabs()
	resized.connect(_lay_out_tabs)
	_span()


## The same paper, chrome and shadow as the anatomy drawer — see
## AnatomyPanel._place — in the same dock, a column wider than its.
func _place() -> void:
	HudDock.place(self, WIDTH)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_span()

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(PAPER, 0.86)
	_style.border_color = Color(INK, 0.13)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(2)
	_style.shadow_color = Color(INK, 0.14)
	_style.shadow_size = 20
	_style.shadow_offset = Vector2(0.0, 10.0)


## How wide a column the drawer takes in the dock — see HudDock. Wider than the
## anatomy drawer's, and the field gives up that much more of the window while it
## is open.
func dock_width() -> float:
	return WIDTH


## Told how tall the dock is, the same way the anatomy drawer is. The rect itself
## is HudDock's; what this decides is how that height gets divided.
func fit_to_height(available: float) -> void:
	_dock_h = available
	_span()


## How the drawer's height is divided, and how big the animal comes out in the
## band that division leaves. Re-taken every frame it is up rather than only on a
## resize, because the chart is two rows shorter on a two-legged animal and
## swapping the species is not a resize.
func _span() -> void:
	var tall: float = size.y if size.y > 1.0 else _dock_h
	var wide: float = size.x if size.x > 1.0 else WIDTH
	# The fixed bands come to what they come to and the figure has the rest, which
	# is how the anatomy drawer spends its own column — with the difference that a
	# figure is a picture of a whole animal and past about half the drawer it stops
	# being one instrument among three. On a window too short for all of them it is
	# still the figure that gives ground, because the readings cannot be shortened
	# without being cut.
	var fixed: float = HEADER_H + TABS_H + CAPTION_H + _chart_height() + CHART_GAP \
		+ _readout_height() + FOOT_H + TAIL
	_figure_h = clampf(tall - fixed, FIGURE_MIN, maxf(tall * FIGURE_SHARE, FIGURE_MIN))
	_fit = 1.0
	if _usable():
		# What the width allows, and what the depth allows, whichever is the tighter
		# — a long-tailed animal is bound by the column's width and a tall standing
		# one by its depth, and the figure is the largest that clears both.
		var reach: Vector2 = _extent()
		var chrome: float = FIG_AIR + GROUND_LIP
		_fit = minf((wide - PAD * 2.0) * FRAME_FILL / (reach.x - reach.y), FIT_MAX)
		_fit = minf(_fit, maxf((_figure_h - chrome) / _headroom(), 0.06))
	if _stage != null:
		_stage.position = Vector2(0.0, HEADER_H + TABS_H)
		_stage.size = Vector2(wide, _figure_h)


func set_ui_fonts(sans: Font, sans_tracked: Font, mono: Font, mono_tracked: Font) -> void:
	_sans = sans
	_sans_tracked = sans_tracked
	_mono = mono
	_mono_tracked = mono_tracked
	for name in _species_buttons:
		var button: Button = _species_buttons[name]
		button.add_theme_font_override("font", _sans_tracked)


## Whose walk this is. The landing rings come off the creature's own signal, so
## a ring is a foot that really arrived rather than a phase crossing a line.
func set_subject(each: Creature) -> void:
	if subject == each:
		return
	if subject != null and is_instance_valid(subject) \
			and subject.foot_landed.is_connected(_on_foot_landed):
		subject.foot_landed.disconnect(_on_foot_landed)
	subject = each
	_rings.clear()
	_trails.clear()
	if subject != null:
		subject.foot_landed.connect(_on_foot_landed)


func set_active_species(preset_name: String) -> void:
	_active_species = preset_name
	_rings.clear()
	_trails.clear()
	_style_species_tabs()


func _on_foot_landed(at: Vector2, _intensity: float) -> void:
	if not visible:
		return
	_rings.append({"at": at, "t0": _time})
	while _rings.size() > RING_MAX:
		_rings.pop_front()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_span()
	_collect_trails()
	queue_redraw()
	_stage.queue_redraw()


## Six species, three across and two deep, spread across the column's whole
## width: a tab is a target as well as a word, and three that reach the margins
## read as one control in a way six squeezed into a row never would.
func _build_species_tabs() -> void:
	var grid := GridContainer.new()
	grid.name = "SpeciesTabs"
	grid.columns = TAB_COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 0)
	add_child(grid)
	_tab_row = grid
	var index: int = 1
	for preset_name in CreatureParams.PRESETS:
		var button := Button.new()
		button.text = "%02d  %s" % [index, str(preset_name).to_upper()]
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, TAB_H - 2.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_on_species_pressed.bind(str(preset_name)))
		grid.add_child(button)
		_species_buttons[str(preset_name)] = button
		index += 1
	_lay_out_tabs()
	_style_species_tabs()


func _lay_out_tabs() -> void:
	if _tab_row == null:
		return
	_tab_row.position = Vector2(PAD, HEADER_H)
	_tab_row.size = Vector2(maxf(size.x - PAD * 2.0, 1.0), TABS_H)


func _on_species_pressed(preset_name: String) -> void:
	species_selected.emit(preset_name)


## The wheel anywhere on the band leans the figure in and out, and a double-click
## puts it back at the fit — the anatomy drawer's two gestures, on the anatomy
## drawer's step, because the two F3 stops are one instrument and a wheel that
## means different things on each of them is one the player has to remember.
##
## Anywhere on the band rather than over the figure alone, for the reason the
## anatomy panel takes it panel-wide: an instrument whose picture only answers
## the wheel over part of its own surface is one the player has to aim at. The
## species tabs are buttons and keep their own clicks; they do not take the wheel.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_WHEEL_UP \
			or click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_zoom(zoom * (ZOOM_STEP if click.button_index == MOUSE_BUTTON_WHEEL_UP
			else 1.0 / ZOOM_STEP))
		accept_event()
		return
	if click.button_index == MOUSE_BUTTON_LEFT and click.double_click:
		set_zoom(1.0)
		accept_event()


## Leans the figure in or back. The fit the band worked out is untouched — this
## multiplies it — so leaning in cannot change what the figure is centred on.
func set_zoom(value: float) -> void:
	var want: float = clampf(value, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(want, zoom):
		return
	zoom = want
	# The trails were laid down at the old scale, so keeping them would draw the
	# last second of the walk at a size the animal is no longer being drawn at.
	_trails.clear()
	queue_redraw()
	if _stage != null:
		_stage.queue_redraw()


func _style_species_tabs() -> void:
	for name in _species_buttons:
		var button: Button = _species_buttons[name]
		var selected: bool = str(name) == _active_species
		button.add_theme_color_override("font_color", INK if selected else Color(INK, 0.42))
		button.add_theme_color_override("font_hover_color", INK if selected else Color(INK, 0.72))
		button.add_theme_color_override("font_pressed_color", INK)
		button.add_theme_stylebox_override("normal", _tab_style(selected))
		button.add_theme_stylebox_override("hover", _tab_style(selected, 0.28))
		button.add_theme_stylebox_override("pressed", _tab_style(true))


func _tab_style(selected: bool, hover_alpha: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = INK if selected else Color(INK, hover_alpha)
	style.border_width_bottom = 1
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	return style


# --- the projection -------------------------------------------------------------
# One frame for the whole figure: the body's own axis through the middle of its
# girdles, so the elevation is drawn along the animal however it is heading, and
# a world height straight up the screen. Everything the figure shows goes through
# `_to_fig` and nothing else, which is what keeps the picture a projection of the
# simulation rather than a drawing beside one.

var _centre: Vector2 = Vector2.ZERO
var _fwd: Vector2 = Vector2.RIGHT
var _fig_scale: float = 1.0
var _fig_cx: float = 400.0
var _ground_y: float = 400.0
## What the band's own width and depth allow, before the wheel. Worked out once a
## frame in `_span`, because how big the animal comes out is also what decides how
## deep the band has to be.
var _fit: float = 1.0
## How far off the floor the whole animal is this instant — see `_to_fig`.
var _lift: float = 0.0
## How far the wheel has leaned in past the fit the band worked out. Multiplies
## the scale and nothing else, exactly as the anatomy stage's does.
var zoom: float = 1.0


## The stage's own frame, taken fresh: the ground line is its bottom edge and the
## scale is the fit `_span` worked out, leaned in on by the wheel.
func _refresh_frame() -> void:
	var reach: Vector2 = _extent()
	# Every height the figure draws is a height off the ground the animal took off
	# from, so the one thing none of them carry is how far off that ground the
	# animal currently is. Added once, here, rather than at each of the dozen
	# places a height is read: a leap lifts the whole body — sockets, tucked feet,
	# head and tail together — because that is what a leap does to it. The floor
	# and the footfall rings are on the ground and stay there; they go through
	# `_to_ground`.
	_lift = maxf(subject.elevation.height, 0.0)
	_fig_scale = _fit * zoom
	_ground_y = _stage.size.y - GROUND_LIP - _slack() * 0.5
	_fig_cx = _stage.size.x * 0.5 - (reach.x + reach.y) * 0.5 * _fig_scale
	# A leap past what the band was standing ready for takes the ground down with
	# it rather than the animal down to the band. This is a camera following what
	# it is pointed at: the figure keeps the size it has had all along and the
	# floor slides out of the bottom of the frame, which is the picture a body
	# rising off it makes. Nothing is scaled by how high the animal is — a figure
	# that shrank as it went up would be reporting the jump twice and the height
	# wrongly. The caption keeps saying how far up it has got.
	var over: float = (_top() + _lift) * _fig_scale + FIG_AIR - _ground_y
	if over > 0.0:
		_ground_y += over


## The band's paper the animal is not standing in, which is split above and below
## it rather than left in one piece over its back.
##
## The band is a share of the drawer and the animal in it is whatever shape it is:
## a long flat one is fitted to the width and comes out a few fingers deep, and
## stood on the floor of a band five times that it reads as a drawing that has
## slid to the bottom of the page. Centred, the same drawing is a plate. The
## ground line goes with it — it is the animal's floor, not the band's — so the
## ticks, the toe marks and the footfall rings stay where its feet are.
func _slack() -> float:
	if not _usable():
		return 0.0
	return maxf(_stage.size.y - (_top() * _fig_scale + FIG_AIR + GROUND_LIP), 0.0)


## How far the animal reaches fore and aft of the middle of its girdles, along
## its own axis — nose past the head, tail tip behind. What the figure is fitted
## and centred on, rather than the girdle midpoint: a long-tailed body centred on
## its girdles hangs its tail off the edge of the band. Sets the frame the whole
## projection is taken in on its way past.
func _extent() -> Vector2:
	var line: Array = subject.gait.girdle_line()
	_centre = line[0]
	_fwd = line[1]
	var ahead: float = (subject.body.head.pos - _centre).dot(_fwd) \
		+ subject.body.head_radius * 2.5
	var behind: float = (subject.spine.points[subject.body.last_index] - _centre).dot(_fwd)
	return Vector2(maxf(ahead, 10.0), minf(behind, -10.0))


## How tall the animal stands, in world height: the back or the carried head,
## whichever it holds higher. What the band is deep enough for.
func _top() -> float:
	return maxf(maxf(subject.stature.stand_height(),
		subject.stature.head_height + subject.body.head_radius), 20.0)


## ...and how much air the band holds over it. A fraction of the animal's own
## jump, not the whole of it: a body that can clear several times its own height
## and is drawn small enough to prove it is a body drawn as a smudge on the ground
## line for the whole of the time it is walking. What this buys is a hop that
## happens inside a still frame; past it the ground goes down instead — see
## `_refresh_frame`, which pans rather than shrinks.
func _headroom() -> float:
	var jump: float = subject.leap.peak(1.0) if subject.leap != null else 0.0
	return _top() + clampf(jump, 0.0, _top() * JUMP_ROOM)


func _chart_height() -> float:
	var rows: int = 4 if subject != null and subject.locomotion.forelimbs_bear else 2
	return 24.0 + rows * CHART_ROW + 14.0


## The readout block under the chart: a heading, its rule, and the taller of the
## two blocks' rows. Both blocks start at the same line, so the block is as deep
## as the pattern's eight rows however few the machine has.
func _readout_height() -> float:
	return 6.0 + ROW_PITCH + 4.0 + float(READOUT_ROWS) * ROW_PITCH


## A place on the animal. `height` is off the ground it is standing on; how far
## the animal itself is off that ground is `_lift`, and it is added here so no
## caller has to remember it.
func _to_fig(world: Vector2, height: float) -> Vector2:
	return Vector2(_fig_cx + (world - _centre).dot(_fwd) * _fig_scale,
		_ground_y - (height + _lift) * _fig_scale)


## A place on the ground under it, which a leap does not move.
func _to_ground(world: Vector2) -> Vector2:
	return Vector2(_fig_cx + (world - _centre).dot(_fwd) * _fig_scale, _ground_y)


# --- the lower band ------------------------------------------------------------
# The chart and the readouts under the caption, one above the other and both the
# full width of the column. Every band below the figure is measured from here, so
# nothing downstream has an opinion about where the one above it ended.

## The foot of the figure's stage, in the panel's own coordinates rather than the
## stage's. Everything below the figure is measured down from here — the caption
## first, then the chart, then the readouts.
func _stage_bottom() -> float:
	return HEADER_H + TABS_H + _figure_h


func _lower_top() -> float:
	return _stage_bottom() + CAPTION_H


func _chart_rect() -> Rect2:
	return Rect2(PAD, _lower_top(), maxf(size.x - PAD * 2.0, 1.0), _chart_height())


## Where the readout blocks start, under the chart.
func _readout_top() -> float:
	return _lower_top() + _chart_height() + CHART_GAP


func _usable() -> bool:
	return subject != null and is_instance_valid(subject) and subject.body != null \
			and subject.gait != null and subject.gait.measured \
			and not subject.gait.limbs.is_empty()


func _idle() -> bool:
	return subject.speed_norm < IDLE_PACE and absf(subject.speed) < 2.0 \
			and not subject.gait.any_stepping()


func _collect_trails() -> void:
	if not _usable():
		return
	_refresh_frame()
	for limb in subject.gait.limbs:
		if limb.severed or limb.side > 0.0:
			continue
		var trail: PackedVector2Array = _trails.get(limb.key, PackedVector2Array())
		trail.append(_to_fig(limb.plan[2], limb.heights[2]))
		while trail.size() > TRAIL_MAX:
			trail.remove_at(0)
		_trails[limb.key] = trail


func _draw() -> void:
	# The drawer's own paper, drawn even with nothing to measure: an empty
	# instrument is still an instrument.
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	if _mono == null:
		return
	_draw_header()
	if not _usable():
		return
	# The figure is the stage's — see Stage. Everything below the ground line is
	# the panel's own paper.
	_draw_caption()
	_draw_zoom_word()
	_draw_chart()
	_draw_readouts()
	_draw_note()
	_draw_legend()


## The figure, on its own clipped canvas. Called back from Stage._draw, with the
## stage as the thing being drawn on: the projection, the frame and every line of
## the elevation still live here, so there is one figure and one place it is
## decided — the stage is the paper it is on and nothing else.
func _draw_stage(c: Control) -> void:
	if not _usable() or _mono == null:
		return
	_refresh_frame()
	_draw_ground(c)
	_draw_figure(c)
	_draw_rings(c)


## The drawer's title row: the mark, the word, and the four regimes with the
## live one marked — they are indicators, not tabs; the keys drive the animal.
func _draw_header() -> void:
	draw_rect(Rect2(PAD, 12.0, 5.0, 5.0), INK)
	var font: Font = _sans_tracked if _sans_tracked != null else _mono
	draw_string(font, Vector2(PAD + 13.0, 19.0), "GAIT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
	draw_line(Vector2(0.0, HEADER_H - 5.5), Vector2(size.x, HEADER_H - 5.5),
		Color(INK, 0.11), 1.0)
	if not _usable():
		return
	var current: String = _regime()
	var x: float = size.x - PAD
	# Five, not four: `_regime` has always been able to answer AIRBORNE and the
	# strip had nowhere to show it, so a jumping animal lit none of them.
	var labels: Array[String] = ["AIRBORNE", "LAY LOW", "RUN", "WALK", "IDLE"]
	for label in labels:
		var wide: float = _mono_tracked.get_string_size(label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		x -= wide
		var active: bool = label == current
		_text(Vector2(x, 19.0), label, 8, INK if active else Color(INK, 0.35))
		if active:
			draw_rect(Rect2(x - 9.0, 14.0, 4.0, 4.0), RED)
		x -= 17.0


## What the wheel has done to the figure, in the top corner of its own band. The
## hint until it has been turned and the reading afterwards — the same rule the
## anatomy drawer states its zoom by, because on a figure sitting at the fit the
## band worked out for it, "1.0×" is a reading of nothing.
func _draw_zoom_word() -> void:
	var at := Vector2(size.x - PAD, HEADER_H + TABS_H + 9.0)
	if is_equal_approx(zoom, 1.0):
		_text(at, "WHEEL TO ZOOM", 8, Color(INK, 0.26), false, true, true)
		return
	_text(at, "%.1f× · DOUBLE-CLICK RESETS" % zoom, 8, Color(INK, 0.40), false, true, true)


func _draw_ground(c: Control) -> void:
	c.draw_line(Vector2(0.0, _ground_y + 0.5), Vector2(c.size.x, _ground_y + 0.5),
		Color(INK, 0.30), 1.0)
	# Ticks are nailed to the world, so the ground genuinely goes by at the speed
	# the animal is covering it — and holds still under one turning on the spot.
	var along: float = _centre.dot(_fwd)
	var half: float = _fig_cx / _fig_scale + TICK_SPACING
	var world_tick: float = floor((along - half) / TICK_SPACING) * TICK_SPACING
	while world_tick < along + half:
		var x: float = _fig_cx + (world_tick - along) * _fig_scale
		if x > -10.0 and x < c.size.x + 10.0:
			c.draw_line(Vector2(x, _ground_y + 3.0), Vector2(x, _ground_y + 8.0),
				Color(INK, 0.12), 1.0)
		world_tick += TICK_SPACING


func _draw_figure(c: Control) -> void:
	var gait: Gait = subject.gait
	var stature: Stature = subject.stature
	var quad: bool = subject.locomotion.forelimbs_bear

	# Sockets, girdle by girdle: the mean of each pair's plan position, at the
	# height the gait says that pair is being held.
	var fore_mid := Vector2.ZERO
	var rear_mid := Vector2.ZERO
	var counted := Vector2.ZERO
	for limb in gait.limbs:
		if limb.severed:
			continue
		if limb.pair == Limb.FRONT:
			fore_mid += limb.plan[0]
			counted.x += 1.0
		else:
			rear_mid += limb.plan[0]
			counted.y += 1.0
	if counted.x <= 0.0 or counted.y <= 0.0:
		return
	fore_mid /= counted.x
	rear_mid /= counted.y
	var shoulder: Vector2 = _to_fig(fore_mid, gait.shoulder_height)
	var hip: Vector2 = _to_fig(rear_mid, gait.hip_height)

	# Far side first, faint — the design's depth cue, and honest: those are the
	# limbs on the other flank of the same solve.
	for limb in gait.limbs:
		if limb.severed or limb.side <= 0.0:
			continue
		_draw_limb(c, limb, false, quad)

	# The body's own depth as a soft silhouette between the girdles. Rounded off
	# at the ends so it reads as a trunk rather than a crate.
	var depth: float = maxf(stature.depth * _fig_scale * 0.6, 4.0)
	c.draw_line(hip, shoulder, Color(INK, 0.07), depth)
	c.draw_circle(hip, depth * 0.5, Color(INK, 0.07))
	c.draw_circle(shoulder, depth * 0.5, Color(INK, 0.07))

	_draw_tail(c, hip)

	# The back the two pairs of legs are holding up. Its pitch is the two heights,
	# not a pose: short arms draw it nose-down because they hold it nose-down.
	c.draw_line(hip, shoulder, Color(INK, 0.85), 1.7)

	# Neck and head, off the solved head and the measured carry height.
	var head: Vector2 = _to_fig(subject.body.head.pos, stature.head_height)
	var head_r: float = maxf(subject.body.head_radius * _fig_scale, 3.0)
	c.draw_line(shoulder, head, Color(INK, 0.85), 1.8)
	c.draw_arc(head, head_r, 0.0, TAU, 24, Color(INK, 0.85), 1.5, true)
	c.draw_circle(head + Vector2(head_r * 0.35, -head_r * 0.2), 1.6, INK)
	c.draw_line(head + Vector2(head_r * 0.7, head_r * 0.15),
		head + Vector2(head_r * 0.7 + head_r, head_r * 0.35), Color(INK, 0.85), 2.0)

	for trail_key in _trails:
		var trail: PackedVector2Array = _trails[trail_key]
		if trail.size() > 2:
			c.draw_polyline(trail, Color(INK, 0.09), 1.0)

	# Near side over the top, bold.
	for limb in gait.limbs:
		if limb.severed or limb.side > 0.0:
			continue
		_draw_limb(c, limb, true, quad)


## One limb, exactly as FABRIK left it: socket, joint, foot through the shared
## projection, with the fold the chain actually has. `quad` says whether the
## forelimbs bear; on a two-legged build they draw as carried arms.
func _draw_limb(c: Control, limb: Limb, near: bool, quad: bool) -> void:
	var arm: bool = limb.pair == Limb.FRONT and not quad
	var alpha: float = (0.7 if arm else 0.9) if near else 0.30
	var ink := Color(INK, alpha)
	var width: float = (1.6 if arm else (2.2 if near else 1.8))
	var socket: Vector2 = _to_fig(limb.plan[0], limb.heights[0])
	var joint: Vector2 = _to_fig(limb.plan[1], limb.heights[1])
	var foot: Vector2 = _to_fig(limb.plan[2], limb.heights[2])
	var points := PackedVector2Array([socket, joint, foot])
	c.draw_polyline(points, ink, width, true)
	c.draw_circle(joint, 2.0, ink)
	if arm:
		return
	# The toe: down and rolled onto when planted, trailed when swinging.
	var toe: float = maxf(limb.foot_size * 2.0 * _fig_scale, 2.0)
	var down: bool = not limb.stepping and limb.bearing \
			and not subject.elevation.is_airborne()
	if down:
		var toe_tip := Vector2(foot.x + toe, _to_fig(limb.planted, limb.surface).y)
		c.draw_line(foot, toe_tip, ink, width)
		var mark := Color(RED, 1.0 if near else 0.35)
		c.draw_line(Vector2(foot.x - 4.0, toe_tip.y + 4.0),
			Vector2(foot.x + toe + 4.0, toe_tip.y + 4.0), mark, 2.0)
	else:
		c.draw_line(foot, foot + Vector2(toe * 0.65, toe * 0.4), ink, width)


func _draw_tail(c: Control, hip: Vector2) -> void:
	var droop: Droop = subject.droop
	var spine: Spine = subject.spine
	var body: BodyShape = subject.body
	if droop == null or spine == null or droop.heights.is_empty():
		return
	var last: int = mini(body.last_index, mini(spine.size() - 1, droop.heights.size() - 1))
	var start: int = clampi(int(round(droop.anchor * float(last))), 0, last)
	if last - start < 1:
		return
	var previous: Vector2 = hip
	for i in range(start + 1, last + 1):
		var here: Vector2 = _to_fig(spine.points[i], droop.heights[i])
		var t: float = float(i - start) / float(maxi(last - start, 1))
		var width: float = clampf(body.widths[i] * 0.4 * _fig_scale, 0.8, 7.0)
		c.draw_line(previous, here, Color(INK, lerpf(0.8, 0.55, t)), width)
		previous = here


func _draw_caption() -> void:
	var p: CreatureParams = subject.params
	var joints: Articulation = subject.locomotion.articulation
	var label: String = "%s · TILT %d° · JOINT F %d° / H %d° · LEG %d / ARM %d" % [
		subject.posture.name().to_upper(),
		int(round(rad_to_deg(subject.posture.tilt))),
		int(round(rad_to_deg(joints.fore.stand_angle))),
		int(round(rad_to_deg(joints.hind.stand_angle))),
		int(round(p.leg_length)), int(round(p.arm_length))]
	# Two lines under the stage rather than the two ends of one: the build the walk
	# is being taken off, and the walk. A column has not the width to hang the
	# second off the far margin, and stacked they read as what they are — a
	# statement about the animal followed by a statement about what it is doing.
	var y: float = _stage_bottom() + 11.0
	_text(Vector2(PAD, y), label, 8, Color(INK, 0.35), false, true)
	var pattern: String = _pattern_text()
	if not _idle():
		pattern += " — DUTY %.2f · CYCLE %.2f S" % [
			subject.gait.duty_measured(), subject.gait.cycle_length()]
	# How far off the floor, once there is any: the figure is up there, and a
	# height nobody names is a picture the reader has to trust rather than read.
	if _lift > 0.5:
		pattern += " · AIRBORNE %d PX" % int(round(_lift))
	_text(Vector2(PAD, y + 11.0), pattern, 8, Color(INK, 0.55), false, true)


func _draw_rings(c: Control) -> void:
	var alive: Array[Dictionary] = []
	for ring in _rings:
		var age: float = _time - float(ring["t0"])
		if age >= RING_LIFE:
			continue
		alive.append(ring)
		var at: Vector2 = _to_ground(ring["at"])
		if at.x < -20.0 or at.x > c.size.x + 20.0:
			continue
		c.draw_arc(at, 4.0 + age * 46.0, 0.0, TAU, 24,
			Color(RED, 0.5 * (1.0 - age / RING_LIFE)), 1.0, true)
	_rings = alive


func _pattern_text() -> String:
	if _idle():
		return "STANDING"
	return subject.gait.footfall.describe().to_upper()


## A fore split past half a cycle is the same landing gap run the other way —
## the rotary lead — so it is quoted as the gap it is, marked R, the way the
## reference sheet writes it.
func _split_text(footfall: Footfall) -> String:
	if footfall.fore_split > 0.5:
		return "%.2f · %.2f R" % [footfall.hind_split, 1.0 - footfall.fore_split]
	return "%.2f · %.2f" % [footfall.hind_split, footfall.fore_split]


func _draw_readouts() -> void:
	var gait: Gait = subject.gait
	var footfall: Footfall = gait.footfall
	var loco: Locomotion = subject.locomotion
	var idle: bool = _idle()
	var lift_text: String = "ALL DOWN"
	if not idle:
		match footfall.lift_limit:
			Footfall.LIFT_CAREFUL: lift_text = "1 FOOT"
			# A suspension is every bearing foot off the floor, and how many that
			# is is the body's own count — two on a biped, four on the rest.
			Footfall.LIFT_SUSPENDED: lift_text = "%d — SUSPENDED" \
				% (4 if footfall.forelimbs_bear else 2)
			_: lift_text = "2 FEET"
	var rows: Array = [
		["POSTURE", subject.posture.name().to_upper()],
		["PATTERN", _pattern_text()],
		["FROUDE", "%.2f" % footfall.froude],
		["GIRDLE LAG", ("%.2f" % footfall.girdle_lag) if footfall.forelimbs_bear and not idle else "—"],
		["SPLIT H·F", _split_text(footfall) if not idle else "—"],
		["DUTY", ("%.2f" % gait.duty_measured()) if not idle else "—"],
		["LIFT MAX", lift_text],
		["CYCLE", ("%.2f S" % gait.cycle_length()) if not idle and gait.cycle_length() > 0.0 else "—"],
	]
	# ...and the machine those numbers come out of: the joint each girdle stands
	# at, the lever its muscle works it through, and what the whole body can do
	# about leaving the ground. See Articulation for the lever, Leap for the rest.
	var joints: Articulation = loco.articulation
	var machine: Array = [
		["FORE LEVER", "%d° · IN %.2f · GEAR %.2f" % [
			int(round(rad_to_deg(joints.fore.stand_angle))),
			joints.fore.insertion, joints.fore.gear]],
		["HIND LEVER", "%d° · IN %.2f · GEAR %.2f" % [
			int(round(rad_to_deg(joints.hind.stand_angle))),
			joints.hind.insertion, joints.hind.gear]],
		["LAUNCH", "%.2f" % loco_launch()],
		["SPINE", "%.2f" % loco.spine_freedom],
		["LEG SPEED", "%d PX/S" % int(round(gait.leg_speed))],
	]
	# Under the chart and beside each other: the pattern the animal is in on the
	# left, the machine producing it on the right. They were one column of thirteen
	# rows the first time this panel was one, which is the shape that made it tall
	# enough to need to be a band.
	var inner: float = size.x - PAD * 2.0
	var left: float = inner * PATTERN_SHARE
	_column(PAD, left, rows, "P A T T E R N")
	_column(PAD + left, inner - left, machine, "M A C H I N E")


## Where a block's values are hung, given how wide the block is: far enough over
## to clear the longest label, near enough that the longest reading — a lever's,
## which is three numbers — still lands inside the block. A share rather than a
## fixed indent, because the two blocks are not the same width.
func _value_indent(wide: float) -> float:
	return minf(84.0, wide * 0.34)


## One block of label-and-value rows under its own rule. The values are set tight:
## a column has no room to letterspace a reading as long as a lever's.
func _column(x: float, wide: float, rows: Array, heading: String) -> void:
	var y: float = _readout_top() + 6.0
	var value_x: float = x + _value_indent(wide)
	_text(Vector2(x, y), heading, 8, Color(INK, 0.32))
	draw_line(Vector2(x, y + 5.5), Vector2(x + wide - GUTTER, y + 5.5),
		Color(INK, 0.10), 1.0)
	y += ROW_PITCH + 4.0
	for row in rows:
		_text(Vector2(x, y), str(row[0]), 9, Color(INK, 0.40))
		_text(Vector2(value_x, y), str(row[1]), 9, Color(INK, 0.72), false, true)
		y += ROW_PITCH


func _regime() -> String:
	if subject.elevation.is_airborne():
		return "AIRBORNE"
	if subject.is_stalking():
		return "LAY LOW"
	if _idle():
		return "IDLE"
	return "RUN" if subject.gait.footfall.caution < 0.45 else "WALK"


## Two lines about why the pattern is what it is, said in the sim's own numbers.
## Composed rather than quoted from a table, so it cannot describe a gait the
## body is not in.
func _draw_note() -> void:
	var footfall: Footfall = subject.gait.footfall
	var loco: Locomotion = subject.locomotion
	var first: String = "LAUNCH %.2f AGAINST %.2f MIN / %.2f FULL · SPINE %.2f · INTERFERENCE %.2f" % [
		loco_launch(), Footfall.LAUNCH_MIN, Footfall.LAUNCH_FULL,
		loco.spine_freedom, footfall.interference]
	var second: String
	if subject.is_stalking():
		second = "CLOSE CONTROL — HELD TO %d%% OF TOP SPEED, FOLDED %d PX DOWN ITS OWN LEGS, DUTY %.2f." % [
			int(round(Creature.STALK_SPEED * 100.0)),
			int(round(subject.stature.fold)), subject.gait.duty_measured()]
	elif footfall.crawl > 0.5:
		second = "PENTAPEDAL — TAIL PROP %.2f BEARS THE WALK, SO THE HIND PAIR SWINGS TOGETHER AT CAUTION %.2f." % [
			loco.tail_prop, footfall.caution]
	elif not footfall.forelimbs_bear:
		second = "TWO-LEGGED BY MEASUREMENT — ARM %d UNDER LEG %d × BEARING %.2f, SO THE FORE GIRDLE CARRIES NOTHING." % [
			int(round(subject.params.arm_length)), int(round(subject.params.leg_length)),
			Locomotion.BEARING_RATIO]
	elif footfall.aerial >= Footfall.SUSPENSION_AT:
		second = "SUSPENDED — SPLITS COLLAPSED TO %.2f · %.2f, THE BACK WORKING %.2f OF ITS FREEDOM INTO THE STRIDE." % [
			footfall.hind_split, footfall.fore_split, footfall.aerial]
	elif _idle():
		second = "STANDING — EVERY FOOT DOWN, NOTHING OWED A STEP. THE PATTERN RESUMES WITH THE FIRST ONE."
	else:
		second = "FROUDE %.2f IN A WALK REGIME ENDING AT %.2f — CAUTION %.2f KEEPS %s ON THE FLOOR." % [
			footfall.froude, Footfall.FROUDE_WALK, footfall.caution,
			"THREE FEET" if footfall.lift_limit <= 1 else "A PAIR"] \
			if footfall.caution > 0.45 else \
			"FROUDE %.2f PAST THE WALK AT %.2f — THE SYMMETRICAL FAMILY, RUN AS HARD AS THE LAUNCH ALLOWS." % [
			footfall.froude, Footfall.FROUDE_WALK]
	# The legend has its own line over the note now, so the note is wrapped to the
	# whole width of the column rather than to what is left beside it — which is
	# what a sentence composed out of six readings needs to be given, and in a
	# column there was not that much left over.
	var wide: float = size.x - PAD * 2.0
	var lines: Array[String] = _wrap(first, 8, wide)
	lines.append_array(_wrap(second, 8, wide))
	var y: float = size.y - FOOT_H + 27.0
	for line in lines.slice(0, NOTE_LINES):
		_text(Vector2(PAD, y), line, 8, Color(INK, 0.42), false, true)
		y += 11.0


## Greedy word wrap in the note's own face, so a sentence composed from the
## sim's numbers never runs off the drawer however long the numbers came out.
func _wrap(text: String, px: int, width: float) -> Array[String]:
	var lines: Array[String] = []
	var line: String = ""
	for word in text.split(" "):
		var trial: String = word if line.is_empty() else line + " " + word
		if _mono.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width \
				and not line.is_empty():
			lines.append(line)
			line = word
		else:
			line = trial
	if not line.is_empty():
		lines.append(line)
	return lines


## The two marks the figure and the chart are read by, on their own line under
## the rule that closes the instrument off.
func _draw_legend() -> void:
	var y: float = size.y - FOOT_H + 13.0
	draw_line(Vector2(PAD, y - 13.5), Vector2(size.x - PAD, y - 13.5), Color(INK, 0.10), 1.0)
	var x: float = PAD
	draw_rect(Rect2(x, y - 4.0, 12.0, 2.0), RED)
	_text(Vector2(x + 19.0, y), "PLANTED", 8, Color(INK, 0.42))
	var x2: float = x + 92.0
	draw_arc(Vector2(x2 + 4.0, y - 3.0), 4.5, 0.0, TAU, 16, Color(RED, 0.7), 1.0, true)
	_text(Vector2(x2 + 16.0, y), "FOOTFALL", 8, Color(INK, 0.42))


## The one-cycle footfall chart: a row per bearing limb, its bar at the phase the
## pattern holds it to, wrapped where it runs off the end. Red while that foot is
## really on the ground this frame — the chart is the pattern and the colour is
## the animal.
func _draw_chart() -> void:
	var gait: Gait = subject.gait
	var footfall: Footfall = gait.footfall
	var quad: bool = subject.locomotion.forelimbs_bear
	var keys: Array[String] = ["RL", "RR", "FL", "FR"]
	var labels: Array[String] = ["RL", "RR", "FL", "FR"]
	if not quad:
		keys = ["RL", "RR"]
		labels = ["L", "R"]
	var rows: int = keys.size()
	var frame: Rect2 = _chart_rect()
	var row_h: float = CHART_ROW
	var x0: float = frame.position.x
	var y0: float = frame.position.y
	var w: float = frame.size.x
	var h: float = frame.size.y
	draw_rect(Rect2(x0, y0, w, h), Color(PAPER, 0.92))
	draw_rect(Rect2(x0, y0, w, h), Color(INK, 0.13), false, 1.0)
	draw_rect(Rect2(x0 + 12.0, y0 + 9.0, 5.0, 5.0), RED)
	_text(Vector2(x0 + 25.0, y0 + 15.0), "F O O T F A L L  —  O N E  C Y C L E", 9, INK)
	var lx: float = x0 + 46.0
	var rx: float = x0 + w - 14.0
	var span: float = rx - lx
	var idle: bool = _idle()
	var duty: float = gait.duty_measured()
	for i in rows:
		var y: float = y0 + 24.0 + i * row_h + row_h * 0.5
		_text(Vector2(x0 + 12.0, y + 3.0), labels[i], 9, Color(INK, 0.45))
		draw_line(Vector2(lx, y), Vector2(rx, y), Color(INK, 0.12), 1.0)
		var limb: Limb = _limb_by_key(keys[i])
		var down: bool = limb != null and not limb.stepping \
				and not subject.elevation.is_airborne()
		var bar := Color(RED) if down else Color(INK, 0.75)
		if idle:
			draw_rect(Rect2(lx, y - 3.0, span, 6.0), Color(INK, 0.75))
			continue
		var phase: float = footfall.phase(keys[i])
		var tail: float = phase + duty
		if tail <= 1.0:
			draw_rect(Rect2(lx + phase * span, y - 3.0, duty * span, 6.0), bar)
		else:
			draw_rect(Rect2(lx + phase * span, y - 3.0, (1.0 - phase) * span, 6.0), bar)
			draw_rect(Rect2(lx, y - 3.0, (tail - 1.0) * span, 6.0), bar)
	if not idle:
		var u: float = gait.cycle_position()
		if u >= 0.0:
			draw_line(Vector2(lx + u * span, y0 + 21.0),
				Vector2(lx + u * span, y0 + 24.0 + rows * row_h), Color(RED, 0.85), 1.0)
	var ticks: Array[String] = ["0", "¼", "½", "¾", "1"]
	for i in 5:
		_text(Vector2(lx + (float(i) / 4.0) * span - 2.0, y0 + h - 4.0),
			ticks[i], 9, Color(INK, 0.30))


## The launch the pattern is actually gated on: the leap's spring read through
## the posture's drive axis and the spine — see Footfall.update. Quoting the
## spring alone here would show a sprawled build a number it cannot spend.
func loco_launch() -> float:
	return subject.gait.footfall.launch


func _limb_by_key(key: String) -> Limb:
	for limb in subject.gait.limbs:
		if limb.key == key:
			return limb
	return null


## `tight` drops the tracking — for the lines that have to fit the drawer's
## width, where the letterspacing costs more than it reads. `right` hangs the
## line off `at` instead of starting it there.
func _text(at: Vector2, text: String, px: int, ink: Color, centred: bool = false,
		tight: bool = false, right: bool = false) -> void:
	var font: Font = _mono if tight and _mono != null \
		else (_mono_tracked if _mono_tracked != null else _mono)
	if centred or right:
		var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		at.x -= wide * (0.5 if centred else 1.0)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
