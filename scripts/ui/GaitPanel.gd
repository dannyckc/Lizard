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
##   * the readout column — the pattern in Hildebrand's numbers: Froude, girdle
##     lag, the two splits, duty, lift and cycle, plus the machine underneath
##     them: what angle each girdle carries its joint at and what its tendon
##     lever gears the muscle to.
##   * the figure — a true side elevation of the solved skeleton. The limb
##     chains are the actual `plan`/`heights` FABRIK just produced, projected
##     along the body's own axis, so a folding knee here is the knee folding in
##     the world; nothing is re-animated for the panel.
##   * the footfall chart — one cycle, one row per bearing limb, each bar at the
##     phase the pattern holds that foot to, red while the real foot is down.
##
## The panel is a drawer rather than a page: it stands in exactly the rect the
## anatomy drawer stands in, so the two F3 stops read as one instrument being
## turned over — and the field stays visible beside it, which matters here more
## than anywhere: the walk being measured is happening out there.
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

## The drawer's rect is the anatomy drawer's rect, taken from it rather than
## restated, so the two can never drift apart.
const BAND: float = 48.0
const PAD: float = 16.0
## Vertical layout: the figure takes whatever the fixed bands leave over.
const HEADER_H: float = 36.0
const TABS_H: float = 60.0
## Two caption lines between the ground line and the chart.
const CAPTION_H: float = 46.0
## The 13 readout rows (8 pattern + 5 machine) at their pitch, plus the split.
const ROW_PITCH: float = 13.0
const READOUTS_H: float = 13.0 * ROW_PITCH + 8.0
## The wrapped two-sentence note plus the legend under it.
const FOOT_H: float = 84.0

var subject: Creature

var _sans: Font
var _sans_tracked: Font
var _mono: Font
var _mono_tracked: Font

var _species_buttons: Dictionary = {}
var _active_species: String = "Lizard"
var _time: float = 0.0
## Footfall rings: {at: Vector2 (world), t0: float}.
var _rings: Array[Dictionary] = []
## Per-limb trails of drawn foot positions, keyed as the limbs are.
var _trails: Dictionary = {}


var _style: StyleBoxFlat


func _ready() -> void:
	_place()
	clip_contents = true
	_build_species_tabs()


## The same rect, chrome and shadow as the anatomy drawer — see
## AnatomyPanel._place — so switching stops swaps the instrument, not the frame.
func _place() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -(AnatomyPanel.WIDTH + AnatomyPanel.INSET)
	offset_right = -AnatomyPanel.INSET
	offset_top = BAND
	offset_bottom = -BAND
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(PAPER, 0.86)
	_style.border_color = Color(INK, 0.13)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(2)
	_style.shadow_color = Color(INK, 0.14)
	_style.shadow_size = 20
	_style.shadow_offset = Vector2(0.0, 10.0)


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
	_collect_trails()
	queue_redraw()


## Six species in two rows of three: the drawer is a third the width the page
## was, so the tabs stack instead of queueing along the top edge.
func _build_species_tabs() -> void:
	var grid := GridContainer.new()
	grid.name = "SpeciesTabs"
	grid.columns = 3
	grid.set_anchors_preset(Control.PRESET_TOP_WIDE)
	grid.offset_left = PAD
	grid.offset_top = HEADER_H
	grid.offset_right = -PAD
	grid.offset_bottom = HEADER_H + TABS_H
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	var index: int = 1
	for preset_name in CreatureParams.PRESETS:
		var button := Button.new()
		button.text = "%02d  %s" % [index, str(preset_name).to_upper()]
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 26.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_on_species_pressed.bind(str(preset_name)))
		grid.add_child(button)
		_species_buttons[str(preset_name)] = button
		index += 1
	_style_species_tabs()


func _on_species_pressed(preset_name: String) -> void:
	species_selected.emit(preset_name)


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


func _refresh_frame() -> void:
	var line: Array = subject.gait.girdle_line()
	_centre = line[0]
	_fwd = line[1]
	# The fixed bands are measured up from the floor of the drawer; the figure is
	# given whatever is left between them and the tabs.
	_ground_y = size.y - FOOT_H - READOUTS_H - 14.0 - _chart_height() - CAPTION_H
	var fig_top: float = HEADER_H + TABS_H + 8.0
	var stand: float = maxf(subject.stature.stand_height(), 20.0)
	# Fit and centre the animal's actual extent along its own axis — nose past
	# the head, tail tip behind — rather than the girdle midpoint: a long-tailed
	# body centred on its girdles hangs its tail off the edge of the drawer.
	var ahead: float = (subject.body.head.pos - _centre).dot(_fwd) \
		+ subject.body.head_radius * 2.5
	var behind: float = (subject.spine.points[subject.body.last_index] - _centre).dot(_fwd)
	ahead = maxf(ahead, 10.0)
	behind = minf(behind, -10.0)
	_fig_scale = clampf(minf((size.x - PAD * 2.0 - 18.0) / (ahead - behind),
		(_ground_y - fig_top - 14.0) / maxf(stand, 1.0)), 0.16, 2.0)
	_fig_cx = size.x * 0.5 - (ahead + behind) * 0.5 * _fig_scale


