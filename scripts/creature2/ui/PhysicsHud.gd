## The Physics HUD: the locomotion loop, full screen, while it runs.
##
## Built from `Evolution Game UI Design-7/Physics HUD.dc.html`, which is the
## layout's source of truth — the two rails and the three-view canvas between
## them, the type scale, the ink, the order of every reading. What is *not* taken
## from the handoff is its arithmetic: the mock carries a JavaScript
## re-implementation of the mover, and every number here comes instead from the
## one seam `Travel` publishes (`MotionReadout`). Where the two disagree the game
## wins.
##
## It exists because two things about a walking animal cannot be seen by watching
## it walk — *why* a foot stepped when it did, and *where* the stiffness in the
## picture is coming from — and both are decisions the loop makes several times a
## second and then throws away.
##
## A pure reader of the body, and strictly: it owns no simulation state, no second
## centre of mass, no smoothing. The two things it does own are the clock (pause,
## frame-step, slow motion — half of judging whether a movement reads naturally is
## being able to slow it down) and the hand on the controls (the drive and the
## nine scenarios, which are commands and nothing else — see `MotionScenario`).
##
## The lab keeps its own narrow version of this panel for use while the game is
## being played (`MotionDrawer`); the bands, the marks and the timeline are shared
## by both (`MotionRead`).
class_name PhysicsHud
extends Control

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
const RED := Color("8e1b12")

## The page, as the handoff lays it out: the rails stand off the window edges and
## the canvas fills what is between them.
const MARGIN: float = 32.0
const TOP: float = 30.0
const LEFT_RAIL: float = 250.0
const RIGHT_RAIL: float = 176.0
const CANVAS_LEFT: float = 302.0
const CANVAS_RIGHT: float = 230.0
const CANVAS_TOP: float = 24.0
const CANVAS_BOTTOM: float = 24.0
## The hairline the whole page sits inside.
const FRAME: float = 14.0
## Air between the three views and the timeline under them.
const CANVAS_GUTTER: float = 14.0

## Slow motion's ends. Under a tenth nothing is legible as movement any more, and
## over one and a half the animal is being lied about.
const RATE_MIN: float = 0.10
const RATE_MAX: float = 1.50
## What an arrow key moves the drive by.
const NUDGE: float = 0.06

## What the loop prints of itself, in the order the loop happens: the intent, the
## middle, the feet, the weight, the attitude, and the scenario's own clock.
const LOOP: Array[String] = [
	"ASK", "SPEED", "DEMAND", "DELIVERED", "CEILING", "GRIP", "ANG VEL",
	"FEET DOWN", "MARGIN", "BASE", "STEADINESS", "ROLL", "RIGHTING",
	"SCENARIO T",
]

## The states that are the body being *had* rather than the body doing something.
const ALARM: Array[StringName] = [&"COLLAPSED", &"RESCUE", &"FALLING", &"BALKED"]


## A track with a caret on it — the drive and the slow motion, both drawn exactly
## as the handoff draws them: a hairline, the part of it that has been spent in
## solid ink, a red caret at the value and the scale written under it.
class Hairline extends Control:
	signal moved(share: float)

	var share: float = 0.0
	var ticks: PackedStringArray = PackedStringArray()
	var font: Font
	## Where the rule sits inside the control's own height.
	var rule: float = 11.0

	func _init(tall: float, rule_y: float, scale: PackedStringArray) -> void:
		custom_minimum_size = Vector2(0.0, tall)
		rule = rule_y
		ticks = scale
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_HSIZE

	func set_share(next: float) -> void:
		share = clampf(next, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var at: float = share * size.x
		draw_line(Vector2(0.0, rule), Vector2(size.x, rule),
			Color(PhysicsHud.INK, 0.22), 1.0)
		if at > 0.0:
			draw_line(Vector2(0.0, rule), Vector2(at, rule), PhysicsHud.INK, 1.0)
		draw_rect(Rect2(clampf(at - 1.0, 0.0, maxf(size.x - 2.0, 0.0)), rule - 5.0,
			2.0, 11.0), PhysicsHud.RED)
		if font == null or ticks.is_empty():
			return
		var y: float = rule + 13.0
		for i in ticks.size():
			var text: String = ticks[i]
			var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 8).x
			# Spread like the handoff's flex row: the ends are flush with the track
			# and the rest are laid out evenly between them.
			var x: float = 0.0 if i == 0 else (size.x - wide if i == ticks.size() - 1 \
				else (size.x - wide) * float(i) / float(ticks.size() - 1))
			draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8,
				Color(PhysicsHud.INK, 0.30))

	func _gui_input(event: InputEvent) -> void:
		var pressing: bool = event is InputEventMouseButton \
			and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		var dragging: bool = event is InputEventMouseMotion \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if not pressing and not dragging:
			return
		set_share((event as InputEventMouse).position.x / maxf(size.x, 1.0))
		moved.emit(share)
		accept_event()


