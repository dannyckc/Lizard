## The specimen on the anatomy drawer's slab: the v2 animal opened up and turned
## by hand — AnatomyView's counterpart, and a fraction of its size for the reason
## docs/V2_DESIGN.md §10 predicted.
##
## v1's stage walked a cell lattice and re-derived a surface out of it every
## frame. There is nothing to derive here. `Contour` is already the animal's one
## surface, posed on the solved skeleton at the end of every tick, and the peel is
## the same rings evaluated at a smaller radius — `Corpus.layer_radius` summing
## fewer layers, per §10. So what this file owns is a *camera*: a body frame, an
## orbit, a painter's order, and the picking that turns a pixel back into a census
## address. It owns no anatomy at all, which is why a wound needs no code here —
## the ring got thinner and a different layer came out on top, because the census
## says so.
##
## Three things can be done to the specimen, and all three are subtractions from
## the same cells rather than a second model:
##
##   * the **peel** lifts tissue off outside-in, and is one number — how many
##     layers from the bone core the surface is evaluated at;
##   * the **section** carves the body on one of its own three axes, and is a
##     cull of facets past a plane;
##   * the **X-ray** thins every facet to a film.
##
## The two networks are drawn over the top rather than inside, and deliberately:
## they are authored as body coordinates (§6), not as cells, so there is no depth
## at which they would occlude correctly. What is honest about drawing them over
## the animal is that they fade as the flesh they run through is peeled away —
## faint under whole skin, solid over an opened body.
##
## The pose it shows is the live one. v1's specimen was a rest-pose census and had
## to be; this is the animal that is walking about in the field beside the drawer,
## which is the whole point of a drawer that does not take the window.
class_name SpecimenStage
extends Control

## What the pointer is over, already in words — the drawer prints it.
signal cell_hovered(readout: String, alarm: bool)

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
## v1's palette, restated rather than imported: the drawer has to look like the
## drawer, and the two views must not part company over a colour.
const COL_FAT := Color("e0cfa8")
const COL_FAT_DEEP := Color("c4ab7c")
const COL_MUSCLE := Color("9c3b26")
const COL_MUSCLE_DEEP := Color("5f2114")
const COL_BONE := Color("c9bda0")
const COL_BONE_WORN := Color("a08d68")
const COL_ORGAN := Color("6d1230")
const COL_VESSEL := Color("a8202a")
const COL_NERVE := Color("2f6f8f")
## Skin is the ink silhouette itself, so its swatch in the layer list is the one
## that is drawn as an outline rather than a fill.
const COL_HIDE := Color("000000")

## Every layer shown — the specimen as the animal, before anything is lifted off.
const ALL_LAYERS: int = 0b1111

const SLICE_OFF: int = -1
## The body's own three axes: along it, across it, and up it.
const SLICE_LONG: int = 0
const SLICE_SIDE: int = 1
const SLICE_FLAT: int = 2

## The wheel, on v1's step exactly — the two F3 stops are one instrument and a
## wheel that means different things on each is one the player has to remember.
const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 3.2
const ZOOM_STEP: float = 1.09

## Where the eye stands when the drawer opens: above the animal's left shoulder,
## far enough round for the near foreleg to stand clear of the flank behind it.
const DEFAULT_TILT: float = -58.0
const DEFAULT_SPIN: float = -32.0

## How much of the shorter side of the band the fitted specimen fills.
const FILL: float = 0.84
## Past this fraction of the ball's radius the trackball is a hyperbola rather
## than a sphere, so a drag that leaves the ball still turns the specimen.
const BALL_EDGE: float = 0.70710678
## How fast the fit follows a body changing shape — a collapse sprawls a cat over
## twice its standing extent, and snapping to it would be a camera flinching.
const SETTLE: float = 5.0

## Lambert, in the flat editorial register: a facet never goes to black and never
## blows out, so the silhouette carries the form and the shading only reads it.
const LIGHT := Vector3(-0.42, -0.30, 0.86)
const FACET_FLOOR: float = 0.66
const FACET_GAIN: float = 0.62
## A facet turned away from the eye is still drawn — the far wall of an opened
## body is what says it is a volume — but it is drawn as the inside of something.
const FACET_BACK: float = 0.58
const XRAY_ALPHA: float = 0.30

