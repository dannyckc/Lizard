## The Gait drawer: the animal's walk, measured while it happens — GaitPanel
## ported onto the v2 gait (docs/V2_DESIGN.md §8, "same fields, new provider").
##
## Every readout is a measurement the simulation has just taken of the body being
## played: the footfall pattern off `Cadence`, the duty and the cycle off `Tread`,
## the joints and their tendon levers off `Carriage`, the launch off `Bound`, the
## per-limb stride and swing off `Tread.Foot`. Nothing is re-animated for the
## panel and nothing is quoted from a table — drive the creature and the numbers
## move, chew a haunch and the same readouts describe the limping animal.
##
## Three instruments, as v1 laid them out:
##
##   * the figure — a true side elevation of the solved skeleton, across the top.
##     The limb chains are the armature's own nodes projected along the body's
##     axis, so a folding knee here is the knee folding in the world and a leap
##     here is the body genuinely off the floor. Every height is the node's own
##     `z`, which in v2 is an absolute world height, so the ground line is the
##     surface under the animal and a walk up a ledge is drawn as one.
##   * the footfall chart — one cycle, one row per bearing limb, each bar at the
##     phase the pattern holds that foot to, red while the real foot is down.
##   * the readouts — the pattern in Hildebrand's numbers beside the machine
##     underneath them: what angle each girdle carries its joint at, what its
##     tendon lever gears the muscle to, and what the body can do about leaving
##     the ground.
##
## Where v1's species tabs were, v2 has one body — so the band carries what the
## lab actually needs to look at instead: the four feet, selectable, and the
## stances this build measured up to. Picking a foot puts that limb's own numbers
## under the figure, which is the question a gait bug is usually a version of —
## *why is that leg not stepping* — and it is answered out of `Tread.Foot`
## directly rather than by a second opinion about the same limb.
class_name GaitDrawer
extends Control

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
## The band under the header, two rows deep: the four feet across the top and the
## stances this build supports under them.
const TAB_COLUMNS: int = 4
const TAB_H: float = 24.0
const TABS_H: float = TAB_H * 2.0
## What the figure will never be squeezed below, and the most of the drawer it
## may take when the fixed bands leave more than that.
const FIGURE_MIN: float = 96.0
const FIGURE_SHARE: float = 0.50
## Three caption lines between the ground line and the chart, and the gap under
## the chart. Three rather than v1's two: the third is whichever foot is selected.
const CAPTION_H: float = 35.0
const CHART_GAP: float = 12.0
## The readout rows at their pitch, and the footfall chart's own row pitch.
const ROW_PITCH: float = 12.0
const READOUT_ROWS: int = 8
const CHART_ROW: float = 17.0
## The legend, the note lines under it, and the paper left under them.
const FOOT_H: float = 57.0
const NOTE_LINES: int = 3
const TAIL: float = 5.0

# --- the figure's camera -------------------------------------------------------
## How much of the column's width the animal's own length may take, and how far
## the fit may magnify a small one. The first is margin: an elevation pressed to
## the edges of its frame is one whose nose and tail tip are the first things to
## go. The second is higher than v1's 1.35 because this is an instrument rather
## than an illustration — a cat is 178 px nose to tail in a 464 px column, and at
## v1's cap a folding knee was three pixels of fold.
const FRAME_FILL: float = 0.82
const FIT_MAX: float = 2.1
## Paper kept over the top of whatever the figure needs, and under the ground
## line where the ticks and a planted toe's mark hang.
const FIG_AIR: float = 8.0
const GROUND_LIP: float = 11.0
## How much of its own leap the band stands ready for without moving.
const JUMP_ROOM: float = 0.35
## The wheel, on the anatomy drawer's terms.
const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 3.2
const ZOOM_STEP: float = 1.09

## The four feet, in the order a chart reads them: hind pair then fore.
const CHART_KEYS: Array[StringName] = [&"HL", &"HR", &"FL", &"FR"]


var subject: Creature2

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _foot_buttons: Dictionary = {}
var _tab_row: GridContainer
## Which foot the caption and the chart's marker are pinned to, or &"" for none.
var _picked: StringName = &""
var _time: float = 0.0
## Footfall rings: {at: Vector2 (world), t0: float}.
var _rings: Array[Dictionary] = []
## Per-limb trails of drawn foot positions, keyed as the feet are.
var _trails: Dictionary = {}
## Whether each foot was mid-step last frame — a landing is the edge, and reading
## it here means the gait needs no signal to say a foot arrived.
var _was_stepping: Dictionary = {}

