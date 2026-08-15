## The Physics drawer: the locomotion loop, while it runs.
##
## It exists because two things about a walking animal cannot be seen by watching
## it walk — *why* a foot stepped when it did, and *where* the stiffness in the
## picture is coming from — and both are decisions the loop makes several times a
## second and then throws away. Everything here is one of those decisions, drawn
## at the moment it is taken: the drift that became a step, the landing being
## re-aimed while the foot is in the air, the demand the feet could not deliver,
## the weight going out over the edge of its own support, the joint that has run
## out of fold.
##
## A pure reader, and strictly. It owns no simulation state, no second centre of
## mass, no smoothing: every number comes through `MotionReadout` — the one seam
## `Travel` assembles — and the geometry is `Armature`'s posed nodes projected
## three ways (see `MotionStage`). Where a reading looks wrong, the reading is
## right; the finding belongs to the mover.
##
## It is a drawer like the other two: it stands in the shared right-hand dock,
## the camera pays for the column it takes, and F3 steps onto it — see HudDock and
## LabHUD.field_shift. The one thing it does that no other drawer does is take
## hold of the clock (pause, frame-step and slow motion), because half of judging
## whether a movement reads naturally is being able to slow it down.
##
## The column is laid out picture first and by a long way: the three views take
## every pixel the readings under them do not want, the timeline takes the next
## most, and everything written is either a measurement or the name of one. There
## is no legend and no prose — the tells are drawn as gauges against their own
## bands (`MotionRead.Band`) and the marks on the stage are explained by the
## bench, which has the paper for it. A panel whose subject is a moving animal
## should be mostly animal.
class_name MotionDrawer
extends PanelContainer

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
const RED := Color("8e1b12")

## The column, as a share of the window with a floor and a ceiling under it.
##
## Wider than a drawer of readings needs to be, because this one is mostly
## *picture*: three projections of an animal that is longer than it is tall, and
## the width they are given is the width the walk is legible at. Half the window
## and a little, so the field beside it still holds the creature and its ground —
## the point of reading the loop in the lab rather than at the bench is that the
## animal is right there being played.
const WIDTH: float = 880.0
const WIDTH_MIN: float = 520.0
const WIDTH_SHARE: float = 0.53
## What the timeline takes out of the column — see MotionRead.Ribbon, which asks
## for more than this on a page that has it.
const RIBBON_HEIGHT: float = 142.0
## The three views take whatever the readings under them do not, between these.
const STAGE_HEIGHT: float = 720.0
const STAGE_MIN_HEIGHT: float = 200.0

## Slow motion's ends. Under a tenth nothing is legible as movement any more,
## and over one and a half the animal is being lied about.
const RATE_MIN: float = 0.10
const RATE_MAX: float = 1.50

## What the loop prints of itself, a row at a time in the order the loop happens:
## what was asked and what came of it, what the feet had to give, what the body
## is standing on, and how it is being held up. Sixteen readings in four rows of
## four, so a row is a subject rather than wherever the wrapping happened to fall.
const LOOP: Array[String] = [
	"ASK", "SPEED", "DEMAND", "DELIVERED",
	"CEILING", "GRIP", "ANG VEL", "FEET DOWN",
	"MARGIN", "BASE", "COM Z", "STEADINESS",
	"ROLL", "RIGHTING", "HEADROOM", "SEATS",
]
const LOOP_COLUMNS: int = 4

## The eight tells, the bands and the timeline are the *reading* rather than this
## panel's own: the bench draws the same loop full screen, and two panels holding
## two opinions about what a natural sway is would disagree the first time one of
## them was retuned — see MotionRead, which is where they now live.
const TELLS: Array[Dictionary] = MotionRead.TELLS
## How many gauges stand across the column.
const TELL_COLUMNS: int = 4





var subject: Creature2
var stage: MotionStage

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _ribbon: MotionRead.Ribbon
var _state: Label
var _clock: Label
var _loop: Dictionary = {}
var _tells: Array[MotionRead.Band] = []
var _pause: Button
var _step: Button
var _rate_value: Label
var _rate: MinimalSlider
var _chips: Array[Dictionary] = []
var _stage_wrap: Control
## The column this drawer is currently standing in, which follows the window.
var _width: float = WIDTH
## ...and the height the dock last said it had.
var _dock_height: float = 0.0