## Wear steps a layer's colour is banked at, exactly as Likeness banks them: six
## is where the gradient stops being a staircase and the bank stops being a
## palette.
const WEAR: int = 6

## How far a network is allowed to show through whole flesh.
const CONDUIT_UNDER: float = 0.22
## ...and the calibre a vessel is drawn at, in screen px per body px.
const CONDUIT_WIDTH: float = 1.6

## How much of the drawer's paper the axis gizmo stands off the corner.
const AXIS_INSET: float = 22.0
const AXIS_ARM: float = 14.0


var creature: Creature2

## Which tissues are still on the specimen, as a mask over BodySchema.Layer.
var layers: int = ALL_LAYERS
var show_vessels: bool = true
var show_nerves: bool = true
var xray: bool = false
var slice_axis: int = SLICE_OFF
var slice_at: float = 1.0
## One chain held up on its own, or &"" for the whole animal. The rest of the
## body stays on the slab at a whisper, because a tail with no cat around it is
## not a diagnosis of anything.
var focus: StringName = &""

var zoom: float = 1.0
## Where the specimen is being looked at from, in its own frame.
var orient: Basis = Basis():
	set(value):
		orient = value.orthonormalized()

var _mono: Font

# --- the frame ---------------------------------------------------------------
## The animal's own axes in contour space, and the point they are taken about.
var _origin: Vector3 = Vector3.ZERO
var _along: Vector3 = Vector3(1.0, 0.0, 0.0)
var _across: Vector3 = Vector3(0.0, 1.0, 0.0)
var _radius: float = 40.0
var _ball: float = 100.0
var _scale: float = 1.0
var _fitted: bool = false
## The body-space bounds, for the section plane to be quoted against, and the
## middle of them — which is what the specimen is centred on. Not the mean of the
## ring centres: a cat is two thirds tail by station count and would hang off the
## slab, exactly as a gait figure centred on its girdles does.
var _low := Vector3.ZERO
var _high := Vector3.ZERO
var _mid := Vector3.ZERO

# --- per-frame geometry, allocated once --------------------------------------
## Every ring-sector, in body space and on the page.
var _body: PackedVector3Array = PackedVector3Array()
var _pt: PackedVector2Array = PackedVector2Array()
## The peel radius of each ring-sector, re-read only when the peel or the census
## moves.
var _peel: PackedFloat32Array = PackedFloat32Array()
var _peel_key: int = -1
var _peel_rev: int = -1

## The drawn facets: four unshared corners each, so one triangle array carries
## the whole specimen in painter's order and a facet's colour is its own.
var _face_pt: PackedVector2Array = PackedVector2Array()
var _face_col: PackedColorArray = PackedColorArray()
var _face_ix: PackedInt32Array = PackedInt32Array()
var _drawn: int = 0
## What each drawn facet is, so a pixel can be turned back into a census address:
## ring and sector, packed as `ring * 64 + sector`.
var _face_of: PackedInt32Array = PackedInt32Array()

## Spans (a ring and the one after it) in far-to-near order.
var _span_ix: PackedInt32Array = PackedInt32Array()
var _span_depth: PackedFloat32Array = PackedFloat32Array()
## One ring's sectors in paint order, refilled per span rather than reallocated:
## there are ninety-odd of them a frame and they are all the same shape.
var _order: PackedInt32Array = PackedInt32Array()

var _bank: PackedColorArray = PackedColorArray()

var _orbiting: bool = false
var _grab := Vector3.FORWARD
var _grabbed: Basis = Basis()
var _hover: int = -1


func _init() -> void:
	orient = default_orbit()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_bank_shades()


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


func set_ui_font(mono: Font) -> void:
	_mono = mono


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## The viewpoint the drawer opens at. Composed as an elevation and then a bearing
## so the two constants mean what they say: the tilt lifts the eye off the
## animal's own horizon, the spin walks it round the body.
static func default_orbit() -> Basis:
	return Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(DEFAULT_TILT)) \
		* Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(DEFAULT_SPIN))


## Whether the eye is still where the drawer opened it — what the drawer asks
## before naming the angles, because on an untouched specimen they are the file's
## numbers rather than the hand's.
func at_default_orbit() -> bool:
	return orient.is_equal_approx(default_orbit()) and is_equal_approx(zoom, 1.0)