var _style: StyleBoxFlat
var _stage: Stage
## How tall the figure band has come out: what the fixed bands left, capped at
## its share of the drawer. See `_span`.
var _figure_h: float = FIGURE_MIN
## How tall the dock last said it was, for the frames before the layout has
## caught up with it — see `fit_to_height`.
var _dock_h: float = 0.0


## The figure's own canvas. A child rather than a region of the panel's, and for
## the one reason a stage is ever its own node: leaning the wheel in has to be
## able to run the animal off the edges of its band without running it over the
## tabs above and the chart below. Everything it draws it asks the panel for —
## see `_draw_stage` — so there is still one figure and one projection.
class Stage extends Control:
	var panel: GaitDrawer

	func _init(owner_panel: GaitDrawer) -> void:
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
	_build_foot_tabs()
	resized.connect(_lay_out_tabs)
	_span()


## The same paper, chrome and shadow as the anatomy drawer — see
## SpecimenDrawer._place — in the same dock, a column wider than its.
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


func dock_width() -> float:
	return WIDTH


## Told how tall the dock is, the same way the anatomy drawer is. The rect itself
## is HudDock's; what this decides is how that height gets divided.
func fit_to_height(available: float) -> void:
	_dock_h = available
	_span()


## How the drawer's height is divided, and how big the animal comes out in the
## band that division leaves. Re-taken every frame it is up rather than only on a
## resize, because the chart is two rows shorter on a body walking on two legs
## and entering a bipedal sprint is not a resize.
func _span() -> void:
	var tall: float = size.y if size.y > 1.0 else _dock_h
	var wide: float = size.x if size.x > 1.0 else WIDTH
	var fixed: float = HEADER_H + TABS_H + CAPTION_H + _chart_height() + CHART_GAP \
		+ _readout_height() + FOOT_H + TAIL
	_figure_h = clampf(tall - fixed, FIGURE_MIN, maxf(tall * FIGURE_SHARE, FIGURE_MIN))
	_fit = 1.0
	if _usable():
		# What the width allows, and what the depth allows, whichever is tighter —
		# a long-tailed animal is bound by the column's width and a tall standing
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
	for key in _foot_buttons:
		(_foot_buttons[key] as Button).add_theme_font_override("font", _sans_tracked)


## Whose walk this is.
func set_subject(each: Creature2) -> void:
	if subject == each:
		return
	subject = each
	_rings.clear()
	_trails.clear()
	_was_stepping.clear()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_span()
	_collect_landings()
	_collect_trails()
	_style_foot_tabs()
	queue_redraw()
	_stage.queue_redraw()


## A landing is a foot that was swinging last frame and is planted this one. Read
## as an edge rather than taken off a signal, because `Tread.landed` is cleared
## every physics tick and a panel running on frames would miss half of them.
func _collect_landings() -> void:
	if not _usable():
		return
	for foot in subject.tread.feet:
		var was: bool = bool(_was_stepping.get(foot.key, false))
		_was_stepping[foot.key] = foot.stepping
		if was and not foot.stepping:
			_rings.append({"at": foot.planted, "t0": _time})
			while _rings.size() > RING_MAX:
				_rings.pop_front()


# --- the tabs ------------------------------------------------------------------

## The band under the header. The four feet across it, selectable, and the
## stances this build measured up to under them — one row that does something and
## one that reports, which is the split v1's species tabs and regime strip
## already had; they are just both about this animal now.
func _build_foot_tabs() -> void:
	var grid := GridContainer.new()
	grid.name = "FootTabs"
	grid.columns = TAB_COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 0)
	add_child(grid)
	_tab_row = grid
	for key in CHART_KEYS:
		var button := Button.new()
		button.text = str(key)
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, TAB_H - 2.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_on_foot_pressed.bind(key))
		grid.add_child(button)
		_foot_buttons[key] = button
	_lay_out_tabs()
	_style_foot_tabs()


func _lay_out_tabs() -> void:
	if _tab_row == null:
		return
	_tab_row.position = Vector2(PAD, HEADER_H)
	_tab_row.size = Vector2(maxf(size.x - PAD * 2.0, 1.0), TAB_H)


func _on_foot_pressed(key: StringName) -> void:
	_picked = &"" if _picked == key else key
	_style_foot_tabs()


## A foot's tab says what that foot is doing before it is picked: lit while it is
## on the ground, hollow while it is swinging, struck through when the limb has
## been chewed past answering. The selected one is underlined.
func _style_foot_tabs() -> void:
	for key in _foot_buttons:
		var button: Button = _foot_buttons[key]
		var selected: bool = key == _picked
		var down: bool = false
		var sound: float = 1.0
		if _usable():
			var foot: Tread.Foot = subject.tread.of(key)
			if foot != null:
				down = not foot.stepping and foot.bearing
				sound = subject.corpus.soundness(key)
		var ink: Color = INK if selected or down else Color(INK, 0.42)
		if sound < 0.995:
			ink = RED
		button.text = "%s %s" % [str(key), "▮" if down else "▯"]
		button.add_theme_color_override("font_color", ink)
		button.add_theme_color_override("font_hover_color", INK)
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