## One scenario in the list: its tag, its name, and the rule under whichever one
## is running.
class ScenarioRow extends Control:
	signal picked(which: int)

	var which: int = 0
	var tag: String = ""
	var title: String = ""
	var active: bool = false
	var mono: Font
	var sans: Font

	func _init(index: int, p_tag: String, p_title: String) -> void:
		which = index
		tag = p_tag
		title = p_title
		custom_minimum_size = Vector2(0.0, 24.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_active(on: bool) -> void:
		active = on
		queue_redraw()

	func set_title(next: String) -> void:
		title = next
		queue_redraw()

	func _draw() -> void:
		var mid: float = size.y * 0.5 + 3.0
		if mono != null:
			draw_string(mono, Vector2(0.0, mid), tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				9, PhysicsHud.RED if active else Color(PhysicsHud.INK, 0.28))
		var over: float = 0.0
		if mono != null:
			over = mono.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
		if sans != null:
			draw_string(sans, Vector2(over + 9.0, mid), title,
				HORIZONTAL_ALIGNMENT_LEFT, size.x - over - 9.0, 9,
				PhysicsHud.INK if active else Color(PhysicsHud.INK, 0.42))
		if active:
			draw_line(Vector2(0.0, size.y - 0.5), Vector2(size.x, size.y - 0.5),
				PhysicsHud.INK, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			picked.emit(which)
			accept_event()


## The three tabs the handoff carries in its corner. Physics is the one this
## screen is, and the other two are the other handoffs — there is no blood or
## gait screen in v2 to send anybody to, so they are drawn as the mock draws an
## unselected tab and do nothing, rather than being wired to a lie.
class TabRow extends Control:
	const PAD: float = 12.0
	var tabs: PackedStringArray = PackedStringArray(["BLOOD", "GAIT", "PHYSICS"])
	var here: int = 2
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 26.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if font == null:
			return
		var x: float = 0.0
		for i in tabs.size():
			var text: String = tabs[i]
			var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 9).x
			var dot: float = 11.0 if i == here else 0.0
			draw_string(font, Vector2(x + dot, 16.0), text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 9, PhysicsHud.INK if i == here else Color(PhysicsHud.INK, 0.42))
			if i == here:
				draw_circle(Vector2(x + 2.0, 12.5), 2.0, PhysicsHud.RED)
				draw_line(Vector2(x - 4.0, 23.5), Vector2(x + dot + wide + 4.0, 23.5),
					PhysicsHud.INK, 1.0)
			x += dot + wide + PAD * 2.0


var subject: Creature2
var scenario: MotionScenario
var stage: MotionStage

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _ribbon: MotionRead.Ribbon
var _state: Label
var _loop: Dictionary = {}
var _tells: Array[Dictionary] = []
var _note: Label
var _rows: Array[ScenarioRow] = []
var _drive: Hairline
var _drive_value: Label
var _rate_slider: Hairline
var _rate_value: Label
var _pause: Button
var _step: Button

var _paused: bool = false
var _speed: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_fonts()
	_build_ground()
	_build_canvas()
	_build_overlays()
	_build_left_rail()
	_build_right_rail()
	_watch(true)
	_style_time()
	refresh()


func _exit_tree() -> void:
	# The clock is the one thing here that is not this panel's own: leaving it
	# stopped because a window went away would freeze the world.
	Engine.time_scale = 1.0
	_watch(false)


func _process(_delta: float) -> void:
	refresh()


## Whose loop this is.
func set_subject(each: Creature2) -> void:
	subject = each
	if stage != null:
		stage.creature = each
	_watch(true)


## The hand on the controls — the drive and the nine scenarios.
func set_scenario(each: MotionScenario) -> void:
	scenario = each
	_name_scenarios()


# ------------------------------------------------------------------ the clock ----

## Pause, and the frame-step out of it. A footfall lasts about a fifth of a
## second, which is twelve ticks — the only way to see what happened inside one is
## to walk through it a tick at a time.
func toggle_pause() -> void:
	_paused = not _paused
	_apply_time()
	_style_time()


func paused() -> bool:
	return _paused


## One physics tick, by hand — the scenario's ask and then the body's own tick, in
## the order the bench runs them.
##
## Driven directly rather than by letting the clock run for a frame, because a
## frame is however many ticks the accumulator had in it — nought, one or three —
## and a step that steps an unknown amount is not a step.
func step_once() -> void:
	if subject == null or not _paused:
		return
	var step: float = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	if scenario != null:
		scenario.tick(step)
	subject._physics_process(step)
	refresh()


## How fast the world runs, 0.10×–1.50×.
func set_rate(rate: float) -> void:
	_speed = clampf(rate, RATE_MIN, RATE_MAX)
	if _rate_slider != null:
		_rate_slider.set_share((_speed - RATE_MIN) / (RATE_MAX - RATE_MIN))
	_apply_time()
	_style_time()


func rate() -> float:
	return _speed


# --------------------------------------------------------------- the controls ----

## Picks a scenario: the ground is rebuilt, the body goes back to its start and
## the record is cleared.
func pick_scenario(which: int) -> void:
	if scenario == null:
		return
	scenario.pick(which)
	_name_scenarios()
	refresh()


## The arrow keys under the drive slider.
func nudge_drive(by: float) -> void:
	if scenario == null:
		return
	scenario.nudge(by)
	refresh()


func _drive_moved(share: float) -> void:
	if scenario != null:
		scenario.hand_drive(share)


func _rate_moved(share: float) -> void:
	set_rate(RATE_MIN + share * (RATE_MAX - RATE_MIN))


func _watch(on: bool) -> void:
	if subject != null:
		subject.motion_readout().watch(on)
	if _ribbon != null:
		_ribbon.readout = subject.motion_readout() if subject != null else null


func _apply_time() -> void:
	Engine.time_scale = 0.0 if _paused else _speed


# ------------------------------------------------------------------ the reading ----

## Re-reads the loop. Every number below is a query on the one seam, taken fresh:
## nothing here is stored between frames, and nothing here is averaged.
func refresh() -> void:
	if _state == null or subject == null:
		return
	var r: MotionReadout = subject.motion_readout()
	_ribbon.readout = r
	_state.text = str(r.state)
	_state.add_theme_color_override("font_color",
		RED if r.state in ALARM else Color(INK, 0.72))

	_put("ASK", "%.0f PX/S" % r.ask)
	_put("SPEED", "%.1f PX/S" % r.speed)
	_put("DEMAND", "%.0f PX/S²" % r.demand)
	_put("DELIVERED", "%.0f PX/S²" % r.delivered)
	_put("CEILING", "%.0f PX/S²" % r.ceiling)
	_put("GRIP", "%.2f" % r.grip)
	_put("ANG VEL", "%.2f RAD/S" % r.ang_vel)
	_put("FEET DOWN", "%d / %d" % [r.feet_down, r.steps.size()])
	_put("MARGIN", "%.1f PX" % r.margin, RED if r.margin < 0.0 else Color(INK, 0.82))
	# How wide the support the margin is measured inside actually is — printed
	# here rather than under the plan, where it used to sit on top of the picture.
	_put("BASE", "%.0f PX" % r.span)
	_put("STEADINESS", "%.2f" % r.steadiness)
	_put("ROLL", "%.1f°" % rad_to_deg(r.roll), RED if r.strained else Color(INK, 0.82))
	_put("RIGHTING", "%.1f / %.1f" % [r.righting, r.righting_ceiling])
	_put("SCENARIO T", "+%.2f S" % (scenario.elapsed if scenario != null else 0.0))

	var reading: Dictionary = MotionRead.reading(r)
	var rows: Array = reading["rows"]
	for i in mini(rows.size(), _tells.size()):
		var row: Dictionary = rows[i]
		var value: Label = _tells[i]["value"]
		var verdict: Label = _tells[i]["verdict"]
		value.text = str(row["value"])
		value.add_theme_color_override("font_color", row["value_ink"])
		verdict.text = str(row["verdict"])
		verdict.add_theme_color_override("font_color", row["verdict_ink"])
	_note.text = str(reading["note"])
	_note.add_theme_color_override("font_color", reading["note_ink"])

	if scenario != null:
		_drive.set_share(scenario.drive)
		_drive_value.text = "%d PX/S" % int(round(scenario.ask_speed()))
		for row in _rows:
			row.set_active(row.which == scenario.index)
	stage.queue_redraw()
	_ribbon.queue_redraw()


func _put(key: String, text: String, ink: Color = Color(INK, 0.82)) -> void:
	var label: Label = _loop.get(key)
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", ink)


func _name_scenarios() -> void:
	if scenario == null:
		return
	for row in _rows:
		row.set_title(scenario.label(row.which))
		row.set_active(row.which == scenario.index)


# ---------------------------------------------------------------------- layout ----

## The page's own ground, under everything: the paper the whole design is printed
## on, so the screen is the same sheet whatever is (or is not) behind it.
func _build_ground() -> void:
	var paper := ColorRect.new()
	paper.name = "Paper"
	paper.color = PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)