func reset_orbit() -> void:
	orient = default_orbit()
	set_zoom(1.0)


## Forgets the fit, so a rebuilt body arrives framed rather than easing across
## from wherever the last one sat.
func reset_fit() -> void:
	_fitted = false
	_hover = -1


func set_zoom(value: float) -> void:
	var want: float = clampf(value, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(want, zoom):
		return
	zoom = want
	queue_redraw()


func layer_shown(layer: int) -> bool:
	return (layers & (1 << layer)) != 0


func set_layer_shown(layer: int, shown: bool) -> void:
	layers = (layers | (1 << layer)) if shown else (layers & ~(1 << layer))
	queue_redraw()


## Where the eye has got to, in the two readings that can be asked for. Roll is
## not among them: the trackball rolls the specimen freely, and a number for it
## on a body nobody has rolled would be a reading of nothing.
func bearing() -> float:
	var eye: Vector3 = orient.inverse() * Vector3(0.0, 0.0, 1.0)
	return atan2(eye.y, eye.x)


func elevation() -> float:
	var eye: Vector3 = orient.inverse() * Vector3(0.0, 0.0, 1.0)
	return asin(clampf(eye.z, -1.0, 1.0))


# ------------------------------------------------------------------- shades ----

## Every colour a facet can be, banked once — a drawn wedge is a lookup, which is
## v1's per-cell lesson kept.
func _bank_shades() -> void:
	_bank.resize(4 * WEAR + 1)
	for step in WEAR:
		var wear: float = float(step) / float(WEAR - 1)
		_bank[BodySchema.Layer.SKIN * WEAR + step] = INK.lerp(Color("2b211b"), wear * 0.30)
		_bank[BodySchema.Layer.FAT * WEAR + step] = COL_FAT.lerp(COL_FAT_DEEP, wear)
		_bank[BodySchema.Layer.MUSCLE * WEAR + step] = COL_MUSCLE.lerp(COL_MUSCLE_DEEP, wear)
		_bank[BodySchema.Layer.BONE * WEAR + step] = COL_BONE.lerp(COL_BONE_WORN, wear)
	_bank[4 * WEAR] = COL_BONE_WORN


## How deep the peel currently cuts, counted from the bone core outward the way
## `Corpus.layer_radius` counts: 4 is the whole animal, 0 is the bare core. The
## outermost tissue still switched on is the surface, which is what makes the
## layer list a stack rather than four independent switches.
func _depth() -> int:
	if layer_shown(BodySchema.Layer.SKIN):
		return 4
	if layer_shown(BodySchema.Layer.FAT):
		return 3
	if layer_shown(BodySchema.Layer.MUSCLE):
		return 2
	if layer_shown(BodySchema.Layer.BONE):
		return 1
	return 0


## The ink of one census column at the current peel: the outermost layer still
## shown that has anything left of it, shaded by how much that is. A wedge chewed
## past its last layer is the bone core it is standing on.
func _ink(column: int, depth: int) -> Color:
	var corpus: Corpus = creature.corpus
	var base: int = column * 4
	for layer in range(depth - 1, -1, -1):
		if corpus.thickness[base + layer] <= 0.0:
			continue
		var hp: float = corpus.hp[base + layer]
		if hp <= 0.0:
			continue
		return _bank[layer * WEAR + clampi(int((1.0 - hp) * float(WEAR)), 0, WEAR - 1)]
	return _bank[4 * WEAR]


# -------------------------------------------------------------------- frame ----

## The animal's own frame, taken fresh: along the body from the pelvis to the
## withers, across it, and up. Taken off the armature rather than off the rings,
## because the frame has to be the *animal's* however its back is bent — a
## specimen that yawed with the tail would be unreadable the moment it turned.
func _frame(skin: Contour) -> bool:
	var a: Armature = creature.armature
	var fore: Vector2 = a.plan(a.withers_index())
	var rear: Vector2 = a.plan(a.pelvis_index())
	var axis: Vector2 = fore - rear
	if axis.length_squared() < 0.0001:
		axis = Vector2.RIGHT
	axis = axis.normalized()
	_along = Vector3(axis.x, axis.y, 0.0)
	_across = Vector3(-axis.y, axis.x, 0.0)

	# The middle of the animal, and how far it reaches from it. Both are measured
	# on the surface rather than on the chain, so a fat cat is framed as a fat cat.
	var mid := Vector3.ZERO
	for r in skin.rings:
		mid += skin.ring_centre[r]
	if skin.rings > 0:
		mid /= float(skin.rings)
	_origin = mid

	var count: int = skin.surface.size()
	if _body.size() != count:
		_body.resize(count)
		_pt.resize(count)
		_peel_key = -1
	_refresh_peel(skin)

	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for band in skin.bands:
		for r in range(band.first, band.first + band.count):
			var at: int = skin.ring_base[r]
			for s in band.sectors:
				var p: Vector3 = skin.ring_centre[r] \
					+ skin.direction(r, s) * _peel[at + s] - _origin
				var q := Vector3(_along.dot(p), _across.dot(p), p.z)
				_body[at + s] = q
				low = low.min(q)
				high = high.max(q)
	if not is_finite(low.x):
		return false
	_low = low
	_high = high
	_mid = (low + high) * 0.5

	# The fit follows the body rather than being retaken: a walking animal's
	# extent breathes by a few px a stride and a camera that answered it would
	# never be still. A collapse is a real change of shape and the ease carries it.
	var want: float = maxf(maxf(high.x - low.x, high.y - low.y), high.z - low.z) * 0.5
	if not _fitted:
		_radius = maxf(want, 1.0)
		_fitted = true
	else:
		_radius = lerpf(_radius, maxf(want, 1.0),
			1.0 - exp(-SETTLE * get_process_delta_time()))
	_ball = minf(size.x, size.y) * 0.5 * FILL
	_scale = _ball * zoom / maxf(_radius, 0.001)
	return true


## Re-reads the peel radii. Keyed to the peel depth and the census's revision, so
## an animal being watched walk about costs nothing here at all and a bite costs
## one walk of rings.
func _refresh_peel(skin: Contour) -> void:
	var depth: int = _depth()
	if _peel.size() != _body.size():
		_peel.resize(_body.size())
		_peel_key = -1
	if _peel_key == depth and _peel_rev == creature.corpus.revision:
		return
	_peel_key = depth
	_peel_rev = creature.corpus.revision
	for band in skin.bands:
		for r in range(band.first, band.first + band.count):
			var at: int = skin.ring_base[r]
			for s in band.sectors:
				_peel[at + s] = skin.radius_at(band.name, skin.ring_t[r], s, depth)


## Body space to the page. The eye's own +z points at the viewer, so a facet's
## depth is what the sort is taken on and screen y runs the other way from it. The
## body is centred on the middle of its own bounds on the way past — the one place
## the translation happens, so `_eye` stays a rotation and can be handed a
## direction without turning it into a position.
func _to_page(q: Vector3) -> Vector2:
	var e: Vector3 = orient * (q - _mid)
	return Vector2(size.x * 0.5 + e.x * _scale, size.y * 0.5 - e.y * _scale)


func _eye(q: Vector3) -> Vector3:
	return orient * q


# --------------------------------------------------------------------- draw ----

func _draw() -> void:
	if creature == null or creature.contour == null or creature.contour.rings == 0:
		return
	var skin: Contour = creature.contour
	if not _frame(skin):
		return
	for v in _body.size():
		_pt[v] = _to_page(_body[v])
	_paint(skin)
	_draw_features(skin)
	_draw_axes()


## The specimen itself, in painter's order.
##
## Spans are sorted rather than facets — a tube segment is the unit the surface
## is actually made of, and 91 of them sort for the price of a fraction of the
## 724 facets they carry. Within a span the sectors are walked outward from the
## one facing furthest away from the eye, which is the same order a sort would
## have produced and costs no comparison at all.
func _paint(skin: Contour) -> void:
	var depth: int = _depth()
	var cut: float = _cut_at()
	_collect_spans(skin)
	_drawn = 0
	var quads: int = skin.facet_count()
	_reserve(quads)
	for i in _span_ix.size():
		var ring: int = _span_ix[i]
		var band: Contour.Band = skin.bands[skin.ring_band[ring]]
		var faint: float = 1.0 if focus.is_empty() or band.name == focus else 0.10
		var near: int = skin.ring_base[ring]
		var far: int = skin.ring_base[ring + 1]
		for s in _sector_order(skin, ring, band):
			var t: int = (s + 1) % band.sectors
			if _sectioned(cut, near + s, near + t, far + t, far + s):
				continue
			_emit(near + s, near + t, far + t, far + s,
				_facet_ink(skin, ring, s, depth, faint), ring, s)
	if _drawn == 0:
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),
		_face_ix.slice(0, _drawn * 6), _face_pt.slice(0, _drawn * 4),
		_face_col.slice(0, _drawn * 4))