var _paused: bool = false
var _speed: float = 1.0
## Whether this drawer is the open one. The loop is only recorded, and the clock
## is only touched, while it is — a closed panel costs the body nothing.
var _open: bool = false


func set_ui_fonts(sans: Font, sans_tracked: Font, mono: Font, mono_tracked: Font) -> void:
	_sans = sans
	_sans_tracked = sans_tracked
	_mono = mono
	_mono_tracked = mono_tracked
	if stage != null:
		stage.set_ui_font(mono)
	if _ribbon != null:
		_ribbon.font = mono


func _ready() -> void:
	_ensure_fonts()
	_place()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_stage())
	root.add_child(_build_ribbon())
	root.add_child(_build_loop())
	root.add_child(_build_tells())
	root.add_child(_build_controls())
	set_subject(subject)
	refresh()


func _exit_tree() -> void:
	# The clock is the one thing here that is not this panel's own: leaving it
	# stopped because a drawer went away with the window would freeze the game.
	set_open(false)


## Whose loop this is.
func set_subject(each: Creature2) -> void:
	subject = each
	if stage != null:
		stage.creature = each
	_watch(_open)


## How wide a column the drawer takes in the dock — see HudDock. The field pays
## for exactly this much, so it is the one answer and it is asked every frame.
func dock_width() -> float:
	return _width


## Told how tall the dock is. The three views are the drawer's one expanding
## section, exactly as the specimen is the anatomy drawer's: on a short window
## the picture gives way and every reading under it stays on screen, because a
## number that has been pushed off the bottom is a number that is not being read.
##
## The column is re-measured here too. It is the one moment the panel is told the
## window changed, and a drawer that took a fixed 880 px would swallow a small
## window whole and waste a large one.
func fit_to_height(available: float) -> void:
	_dock_height = available
	_refit_width()
	_fit_stage()
	# ...and again once the layout has actually happened. A control's minimum size
	# settles a frame after its children are built, so the first fit of a panel
	# that has only just been assembled is taken against a chrome that is still
	# missing its last few rows — which is a picture that hangs off the bottom of
	# the window by however much was not counted yet.
	call_deferred("_fit_stage")


func _fit_stage() -> void:
	if _stage_wrap == null or _dock_height <= 0.0:
		return
	var chrome: float = get_combined_minimum_size().y - _stage_wrap.custom_minimum_size.y
	var tall: float = clampf(_dock_height - chrome, STAGE_MIN_HEIGHT, STAGE_HEIGHT)
	if absf(tall - _stage_wrap.custom_minimum_size.y) < 0.5:
		return
	_stage_wrap.custom_minimum_size.y = tall


func _refit_width() -> void:
	var wide: float = clampf(get_viewport_rect().size.x * WIDTH_SHARE,
		WIDTH_MIN, WIDTH)
	if is_equal_approx(wide, _width):
		return
	_width = wide
	HudDock.place(self, _width)


## Opened or closed. Opening switches the recording on and hands the panel the
## clock; closing gives both back.
func set_open(on: bool) -> void:
	if _open == on:
		return
	_open = on
	_watch(on)
	if not on:
		_paused = false
		Engine.time_scale = 1.0
	else:
		_apply_time()
	_style_time()


func is_open() -> bool:
	return _open


## Pause, and the frame-step out of it. A footfall lasts about a fifth of a
## second, which is twelve ticks — the only way to see what happened inside one
## is to walk through it a tick at a time.
func toggle_pause() -> void:
	_paused = not _paused
	_apply_time()
	_style_time()


## One physics tick, by hand.
##
## Driven directly rather than by letting the clock run for a frame, because a
## frame is however many ticks the accumulator had in it — nought, one or three —
## and a step that steps an unknown amount is not a step. This is the same hand
## the probes advance a body with (`Creature2.simulate`).
func step_once() -> void:
	if subject == null or not _paused:
		return
	subject._physics_process(1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0))
	refresh()


func paused() -> bool:
	return _paused


## How fast the world runs while this panel is open, 0.10×–1.50×.
func set_rate(rate: float) -> void:
	_speed = clampf(rate, RATE_MIN, RATE_MAX)
	if _rate != null:
		_rate.set_value_silent(_speed)
	_apply_time()
	_style_time()


