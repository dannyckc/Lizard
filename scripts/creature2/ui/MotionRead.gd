## The physics reading — the judgement half of the Physics HUD, stated once.
##
## Two panels draw the locomotion loop now: the full-screen `PhysicsHud` (the
## bench, with the scenarios) and the lab's `MotionDrawer` (the same loop while
## the game is being played). Everything they *measure* already has one owner —
## `MotionReadout`, the seam `Travel` assembles — and this file is the other half:
## what a measurement is worth. The bands the eight tells are natural inside, the
## words for being outside one, the mark each thing on the stage is drawn with,
## and the timeline the ring is drawn as.
##
## It lives here rather than in either panel for the same reason the seam lives in
## one place: two panels holding two copies of "a natural lateral sway is 2.2 to 9
## px" would disagree the first time one of them was retuned, and the number the
## reader was looking at would be an accident of which window they opened.
##
## Nothing here measures anything. Every value comes in through `MotionReadout`,
## and where a reading is out of band the finding belongs to the mover.
class_name MotionRead
extends RefCounted

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
const RED := Color("8e1b12")

## The eight tells, with the band each is natural inside and the mechanism behind
## going outside it. The bands are the design's, and they are a *judgement about
## an animal* rather than a measurement of one — which is exactly why they live
## here in the reading and not in the seam. Nothing is tuned to make one go quiet:
## a reading out of band is the finding.
const TELLS: Array[Dictionary] = [
	{"key": &"bob", "label": "COM BOB", "unit": " PX", "digits": 1,
		"low": 3.5, "high": 10.0, "under": "FLAT", "over": "HEAVY",
		"why_under": "THE WEIGHT RIDES FLAT — THE LEGS ARE NOT SPENDING THEIR FOLD, "
			+ "SO THE BODY GLIDES OVER ITS OWN STANCE INSTEAD OF VAULTING OVER IT.",
		"why_over": "THE WEIGHT IS HEAVING — THE CARRIES ARE MOVING FURTHER THAN A "
			+ "STRIDE PUTS THEM, WHICH READS AS A BOUNCE RATHER THAN A WALK."},
	{"key": &"sway", "label": "LAT SWAY", "unit": " PX", "digits": 1,
		"low": 2.2, "high": 9.0, "under": "RIGID", "over": "LOOSE",
		"why_under": "THE WEIGHT NEVER SHIFTS OVER THE SUPPORTING SIDE — A BODY "
			+ "WALKING WITHOUT TRANSFERRING ITS WEIGHT IS A BODY ON RAILS.",
		"why_over": "THE WEIGHT IS ROLLING SIDE TO SIDE FURTHER THAN THE STANCE IS "
			+ "WIDE — THE SUPPORT IS BEING CHASED RATHER THAN STOOD ON."},
	{"key": &"lag", "label": "SPINE LAG", "unit": "°", "digits": 1,
		"low": 3.5, "high": 16.0, "under": "RIGID", "over": "SLACK",
		"why_under": "THE BACK IS NOT BENDING THROUGH THE TURN — A RIGID PIROUETTE. "
			+ "THE STEER'S LEAD IS NOT REACHING THE TRUNK.",
		"why_over": "THE BACK IS FOLDING INTO THE TURN FURTHER THAN A CAT'S BENDS — "
			+ "THE STEER IS SPENDING AS AN INTEGRAL RATHER THAN HOLDING A LEAD."},
	{"key": &"tail", "label": "TAIL TRAIL", "unit": "°", "digits": 1,
		"low": 6.0, "high": 90.0, "under": "STIFF", "over": "WHIP",
		"why_under": "THE TAIL IS WELDED TO THE PELVIS — NOTHING IS LAGGING BEHIND "
			+ "THE BODY, SO THE ANIMAL HAS NO FOLLOW-THROUGH AT ALL.",
		"why_over": "THE TAIL IS WHIPPING PAST WHAT ITS JOINTS SHOULD ALLOW."},
	{"key": &"spread", "label": "BEAT SPREAD", "unit": "%", "digits": 1,
		"low": 5.0, "high": 22.0, "under": "METRONOME", "over": "RAGGED",
		"why_under": "THE STRIDE PERIOD IS A CLOCK — ON FLAT GROUND NOTHING "
			+ "PERTURBS THE DRIFT, SO EVERY FOOT COMES DOWN ON THE BEAT.",
		"why_over": "THE BEAT IS RAGGED — FEET ARE BEING GRANTED OUT OF TURN, WHICH "
			+ "IS RHYTHM LOSING TO DESPERATION."},
	{"key": &"clip", "label": "JOINTS AT CAP", "unit": "", "digits": 0,
		"low": 0.0, "high": 1.4, "under": "—", "over": "CLIPPING",
		"why_under": "", "why_over": "JOINTS ARE PRESSED AGAINST THEIR OWN LIMITS — "
			+ "THE IK IS CLAMPING, AND A CLAMPED JOINT IS WHERE STIFFNESS COMES FROM."},
	{"key": &"stride", "label": "STRIDE/REACH", "unit": "", "digits": 2,
		"low": 0.40, "high": 0.86, "under": "MINCING", "over": "OVERREACH",
		"why_under": "STEPS COVER A FRACTION OF THE DISC THE LEG MAY BE PLACED IN — "
			+ "THE ANIMAL IS SCURRYING RATHER THAN WALKING.",
		"why_over": "STEPS REACH PAST WHAT THE STANCE LEAVES IN HAND — THERE IS NO "
			+ "ROOM LEFT FOR A DESPERATE STEP OR A MISPREDICTED LANDING."},
	{"key": &"delivery", "label": "DELIVERY", "unit": "", "digits": 2,
		"low": 0.30, "high": 0.94, "under": "STARVED", "over": "WEIGHTLESS",
		"why_under": "ALMOST NOTHING OF THE DEMAND IS BEING DELIVERED — THE FEET "
			+ "HAVE NO PRESS LEFT, AND THE BODY IS ASKING FOR WHAT IT CANNOT HAVE.",
		"why_over": "THE DEMAND IS NEVER CLAMPED — THE BODY HAS NO MASS TO FEEL, "
			+ "AND ACCELERATION COSTS IT NOTHING."},
]