## Every span of every band, ordered back to front on the mean depth of the two
## rings it runs between. A bucket rather than a comparison sort: the depths are
## bounded by the fit, the order only has to be right to the width of a facet,
## and this is a panel that runs every frame.
func _collect_spans(skin: Contour) -> void:
	var count: int = 0
	for band in skin.bands:
		count += band.count - 1
	if _span_ix.size() != count:
		_span_ix.resize(count)
		_span_depth.resize(count)
	var at: int = 0
	var low: float = INF
	var high: float = -INF
	for band in skin.bands:
		for r in range(band.first, band.first + band.count - 1):
			var d: float = _eye(_centre_of(skin, r)).z + _eye(_centre_of(skin, r + 1)).z
			_span_ix[at] = r
			_span_depth[at] = d
			low = minf(low, d)
			high = maxf(high, d)
			at += 1
	if count == 0 or high - low < 0.0001:
		return
	var buckets: int = 128
	var scale: float = float(buckets - 1) / (high - low)
	var counts := PackedInt32Array()
	counts.resize(buckets + 1)
	counts.fill(0)
	for i in count:
		counts[int((_span_depth[i] - low) * scale)] += 1
	var running: int = 0
	for b in buckets:
		var here: int = counts[b]
		counts[b] = running
		running += here
	var sorted := PackedInt32Array()
	sorted.resize(count)
	for i in count:
		var b: int = int((_span_depth[i] - low) * scale)
		sorted[counts[b]] = _span_ix[i]
		counts[b] += 1
	_span_ix = sorted