## The wheel anywhere on the band leans the figure in and out, and a double-click
## puts it back at the fit — the anatomy drawer's two gestures, on the anatomy
## drawer's step, because the two F3 stops are one instrument and a wheel that
## means different things on each is one the player has to remember.
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
	# last second of the walk at a size the animal is no longer drawn at.
	_trails.clear()
	queue_redraw()
	if _stage != null:
		_stage.queue_redraw()


# --- the projection -------------------------------------------------------------
# One frame for the whole figure: the body's own axis through the middle of its
# girdles, so the elevation is drawn along the animal however it is heading, and a
# world height straight up the screen. Everything the figure shows goes through
# `_to_fig` and nothing else, which is what keeps the picture a projection of the
# simulation rather than a drawing beside one.

var _centre: Vector2 = Vector2.ZERO
var _fwd: Vector2 = Vector2.RIGHT
var _fig_scale: float = 1.0
var _fig_cx: float = 400.0
var _ground_y: float = 400.0
## What the band's own width and depth allow, before the wheel.
var _fit: float = 1.0
## The surface the animal is standing over, and how far off it the body is. In v2
## a node's `z` is an absolute world height, so the figure subtracts the floor
## once, here, and every height downstream is honest about terrain and about a
## leap without a single caller remembering either.
var _floor: float = 0.0
var _lift: float = 0.0
## How far the wheel has leaned in past the fit the band worked out.
var zoom: float = 1.0


func _refresh_frame() -> void:
	var reach: Vector2 = _extent()
	var fall: Gravity.Fall = subject.armature.fall
	_floor = fall.floor_height
	_lift = maxf(fall.height - fall.floor_height, 0.0)
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


## The band's paper the animal is not standing in, split above and below it
## rather than left in one piece over its back: a long flat animal fitted to the
## width and stood on the floor of a band five times its depth reads as a drawing
## that has slid to the bottom of the page, and centred it is a plate.
func _slack() -> float:
	if not _usable():
		return 0.0
	return maxf(_stage.size.y - (_top() * _fig_scale + FIG_AIR + GROUND_LIP), 0.0)


## How far the animal reaches fore and aft of the middle of its girdles, along its
## own axis — nose past the head, tail tip behind. What the figure is fitted and
## centred on, rather than the girdle midpoint: a long-tailed body centred on its
## girdles hangs its tail off the edge of the band. Sets the frame the whole
## projection is taken in on its way past.
func _extent() -> Vector2:
	var a: Armature = subject.armature
	var fore: Vector2 = a.plan(a.withers_index())
	var rear: Vector2 = a.plan(a.pelvis_index())
	_centre = (fore + rear) * 0.5
	var axis: Vector2 = fore - rear
	_fwd = axis.normalized() if axis.length_squared() > 0.0001 else Vector2.RIGHT
	var ahead: float = (a.plan(a.head_index()) - _centre).dot(_fwd) \
		+ subject.body.skull_radius * 2.5
	var tail: Armature.Chain = a.chain(BodySchema.TAIL)
	var behind: float = -10.0
	if tail != null and tail.nodes.size() > 0:
		behind = (a.plan(tail.nodes[tail.nodes.size() - 1]) - _centre).dot(_fwd)
	return Vector2(maxf(ahead, 10.0), minf(behind, -10.0))


## How tall the animal *stands*, in world height: the higher girdle or the carried
## head, whichever it holds highest. What the band is deep enough for.
##
## Deliberately the standing height and not the live one. The girdle carries are
## the gait's own measurement off the feet and are quoted above the body's datum
## rather than above the world, and the head is taken above that same datum — so
## none of the three moves when the animal leaves the ground. A band that deepened
## with the leap would shrink the figure as it went up, which reports the jump
## twice and its height wrongly; the ground goes down instead, in `_refresh_frame`.
func _top() -> float:
	var a: Armature = subject.armature
	var head: float = a.pos[a.head_index()].z - a.fall.height + subject.body.skull_radius
	return maxf(maxf(subject.tread.shoulder_height, subject.tread.hip_height),
		maxf(head, 20.0))


## ...and how much air the band holds over it. A fraction of the animal's own
## jump, not the whole of it: a body that can clear several times its own height
## and is drawn small enough to prove it is a body drawn as a smudge on the ground
## line for the whole of the time it is walking. What this buys is a hop that
## happens inside a still frame; past it the ground goes down instead.
func _headroom() -> float:
	var jump: float = subject.bound.peak(1.0) if subject.bound != null else 0.0
	var top: float = _top()
	return top + clampf(jump, 0.0, top * JUMP_ROOM)


