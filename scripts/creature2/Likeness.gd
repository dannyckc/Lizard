## The drawn animal — CreatureView's successor, reading the skin and nothing
## else (docs/V2_DESIGN.md §10).
##
## Purely a consumer: it reads the posed contour and the census's cell state and
## writes to neither, so the simulation runs identically headless. What it draws
## is the animal's own surface — a quad per ring-sector, inked by whichever
## layer of that wedge is still on top. So a bite does not get painted onto the
## picture; the wedge it emptied is thinner and a different colour on the tick it
## lands, because the picture is the census and there is nothing in between.
##
## The projection is one line and it is the same one the whole game is drawn in:
## a point at height z is drawn `z · PERSPECTIVE` up the screen from its plan
## position (`Carriage.drop`, the one statement of how far the view is tilted).
## v1 needed a shear transform on top of that because it drew the body as a flat
## sheet at one height and had to tip the sheet to say a leg was holding a corner
## lower; every v2 vertex carries its own height, so the tip is a consequence
## rather than a correction, and the shear is gone.
##
## Draw order is v1's, and for v1's reason: limbs, then the body over them, then
## the paws over that, so the legs read as being underneath the animal the way
## they do from above. Within a ring the sectors are painted ventral-first —
## from almost overhead a ring projects to a sliver and both its sides land on
## the same pixels, so the side facing the camera has to go down last.
##
## Cost is the lesson from v1's cell layer, kept: shades are banked per layer and
## wear, the geometry is written into arrays that are allocated once, the whole
## animal is four batched triangle arrays rather than several hundred polygon
## commands, and none of it walks the census unless a wound moved it.
class_name Likeness
extends Node2D

## How far off vertical the view is tilted. One owner — the same constant the
## stance geometry is built against, because how upright a body may stand and
## how far the picture is tilted are one decision.
const PERSPECTIVE: float = Carriage.PERSPECTIVE

const INK := Color("14140f")
const PAPER := Color("f3f1ec")
## Skin holds together as a membrane until it tears; a slight warm shift says
## strained without dissolving the silhouette wedge by wedge.
const SKIN_STRAINED := Color("2b211b")
## Fat is the one warm light tone on the animal, which is what keeps a fat body
## legibly different from a lean one the moment either is opened.
const FAT := Color("e0cfa8")
const FAT_DEEP := Color("c4ab7c")
const MUSCLE := Color("9c3b26")
const MUSCLE_DEEP := Color("5f2114")
## Bone is a tone, not a highlight, and it darkens as it is ground down: pale
## out and a skeleton is indistinguishable from a hole.
const BONE := Color("c9bda0")
const BONE_WORN := Color("a08d68")
const EYE := PAPER

## Three restrained offset copies of the plan silhouette approximate the
## diffused editorial shadow without a sprite or a blur; limbs sit close to the
## ground and take one tight copy instead.
const SHADOW_FAR := Color(INK, 0.020)
const SHADOW_MID := Color(INK, 0.035)
const SHADOW_NEAR := Color(INK, 0.055)
const SHADOW_LIMB := Color(INK, 0.05)
const SHADOW_SPREAD := Vector2(0.0, 6.0)

## Wear steps a layer's colour is banked at. Penetration reads as a gradient and
## breaching a layer as a step change; six steps is where the gradient stops
## being a staircase and the bank stops being a palette.
const WEAR: int = 6

@export var debug_rings: bool = false

var creature: Creature2

# --- geometry, allocated once ------------------------------------------------
## Screen points and their own ground shadows, one per ring-sector plus one per
## band's cone tip.
var _pt := PackedVector2Array()
var _plan := PackedVector2Array()
var _col := PackedColorArray()
## Triangles, by pass. Rebuilt only when a ring turns over.
var _limb_faces := PackedInt32Array()
var _body_faces := PackedInt32Array()
var _paw_faces := PackedInt32Array()
## The plan silhouette, as a strip between each band's two flanks.
var _body_shade := PackedInt32Array()
var _limb_shade := PackedInt32Array()
## Which way up each ring was facing when the triangles were last stitched.
var _turned := PackedByteArray()

## Single-entry colour array: Godot broadcasts one colour across a whole
## triangle array, which is what lets a shadow reuse geometry already built.
var _flat := PackedColorArray([Color.TRANSPARENT])
## Shades per (layer, wear), plus the bare bone core at the end — a wedge eaten
## through to the vertebra is still a vertebra.
var _bank := PackedColorArray()

var _shaded_rev: int = -1
var _built_for: int = -1


func _ready() -> void:
	creature = get_parent() as Creature2
	_bank_shades()


func _physics_process(_delta: float) -> void:
	queue_redraw()


# ------------------------------------------------------------------- shades ----