func _centre_of(skin: Contour, ring: int) -> Vector3:
	var p: Vector3 = skin.ring_centre[ring] - _origin
	return Vector3(_along.dot(p), _across.dot(p), p.z)


## The sectors of one ring, furthest-facing first. The sector whose outward
## direction points most directly away from the eye is a closed form — the
## turning point of `cos(θ)·up·ẑ + sin(θ)·lat·ẑ` — and the rest of the ring is
## walked outward from it in both directions at once.
func _sector_order(skin: Contour, ring: int, band: Contour.Band) -> PackedInt32Array:
	var up: float = _eye(_rotate(skin.ring_up[ring])).z
	var lat: float = _eye(_rotate(skin.ring_lat[ring])).z
	var away: float = atan2(lat, up) + PI
	var start: int = int(round(away / TAU * float(band.sectors))) % band.sectors
	if _order.size() != band.sectors:
		_order.resize(band.sectors)
	_order[0] = (start + band.sectors) % band.sectors
	var at: int = 1
	var step: int = 1
	while at < band.sectors:
		_order[at] = (start + step + band.sectors * 2) % band.sectors
		at += 1
		if at < band.sectors:
			_order[at] = (start - step + band.sectors * 2) % band.sectors
			at += 1
		step += 1
	return _order


## A direction in contour space, in the specimen's own frame.
func _rotate(d: Vector3) -> Vector3:
	return Vector3(_along.dot(d), _across.dot(d), d.z)


## Where the section plane stands, in the body coordinate it cuts. Parked past
## the end of the animal it cuts nothing, which is where the slider rests.
func _cut_at() -> float:
	if slice_axis < 0:
		return INF
	var low: float = [_low.x, _low.y, _low.z][slice_axis]
	var high: float = [_high.x, _high.y, _high.z][slice_axis]
	return lerpf(low, high, clampf(slice_at, 0.0, 1.0)) + 0.0001


## A facet is cut if any of its corners is past the plane — the carve takes the
## whole wedge rather than a sliver of it, so what is left standing is genuinely
## a body with a face on it.
func _sectioned(cut: float, a: int, b: int, c: int, d: int) -> bool:
	if cut == INF:
		return false
	var axis: int = slice_axis
	return _coord(a, axis) > cut or _coord(b, axis) > cut \
		or _coord(c, axis) > cut or _coord(d, axis) > cut


