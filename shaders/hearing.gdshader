shader_type canvas_item;
render_mode blend_mul, unshaded;

// The renderer submits every wave particle in one triangle array. UV stores the
// dot-local position in radius units; derivatives preserve the soft edge even
// though the dots are only about one screen pixel across.
varying vec4 pigment;

void vertex() {
	pigment = COLOR;
}

void fragment() {
	float distance_from_center = length(UV);
	float edge = max(fwidth(distance_from_center), 0.001);
	float coverage = 1.0 - smoothstep(1.0 - edge, 1.0 + edge,
		distance_from_center);
	float alpha = pigment.a * coverage;
	COLOR = vec4(mix(vec3(1.0), pigment.rgb, alpha), 1.0);
}
