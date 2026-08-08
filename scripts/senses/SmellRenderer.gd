## Screen-space presentation of one SmellSense.
##
## The marks are painted on a fixed reading lattice in screen pixels, not in the
## habitat, so they never behave like objects in it — they belong to the observer.
## Nothing is drawn at a source: a pellet, a carcass and a scrap look exactly as
## they always did, and the impressions hang in the air near them.
##
## It sits above the sight treatment and below the controlled creature, which is
## the whole argument for smell existing beside sight: what the eyes could not
## resolve, the nose still annotates. It answers no perception questions — that
## is SmellSense's API — and reading a mark's glyph, size and hue off its fixed
## seed here is what keeps typography out of the sense.
class_name SmellRenderer
extends Node2D

@export var senses_path: NodePath
## Between SightRenderer (5) and the player's CreatureView (10).
@export var effect_z_index: int = 7

## Weak reads are sparse and scattered, sure ones tighten and gain structure.
const GLYPHS_FAR := ["·", ".", "˙", "·", ",", "·"]
const GLYPHS_MID := ["·", ":", "˙", "∶", "-", "/", "\\", "·", "·", "⁚"]
const GLYPHS_NEAR := [":", "⁚", "∷", "×", "+", "·", "≡", "//", "·", ":", "~", "="]
const BAND_NEAR: float = 0.55
const BAND_MID: float = 0.24

## What a read that resolved far enough to become legible says, per
## ScentField.Kind.
const WORDS := [
	["SEED", "STARCH", "TRACE", "SWEET", "FAINT"],
	["MUSK", "BREATH", "ALIVE", "WARM", "MOVES"],
	["DECAY", "IRON", "WARM", "MASS", "CLOSE"],
	["IRON", "FRESH", "WOUND", "HOT", "WET"],
	["MEAT", "TORN", "RAW", "SALT", "SCRAP"],
]
## Chance a legible mark shows the read's own certainty instead of a word.
const NUMERAL_CHANCE: float = 0.35
const LEGIBLE_SIZE: float = 8.0
const LEGIBLE_OPACITY: float = 0.85

## Fractions of a mark's life spent appearing and dissolving.
const FADE_IN: float = 0.22
const FADE_OUT: float = 0.4
const FLICKER_DEPTH: float = 0.26
## Certainty at which a mark has fully warmed to its source's hue.
const WARM_GAIN: float = 1.3
## Below this an impression is not on the paper at all.
const MIN_ALPHA: float = 0.02
## Margin in screen pixels beyond which a mark is not worth drawing.
const CULL_MARGIN: float = 70.0
## Random spread and certainty bonus on a mark's size, in points.
const SIZE_SPREAD: float = 3.0
const SIZE_GAIN: float = 2.4
## Box a mark is centred in. Only wide enough that no legible read overflows it.
const CENTRE_BOX: float = 160.0
const PIGMENT_SHADER: String = "res://shaders/smell.gdshader"


## Text choice, shaping and hue are immutable for a mark. TextLine retains the
## shaped glyph run, so an active field no longer asks the text server to shape
## hundreds of identical one-character strings again every frame.
class MarkVisual extends RefCounted:
	var line: TextLine
	var hue: Color = Color.WHITE
	var glyphs: Array[GlyphVisual] = []


## One already-shaped glyph, expressed as a quad in its font atlas. Marks can
## share these immutable metrics, then all glyphs using the same atlas texture
## are submitted as one triangle array instead of one TextLine draw at a time.
class GlyphVisual extends RefCounted:
	var texture: RID
	var offset: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2.ZERO
	var uv: Rect2 = Rect2()


class GlyphBatch extends RefCounted:
	var texture: RID
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func append_glyph(glyph: GlyphVisual, origin: Vector2, colour: Color) -> void:
		var first: int = points.size()
		var at: Vector2 = origin + glyph.offset
		points.append(at)
		points.append(at + Vector2(glyph.size.x, 0.0))
		points.append(at + glyph.size)
		points.append(at + Vector2(0.0, glyph.size.y))
		colours.append(colour)
		colours.append(colour)
		colours.append(colour)
		colours.append(colour)
		uvs.append(glyph.uv.position)
		uvs.append(glyph.uv.position + Vector2(glyph.uv.size.x, 0.0))
		uvs.append(glyph.uv.end)
		uvs.append(glyph.uv.position + Vector2(0.0, glyph.uv.size.y))
		indices.append(first)
		indices.append(first + 1)
		indices.append(first + 2)
		indices.append(first)
		indices.append(first + 2)
		indices.append(first + 3)


var senses: CreatureSenses

var _font: Font
var _tracked: Font
var _glyphs: Array[PackedStringArray] = []
var _mark_visuals: Dictionary = {}
var _glyph_batches: Dictionary = {}

## Exposed to the renderer benchmark: a saturated read should cost
## one command per live font atlas, not one command per mark.
var last_batch_count: int = 0
var last_glyph_count: int = 0