func _watch(on: bool) -> void:
	if subject != null:
		subject.motion_readout().watch(on)
	if _ribbon != null:
		_ribbon.readout = subject.motion_readout() if subject != null else null


func _apply_time() -> void:
	if not _open:
		return
	Engine.time_scale = 0.0 if _paused else _speed


# ---------------------------------------------------------------- the reading ----

## Re-reads the loop. Every number below is a query on the one seam, taken fresh:
## nothing here is stored between frames, and nothing here is averaged.
func refresh() -> void:
	if _state == null or subject == null:
		return
	var r: MotionReadout = subject.motion_readout()
	_ribbon.readout = r
	_state.text = str(r.state)
	_state.add_theme_color_override("font_color",
		RED if r.state in [&"COLLAPSED", &"RESCUE", &"FALLING", &"BALKED"] \
		else Color(INK, 0.72))
	_clock.text = "%0.1f S" % r.clock

	_put("ASK", "%.0f PX/S" % r.ask)
	_put("SPEED", "%.1f PX/S" % r.speed)
	_put("DEMAND", "%.0f PX/S²" % r.demand)
	_put("DELIVERED", "%.0f PX/S²" % r.delivered)
	_put("CEILING", "%.0f PX/S²" % r.ceiling)
	_put("GRIP", "%.2f" % r.grip)
	_put("ANG VEL", "%.2f RAD/S" % r.ang_vel)
	_put("FEET DOWN", "%d / %d" % [r.feet_down, r.steps.size()])
	_put("MARGIN", "%.1f PX" % r.margin, RED if r.margin < 0.0 else Color(INK, 0.82))
	_put("BASE", "%.0f PX" % r.span)
	# How high the weight rides over the ground it is standing on, which is what
	# the sagittal is a picture of — and the reading the bob tell is taken from.
	_put("COM Z", "%.1f PX" % (r.com_height - subject.ground_at(r.com)))
	_put("STEADINESS", "%.2f" % r.steadiness)
	_put("ROLL", "%.1f°" % rad_to_deg(r.roll),
		RED if r.strained else Color(INK, 0.82))
	_put("RIGHTING", "%.1f / %.1f" % [r.righting, r.righting_ceiling])
	_put("HEADROOM", "%.2f" % r.headroom,
		RED if r.headroom <= 0.0 else Color(INK, 0.82))
	_put("SEATS", "%d" % r.seats)

	_read_tells(r)
	# The picture is given whatever the readings under it do not want, and what
	# they want settles a frame or two after the panel is built and again every
	# time a row changes its mind about how wide a number is. Cheap, and it is a
	# fixed point rather than a loop: `_fit_stage` does nothing once it agrees
	# with itself.
	_fit_stage()
	stage.queue_redraw()
	_ribbon.queue_redraw()


## The eight tells, banded. The judgement is MotionRead's — this only hands each
## gauge the row that belongs to it.
func _read_tells(r: MotionReadout) -> void:
	var rows: Array = MotionRead.reading(r)["rows"]
	for i in mini(rows.size(), _tells.size()):
		_tells[i].show_row(rows[i])


func _put(key: String, text: String, ink: Color = Color(INK, 0.82)) -> void:
	var label: Label = _loop.get(key)
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", ink)


# ------------------------------------------------------------------- layout ----

func _place() -> void:
	_width = clampf(get_viewport_rect().size.x * WIDTH_SHARE, WIDTH_MIN, WIDTH)
	HudDock.place(self, _width)
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


## Who this is, what it is doing, and — because a switch belongs against the
## thing it switches — which of the views are up. The five toggles sit directly
## over the panes rather than in the control block at the foot of the column:
## they are about the picture, not about the clock, and a reader turning the plan
## off is looking at the plan while they do it.
func _build_header() -> Control:
	var section := _section(16.0, 12.0, 10.0, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	section.add_child(row)
	row.add_child(_mark(6.0))
	row.add_child(_label("PHYSICS", 11, _sans_tracked, INK))

	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 5)
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(views)
	for entry in [["SAGITTAL", "sagittal"], ["PLAN", "plan"], ["FRONTAL", "frontal"],
			["HULL", "hull"], ["TRAILS", "trails"]]:
		var chip := _chip_button(str(entry[0]), Callable())
		chip.custom_minimum_size.y = 26.0
		chip.pressed.connect(_toggle_shown.bind(str(entry[1])))
		views.add_child(chip)
		_chips.append({"chip": chip, "what": str(entry[1])})

	_state = _label("STANDING", 10, _mono_tracked, Color(INK, 0.72))
	row.add_child(_state)
	_clock = _label("0.0 S", 10, _mono_tracked, Color(INK, 0.34))
	_clock.custom_minimum_size.x = 60.0
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_clock)
	return section