func _chart_height() -> float:
	var rows: int = 4 if subject != null and subject.locomotion.forelimbs_bear else 2
	return 52.0 + rows * 20.0


func _to_fig(world: Vector2, height: float) -> Vector2:
	return Vector2(_fig_cx + (world - _centre).dot(_fwd) * _fig_scale,
		_ground_y - height * _fig_scale)


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
	_refresh_frame()
	_draw_ground()
	_draw_figure()
	_draw_caption()
	_draw_rings()
	_draw_chart()
	_draw_readouts()
	_draw_note()
	_draw_legend()


## The drawer's title row: the mark, the word, and the four regimes with the
## live one marked — they are indicators, not tabs; the keys drive the animal.
func _draw_header() -> void:
	draw_rect(Rect2(PAD, 15.0, 5.0, 5.0), INK)
	var font: Font = _sans_tracked if _sans_tracked != null else _mono
	draw_string(font, Vector2(PAD + 13.0, 22.0), "GAIT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
	draw_line(Vector2(0.0, HEADER_H - 4.5), Vector2(size.x, HEADER_H - 4.5),
		Color(INK, 0.11), 1.0)
	if not _usable():
		return
	var current: String = _regime()
	var x: float = size.x - PAD
	var labels: Array[String] = ["LAY LOW", "RUN", "WALK", "IDLE"]
	for label in labels:
		var wide: float = _mono_tracked.get_string_size(label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		x -= wide
		var active: bool = label == current
		_text(Vector2(x, 22.0), label, 8, INK if active else Color(INK, 0.35))
		if active:
			draw_rect(Rect2(x - 9.0, 17.0, 4.0, 4.0), RED)
		x -= 17.0


func _draw_ground() -> void:
	draw_line(Vector2(0.0, _ground_y + 0.5), Vector2(size.x, _ground_y + 0.5),
		Color(INK, 0.30), 1.0)
	# Ticks are nailed to the world, so the ground genuinely goes by at the speed
	# the animal is covering it — and holds still under one turning on the spot.
	var along: float = _centre.dot(_fwd)
	var half: float = _fig_cx / _fig_scale + TICK_SPACING
	var world_tick: float = floor((along - half) / TICK_SPACING) * TICK_SPACING
	while world_tick < along + half:
		var x: float = _fig_cx + (world_tick - along) * _fig_scale
		if x > -10.0 and x < size.x + 10.0:
			draw_line(Vector2(x, _ground_y + 4.0), Vector2(x, _ground_y + 10.0),
				Color(INK, 0.14), 1.0)
		world_tick += TICK_SPACING


func _draw_figure() -> void:
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
		_draw_limb(limb, false, quad)

	# The body's own depth as a soft silhouette between the girdles. Rounded off
	# at the ends so it reads as a trunk rather than a crate.
	var depth: float = maxf(stature.depth * _fig_scale * 0.6, 4.0)
	draw_line(hip, shoulder, Color(INK, 0.07), depth)
	draw_circle(hip, depth * 0.5, Color(INK, 0.07))
	draw_circle(shoulder, depth * 0.5, Color(INK, 0.07))

	_draw_tail(hip)

	# The back the two pairs of legs are holding up. Its pitch is the two heights,
	# not a pose: short arms draw it nose-down because they hold it nose-down.
	draw_line(hip, shoulder, Color(INK, 0.85), 1.7)

	# Neck and head, off the solved head and the measured carry height.
	var head: Vector2 = _to_fig(subject.body.head.pos, stature.head_height)
	var head_r: float = maxf(subject.body.head_radius * _fig_scale, 3.0)
	draw_line(shoulder, head, Color(INK, 0.85), 1.8)
	draw_arc(head, head_r, 0.0, TAU, 24, Color(INK, 0.85), 1.5, true)
	draw_circle(head + Vector2(head_r * 0.35, -head_r * 0.2), 1.6, INK)
	draw_line(head + Vector2(head_r * 0.7, head_r * 0.15),
		head + Vector2(head_r * 0.7 + head_r, head_r * 0.35), Color(INK, 0.85), 2.0)

	for trail_key in _trails:
		var trail: PackedVector2Array = _trails[trail_key]
		if trail.size() > 2:
			draw_polyline(trail, Color(INK, 0.09), 1.0)

	# Near side over the top, bold.
	for limb in gait.limbs:
		if limb.severed or limb.side > 0.0:
			continue
		_draw_limb(limb, true, quad)


## One limb, exactly as FABRIK left it: socket, joint, foot through the shared
## projection, with the fold the chain actually has. `quad` says whether the
## forelimbs bear; on a two-legged build they draw as carried arms.
func _draw_limb(limb: Limb, near: bool, quad: bool) -> void:
	var arm: bool = limb.pair == Limb.FRONT and not quad
	var alpha: float = (0.7 if arm else 0.9) if near else 0.30
	var ink := Color(INK, alpha)
	var width: float = (1.6 if arm else (2.2 if near else 1.8))
	var socket: Vector2 = _to_fig(limb.plan[0], limb.heights[0])
	var joint: Vector2 = _to_fig(limb.plan[1], limb.heights[1])
	var foot: Vector2 = _to_fig(limb.plan[2], limb.heights[2])
	var points := PackedVector2Array([socket, joint, foot])
	draw_polyline(points, ink, width, true)
	draw_circle(joint, 2.0, ink)
	if arm:
		return
	# The toe: down and rolled onto when planted, trailed when swinging.
	var toe: float = maxf(limb.foot_size * 2.0 * _fig_scale, 2.0)
	var down: bool = not limb.stepping and limb.bearing \
			and not subject.elevation.is_airborne()
	if down:
		var toe_tip := Vector2(foot.x + toe, _to_fig(limb.planted, limb.surface).y)
		draw_line(foot, toe_tip, ink, width)
		var mark := Color(RED, 1.0 if near else 0.35)
		draw_line(Vector2(foot.x - 4.0, toe_tip.y + 4.0),
			Vector2(foot.x + toe + 4.0, toe_tip.y + 4.0), mark, 2.0)
	else:
		draw_line(foot, foot + Vector2(toe * 0.65, toe * 0.4), ink, width)


func _draw_tail(hip: Vector2) -> void:
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
		draw_line(previous, here, Color(INK, lerpf(0.8, 0.55, t)), width)
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
	_text(Vector2(_fig_cx, _ground_y + 24.0), label, 8, Color(INK, 0.35), true, true)
	var pattern: String = _pattern_text()
	if not _idle():
		pattern += " — DUTY %.2f · CYCLE %.2f S" % [
			subject.gait.duty_measured(), subject.gait.cycle_length()]
	_text(Vector2(_fig_cx, _ground_y + 38.0), pattern, 8, Color(INK, 0.55), true, true)


func _draw_rings() -> void:
	var alive: Array[Dictionary] = []
	for ring in _rings:
		var age: float = _time - float(ring["t0"])
		if age >= RING_LIFE:
			continue
		alive.append(ring)
		var at: Vector2 = _to_fig(ring["at"], 0.0)
		if at.x < -20.0 or at.x > size.x + 20.0:
			continue
		draw_arc(at, 4.0 + age * 46.0, 0.0, TAU, 24,
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
	var y: float = _ground_y + CAPTION_H + _chart_height() + 14.0 + ROW_PITCH
	for row in rows:
		_text(Vector2(PAD, y), str(row[0]), 9, Color(INK, 0.40))
		_text(Vector2(118.0, y), str(row[1]), 9, Color(INK, 0.72))
		y += ROW_PITCH
	y += 8.0
	for row in machine:
		_text(Vector2(PAD, y), str(row[0]), 9, Color(INK, 0.40))
		_text(Vector2(118.0, y), str(row[1]), 9, Color(INK, 0.72))
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
	var lines: Array[String] = _wrap(first, 8, size.x - PAD * 2.0)
	lines.append_array(_wrap(second, 8, size.x - PAD * 2.0))
	var y: float = size.y - FOOT_H + 12.0
	for line in lines.slice(0, 4):
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


func _draw_legend() -> void:
	var y: float = size.y - 14.0
	var x: float = size.x - PAD - 186.0
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
	var w: float = size.x - PAD * 2.0
	var row_h: float = 20.0
	var x0: float = PAD
	var y0: float = _ground_y + CAPTION_H
	var h: float = 30.0 + rows * row_h + 22.0
	draw_rect(Rect2(x0, y0, w, h), Color(PAPER, 0.92))
	draw_rect(Rect2(x0, y0, w, h), Color(INK, 0.13), false, 1.0)
	draw_rect(Rect2(x0 + 14.0, y0 + 14.0, 5.0, 5.0), RED)
	_text(Vector2(x0 + 27.0, y0 + 20.0), "F O O T F A L L  —  O N E  C Y C L E", 9, INK)
	var lx: float = x0 + 52.0
	var rx: float = x0 + w - 16.0
	var span: float = rx - lx
	var idle: bool = _idle()
	var duty: float = gait.duty_measured()
	for i in rows:
		var y: float = y0 + 30.0 + i * row_h + row_h * 0.5
		_text(Vector2(x0 + 14.0, y + 3.0), labels[i], 9, Color(INK, 0.45))
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
			draw_line(Vector2(lx + u * span, y0 + 27.0),
				Vector2(lx + u * span, y0 + 30.0 + rows * row_h), Color(RED, 0.85), 1.0)
	var ticks: Array[String] = ["0", "¼", "½", "¾", "1"]
	for i in 5:
		_text(Vector2(lx + (float(i) / 4.0) * span - 2.0, y0 + h - 8.0),
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
## width, where the letterspacing costs more than it reads.
func _text(at: Vector2, text: String, px: int, ink: Color, centred: bool = false,
		tight: bool = false) -> void:
	var font: Font = _mono if tight and _mono != null \
		else (_mono_tracked if _mono_tracked != null else _mono)
	if centred:
		var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		at.x -= wide * 0.5
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