func _ready() -> void:
	z_index = effect_z_index
	if not senses_path.is_empty():
		senses = get_node_or_null(senses_path) as CreatureSenses
	_build_fonts()
	# Marks are struck into the paper rather than laid over it. CanvasItemMaterial's
	# multiply mode cannot express that for text — it has no use for the glyph's
	# coverage and stamps solid quads — so the blend carries the coverage itself.
	var pigment := ShaderMaterial.new()
	pigment.shader = load(PIGMENT_SHADER) as Shader
	material = pigment
	queue_redraw()


func _process(_delta: float) -> void:
	visible = senses != null and senses.smell != null and senses.smell.profile != null
	if visible:
		queue_redraw()


## Kept for symmetry with SightRenderer: a species swap replaces the profile, and
## nothing here caches anything off it that a redraw will not pick up.
func refresh_profile() -> void:
	_mark_visuals.clear()
	queue_redraw()


func _build_fonts() -> void:
	_font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if _font == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["IBM Plex Mono", "SF Mono", "Menlo", "monospace"])
		_font = fallback
	var tracked := FontVariation.new()
	tracked.base_font = _font
	tracked.spacing_glyph = 1
	_tracked = tracked
	# The design's marks reach past ASCII for a few of their denser forms. Drop the
	# ones this face cannot actually draw rather than stamping notdef boxes across
	# the habitat; what is left is still the same alphabet, only shorter.
	for bank in [GLYPHS_FAR, GLYPHS_MID, GLYPHS_NEAR]:
		var usable := PackedStringArray()
		for glyph in bank:
			if _drawable(glyph):
				usable.append(glyph)
		if usable.is_empty():
			usable.append("·")
		_glyphs.append(usable)


func _drawable(glyph: String) -> bool:
	for i in glyph.length():
		if not _font.has_char(glyph.unicode_at(i)):
			return false
	return true


func _draw() -> void:
	if senses == null or senses.smell == null:
		return
	var smell: SmellSense = senses.smell
	var profile: SmellProfile = smell.profile
	if profile == null:
		return
	if smell.marks.is_empty():
		_mark_visuals.clear()
		return

	# Draw in screen pixels while staying an ordinary node in the world canvas, so
	# the marks keep their place in the habitat's draw order but neither their size
	# nor their lattice follows the camera's zoom.
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	draw_set_transform_matrix(canvas.affine_inverse())
	var screen: Vector2 = get_viewport_rect().size
	var cell: float = maxf(profile.lattice_cell, 1.0)
	var steps: float = float(profile.opacity_steps)
	_prune_visuals(smell.marks)
	_glyph_batches.clear()
	last_batch_count = 0
	last_glyph_count = 0

	for mark in smell.marks:
		var at: Vector2 = canvas * mark.pos
		if at.x < -CULL_MARGIN or at.y < -CULL_MARGIN \
				or at.x > screen.x + CULL_MARGIN or at.y > screen.y + CULL_MARGIN:
			continue
		var alpha: float = _opacity(mark, smell.elapsed, profile)
		alpha = roundf(alpha * steps) / steps
		if alpha <= MIN_ALPHA:
			continue
		at = (at / cell).round() * cell
		var visual: MarkVisual = _visual_for(mark, profile)
		var line_size: Vector2 = visual.line.get_size()
		var origin := Vector2(at.x - CENTRE_BOX * 0.5, at.y - line_size.y * 0.5)
		var colour := Color(visual.hue, alpha * profile.layer_opacity)
		for glyph in visual.glyphs:
			_batch_for(glyph.texture).append_glyph(glyph, origin, colour)
			last_glyph_count += 1
	_flush_glyph_batches()
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _visual_for(mark: SmellSense.Mark, profile: SmellProfile) -> MarkVisual:
	var mark_id: int = mark.get_instance_id()
	if _mark_visuals.has(mark_id):
		return _mark_visuals[mark_id] as MarkVisual
	var visual := MarkVisual.new()
	var size: int = int(LEGIBLE_SIZE)
	var text: String
	var font: Font
	if mark.legible:
		text = _phrase(mark)
		font = _tracked
	else:
		var bank: PackedStringArray = _glyphs[_band(mark.confidence)]
		text = bank[_pick(mark.seed, 977.0, bank.size())]
		size = roundi(profile.glyph_size + _jitter(mark.seed, 13.0) * SIZE_SPREAD
			+ mark.confidence * SIZE_GAIN)
		font = _font
	size = maxi(size, 1)
	visual.line = TextLine.new()
	visual.line.width = CENTRE_BOX
	visual.line.alignment = HORIZONTAL_ALIGNMENT_CENTER
	visual.line.add_string(text, font, size)
	visual.hue = _pigment_hue(mark, profile)
	_cache_glyphs(visual)
	_mark_visuals[mark_id] = visual
	return visual


