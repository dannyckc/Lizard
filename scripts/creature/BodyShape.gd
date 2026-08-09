## Parametric body construction — everything visible is derived from the spine.
##
## There is no mesh, no rig and no authored silhouette. Each tick we walk the
## spine, read its local forward/perpendicular basis, look up a width from a
## profile curve, and emit the outline, the head, the eyes and the four limb
## anchors from that. Because it is rebuilt from scratch every tick, the body
## automatically deforms correctly no matter how the constraint solver bent the
## spine — and because the widths come from a smooth profile rather than the
## chain itself, the creature keeps a recognisable lizard shape while bending.
class_name BodyShape
extends RefCounted

const CAP_SEGMENTS: int = 10

## Cross-section widths, one per spine point.
var widths: PackedFloat32Array = PackedFloat32Array()
## Closed silhouette, counter-clockwise from the right side of the snout.
var outline: PackedVector2Array = PackedVector2Array()
## Left/right flank points, kept separately so the renderer can fill with quads.
var flank_left: PackedVector2Array = PackedVector2Array()
var flank_right: PackedVector2Array = PackedVector2Array()

var head: Spine.Frame = Spine.Frame.new()
var head_radius: float = 10.0
var eye_left: Vector2 = Vector2.ZERO
var eye_right: Vector2 = Vector2.ZERO
var eye_radius: float = 2.0

## A mouthful travelling down the gullet: how far along the body it currently is,
## and how much of the body's own width it adds where it is.
##
## Written into the width profile rather than painted over the top of it, so the
## distension is the body — the lattice tessellates the swollen cross-sections, the
## silhouette bulges, the collision capsules widen, and what the creature weighs
## goes briefly up because there is briefly more of it. A lump drawn on the outside
## of a body would be none of those things.
var swallow_at: float = 0.0
var swallow_size: float = 0.0
## How far along the body a swallow's distension reaches either side of itself.
## Narrow, because what is passing is a discrete object rather than a wave.
const SWALLOW_SPREAD: float = 0.11

## "FL" / "FR" / "RL" / "RR" -> Spine.Frame positioned at the limb socket.
var anchors: Dictionary = {}
## The same keys -> how far that socket sits off the spine, in world pixels. What
## "under the body" is measured against: a foot brought this far inboard of its
## own shoulder is a foot on the animal's midline.
var socket_out: Dictionary = {}
## Index of the last spine point included in the silhouette (tail clipping).
var last_index: int = 0
var tail_tip: Vector2 = Vector2.ZERO


