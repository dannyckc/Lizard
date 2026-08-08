shader_type canvas_item;
// Multiplicative, because a mark is pigment struck onto the same paper as the
// habitat under it rather than light laid over it: a mark crossing ink darkens
// it instead of glowing on top of it, and overlapping marks compound the way
// overlapping ink does.
render_mode blend_mul, unshaded;

void fragment() {
	// The hardware mul blend has no use for a source alpha, so the glyph's own
	// coverage has to be folded into the colour instead. Without this every mark
	// would multiply across its whole quad and the field would be squares.
	// COLOR arrives as the draw colour times the glyph texture, whose RGB is white
	// and whose alpha is the coverage, so COLOR.a is already coverage × opacity.
	COLOR = vec4(mix(vec3(1.0), COLOR.rgb, COLOR.a), 1.0);
}