func _cache_glyphs(visual: MarkVisual) -> void:
	var text_server := TextServerManager.get_primary_interface()
	var shaped: RID = visual.line.get_rid()
	var line_size: Vector2 = visual.line.get_size()
	# TextLine draws from the top-left of its alignment box. Convert the shaped
	# baseline and advances into offsets from that same point once, at creation.
	var pen := Vector2((CENTRE_BOX - line_size.x) * 0.5,
		text_server.shaped_text_get_ascent(shaped))
	for shaped_glyph in text_server.shaped_text_get_glyphs(shaped):
		var repeat: int = maxi(int(shaped_glyph.get("repeat", 1)), 1)
		var font_rid: RID = shaped_glyph.font_rid
		var font_size: int = shaped_glyph.font_size
		var glyph_index: int = shaped_glyph.index
		var cache_size := Vector2i(font_size, 0)
		var glyph_size: Vector2 = text_server.font_get_glyph_size(
			font_rid, cache_size, glyph_index)
		var texture_size: Vector2 = text_server.font_get_glyph_texture_size(
			font_rid, cache_size, glyph_index)
		var texture: RID = text_server.font_get_glyph_texture_rid(
			font_rid, cache_size, glyph_index)
		var uv_pixels: Rect2 = text_server.font_get_glyph_uv_rect(
			font_rid, cache_size, glyph_index)
		var glyph_offset: Vector2 = text_server.font_get_glyph_offset(
			font_rid, cache_size, glyph_index) + shaped_glyph.offset
		for _copy in repeat:
			if texture.is_valid() and glyph_size.x > 0.0 and glyph_size.y > 0.0 \
					and texture_size.x > 0.0 and texture_size.y > 0.0:
				var glyph := GlyphVisual.new()
				glyph.texture = texture
				glyph.offset = pen + glyph_offset
				glyph.size = glyph_size
				glyph.uv = Rect2(uv_pixels.position / texture_size,
					uv_pixels.size / texture_size)
				visual.glyphs.append(glyph)
			pen.x += float(shaped_glyph.advance)


func _batch_for(texture: RID) -> GlyphBatch:
	if _glyph_batches.has(texture):
		return _glyph_batches[texture] as GlyphBatch
	var batch := GlyphBatch.new()
	batch.texture = texture
	_glyph_batches[texture] = batch
	return batch


func _flush_glyph_batches() -> void:
	for batch_value in _glyph_batches.values():
		var batch := batch_value as GlyphBatch
		if batch.indices.is_empty():
			continue
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),
			batch.indices, batch.points, batch.colours, batch.uvs,
			PackedInt32Array(), PackedFloat32Array(), batch.texture)
		last_batch_count += 1


func _prune_visuals(marks: Array[SmellSense.Mark]) -> void:
	var live: Dictionary = {}
	for mark in marks:
		live[mark.get_instance_id()] = true
	for mark_id in _mark_visuals.keys():
		if not live.has(mark_id):
			_mark_visuals.erase(mark_id)


## Appear on the beat, hold, dissolve — with a fine tremor over the whole of it,
## because a read is never quite steady.
func _opacity(mark: SmellSense.Mark, elapsed: float, profile: SmellProfile) -> float:
	var t: float = mark.age / maxf(mark.life, 0.001)
	var envelope: float = minf(1.0, t / FADE_IN) * minf(1.0, (1.0 - t) / FADE_OUT)
	var tremor: float = (1.0 - FLICKER_DEPTH) \
		+ FLICKER_DEPTH * sin(elapsed * profile.flicker_rate + mark.seed * 4.0 * TAU)
	var weight: float = profile.mark_opacity_floor + mark.confidence * profile.mark_opacity
	return envelope * tremor * weight * (LEGIBLE_OPACITY if mark.legible else 1.0)


## Uncertainty is cool and anonymous; certainty warms toward the hue of the thing
## being read, which is how a glance at the field says *what* as well as *where*.
func _pigment_hue(mark: SmellSense.Mark, profile: SmellProfile) -> Color:
	var cool: Color = profile.unread_tone
	if mark.kind != SmellSense.UNREAD and not profile.cool_tones.is_empty():
		cool = profile.cool_tones[_pick(mark.seed, 311.0, profile.cool_tones.size())]
	var warm: Color = cool
	if mark.kind >= 0 and mark.kind < profile.warm_tones.size():
		warm = profile.warm_tones[mark.kind]
	return cool.lerp(warm, minf(1.0, mark.confidence * WARM_GAIN))


func _phrase(mark: SmellSense.Mark) -> String:
	if _jitter(mark.seed, 7.0) < NUMERAL_CHANCE:
		return "%.2f" % mark.confidence
	if mark.kind < 0 or mark.kind >= WORDS.size():
		return "TRACE"
	var set: Array = WORDS[mark.kind]
	return set[_pick(mark.seed, 613.0, set.size())]


func _band(confidence: float) -> int:
	if confidence > BAND_NEAR:
		return 2
	return 1 if confidence > BAND_MID else 0


## Independent arbitrary choices pulled out of one seed, so a mark's glyph, size,
## tone and wording never drift while it is on the paper.
func _jitter(seed: float, salt: float) -> float:
	return fposmod(seed * salt, 1.0)


func _pick(seed: float, salt: float, count: int) -> int:
	return mini(int(_jitter(seed, salt) * float(count)), maxi(count - 1, 0))