## The marks, so the picture can be read without this file. Each is drawn by the
## legend itself in the ink the stage draws it in.
enum { MARK_ANCHOR, MARK_SWING, MARK_HOME, MARK_LANDING, MARK_HULL, MARK_COM }
const LEGEND: Array[Array] = [
	[MARK_ANCHOR, "PLANTED ANCHOR"], [MARK_SWING, "SWINGING FOOT"],
	[MARK_HOME, "HOME / DRIFT"], [MARK_LANDING, "PREDICTED LANDING"],
	[MARK_HULL, "SUPPORT POLYGON"], [MARK_COM, "CENTRE OF MASS"],
]


## The eight tells, banded, in the order `TELLS` states them.
##
## A reading that cannot honestly be taken says so — a standing animal has no gait
## to be stiff and a body going straight has no turn for its back to be rigid
## through — because a panel that printed a verdict on a body standing still would
## be a panel nobody could believe. The seam already answers NAN for those; all
## that is decided here is the word for it.
##
## Returns `{rows, note, note_ink}`: one row per tell, and the mechanism behind
## whichever reading is furthest outside its own band — measured as a share of
## that band's width, which is the only way eight quantities in eight units can be
## compared for which is worst.
static func reading(r: MotionReadout) -> Dictionary:
	var measured: Dictionary = r.tells()
	var rows: Array[Dictionary] = []
	var worst: Dictionary = {}
	var worst_by: float = 0.0
	for tell in TELLS:
		var value: float = measured.get(tell["key"], NAN)
		var known: bool = is_finite(value)
		var low: float = tell["low"]
		var high: float = tell["high"]
		var out: int = 0
		if known:
			out = -1 if value < low else (1 if value > high else 0)
		var word: String = "—"
		if known:
			word = "OK" if out == 0 else str(tell["under" if out < 0 else "over"])
		elif r.speed < MotionReadout.TRAVELLING:
			word = "STILL"
		else:
			word = "N/A"
		rows.append({
			"label": str(tell["label"]),
			"value": "—" if not known \
				else String.num(value, int(tell["digits"])) + str(tell["unit"]),
			"value_ink": RED if out != 0 else Color(INK, 0.82),
			"verdict": word,
			"verdict_ink": (RED if out != 0 else Color(INK, 0.5)) if known \
				else Color(INK, 0.25),
			# The measurement itself, and which side of the band it fell — what a
			# panel drawing the reading rather than tabulating it needs, and the
			# same judgement rather than a second one taken off the same numbers.
			"raw": value,
			"out": out,
			"tell": tell,
		})
		if out == 0 or not known:
			continue
		var by: float = (low - value if out < 0 else value - high) \
			/ maxf(high - low, 0.001)
		if by > worst_by:
			worst_by = by
			worst = {"tell": tell, "under": out < 0}
	if worst.is_empty():
		return {"rows": rows,
			"note": "" if r.speed >= MotionReadout.TRAVELLING \
				else "NOTHING TO READ WHILE THE ANIMAL IS STANDING — WALK IT.",
			"note_ink": Color(INK, 0.30)}
	var tell: Dictionary = worst["tell"]
	return {"rows": rows,
		"note": str(tell["why_under" if worst["under"] else "why_over"]),
		"note_ink": Color(INK, 0.45)}