func _chart_height() -> float:
	var rows: int = 4 if subject != null and subject.locomotor != null \
		and subject.locomotor.forelimbs_bear else 2
	return 24.0 + rows * CHART_ROW + 14.0


## The readout block under the chart: a heading, its rule, and the taller of the
## two blocks' rows. Both blocks start at the same line, so the block is as deep
## as the pattern's eight rows however few the machine has.
func _readout_height() -> float:
	return 6.0 + ROW_PITCH + 4.0 + float(READOUT_ROWS) * ROW_PITCH


## A place on the animal. `height` is the node's own absolute world z; the floor
## under the body is taken off here, once, rather than at each of the dozen places
## a height is read.
func _to_fig(world: Vector2, height: float) -> Vector2:
	return Vector2(_fig_cx + (world - _centre).dot(_fwd) * _fig_scale,
		_ground_y - (height - _floor) * _fig_scale)


## A place on the ground under it, which a leap does not move.
func _to_ground(world: Vector2) -> Vector2:
	return Vector2(_fig_cx + (world - _centre).dot(_fwd) * _fig_scale, _ground_y)


# --- the lower band ------------------------------------------------------------

func _stage_bottom() -> float:
	return HEADER_H + TABS_H + _figure_h


func _lower_top() -> float:
	return _stage_bottom() + CAPTION_H


func _chart_rect() -> Rect2:
	return Rect2(PAD, _lower_top(), maxf(size.x - PAD * 2.0, 1.0), _chart_height())


func _readout_top() -> float:
	return _lower_top() + _chart_height() + CHART_GAP


func _usable() -> bool:
	return subject != null and is_instance_valid(subject) and subject.armature != null \
			and subject.armature.node_count() > 0 and subject.tread != null \
			and not subject.tread.feet.is_empty() and subject.locomotor != null


func _idle() -> bool:
	return subject.speed_norm < IDLE_PACE and absf(subject.speed) < 2.0 \
			and not subject.tread.any_stepping()


func _collect_trails() -> void:
	if not _usable():
		return
	_refresh_frame()
	for foot in subject.tread.feet:
		if foot.side > 0.0:
			continue
		var tip: int = foot.chain.nodes[foot.chain.nodes.size() - 1]
		var p: Vector3 = subject.armature.pos[tip]
		var trail: PackedVector2Array = _trails.get(foot.key, PackedVector2Array())
		trail.append(_to_fig(Vector2(p.x, p.y), p.z))
		while trail.size() > TRAIL_MAX:
			trail.remove_at(0)
		_trails[foot.key] = trail


func _draw() -> void:
	# The drawer's own paper, drawn even with nothing to measure: an empty
	# instrument is still an instrument.
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	if _mono == null:
		return
	_draw_header()
	if not _usable():
		return
	_draw_stances()
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