## The middle of the page: the three views of the moving body, and the timeline of
## the last few seconds under them. Both are the drawn armature and the recorded
## ring — see MotionStage and MotionRead.Ribbon.
func _build_canvas() -> void:
	var canvas := Control.new()
	canvas.name = "Canvas"
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.offset_left = CANVAS_LEFT
	canvas.offset_top = CANVAS_TOP
	canvas.offset_right = -CANVAS_RIGHT
	canvas.offset_bottom = -CANVAS_BOTTOM
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.clip_contents = true
	add_child(canvas)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", int(CANVAS_GUTTER))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(column)

	stage = MotionStage.new()
	stage.set_ui_font(_mono)
	stage.creature = subject
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 200.0
	column.add_child(stage)

	_ribbon = MotionRead.Ribbon.new()
	_ribbon.font = _mono
	column.add_child(_ribbon)


## The three marks the handoff lays over the whole page: the vignette that pulls
## the eye into the middle of the sheet, the grain that keeps a flat colour from
## reading as a screen, and the hairline the design is printed inside.
func _build_overlays() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.45, 1.0])
	gradient.colors = PackedColorArray([Color(INK, 0.0), Color(INK, 0.055)])
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.42)
	vignette_texture.fill_to = Vector2(1.075, 0.42)
	vignette_texture.width = 128
	vignette_texture.height = 128
	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = vignette_texture
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 0.42
	noise.fractal_octaves = 3
	var grain_texture := NoiseTexture2D.new()
	grain_texture.noise = noise
	grain_texture.width = 140
	grain_texture.height = 140
	grain_texture.seamless = true
	var grain := TextureRect.new()
	grain.name = "Grain"
	grain.texture = grain_texture
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.modulate = Color(INK.r, INK.g, INK.b, 0.035)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grain)

	var frame := Panel.new()
	frame.name = "InsetFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = FRAME
	frame.offset_top = FRAME
	frame.offset_right = -FRAME
	frame.offset_bottom = -FRAME
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, 0.10)
	style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)