func _build_stage() -> Control:
	var section := _section(12.0, 2.0, 8.0, true)
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_wrap = Control.new()
	_stage_wrap.custom_minimum_size = Vector2(0.0, STAGE_HEIGHT)
	_stage_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_wrap.clip_contents = true
	section.add_child(_stage_wrap)
	stage = MotionStage.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.set_ui_font(_mono)
	stage.creature = subject
	_stage_wrap.add_child(stage)
	return section


func _build_ribbon() -> Control:
	var section := _section(12.0, 8.0, 9.0, true)
	_ribbon = MotionRead.Ribbon.new()
	# Shorter than the strip asks for: every row the timeline takes comes out of
	# the picture above it, and the strip lays itself out in whatever height it
	# is given.
	_ribbon.custom_minimum_size.y = RIBBON_HEIGHT
	_ribbon.font = _mono
	section.add_child(_ribbon)
	return section


func _build_loop() -> Control:
	var section := _section(16.0, 10.0, 11.0, true)
	# A cell per reading rather than a column per word: with one grid separation
	# doing both jobs, the gap between a caption and its own number is the same
	# gap as the one to the next caption along, and the row stops reading as four
	# pairs. Inside a cell the two are pushed apart; between cells they are held
	# apart by the grid.
	var grid := GridContainer.new()
	grid.columns = LOOP_COLUMNS
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	section.add_child(grid)
	for key in LOOP:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)
		cell.add_child(_label(key, 9, _mono_tracked, Color(INK, 0.40)))
		var value := _label("—", 10, _mono_tracked, Color(INK, 0.82))
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_loop[key] = value
		cell.add_child(value)
	return section


## The eight tells, as gauges rather than as a table: each is a caret on the band
## it is natural inside, so eight judgements are one glance across two rows —
## every caret between its two shoulders is an animal that moves like one.
##
## What is deliberately not here any more is the paragraph that used to explain
## whichever tell was furthest out. It is four lines of prose in the middle of a
## panel whose whole subject is a moving picture, and the gauge says the same
## thing in the one place the reader is already looking. The mechanism behind
## each band still has one home — `MotionRead.TELLS` — and the bench still prints
## it.
func _build_tells() -> Control:
	var section := _section(16.0, 10.0, 11.0, true)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	section.add_child(column)

	var caption := HBoxContainer.new()
	caption.add_theme_constant_override("separation", 8)
	caption.add_child(_label("TELLS", 9, _sans_tracked, Color(INK, 0.38)))
	caption.add_child(_spacer())
	caption.add_child(_label("CARET IN THE BAND IS NATURAL", 8, _mono_tracked,
		Color(INK, 0.30)))
	column.add_child(caption)

	var grid := GridContainer.new()
	grid.columns = TELL_COLUMNS
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for tell in TELLS:
		var gauge := MotionRead.Band.new(str(tell["label"]), float(tell["low"]),
			float(tell["high"]))
		gauge.font = _mono_tracked
		gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(gauge)
		_tells.append(gauge)
	return section


## The clock — the panel's own and the only thing here that is not a reading,
## which is why it is the only control at the foot of the column: everything else
## about the animal is driven by playing the game, and a HUD that could steer
## would be a second set of hands. What is drawn is switched from the header,
## against the picture it switches.
func _build_controls() -> Control:
	var section := _section(16.0, 12.0, 14.0, false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	section.add_child(row)
	_pause = _chip_button("PAUSE", toggle_pause)
	_pause.custom_minimum_size = Vector2(104.0, 32.0)
	row.add_child(_pause)
	_step = _chip_button("STEP", step_once)
	_step.custom_minimum_size = Vector2(84.0, 32.0)
	row.add_child(_step)
	var gap := Control.new()
	gap.custom_minimum_size.x = 10.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	row.add_child(_label("SLOW-MO", 9, _mono_tracked, Color(INK, 0.45)))
	_rate = MinimalSlider.new()
	_rate.min_value = RATE_MIN
	_rate.max_value = RATE_MAX
	_rate.step = 0.05
	_rate.value = 1.0
	_rate.reference = 1.0
	_rate.custom_minimum_size = Vector2(150.0, 32.0)
	_rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rate.value_changed.connect(set_rate)
	row.add_child(_rate)
	_rate_value = _label("1.00×", 10, _mono_tracked, RED)
	_rate_value.custom_minimum_size.x = 50.0
	_rate_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_rate_value)
	_style_time()
	_style_chips()
	return section