## One tell as a gauge: the reading against the band it is natural inside.
##
## The same judgement `reading` makes, drawn instead of written. A tell is a
## number whose only meaning is where it falls between two others, and a column
## of figures makes the reader do that comparison eight times over — here the
## band is a segment of ink on a track and the measurement is a caret on it, so
## being inside is a shape rather than a word. The word survives only for the
## cases the picture cannot carry: which way it went wrong, and having nothing
## honest to say at all.
##
## Fed rows straight out of `reading` — it works nothing out for itself.
class Band extends Control:
	## Where the track sits under the caption, and how much of it is ink.
	const TRACK: float = 11.0
	const CARET: float = 9.0
	## How far past the top of the band the track runs. A caret hard against the
	## end of its own track is unreadable, and a reading well over its band is
	## exactly when the panel is worth looking at.
	const OVERRUN: float = 1.5

	var label: String = ""
	var low: float = 0.0
	var high: float = 1.0
	var value: float = NAN
	var out: int = 0
	var word: String = "—"
	var reading_text: String = "—"
	var font: Font

	func _init(caption: String, band_low: float, band_high: float) -> void:
		label = caption
		low = band_low
		high = band_high
		custom_minimum_size = Vector2(118.0, 30.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## One row of `MotionRead.reading`.
	func show_row(row: Dictionary) -> void:
		value = float(row.get("raw", NAN))
		out = int(row.get("out", 0))
		word = str(row.get("verdict", "—"))
		reading_text = str(row.get("value", "—"))
		queue_redraw()

	func _draw() -> void:
		if font == null:
			return
		var known: bool = is_finite(value)
		var ink: Color = MotionRead.RED if out != 0 else Color(MotionRead.INK, 0.82)
		draw_string(font, Vector2(0.0, 10.0), label, HORIZONTAL_ALIGNMENT_LEFT,
			size.x, 9, Color(MotionRead.INK, 0.5))
		var figure: String = reading_text if known else word
		var wide: float = font.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 9).x
		draw_string(font, Vector2(size.x - wide, 10.0), figure,
			HORIZONTAL_ALIGNMENT_LEFT, wide, 9,
			ink if known else Color(MotionRead.INK, 0.3))
		# Which way it went wrong, where there is paper left for the word — the
		# caret already says *that* it is out, and on a narrow column the word is
		# the part that can be given up.
		if known and out != 0:
			var room: float = size.x - wide - 8.0
			var verdict: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 8).x
			if room - verdict > font.get_string_size(label,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x + 10.0:
				draw_string(font, Vector2(size.x - wide - 7.0 - verdict, 10.0), word,
					HORIZONTAL_ALIGNMENT_LEFT, verdict, 8, MotionRead.RED)

		var y: float = size.y - TRACK * 0.5
		var full: float = maxf(high * OVERRUN, high + (high - low) * 0.5)
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(MotionRead.INK, 0.13), 1.0)
		var a: float = clampf(low / full, 0.0, 1.0) * size.x
		var b: float = clampf(high / full, 0.0, 1.0) * size.x
		draw_line(Vector2(a, y), Vector2(b, y), Color(MotionRead.INK, 0.34), 3.0)
		if not known:
			return
		var at: float = clampf(value / full, 0.0, 1.0) * size.x
		draw_rect(Rect2(clampf(at - 1.0, 0.0, size.x - 2.0), y - CARET * 0.5,
			2.0, CARET), ink)