## The left rail: who this is, what the loop is doing, and what the eight tells
## make of it.
func _build_left_rail() -> void:
	# The column is a fixed 250 px of page, and the readings inside it are right
	# aligned to that edge — so the rail keeps its width instead of being set by
	# whichever verdict happens to be the longest word this tick.
	var column := Control.new()
	column.name = "LoopColumn"
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	column.offset_left = MARGIN
	column.offset_top = TOP
	column.offset_right = MARGIN + LEFT_RAIL
	column.offset_bottom = TOP
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var rail := VBoxContainer.new()
	rail.name = "Loop"
	rail.anchor_right = 1.0
	rail.offset_right = 0.0
	rail.add_theme_constant_override("separation", 14)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rail)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 11)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(_dot(7.0))
	identity.add_child(_label("EVOLUTION", 11, _sans_tracked, INK))
	rail.add_child(identity)

	rail.add_child(_label("CREATURE  PHYSICS  V2  0.1", 9, _mono_tracked,
		Color(INK, 0.42)))

	var tabs := TabRow.new()
	tabs.font = _sans_tracked
	rail.add_child(tabs)

	rail.add_child(_rule_header("THE LOOP", _state_label()))

	var loop := GridContainer.new()
	loop.columns = 2
	loop.add_theme_constant_override("h_separation", 14)
	loop.add_theme_constant_override("v_separation", 3)
	loop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(loop)
	for key in LOOP:
		loop.add_child(_label(key, 10, _mono_tracked, Color(INK, 0.5)))
		var value := _label("—", 10, _mono_tracked, Color(INK, 0.82))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size.x = 96.0
		_loop[key] = value
		loop.add_child(value)

	rail.add_child(_gap(6.0))
	rail.add_child(_rule_header("TELLS",
		_label("NATURAL BAND", 8, _mono_tracked, Color(INK, 0.35))))

	var tells := GridContainer.new()
	tells.columns = 3
	tells.add_theme_constant_override("h_separation", 10)
	tells.add_theme_constant_override("v_separation", 3)
	tells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(tells)
	for tell in MotionRead.TELLS:
		tells.add_child(_label(str(tell["label"]), 9, _mono_tracked, Color(INK, 0.5)))
		var value := _label("—", 9, _mono_tracked, Color(INK, 0.82))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tells.add_child(value)
		var verdict := _label("—", 9, _mono_tracked, Color(INK, 0.25))
		verdict.custom_minimum_size.x = 46.0
		tells.add_child(verdict)
		_tells.append({"value": value, "verdict": verdict})

	_note = _label("", 8, _mono_tracked, Color(INK, 0.38))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(0.0, 40.0)
	_note.add_theme_constant_override("line_spacing", 6)
	rail.add_child(_note)