## Every colour the animal can be, banked once. A drawn wedge is a lookup.
func _bank_shades() -> void:
	_bank.resize(4 * WEAR + 1)
	for step in WEAR:
		var wear: float = float(step) / float(WEAR - 1)
		_bank[BodySchema.Layer.SKIN * WEAR + step] = INK.lerp(SKIN_STRAINED, wear * 0.24)
		_bank[BodySchema.Layer.FAT * WEAR + step] = FAT.lerp(FAT_DEEP, wear)
		_bank[BodySchema.Layer.MUSCLE * WEAR + step] = MUSCLE.lerp(MUSCLE_DEEP, wear)
		_bank[BodySchema.Layer.BONE * WEAR + step] = BONE.lerp(BONE_WORN, wear)
	_bank[4 * WEAR] = BONE_WORN


## The ink of one census column: whichever layer is still outermost there, shaded
## by how much of it is left. Layers are tested in the order a bite goes through
## them, which is the whole reason nothing here has to know anything about
## damage — a wedge is drawn as whatever is currently on top of it, and a wedge
## chewed past its last layer is drawn as the bone core it is standing on.
func _ink(column: int) -> Color:
	var corpus: Corpus = creature.corpus
	var base: int = column * 4
	for layer in [BodySchema.Layer.SKIN, BodySchema.Layer.FAT,
			BodySchema.Layer.MUSCLE, BodySchema.Layer.BONE]:
		if corpus.thickness[base + layer] <= 0.0:
			continue
		var hp: float = corpus.hp[base + layer]
		if hp <= 0.0:
			continue
		return _bank[layer * WEAR + clampi(int((1.0 - hp) * float(WEAR)), 0, WEAR - 1)]
	return _bank[4 * WEAR]


# --------------------------------------------------------------------- draw ----

func _draw() -> void:
	if creature == null:
		return
	var skin: Contour = creature.contour
	if skin == null or skin.rings == 0:
		return
	_project(skin)
	_shade(skin)
	_stitch(skin)

	# Shadows first and from the plan silhouette, because a shadow is on the
	# ground: a tail held clear of the floor and one lying on it cast the same
	# outline in the same place, and the growing gap between the two is the whole
	# of how height reads in a picture taken from above.
	_cast(_limb_shade, SHADOW_LIMB, SHADOW_SPREAD * 0.25)
	_cast(_body_shade, SHADOW_FAR, SHADOW_SPREAD)
	_cast(_body_shade, SHADOW_MID, SHADOW_SPREAD * 0.6)
	_cast(_body_shade, SHADOW_NEAR, SHADOW_SPREAD * 0.2)

	var canvas: RID = get_canvas_item()
	RenderingServer.canvas_item_add_triangle_array(canvas, _limb_faces, _pt, _col)
	RenderingServer.canvas_item_add_triangle_array(canvas, _body_faces, _pt, _col)
	RenderingServer.canvas_item_add_triangle_array(canvas, _paw_faces, _pt, _col)
	_draw_eyes(skin)
	if debug_rings:
		_draw_rings(skin)


## The one projection: plan position, carried up the screen by its own height.
func _project(skin: Contour) -> void:
	var count: int = skin.surface.size() + skin.bands.size()
	if _pt.size() != count:
		_pt.resize(count)
		_plan.resize(count)
		_col.resize(count)
		_shaded_rev = -1
	for v in skin.surface.size():
		var p: Vector3 = skin.surface[v]
		_plan[v] = Vector2(p.x, p.y)
		_pt[v] = Vector2(p.x, p.y - p.z * PERSPECTIVE)
	var tip: int = skin.surface.size()
	for b in skin.bands.size():
		var p: Vector3 = skin.tips[b]
		_plan[tip + b] = Vector2(p.x, p.y)
		_pt[tip + b] = Vector2(p.x, p.y - p.z * PERSPECTIVE)


## Re-inks the wedges. Keyed to the census's revision: an undamaged animal walks
## about for as long as it likes without a single colour being decided again.
func _shade(skin: Contour) -> void:
	if _shaded_rev == creature.corpus.revision:
		return
	_shaded_rev = creature.corpus.revision
	var tip: int = skin.surface.size()
	for b in skin.bands.size():
		var band: Contour.Band = skin.bands[b]
		for r in range(band.first, band.first + band.count):
			var at: int = skin.ring_base[r]
			var column: int = skin.ring_column[r]
			for s in band.sectors:
				_col[at + s] = _ink(column + s)
		_col[tip + b] = _col[skin.ring_base[band.first + band.count - 1]]