## One legend mark, drawn by a tiny Control in the same ink the stage draws it.
class Glyph extends Control:
	var kind: int = 0

	func _init(which: int) -> void:
		kind = which
		custom_minimum_size = Vector2(14.0, 10.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mid := Vector2(7.0, 5.0)
		match kind:
			MotionRead.MARK_ANCHOR:
				draw_line(Vector2(0.0, 5.0), Vector2(13.0, 5.0), MotionRead.RED, 2.2)
			MotionRead.MARK_SWING:
				draw_arc(mid, 4.0, 0.0, TAU, 14, Color(MotionRead.INK, 0.6), 1.2, true)
			MotionRead.MARK_HOME:
				draw_rect(Rect2(mid - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
					Color(MotionRead.INK, 0.4), false, 1.0)
			MotionRead.MARK_LANDING:
				draw_line(Vector2(2.0, 5.0), Vector2(12.0, 5.0), Color(MotionRead.RED, 0.7), 1.0)
				draw_line(Vector2(7.0, 0.0), Vector2(7.0, 10.0), Color(MotionRead.RED, 0.7), 1.0)
			MotionRead.MARK_HULL:
				for i in 3:
					draw_line(Vector2(i * 5.0, 5.0), Vector2(i * 5.0 + 3.0, 5.0),
						Color(MotionRead.INK, 0.45), 1.0)
			_:
				draw_circle(mid, 3.5, MotionRead.INK)


## The timeline: the last four and a half seconds of the loop, run-length drawn
## off the same ring the tells are reduced from.
##
## The four foot rows are the answer to "why did that foot step" — a solid red
## bar is a foot on the ground, a hollow one is a foot in the air, and a
## full-height tick is a step nothing was allowed to deny. Under them: how much
## support the body had, what it demanded against what it delivered (where the
## fill is clipped flat, mass is being felt), and how far inside its own edge the
## weight stayed.
class Ribbon extends Control:
	## What the strip wants: tall enough for every track the design asks for. The
	## handoff's own band is 148 px and its last two tracks fall off the bottom of
	## it — the poise line and the time ruler are drawn below the frame they are
	## inside — so the band asks for the height its contents need instead, and
	## takes less where a panel has less to give (the drawer's column, which pays
	## for its picture out of the same height).
	const HEIGHT: float = 190.0
	## Where the strip starts: everything left of this is the row's name.
	const GUTTER: float = 66.0
	## The header over the rows, and the ruler under them.
	const HEADER: float = 30.0
	const RULER: float = 14.0
	## How much of what is left the four foot rows take, and the three tracks'
	## heights against each other — the handoff's 22 : 26 : 20.
	const ROWS_SHARE: float = 0.36
	const TRACK_SHARES: Array[float] = [22.0, 26.0, 20.0]
	const TRACK_GAP: float = 8.0

	## The tracks under the feet, in the order they are stacked: what the body had
	## to stand on, what it asked its feet for against what they gave, and how far
	## inside its own support the weight stayed.
	const DOWN: int = 0
	const ACCEL: int = 1
	const POISE: int = 2

	var readout: MotionReadout
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(MotionRead.INK, 0.13), false, 1.0)
		if font != null:
			draw_string(font, Vector2(12.0, 17.0), "TIMELINE",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(MotionRead.INK, 0.72))
			draw_string(font, Vector2(74.0, 17.0),
				"%.1f S WINDOW · FOOTFALL · DELIVERY · POISE" % MotionReadout.WINDOW,
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 86.0, 9,
				Color(MotionRead.INK, 0.32))
		if readout == null or readout.samples() < 2:
			return
		var left: float = GUTTER
		var right: float = size.x - 14.0
		var span: float = maxf(right - left, 1.0)
		var now: float = readout.sample_time(readout.samples() - 1)
		# The rows and the tracks are laid out in the height there actually is,
		# in the proportions the handoff draws them at.
		var feet: int = maxi(readout.steps.size(), 1)
		var space: float = maxf(size.y - HEADER - RULER, 48.0)
		var pitch: float = clampf(space * ROWS_SHARE / float(feet), 8.0, 13.0)
		var y: float = HEADER
		for f in readout.steps.size():
			_foot_row(f, y + pitch * 0.5, left, right, span, now)
			y += pitch
		y += 4.0
		var tracks: float = maxf(size.y - RULER - y - TRACK_GAP * 3.0, 24.0)
		var whole: float = TRACK_SHARES[0] + TRACK_SHARES[1] + TRACK_SHARES[2]
		y = _track(y, tracks * TRACK_SHARES[DOWN] / whole, "DOWN",
			left, right, span, now, DOWN)
		y = _track(y, tracks * TRACK_SHARES[ACCEL] / whole, "ACCEL",
			left, right, span, now, ACCEL)
		var base: float = _track(y, tracks * TRACK_SHARES[POISE] / whole, "POISE",
			left, right, span, now, POISE) - TRACK_GAP
		# Now, and how far back the rest of it is.
		draw_line(Vector2(right, 26.0), Vector2(right, base), Color(MotionRead.RED, 0.8), 1.0)
		if font == null:
			return
		for k in 5:
			var at: float = right - float(k) / 4.0 * span
			var mark: String = "NOW" if k == 0 else "−%.1fS" % (float(k) / 4.0 * MotionReadout.WINDOW)
			draw_string(font, Vector2(at - 20.0, base + 12.0), mark,
				HORIZONTAL_ALIGNMENT_CENTER, 40.0, 8, Color(MotionRead.INK, 0.28))

	## Where a sample falls on the strip — the right edge is now, and everything
	## older than the window has walked off the left.
	func _x(t: float, now: float, right: float, span: float) -> float:
		return right - (now - t) / MotionReadout.WINDOW * span

	func _foot_row(foot: int, y: float, left: float, right: float, span: float,
			now: float) -> void:
		if font != null:
			draw_string(font, Vector2(14.0, y + 3.0), str(readout.steps[foot].name),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(MotionRead.INK, 0.45))
		draw_line(Vector2(left, y), Vector2(right, y), Color(MotionRead.INK, 0.10), 1.0)
		var mark: int = -1
		var from: float = left
		for k in readout.samples():
			var at: float = _x(readout.sample_time(k), now, right, span)
			if at < left:
				continue
			var here: int = readout.sample_mark(k, foot)
			if here != mark:
				if mark >= 0:
					_run(mark, from, at, y)
				mark = here
				from = at
		if mark >= 0:
			_run(mark, from, right, y)

	func _run(mark: int, from: float, to: float, y: float) -> void:
		var wide: float = maxf(to - from, 1.0)
		match mark:
			MotionReadout.PLANTED:
				draw_rect(Rect2(from, y - 2.5, wide, 5.0), Color(MotionRead.RED, 0.85))
			MotionReadout.DESPERATE:
				draw_rect(Rect2(from, y - 4.0, wide, 8.0), MotionRead.RED)
			MotionReadout.RESCUING:
				draw_rect(Rect2(from, y - 2.5, wide, 5.0), Color(MotionRead.RED, 0.6),
					false, 1.0)
			_:
				draw_rect(Rect2(from, y - 2.5, wide, 5.0), Color(MotionRead.INK, 0.42),
					false, 1.0)

	## One measured track under the feet, returning where the next one starts.
	func _track(top: float, tall: float, label: String, left: float, right: float,
			span: float, now: float, which: int) -> float:
		var base: float = top + tall
		if font != null:
			draw_string(font, Vector2(14.0, base - 1.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(MotionRead.INK, 0.45))
		draw_line(Vector2(left, base), Vector2(right, base), Color(MotionRead.INK, 0.10), 1.0)
		var line := PackedVector2Array()
		var dashed := PackedVector2Array()
		var fill := PackedVector2Array()
		## The tallest thing on this track, so an area that is flat on the baseline
		## is left as a line: a strip of nought-height polygon is not a shape, and
		## asking the renderer to triangulate one is how a cruising animal — which
		## demands nothing at all — filled the log with triangulation errors.
		var tallest: float = 0.0
		for k in readout.samples():
			var at: float = _x(readout.sample_time(k), now, right, span)
			if at < left:
				continue
			var value: float = 0.0
			match which:
				DOWN:
					value = float(readout.sample_down(k)) / maxf(float(readout.steps.size()), 1.0)
				ACCEL:
					var cap: float = maxf(readout.sample_ceiling(k), 1.0)
					value = clampf(readout.sample_delivered(k) / cap, 0.0, 1.0)
					dashed.append(Vector2(at, base - clampf(
						readout.sample_demand(k) / cap, 0.0, 1.0) * tall))
				_:
					value = clampf(readout.sample_steadiness(k), 0.0, 1.0)
			tallest = maxf(tallest, value)
			var q := Vector2(at, base - value * tall)
			line.append(q)
			fill.append(q)
		if line.size() < 2:
			return base + TRACK_GAP
		if which == ACCEL:
			# The delivery as an area, because what matters is how much of the
			# demand it filled — and where the top of the fill runs flat under the
			# dashes, the clamp is biting and the body is feeling its own mass.
			if tallest * tall > 0.5:
				var area: PackedVector2Array = fill.duplicate()
				area.append(Vector2(area[area.size() - 1].x, base))
				area.append(Vector2(area[0].x, base))
				draw_colored_polygon(area, Color(MotionRead.RED, 0.22))
			draw_polyline(line, MotionRead.RED, 1.2, true)
			for i in range(1, dashed.size()):
				if i % 3 == 0:
					draw_line(dashed[i - 1], dashed[i], Color(MotionRead.INK, 0.45), 1.0)
		else:
			draw_polyline(line, Color(MotionRead.INK, 0.55), 1.0, true)
		if which == POISE:
			# ...and where the weight was genuinely outside its own support.
			for k in readout.samples():
				var at2: float = _x(readout.sample_time(k), now, right, span)
				if at2 >= left and readout.sample_spill(k) > 0.0:
					draw_rect(Rect2(at2, base - 3.0, 1.0, 3.0), Color(MotionRead.RED, 0.5))
		return base + TRACK_GAP