## `posture` decides one thing here and nothing else: how far inboard of the
## flank the limb sockets sit. Left null the sockets stay on the flank, which is
## where a sprawled animal's are — so a body built without a posture is a
## sprawled body rather than a special case.
func build(spine: Spine, p: CreatureParams, scale: float, posture: Posture = null) -> void:
	var pts: PackedVector2Array = spine.points
	var n: int = pts.size()
	if n < 3:
		return

	# --- width profile -----------------------------------------------------
	# Five knots (head, chest, waist, hip, tail tip) interpolated with a
	# Catmull-Rom spline, so a handful of sliders control the whole silhouette
	# and the taper stays smooth regardless of segment count.
	var knots: PackedFloat32Array = PackedFloat32Array([
		p.head_width, p.chest_width, p.waist_width, p.hip_width, p.tail_tip_width
	])
	widths.resize(n)
	for i in n:
		var t: float = float(i) / float(n - 1)
		widths[i] = maxf(_catmull_rom(knots, t) * p.body_width * scale
			* (1.0 + _swallow_at(t)), 0.6)

	# The tail is just the spine past the hips, so making it optional is a
	# matter of clipping the silhouette early rather than resizing the chain.
	last_index = n - 1
	if not p.tail_enabled:
		last_index = clampi(int(round(p.rear_limb_t * float(n - 1))) + 2, 3, n - 1)
	tail_tip = pts[last_index]

	head.pos = pts[0]
	head.fwd = spine.forwards[0]
	head.perp = spine.perps[0]
	head_radius = widths[0]

	# --- flanks ------------------------------------------------------------
	flank_left.resize(last_index + 1)
	flank_right.resize(last_index + 1)
	for i in range(last_index + 1):
		flank_left[i] = pts[i] + spine.perps[i] * widths[i]
		flank_right[i] = pts[i] - spine.perps[i] * widths[i]

	# --- closed outline ----------------------------------------------------
	# Round snout cap -> left flank -> round tail cap -> right flank back.
	# Every arc starts exactly where the previous run ended, so the loop closes
	# without seams.
	outline.clear()
	var head_angle: float = spine.forwards[0].angle()
	for k in range(CAP_SEGMENTS + 1):
		var a: float = head_angle - PI * 0.5 + PI * (float(k) / float(CAP_SEGMENTS))
		outline.append(pts[0] + Vector2.RIGHT.rotated(a) * widths[0])

	for i in range(1, last_index + 1):
		outline.append(flank_left[i])

	var tail_angle: float = spine.forwards[last_index].angle()
	for k in range(1, CAP_SEGMENTS):
		var a2: float = tail_angle + PI * 0.5 + PI * (float(k) / float(CAP_SEGMENTS))
		outline.append(pts[last_index] + Vector2.RIGHT.rotated(a2) * widths[last_index])

	for i in range(last_index, 0, -1):
		outline.append(flank_right[i])

	# --- eyes --------------------------------------------------------------
	eye_radius = maxf(head_radius * 0.24, 1.0)
	var eye_fwd: Vector2 = head.fwd * (head_radius * 0.34)
	var eye_side: Vector2 = head.perp * (head_radius * 0.52)
	eye_left = head.pos + eye_fwd + eye_side
	eye_right = head.pos + eye_fwd - eye_side

	# --- limb anchors ------------------------------------------------------
	# Sockets sit on the flank at the shoulder/hip station, so they inherit the
	# spine's bend for free and the legs swing with the body. An upright animal's
	# are drawn in toward the midline instead, which is a real anatomical
	# difference and also, for free, what hides the top of its legs: the limbs are
	# drawn beneath the torso, so a socket inside the silhouette is a shoulder the
	# body is standing over.
	var inset: float = 1.0 - (posture.socket_inset if posture != null else 0.0)
	_set_anchor(spine, p, "FL", p.front_limb_t, 1.0, inset)
	_set_anchor(spine, p, "FR", p.front_limb_t, -1.0, inset)
	_set_anchor(spine, p, "RL", p.rear_limb_t, 1.0, inset)
	_set_anchor(spine, p, "RR", p.rear_limb_t, -1.0, inset)


## How much a mouthful going down adds to the width at one station. A smooth hump
## centred on where the piece has got to, so the swelling travels with it and the
## tissue either side of it is drawn taut rather than stepped.
func _swallow_at(t: float) -> float:
	if swallow_size <= 0.0:
		return 0.0
	var away: float = absf(t - swallow_at) / SWALLOW_SPREAD
	if away >= 1.0:
		return 0.0
	var falloff: float = 1.0 - away * away
	return swallow_size * falloff * falloff


func _set_anchor(spine: Spine, p: CreatureParams, key: String, t: float, side: float,
		inset: float = 1.0) -> void:
	var f: Spine.Frame = spine.sample(t)
	var n: int = spine.points.size()
	var idx: int = clampi(int(round(t * float(n - 1))), 0, n - 1)
	var out: float = widths[idx] * 0.85 * inset
	f.pos = f.pos + f.perp * (side * out)
	anchors[key] = f
	socket_out[key] = out


## Uniform Catmull-Rom through `knots`, clamped at both ends.
static func _catmull_rom(knots: PackedFloat32Array, t: float) -> float:
	var last: int = knots.size() - 1
	if last <= 0:
		return knots[0] if last == 0 else 0.0
	var s: float = clampf(t, 0.0, 1.0) * float(last)
	var i: int = clampi(int(floor(s)), 0, last - 1)
	var f: float = s - float(i)
	var p0: float = knots[maxi(i - 1, 0)]
	var p1: float = knots[i]
	var p2: float = knots[i + 1]
	var p3: float = knots[mini(i + 2, last)]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * f
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f
	)


## Chaikin corner cutting on a closed loop — used only to smooth the drawn
## outline stroke, never for collision or gameplay.
static func smooth_closed(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var current: PackedVector2Array = pts
	for _it in range(iterations):
		var n: int = current.size()
		if n < 3:
			return current
		var out: PackedVector2Array = PackedVector2Array()
		out.resize(n * 2)
		for i in n:
			var a: Vector2 = current[i]
			var b: Vector2 = current[(i + 1) % n]
			out[i * 2] = a.lerp(b, 0.25)
			out[i * 2 + 1] = a.lerp(b, 0.75)
		current = out
	return current
