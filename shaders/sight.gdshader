shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec2 sight_origin_uv = vec2(0.5, 0.5);
uniform vec2 viewport_size = vec2(1440.0, 810.0);
uniform vec2 sight_direction = vec2(1.0, 0.0);
uniform float pixels_per_world = 1.0;
uniform float time_seconds = 0.0;

uniform float clear_reach = 300.0;
uniform float clear_width = 130.0;
uniform float clear_near_radius = 52.0;
uniform float peripheral_reach = 560.0;
uniform float peripheral_width = 260.0;
uniform float peripheral_near_radius = 130.0;

uniform float unseen_blur_lod = 3.15;
uniform float peripheral_blur_lod = 1.55;
uniform float unseen_desaturation = 0.92;
uniform float unseen_contrast = 0.58;
uniform float peripheral_desaturation = 0.55;
uniform float peripheral_contrast = 0.88;
uniform float paper_wash = 0.18;
uniform float peripheral_opacity = 0.82;
uniform vec4 unresolved_paper : source_color = vec4(0.933, 0.941, 0.949, 1.0);


// An analytic organic envelope replaces the old chain of 15 Gaussian blobs.
// This is evaluated twice per pixel (clear + peripheral), so the old approach
// performed 30 exp() calls and dozens of trig/pow operations for every fragment.
// The envelope retains the soft near field, irregular sides and breathing tail
// while making its cost constant and small at high output resolutions.
float organic_field(vec2 point, float reach, float width, float near_radius,
		float seed, float tail_power) {
	float near_distance = length(point) / max(near_radius, 0.001);
	float near_field = 1.0 - smoothstep(0.42, 1.15, near_distance);

	float t = clamp(point.x / max(reach, 0.001), 0.0, 1.0);
	float arch = pow(max(sin(3.14159265 * (0.12 + 0.88 * t)), 0.0), 0.75);
	float breath = 1.0
		+ 0.13 * sin(t * 5.1 + time_seconds * 0.22 + seed)
		+ 0.06 * sin(t * 11.7 - time_seconds * 0.14 + seed * 2.1);
	float radius = max(width * (0.34 + 0.78 * arch) * breath, 0.001);
	float lateral_centre = width * (
		0.10 * sin(t * 3.3 + time_seconds * 0.18 + seed)
		+ 0.045 * sin(t * 8.1 - time_seconds * 0.11));
	float across = abs(point.y - lateral_centre) / radius;
	float lateral_field = 1.0 - smoothstep(0.42, 1.0, across);
	float front = smoothstep(-0.025, 0.055, point.x / max(reach, 0.001));
	float tail = 1.0 - smoothstep(0.68, 1.0, pow(t, tail_power * 0.55));
	return max(near_field, lateral_field * front * tail);
}


vec3 resolve_colour(vec3 colour, float desaturation, float contrast) {
	float value = dot(colour, vec3(0.299, 0.587, 0.114));
	vec3 greyed = mix(colour, vec3(value), desaturation);
	return mix(unresolved_paper.rgb, greyed, contrast);
}


void fragment() {
	vec2 forward = normalize(sight_direction);
	vec2 side = vec2(-forward.y, forward.x);
	// SCREEN_UV is resolution-independent. viewport_size and pixels_per_world
	// are both logical canvas units, so their ratio remains correct when an
	// embedded or standalone window renders the canvas at another pixel size.
	vec2 from_eye = ((SCREEN_UV - sight_origin_uv) * viewport_size)
		/ max(pixels_per_world, 0.001);
	vec2 sight_space = vec2(dot(from_eye, forward), dot(from_eye, side));

	float clear_field = organic_field(sight_space, clear_reach, clear_width,
		clear_near_radius, 0.0, 1.7);
	float peripheral_field = organic_field(sight_space, peripheral_reach, peripheral_width,
		peripheral_near_radius, 1.9, 2.9);
	float clear_mask = smoothstep(0.08, 0.88, clear_field);
	float peripheral_mask = smoothstep(0.04, 0.82, peripheral_field);

	vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec4 unresolved_sample = textureLod(screen_texture, SCREEN_UV, unseen_blur_lod);
	vec4 peripheral_sample = textureLod(screen_texture, SCREEN_UV, peripheral_blur_lod);

	vec3 unresolved = resolve_colour(unresolved_sample.rgb,
		unseen_desaturation, unseen_contrast);
	unresolved = mix(unresolved, unresolved_paper.rgb, paper_wash);
	vec3 peripheral = resolve_colour(peripheral_sample.rgb,
		peripheral_desaturation, peripheral_contrast);

	vec3 colour = mix(unresolved, peripheral, peripheral_mask * peripheral_opacity);
	colour = mix(colour, original.rgb, clear_mask);
	COLOR = vec4(colour, original.a);
}