## The right rail: the hand on the animal (the drive and the nine scenarios), the
## hand on the clock, and what the marks in the picture mean.
func _build_right_rail() -> void:
	var rail := VBoxContainer.new()
	rail.name = "Controls"
	rail.anchor_left = 1.0
	rail.anchor_right = 1.0
	rail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rail.offset_left = -(MARGIN + RIGHT_RAIL)
	rail.offset_right = -MARGIN
	rail.offset_top = TOP
	rail.add_theme_constant_override("separation", 9)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)

	_drive_value = _label("0 PX/S", 9, _mono_tracked, RED)
	_drive_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rail.add_child(_rule_header("DRIVE", _drive_value))

	_drive = Hairline.new(24.0, 11.0,
		PackedStringArray(["0", "STROLL", "CRUISE", "SPRINT"]))
	_drive.font = _mono
	_drive.moved.connect(_drive_moved)
	rail.add_child(_drive)

	rail.add_child(_gap(8.0))
	rail.add_child(_rule_header("SCENARIO", null))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(list)
	for i in MotionScenario.CASES.size():
		var row := ScenarioRow.new(i, str(MotionScenario.CASES[i]["tag"]),
			str(MotionScenario.CASES[i]["name"]))
		row.mono = _mono
		row.sans = _sans_tracked
		row.picked.connect(pick_scenario)
		list.add_child(row)
		_rows.append(row)

	rail.add_child(_gap(8.0))
	rail.add_child(_rule_header("TIME", null))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(buttons)
	_pause = _chip("PAUSE", toggle_pause)
	buttons.add_child(_pause)
	_step = _chip("STEP", step_once)
	buttons.add_child(_step)

	var slow := HBoxContainer.new()
	slow.add_theme_constant_override("separation", 6)
	slow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slow.add_child(_label("SLOW-MO", 8, _mono_tracked, Color(INK, 0.45)))
	slow.add_child(_spacer())
	_rate_value = _label("1.00×", 9, _mono_tracked, RED)
	slow.add_child(_rate_value)
	rail.add_child(slow)

	_rate_slider = Hairline.new(20.0, 8.0,
		PackedStringArray(["0.10×", "1.00×", "1.50×"]))
	_rate_slider.font = _mono
	_rate_slider.set_share((1.0 - RATE_MIN) / (RATE_MAX - RATE_MIN))
	_rate_slider.moved.connect(_rate_moved)
	rail.add_child(_rate_slider)

	rail.add_child(_gap(8.0))
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 5)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(legend)
	for entry in MotionRead.LEGEND:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_glyph(int(entry[0])))
		row.add_child(_label(str(entry[1]), 8, _mono_tracked, Color(INK, 0.44)))
		legend.add_child(row)

	rail.add_child(_gap(6.0))
	var keys := _label("SPACE PAUSE · . STEP\n1–9 SCENARIO · ◄► ASK\nA / D TURN",
		8, _mono_tracked, Color(INK, 0.32))
	keys.add_theme_constant_override("line_spacing", 6)
	rail.add_child(keys)