func _coord(v: int, axis: int) -> float:
	var q: Vector3 = _body[v]
	return q.x if axis == 0 else (q.y if axis == 1 else q.z)


## What one facet is painted: the census's own ink for that column at the current
## peel, lit by which way the wedge is facing.
func _facet_ink(skin: Contour, ring: int, sector: int, depth: int, faint: float) -> Color:
	var ink: Color = _ink(skin.ring_column[ring] + sector, depth)
	var n: Vector3 = _eye(_rotate(skin.direction(ring, sector)))
	var lit: float = FACET_FLOOR + FACET_GAIN * maxf(n.dot(LIGHT), 0.0)
	if n.z < 0.0:
		lit *= FACET_BACK
	ink = Color(ink.r * lit, ink.g * lit, ink.b * lit, ink.a)
	ink.a *= faint * (XRAY_ALPHA if xray else 1.0)
	return ink


func _reserve(quads: int) -> void:
	if _face_pt.size() >= quads * 4:
		return
	_face_pt.resize(quads * 4)
	_face_col.resize(quads * 4)
	_face_of.resize(quads)
	_face_ix.resize(quads * 6)
	for q in quads:
		var v: int = q * 4
		var i: int = q * 6
		_face_ix[i] = v
		_face_ix[i + 1] = v + 1
		_face_ix[i + 2] = v + 2
		_face_ix[i + 3] = v
		_face_ix[i + 4] = v + 2
		_face_ix[i + 5] = v + 3


func _emit(a: int, b: int, c: int, d: int, ink: Color, ring: int, sector: int) -> void:
	var v: int = _drawn * 4
	_face_pt[v] = _pt[a]
	_face_pt[v + 1] = _pt[b]
	_face_pt[v + 2] = _pt[c]
	_face_pt[v + 3] = _pt[d]
	_face_col[v] = ink
	_face_col[v + 1] = ink
	_face_col[v + 2] = ink
	_face_col[v + 3] = ink
	_face_of[_drawn] = ring * 64 + sector
	_drawn += 1


# ----------------------------------------------------------------- overlays ----

## The organs and the two networks, from the feature table and nothing else —
## §6's body coordinates placed on the posed rings. They are drawn over the
## animal and fade with how much flesh is still over them, which is the honest
## thing a top view can say about something that is genuinely inside.
func _draw_features(skin: Contour) -> void:
	if not show_vessels and not show_nerves:
		return
	var over: float = lerpf(1.0, CONDUIT_UNDER, float(_depth()) / 4.0)
	if xray:
		over = 1.0
	for band in skin.bands:
		for f: Dictionary in creature.corpus.features_in(band.name, Vector2(0.0, 1.0)):
			match str(f.get("feature", "")):
				"organ":
					if show_vessels:
						_draw_organ(skin, band, f, over)
				"vessel":
					if show_vessels:
						_draw_path(skin, band, f, COL_VESSEL, over,
							CONDUIT_WIDTH * float(f.get("radius", 0.5)) * 2.0)
				"nerve":
					if show_nerves:
						_draw_path(skin, band, f, COL_NERVE, over, CONDUIT_WIDTH)


## One vessel or nerve: its polyline of `[t, θ, depth]` placed on the rings it
## runs through, sampled between the authored points so a run down a bent neck
## follows the neck.
func _draw_path(skin: Contour, band: Contour.Band, f: Dictionary,
		ink: Color, over: float, width: float) -> void:
	var path: Array = f.get("path", [])
	if path.size() < 2:
		return
	var line := PackedVector2Array()
	for i in range(path.size() - 1):
		var a: Array = path[i]
		var b: Array = path[i + 1]
		for step in 5:
			var u: float = float(step) / 5.0
			line.append(_to_page(_address(skin, band,
				lerpf(a[0], b[0], u), lerp_angle(a[1], b[1], u), lerpf(a[2], b[2], u))))
	var last: Array = path[path.size() - 1]
	line.append(_to_page(_address(skin, band, last[0], last[1], last[2])))
	if line.size() > 1:
		draw_polyline(line, Color(ink, over), maxf(width, 1.0), true)