# ----------------------------------------------------------------- reaction ----

func _toggle_shown(what: String) -> void:
	match what:
		"sagittal":
			stage.show_sagittal = not stage.show_sagittal
		"plan":
			stage.show_plan = not stage.show_plan
		"frontal":
			stage.show_frontal = not stage.show_frontal
		"hull":
			stage.show_hull = not stage.show_hull
		_:
			stage.show_trails = not stage.show_trails
	_style_chips()
	stage.queue_redraw()


func _shown(what: String) -> bool:
	match what:
		"sagittal":
			return stage.show_sagittal
		"plan":
			return stage.show_plan
		"frontal":
			return stage.show_frontal
		"hull":
			return stage.show_hull
		_:
			return stage.show_trails


## Which views are up, said in ink rather than in a hairline: a switch whose only
## difference between on and off is the alpha of its own border is a switch that
## has to be compared with its neighbours to be read at all.
func _style_chips() -> void:
	for entry in _chips:
		var chip: Button = entry["chip"]
		var on: bool = _shown(str(entry["what"]))
		chip.add_theme_color_override("font_color", INK if on else Color(INK, 0.38))
		chip.add_theme_stylebox_override("normal",
			_chip_style(0.55 if on else 0.14, 0.07 if on else 0.0))
		chip.add_theme_stylebox_override("hover",
			_chip_style(0.55, 0.10 if on else 0.03))
		chip.add_theme_stylebox_override("pressed", _chip_style(0.65, 0.12))


func _style_time() -> void:
	if _pause == null:
		return
	_pause.text = "RUN" if _paused else "PAUSE"
	_pause.add_theme_color_override("font_color", RED if _paused else Color(INK, 0.7))
	_pause.add_theme_stylebox_override("normal",
		_chip_style(0.55, 0.07) if _paused else _chip_style(0.28))
	# Stepping is only a thing a stopped world can do, and the button says so.
	_step.add_theme_color_override("font_color",
		Color(INK, 0.7) if _paused else Color(INK, 0.24))
	_step.add_theme_stylebox_override("normal", _chip_style(0.28 if _paused else 0.12))
	if _rate_value != null:
		_rate_value.text = "%.2f×" % _speed
		_rate_value.add_theme_color_override("font_color",
			RED if not is_equal_approx(_speed, 1.0) else Color(INK, 0.42))


# -------------------------------------------------------------------- parts ----

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


func _chip_button(text: String, pressed: Callable) -> Button:
	var chip := Button.new()
	chip.text = text
	# Deliberately not `flat`: a flat button draws no box at all whatever styles
	# are hung on it, and the box is the control — without one the five view
	# switches are a row of words that happen to be clickable, and nothing about
	# them says which are on.
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size.y = 26.0
	chip.add_theme_font_override("font", _mono_tracked)
	chip.add_theme_font_size_override("font_size", 9)
	chip.add_theme_stylebox_override("normal", _chip_style(0.28))
	chip.add_theme_stylebox_override("hover", _chip_style(0.45, 0.04))
	chip.add_theme_stylebox_override("pressed", _chip_style(0.6, 0.10))
	if pressed.is_valid():
		chip.pressed.connect(pressed)
	return chip


func _chip_style(border_alpha: float, fill_alpha: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT if fill_alpha <= 0.0 else Color(INK, fill_alpha)
	style.border_color = Color(INK, border_alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _mark(mark_size: float) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(mark_size, mark_size)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(mark_size, mark_size)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = RED
	style.set_corner_radius_all(int(ceil(mark_size * 0.5)))
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