## Stitches the rings into triangles. Topology is fixed, so this runs on the
## first frame and then only when a ring has turned over — which is a body
## rolling onto its back, not a body walking.
func _stitch(skin: Contour) -> void:
	var turned: bool = _built_for != skin.rings or _turned.size() != skin.rings
	if not turned:
		for r in skin.rings:
			if _turned[r] != (1 if skin.ring_up[r].z < 0.0 else 0):
				turned = true
				break
	if not turned:
		return
	_built_for = skin.rings
	_turned.resize(skin.rings)
	for r in skin.rings:
		_turned[r] = 1 if skin.ring_up[r].z < 0.0 else 0

	_limb_faces.clear()
	_body_faces.clear()
	_paw_faces.clear()
	_body_shade.clear()
	_limb_shade.clear()
	var per_stick: int = maxi(BodySchema.RINGS_PER_STICK, 1)
	var tip: int = skin.surface.size()
	for b in skin.bands.size():
		var band: Contour.Band = skin.bands[b]
		# The paw is the last bone of a limb and is drawn over the body, the
		# same way v1 drew feet over the torso: from above, a foot planted
		# beside the animal is in front of the flank it is beside.
		var paw_from: int = band.count - 1 - per_stick if band.limb else band.count
		for span in range(band.count - 1):
			var tube: PackedInt32Array = _stitch_span(skin, band, band.first + span)
			if not band.limb:
				_body_faces.append_array(tube)
				_body_shade.append_array(_silhouette(skin, band, band.first + span))
			else:
				if span >= paw_from:
					_paw_faces.append_array(tube)
				else:
					_limb_faces.append_array(tube)
				_limb_shade.append_array(_silhouette(skin, band, band.first + span))
		if band.tip:
			var cone: PackedInt32Array = _cone(skin, band, tip + b)
			if band.limb:
				_paw_faces.append_array(cone)
			else:
				_body_faces.append_array(cone)


## One span of tube, sector by sector in paint order — ventral first, or dorsal
## first on a ring that has turned over.
func _stitch_span(skin: Contour, band: Contour.Band, ring: int) -> PackedInt32Array:
	var faces := PackedInt32Array()
	faces.resize(band.sectors * 6)
	var near: int = skin.ring_base[ring]
	var far: int = skin.ring_base[ring + 1]
	var flipped: bool = _turned[ring] != 0
	var v: int = 0
	for i in band.sectors:
		var s: int = band.order[band.sectors - 1 - i] if flipped else band.order[i]
		var t: int = (s + 1) % band.sectors
		faces[v] = near + s
		faces[v + 1] = near + t
		faces[v + 2] = far + t
		faces[v + 3] = near + s
		faces[v + 4] = far + t
		faces[v + 5] = far + s
		v += 6
	return faces


## The cone that closes a free end: a snout, a tail tip, a toe.
func _cone(skin: Contour, band: Contour.Band, apex: int) -> PackedInt32Array:
	var faces := PackedInt32Array()
	faces.resize(band.sectors * 3)
	var at: int = skin.ring_base[band.first + band.count - 1]
	var v: int = 0
	for i in band.sectors:
		var s: int = band.order[i]
		faces[v] = apex
		faces[v + 1] = at + s
		faces[v + 2] = at + (s + 1) % band.sectors
		v += 3
	return faces


## The strip between a band's two flanks — the outline the body actually casts.
## Drawn from its own quads rather than from the tube, because a tube's sectors
## overlap in a near-overhead projection and a shadow stacked on itself is a
## shadow with bands of double ink in it.
func _silhouette(skin: Contour, band: Contour.Band, ring: int) -> PackedInt32Array:
	var near: int = skin.ring_base[ring]
	var far: int = skin.ring_base[ring + 1]
	return PackedInt32Array([
		near + band.right, near + band.left, far + band.left,
		near + band.right, far + band.left, far + band.right])


## One copy of a silhouette, displaced and in one flat ink.
func _cast(strip: PackedInt32Array, ink: Color, offset: Vector2) -> void:
	if strip.is_empty():
		return
	_flat[0] = ink
	draw_set_transform(offset)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), strip, _plan, _flat)
	draw_set_transform(Vector2.ZERO)


## Two paper pinpricks give the otherwise abstract ink silhouette its life — but
## only while there is still a head under them to belong to. An eye over an
## eaten-out skull would be the one thing left painting paper onto nothing.
func _draw_eyes(skin: Contour) -> void:
	var band: Contour.Band = skin.band(BodySchema.NECK)
	if band == null:
		return
	var head: int = band.first + band.count - 1
	# Asked of the census rather than of the picture: an eye belongs on a head
	# that still has skin over its skull, and that is a cell, not a colour.
	if creature.corpus.hp[skin.ring_column[head] * 4 + BodySchema.Layer.SKIN] <= 0.0:
		return
	# Placed on the skull in three dimensions and then projected, like every
	# other point on the animal: an eye is on the upper front of a head, and
	# from above that is where it has to be drawn.
	var r: float = skin.mean_radius(head)
	var forward: Vector3 = skin.ring_axis[head] * (r * 0.30)
	var over: Vector3 = skin.ring_up[head] * (r * 0.55)
	for hand in [-1.0, 1.0]:
		var eye: Vector3 = skin.ring_centre[head] + forward + over \
			+ skin.ring_lat[head] * (r * 0.40 * hand)
		draw_circle(Vector2(eye.x, eye.y - eye.z * PERSPECTIVE), r * 0.13, EYE)


## The ring line itself — what the skin is hung on. Diagnostic only.
func _draw_rings(skin: Contour) -> void:
	for r in skin.rings:
		var c: Vector3 = skin.ring_centre[r]
		draw_circle(Vector2(c.x, c.y - c.z * PERSPECTIVE), 0.6, Color(PAPER, 0.5))