# ----------------------------------------------------------------------- parts ----

## A caption, a hairline across whatever is left, and — where a block has one —
## the reading that belongs to it on the right.
func _rule_header(caption: String, trailing: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label(caption, 9, _mono_tracked, Color(INK, 0.75)))
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.18)
	rule.custom_minimum_size = Vector2(10.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	if trailing != null:
		row.add_child(trailing)
	return row


func _state_label() -> Label:
	_state = _label("STANDING", 9, _mono_tracked, Color(INK, 0.72))
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return _state


func _chip(text: String, pressed: Callable) -> Button:
	var chip := Button.new()
	chip.text = text
	# Not `flat`: a flat button draws no box at all, and the box is the control —
	# the handoff's time buttons are a hairline rectangle with a word in it.
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size.y = 30.0
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_font_override("font", _mono_tracked)
	chip.add_theme_font_size_override("font_size", 9)
	chip.add_theme_stylebox_override("normal", _chip_style(0.28))
	chip.add_theme_stylebox_override("hover", _chip_style(0.45))
	chip.add_theme_stylebox_override("pressed", _chip_style(0.6))
	chip.pressed.connect(pressed)
	return chip


func _chip_style(border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(INK, border_alpha)
	style.set_border_width_all(1)
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _style_time() -> void:
	if _pause == null:
		return
	_pause.text = "RUN" if _paused else "PAUSE"
	_pause.add_theme_color_override("font_color", RED if _paused else Color(INK, 0.7))
	_pause.add_theme_stylebox_override("normal", _chip_style(0.45 if _paused else 0.28))
	_step.add_theme_color_override("font_color",
		Color(INK, 0.7) if _paused else Color(INK, 0.3))
	if _rate_value != null:
		_rate_value.text = "%.2f×" % _speed


func _glyph(kind: int) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(14.0, 10.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(MotionRead.Glyph.new(kind))
	return wrap


func _dot(across: float) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(across, across)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(across, across)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = RED
	style.set_corner_radius_all(int(ceil(across * 0.5)))
	mark.add_theme_stylebox_override("panel", style)
	wrap.add_child(mark)
	return wrap


func _gap(tall: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, tall)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


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


func _build_fonts() -> void:
	var sans := SystemFont.new()
	sans.font_names = PackedStringArray(
		["Helvetica Neue", "Helvetica", "Arial", "sans-serif"])
	sans.font_weight = 500
	var mono: Font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if mono == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(
			["IBM Plex Mono", "SF Mono", "Menlo", "PT Mono", "monospace"])
		mono = fallback
	_sans = _tracked(sans, 0)
	_sans_tracked = _tracked(sans, 2)
	_mono = _tracked(mono, 0)
	_mono_tracked = _tracked(mono, 1)


## The handoff's type is tracked out — the letter-spacing is most of what makes
## the small caps read as a label rather than as a word.
func _tracked(base: Font, spacing: int) -> Font:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.set_spacing(TextServer.SPACING_GLYPH, spacing)
	return variation