## An organ as the patch of body it actually occupies: its t range along the
## chain and its angular spread about its own bearing, at the middle of its depth
## band. The thing worth seeing is where the wound walk will find it, so it is
## drawn as that patch and not as a blob near it.
##
## Stitched as a strip rather than closed into one polygon: the patch runs along a
## bent chain and its two edges are on opposite sides of it, so the loop crosses
## itself the moment the back curves — and a self-crossing polygon is not a shape
## the renderer can fill.
func _draw_organ(skin: Contour, band: Contour.Band, f: Dictionary, over: float) -> void:
	var span: Vector2 = f["t_range"]
	var theta: float = float(f["theta"])
	var spread: float = float(f.get("spread", 0.5))
	var band_depth: Vector2 = f.get("depth", Vector2(0.6, 1.0))
	var mid: float = (band_depth.x + band_depth.y) * 0.5
	var steps: int = 7
	var edge := PackedVector2Array()
	var back := PackedVector2Array()
	for step in steps:
		var t: float = lerpf(span.x, span.y, float(step) / float(steps - 1))
		edge.append(_to_page(_address(skin, band, t, theta - spread * 0.5, mid)))
		back.append(_to_page(_address(skin, band, t, theta + spread * 0.5, mid)))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var ix := PackedInt32Array()
	var fill := Color(COL_ORGAN, over * 0.55)
	for step in steps:
		pts.append(edge[step])
		pts.append(back[step])
		cols.append(fill)
		cols.append(fill)
	for step in steps - 1:
		var a: int = step * 2
		ix.append_array(PackedInt32Array([a, a + 1, a + 3, a, a + 3, a + 2]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), ix, pts, cols)
	draw_polyline(edge, Color(COL_ORGAN, over * 0.8), 1.0, true)
	draw_polyline(back, Color(COL_ORGAN, over * 0.8), 1.0, true)


## A body address `(chain, t, θ, depth)` as a point on the page's own frame. The
## depth is a fraction of the local flesh — 0 at the skin, 1 at the bone core —
## exactly as §6 authors it, so a physique retune moves the flesh and the feature
## stays inside it.
##
## The bearing is *not* quantized to a sector. A trunk has ten of them and an
## organ's spread is often narrower than one, so rounding both its edges to the
## same wedge would collapse the patch to a line — the sector is only used to look
## the local flesh depth up, which varies slowly, and the direction is the
## continuous angle.
func _address(skin: Contour, band: Contour.Band, t: float, theta: float,
		depth: float) -> Vector3:
	var wrapped: float = fposmod(theta, TAU)
	var sector: int = int(floor(wrapped / TAU * float(band.sectors))) % band.sectors
	var ring: int = _ring_at(skin, band, t)
	var outer: float = skin.radius_at(band.name, t, sector, 4)
	var core: float = skin.radius_at(band.name, t, sector, 0)
	var dir: Vector3 = skin.ring_up[ring] * cos(wrapped) + skin.ring_lat[ring] * sin(wrapped)
	var p: Vector3 = skin.ring_centre[ring] \
		+ dir * lerpf(outer, core, clampf(depth, 0.0, 1.0)) - _origin
	return Vector3(_along.dot(p), _across.dot(p), p.z)


func _ring_at(skin: Contour, band: Contour.Band, t: float) -> int:
	var last: int = band.first + band.count - 1
	var at: int = band.first + int(round(clampf(t, 0.0, 1.0) * float(band.count - 1)))
	return clampi(at, band.first, last)