## The drawer's title row: the mark, the word, and the five regimes with the live
## one marked — they are indicators, not tabs; the keys drive the animal.
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
	var labels: Array[String] = ["AIRBORNE", "GALLOP", "RUN", "WALK", "IDLE"]
	for label in labels:
		var wide: float = _mono_tracked.get_string_size(label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		x -= wide
		var active: bool = label == current
		_text(Vector2(x, 19.0), label, 8, INK if active else Color(INK, 0.35))
		if active:
			draw_rect(Rect2(x - 9.0, 14.0, 4.0, 4.0), RED)
		x -= 17.0


## The second row of the band: what this build measured up to. Each supported
## (posture × mode) is drawn as a chip, the one it is standing in now marked, and
## the one it is moving toward hollowed while the blend runs — the two-axis stance
## model made visible, which is otherwise only inferable from the numbers moving.
func _draw_stances() -> void:
	var attitude: Attitude = subject.attitude
	if attitude == null or attitude.supported.is_empty():
		return
	var y: float = HEADER_H + TAB_H
	_text(Vector2(PAD, y + 15.0), "STANCE", 8, Color(INK, 0.32))
	var x: float = PAD + 46.0
	for combo in attitude.supported:
		var word: String = "%s %s" % [Carriage.NAMES[combo.x].to_upper(),
			Attitude.MODE_NAMES[combo.y].substr(0, 4).to_upper()]
		var live: bool = combo == attitude.current
		var wide: float = _mono_tracked.get_string_size(word,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		if live:
			draw_rect(Rect2(x - 5.0, y + 4.0, wide + 10.0, 15.0), Color(INK, 0.07))
			draw_rect(Rect2(x - 5.0, y + 18.0, wide + 10.0, 1.0), INK)
		_text(Vector2(x, y + 15.0), word, 8,
			INK if live else Color(INK, 0.34))
		x += wide + 20.0
	if attitude.transitioning():
		_text(Vector2(size.x - PAD, y + 15.0), "SHIFTING", 8, RED, false, true, true)


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
	var a: Armature = subject.armature
	var quad: bool = subject.locomotor.forelimbs_bear

	var shoulder: Vector2 = _node(a.withers_index())
	var hip: Vector2 = _node(a.pelvis_index())

	# Far side first, faint — the depth cue, and honest: those are the limbs on
	# the other flank of the same solve.
	for foot in subject.tread.feet:
		if foot.side <= 0.0:
			continue
		_draw_limb(c, foot, false, quad)

	# The body's own depth as a soft silhouette between the girdles. Rounded off
	# at the ends so it reads as a trunk rather than a crate.
	var depth: float = maxf(subject.corpus.girth(BodySchema.TRUNK, 8) * 2.0
		* _fig_scale * 0.8, 4.0)
	c.draw_line(hip, shoulder, Color(INK, 0.07), depth)
	c.draw_circle(hip, depth * 0.5, Color(INK, 0.07))
	c.draw_circle(shoulder, depth * 0.5, Color(INK, 0.07))

	_draw_chain(c, a.chain(BodySchema.TAIL), 0.8, 0.55)

	# The back the two pairs of legs are holding up. Its pitch is the two heights,
	# not a pose: short arms draw it nose-down because they hold it nose-down.
	_draw_chain(c, a.chain(BodySchema.TRUNK), 0.85, 0.85)

	# Neck and head, off the solved chain and the carried skull.
	_draw_chain(c, a.chain(BodySchema.NECK), 0.85, 0.85)
	var head: Vector2 = _node(a.head_index())
	var head_r: float = maxf(subject.body.skull_radius * _fig_scale, 3.0)
	c.draw_arc(head, head_r, 0.0, TAU, 24, Color(INK, 0.85), 1.5, true)
	c.draw_circle(head + Vector2(head_r * 0.35, -head_r * 0.2), 1.6, INK)

	for trail_key in _trails:
		var trail: PackedVector2Array = _trails[trail_key]
		if trail.size() > 2:
			c.draw_polyline(trail, Color(INK, 0.09), 1.0)

	# Near side over the top, bold.
	for foot in subject.tread.feet:
		if foot.side > 0.0:
			continue
		_draw_limb(c, foot, true, quad)


func _node(i: int) -> Vector2:
	var p: Vector3 = subject.armature.pos[i]
	return _to_fig(Vector2(p.x, p.y), p.z)


## One axial chain, exactly as the solver left it, fading along its length.
func _draw_chain(c: Control, chain: Armature.Chain, from: float, to: float) -> void:
	if chain == null or chain.nodes.size() < 2:
		return
	var previous: Vector2 = _node(chain.nodes[0])
	if chain.parent_node >= 0:
		previous = _node(chain.parent_node)
	for i in chain.nodes.size():
		var here: Vector2 = _node(chain.nodes[i])
		var t: float = float(i) / float(maxi(chain.nodes.size() - 1, 1))
		var width: float = clampf(subject.armature.flesh_r[chain.nodes[i]] * 0.5
			* _fig_scale, 0.9, 7.0)
		c.draw_line(previous, here, Color(INK, lerpf(from, to, t)), maxf(width, 1.4))
		previous = here


## One limb, exactly as FABRIK left it: socket, joints and foot through the shared
## projection, with the fold the chain actually has. `quad` says whether the
## forelimbs bear; on a two-legged build they draw as carried arms.
func _draw_limb(c: Control, foot: Tread.Foot, near: bool, quad: bool) -> void:
	var arm: bool = foot.fore and not quad
	var alpha: float = (0.7 if arm else 0.9) if near else 0.30
	var ink := Color(INK, alpha)
	if _picked == foot.key:
		ink = Color(RED, alpha)
	var width: float = (1.6 if arm else (2.2 if near else 1.8))
	var points := PackedVector2Array()
	if foot.chain.parent_node >= 0:
		points.append(_node(foot.chain.parent_node))
	for n in foot.chain.nodes:
		points.append(_node(n))
	if points.size() < 2:
		return
	c.draw_polyline(points, ink, width, true)
	for i in range(1, points.size() - 1):
		c.draw_circle(points[i], 2.0, ink)
	if arm:
		return
	# The toe: down and rolled onto when planted, trailed when swinging.
	var tip: Vector2 = points[points.size() - 1]
	var toe: float = maxf(foot.foot_size * 2.0 * _fig_scale, 2.0)
	var down: bool = not foot.stepping and foot.bearing \
			and not subject.armature.fall.is_airborne()
	if down:
		var toe_tip := Vector2(tip.x + toe, _to_fig(foot.planted, foot.surface).y)
		c.draw_line(tip, toe_tip, ink, width)
		var mark := Color(RED, 1.0 if near else 0.35)
		c.draw_line(Vector2(tip.x - 4.0, toe_tip.y + 4.0),
			Vector2(tip.x + toe + 4.0, toe_tip.y + 4.0), mark, 2.0)
	else:
		c.draw_line(tip, tip + Vector2(toe * 0.65, toe * 0.4), ink, width)


## Three lines under the stage: the build the walk is being taken off, the walk
## itself, and — when one is selected — that limb's own numbers. A column has not
## the width to hang any of them off the far margin, and stacked they read as what
## they are: a statement about the animal, then about what it is doing, then about
## the leg that is not doing it.
func _draw_caption() -> void:
	var spec: BodySpec = subject.body
	var carriage: Carriage = subject.attitude.active
	var label: String = "%s · TILT %d° · JOINT F %d° / H %d° · LEG %d / ARM %d" % [
		subject.attitude.describe().to_upper(),
		int(round(rad_to_deg(carriage.tilt))),
		int(round(rad_to_deg(carriage.fore.stand_angle))),
		int(round(rad_to_deg(carriage.hind.stand_angle))),
		int(round(spec.hind_leg_length)), int(round(spec.fore_leg_length))]
	var y: float = _stage_bottom() + 11.0
	_text(Vector2(PAD, y), label, 8, Color(INK, 0.35), false, true)
	var pattern: String = _pattern_text()
	if not _idle():
		pattern += " — DUTY %.2f · CYCLE %.2f S" % [
			subject.tread.duty_measured(), subject.tread.cycle_length()]
	# How far off the floor, once there is any: the figure is up there, and a
	# height nobody names is a picture the reader has to trust rather than read.
	if _lift > 0.5:
		pattern += " · AIRBORNE %d PX" % int(round(_lift))
	_text(Vector2(PAD, y + 11.0), pattern, 8, Color(INK, 0.55), false, true)
	_text(Vector2(PAD, y + 22.0), _foot_text(), 8, Color(INK, 0.45), false, true)


## Whichever foot is selected, in its own numbers — the ones a leg that is not
## stepping is not stepping *because* of. Every field is read straight off
## `Tread.Foot`, so this is the gait's own state and not a summary of it.
func _foot_text() -> String:
	if _picked.is_empty():
		return "PICK A FOOT ABOVE FOR ITS OWN STRIDE, SWING AND ERROR"
	var foot: Tread.Foot = subject.tread.of(_picked)
	if foot == null:
		return "%s — NO SUCH LIMB" % str(_picked)
	var state: String = "SWINGING %d%%" % int(round(foot.step_t * 100.0)) if foot.stepping \
		else ("PLANTED" if foot.bearing else "CARRIED")
	return "%s %s · STRIDE %.1f · ERROR %.1f · SWING %d MS · DRIVE %.2f · SOUND %.2f" % [
		str(_picked), state, foot.stride, foot.error,
		int(round(foot.step_duration * 1000.0)), foot.drive,
		subject.corpus.soundness(_picked)]


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
	return subject.tread.cadence.describe().to_upper()


## A fore split past half a cycle is the same landing gap run the other way — the
## rotary lead — so it is quoted as the gap it is, marked R, the way the reference
## sheet writes it.
func _split_text(cadence: Cadence) -> String:
	if cadence.fore_split > 0.5:
		return "%.2f · %.2f R" % [cadence.hind_split, 1.0 - cadence.fore_split]
	return "%.2f · %.2f" % [cadence.hind_split, cadence.fore_split]


func _draw_readouts() -> void:
	var tread: Tread = subject.tread
	var cadence: Cadence = tread.cadence
	var loco: Locomotor = subject.locomotor
	var idle: bool = _idle()
	var lift_text: String = "ALL DOWN"
	if not idle:
		match cadence.lift_limit:
			Cadence.LIFT_CAREFUL: lift_text = "1 FOOT"
			# A suspension is every bearing foot off the floor, and how many that
			# is is the body's own count — two on a biped, four on the rest.
			Cadence.LIFT_SUSPENDED: lift_text = "%d — SUSPENDED" % loco.bearing_limbs
			_: lift_text = "2 FEET"
	var rows: Array = [
		["POSTURE", subject.attitude.describe().to_upper()],
		["PATTERN", _pattern_text()],
		["FROUDE", "%.2f" % cadence.froude],
		["GIRDLE LAG", ("%.2f" % cadence.girdle_lag) if cadence.forelimbs_bear and not idle else "—"],
		["SPLIT H·F", _split_text(cadence) if not idle else "—"],
		["DUTY", ("%.2f" % tread.duty_measured()) if not idle else "—"],
		["LIFT MAX", lift_text],
		["CYCLE", ("%.2f S" % tread.cycle_length()) if not idle and tread.cycle_length() > 0.0 else "—"],
	]
	# ...and the machine those numbers come out of: the joint each girdle stands
	# at, the lever its muscle works it through, and what the whole body can do
	# about leaving the ground and about staying on its feet.
	var carriage: Carriage = subject.attitude.active
	var machine: Array = [
		["FORE LEVER", "%d° · IN %.2f · GEAR %.2f" % [
			int(round(rad_to_deg(carriage.fore.stand_angle))),
			carriage.fore.insertion, carriage.fore.gear]],
		["HIND LEVER", "%d° · IN %.2f · GEAR %.2f" % [
			int(round(rad_to_deg(carriage.hind.stand_angle))),
			carriage.hind.insertion, carriage.hind.gear]],
		["LAUNCH", "%.2f" % cadence.launch],
		["SPINE", "%.2f" % loco.spine_freedom],
		["LEG SPEED", "%d PX/S" % int(round(tread.leg_speed))],
		["POWER", "%.3f" % loco.power],
		["JUMP", _jump_text()],
		["FOOTING", _footing_text()],
	]
	var inner: float = size.x - PAD * 2.0
	var left: float = inner * PATTERN_SHARE
	_column(PAD, left, rows, "P A T T E R N")
	_column(PAD + left, inner - left, machine, "M A C H I N E")


## What the spring is doing, in the jump's own phase names and its own charge —
## a leap is a commitment and the panel says which part of it the body is in.
func _jump_text() -> String:
	var bound: Bound = subject.bound
	if not bound.capable:
		return "NONE"
	var words: Array[String] = ["IDLE", "GATHER", "CHARGE", "THRUST", "FLIGHT"]
	var word: String = words[clampi(bound.phase, 0, 4)]
	if bound.phase == Bound.IDLE:
		return "READY · %d PX" % int(round(bound.peak(1.0)))
	return "%s %d%%" % [word, int(round(bound.charge * 100.0))]


## How much of the standing the legs are still answering for. `hold` is Footing's
## own reading and `failed` is what puts a body down — quoted rather than
## re-derived, because the measurement is the decision.
func _footing_text() -> String:
	var footing: Footing = subject.footing
	if footing.failed:
		return "GONE"
	if footing.hold >= 0.995:
		return "HELD"
	return "%d%% · %.1f S" % [int(round(footing.hold * 100.0)), footing.unheld]


## Where a block's values are hung, given how wide the block is: far enough over
## to clear the longest label, near enough that the longest reading — a lever's,
## which is three numbers — still lands inside the block.
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
	if subject.armature.fall.is_airborne():
		return "AIRBORNE"
	if _idle():
		return "IDLE"
	if subject.tread.cadence.aerial >= Cadence.SUSPENSION_AT:
		return "GALLOP"
	return "RUN" if subject.tread.cadence.caution < 0.45 else "WALK"


## Two lines about why the pattern is what it is, said in the sim's own numbers.
## Composed rather than quoted from a table, so it cannot describe a gait the body
## is not in.
func _draw_note() -> void:
	var cadence: Cadence = subject.tread.cadence
	var loco: Locomotor = subject.locomotor
	var first: String = "LAUNCH %.2f AGAINST %.2f MIN / %.2f FULL · SPINE %.2f · INTERFERENCE %.2f" % [
		cadence.launch, Cadence.LAUNCH_MIN, Cadence.LAUNCH_FULL,
		loco.spine_freedom, cadence.interference]
	var second: String
	if subject.armature.collapsed:
		second = "COLLAPSED — THE CHAIN IS SOLVING SYMMETRICALLY AND NOTHING IS ASKING FOR A FOOT."
	elif cadence.crawl > 0.5:
		second = "PENTAPEDAL — TAIL PROP %.2f BEARS THE WALK, SO THE HIND PAIR SWINGS TOGETHER AT CAUTION %.2f." % [
			loco.tail_prop, cadence.caution]
	elif not cadence.forelimbs_bear:
		second = "TWO-LEGGED BY MEASUREMENT — ARM %d UNDER LEG %d × BEARING %.2f, SO THE FORE GIRDLE CARRIES NOTHING." % [
			int(round(subject.body.fore_leg_length)),
			int(round(subject.body.hind_leg_length)), Attitude.BEARING_RATIO]
	elif cadence.aerial >= Cadence.SUSPENSION_AT:
		second = "SUSPENDED — SPLITS COLLAPSED TO %.2f · %.2f, THE BACK WORKING %.2f OF ITS FREEDOM INTO THE STRIDE." % [
			cadence.hind_split, cadence.fore_split, cadence.aerial]
	elif _idle():
		second = "STANDING — EVERY FOOT DOWN, NOTHING OWED A STEP. THE PATTERN RESUMES WITH THE FIRST ONE."
	elif cadence.caution > 0.45:
		second = "FROUDE %.2f IN A WALK REGIME ENDING AT %.2f — CAUTION %.2f KEEPS %s ON THE FLOOR." % [
			cadence.froude, Cadence.FROUDE_WALK, cadence.caution,
			"THREE FEET" if cadence.lift_limit <= 1 else "A PAIR"]
	else:
		second = "FROUDE %.2f PAST THE WALK AT %.2f — THE SYMMETRICAL FAMILY, RUN AS HARD AS THE LAUNCH ALLOWS." % [
			cadence.froude, Cadence.FROUDE_WALK]
	var wide: float = size.x - PAD * 2.0
	var lines: Array[String] = _wrap(first, 8, wide)
	lines.append_array(_wrap(second, 8, wide))
	var y: float = size.y - FOOT_H + 27.0
	for line in lines.slice(0, NOTE_LINES):
		_text(Vector2(PAD, y), line, 8, Color(INK, 0.42), false, true)
		y += 11.0


## Greedy word wrap in the note's own face, so a sentence composed from the sim's
## numbers never runs off the drawer however long the numbers came out.
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


## The two marks the figure and the chart are read by, on their own line under the
## rule that closes the instrument off.
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
	var tread: Tread = subject.tread
	var cadence: Cadence = tread.cadence
	var quad: bool = subject.locomotor.forelimbs_bear
	# Only the bearing limbs get a row: a body walking on two legs is not a
	# quadruped with two empty tracks in the chart, and the band above it is two
	# rows shorter for the same reason.
	var keys: Array[StringName] = []
	var labels: Array[String] = []
	for i in CHART_KEYS.size():
		if not quad and i >= 2:
			break
		keys.append(CHART_KEYS[i])
		labels.append(str(CHART_KEYS[i]) if quad else str(CHART_KEYS[i]).substr(1, 1))
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
	var duty: float = tread.duty_measured()
	for i in rows:
		var y: float = y0 + 24.0 + i * row_h + row_h * 0.5
		var picked: bool = keys[i] == _picked
		_text(Vector2(x0 + 12.0, y + 3.0), labels[i], 9,
			INK if picked else Color(INK, 0.45))
		draw_line(Vector2(lx, y), Vector2(rx, y), Color(INK, 0.12), 1.0)
		var foot: Tread.Foot = tread.of(keys[i])
		var down: bool = foot != null and not foot.stepping \
				and not subject.armature.fall.is_airborne()
		var bar := Color(RED) if down else Color(INK, 0.75)
		if idle:
			draw_rect(Rect2(lx, y - 3.0, span, 6.0), Color(INK, 0.75))
			continue
		var phase: float = cadence.phase(keys[i])
		var tail: float = phase + duty
		if tail <= 1.0:
			draw_rect(Rect2(lx + phase * span, y - 3.0, duty * span, 6.0), bar)
		else:
			draw_rect(Rect2(lx + phase * span, y - 3.0, (1.0 - phase) * span, 6.0), bar)
			draw_rect(Rect2(lx, y - 3.0, (tail - 1.0) * span, 6.0), bar)
	if not idle:
		var u: float = tread.cycle_position()
		if u >= 0.0:
			draw_line(Vector2(lx + u * span, y0 + 21.0),
				Vector2(lx + u * span, y0 + 24.0 + rows * row_h), Color(RED, 0.85), 1.0)
	var ticks: Array[String] = ["0", "¼", "½", "¾", "1"]
	for i in 5:
		_text(Vector2(lx + (float(i) / 4.0) * span - 2.0, y0 + h - 4.0),
			ticks[i], 9, Color(INK, 0.30))


## `tight` drops the tracking — for the lines that have to fit the drawer's width,
## where the letterspacing costs more than it reads. `right` hangs the line off
## `at` instead of starting it there.
func _text(at: Vector2, text: String, px: int, ink: Color, centred: bool = false,
		tight: bool = false, right: bool = false) -> void:
	var font: Font = _mono if tight and _mono != null \
		else (_mono_tracked if _mono_tracked != null else _mono)
	if centred or right:
		var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		at.x -= wide * (0.5 if centred else 1.0)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