## Which way up the specimen is being held, in the corner of the slab. Three arms
## and no words but the axis letters: it is the one mark on the stage that is not
## the animal, and it exists so a body turned onto its back is legible as one.
## The far corner from the drawer's own captions, which own the near one.
func _draw_axes() -> void:
	if _mono == null:
		return
	var at := Vector2(size.x - AXIS_INSET - AXIS_ARM, size.y - AXIS_INSET)
	var names: Array[String] = ["N", "R", "U"]
	var arms: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0)]
	for i in 3:
		var e: Vector3 = orient * arms[i]
		var tip: Vector2 = at + Vector2(e.x, -e.y) * AXIS_ARM
		var faint: float = 0.20 + 0.28 * clampf(e.z * 0.5 + 0.5, 0.0, 1.0)
		draw_line(at, tip, Color(INK, faint), 1.0)
		draw_string(_mono, tip + Vector2(-2.0, 6.0), names[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(INK, faint + 0.10))


# ---------------------------------------------------------------- the hand ----

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and (click.button_index == MOUSE_BUTTON_WHEEL_UP
			or click.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		set_zoom(zoom * (ZOOM_STEP if click.button_index == MOUSE_BUTTON_WHEEL_UP
			else 1.0 / ZOOM_STEP))
		accept_event()
		return
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			reset_orbit()
		_orbiting = click.pressed
		if click.pressed:
			_grab = _on_ball(click.position)
			_grabbed = orient
			_hover = -1
			cell_hovered.emit("", false)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _orbiting:
		_turn_ball(motion.position)
		accept_event()
		return
	_pick(motion.position)


func _turn_ball(at: Vector2) -> void:
	var to: Vector3 = _on_ball(at)
	var axis: Vector3 = _grab.cross(to)
	var span: float = axis.length()
	if span < 0.000001:
		orient = _grabbed
		return
	orient = Basis(axis / span, atan2(span, _grab.dot(to))) * _grabbed


## The trackball: a sphere under the pointer, and a hyperbola outside it so a
## drag that leaves the ball keeps turning the specimen instead of stopping dead.
func _on_ball(at: Vector2) -> Vector3:
	var p: Vector2 = (at - size * 0.5) / maxf(_ball, 1.0)
	var d: float = p.length()
	var depth: float = sqrt(maxf(1.0 - d * d, 0.0)) if d <= BALL_EDGE else 0.5 / d
	return Vector3(p.x, -p.y, depth).normalized()


func _on_mouse_exited() -> void:
	if _hover >= 0:
		_hover = -1
		cell_hovered.emit("", false)


## Which cell is under the cursor: the frontmost facet whose own quad covers the
## pointer, tested against the facets exactly as they were last drawn. A peeled
## or sectioned specimen therefore picks what is actually showing, and a rolled
## one's near leg beats the flank behind it — because the answer is read out of
## the same painter's order the picture was.
func _pick(at: Vector2) -> void:
	if _drawn == 0 or creature == null:
		return
	for i in range(_drawn - 1, -1, -1):
		var v: int = i * 4
		if not _inside(at, _face_pt[v], _face_pt[v + 1], _face_pt[v + 2], _face_pt[v + 3]):
			continue
		if _hover == _face_of[i]:
			return
		_hover = _face_of[i]
		var word: Array = _read(_face_of[i] / 64, _face_of[i] % 64)
		cell_hovered.emit(word[0], word[1])
		return
	if _hover >= 0:
		_hover = -1
		cell_hovered.emit("", false)


static func _inside(p: Vector2, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return _in_tri(p, a, b, c) or _in_tri(p, a, c, d)


static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1: float = (p - b).cross(a - b)
	var d2: float = (p - c).cross(b - c)
	var d3: float = (p - a).cross(c - a)
	var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)


## What one facet is, in the drawer's own voice: which chain and station of the
## census, what is on top of it there, and how much of that is left. The second
## return is whether it is worth looking at — a breached wedge alarms the footer.
func _read(ring: int, sector: int) -> Array:
	var skin: Contour = creature.contour
	var corpus: Corpus = creature.corpus
	var band: Contour.Band = skin.bands[skin.ring_band[ring]]
	var column: int = skin.ring_column[ring] + sector
	var base: int = column * 4
	var names: Array[String] = ["BONE", "MUSCLE", "FAT", "SKIN"]
	var depth: int = _depth()
	for layer in range(depth - 1, -1, -1):
		if corpus.thickness[base + layer] <= 0.0:
			continue
		var hp: float = corpus.hp[base + layer]
		if hp <= 0.0:
			continue
		var text: String = "%s %02d/%d · %s %.2f PX" % [
			str(band.name).to_upper(), skin.ring_station[ring], band.stations,
			names[layer], corpus.thickness[base + layer] * hp]
		if hp < 0.999:
			return ["%s · %d%% LEFT" % [text, int(round(hp * 100.0))], true]
		return [text, false]
	return ["%s %02d/%d · BONE CORE · BREACHED" % [str(band.name).to_upper(),
		skin.ring_station[ring], band.stations], true]
