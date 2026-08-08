shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec2 sight_origin_px = vec2(720.0, 405.0);
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


float soft_blob(vec2 point, vec2 centre, float radius, float strength) {
	vec2 q = (point - centre) / max(radius, 0.001);
	return exp(-dot(q, q) * 2.35) * strength;
}


// A chain of overlapping, gently wandering blobs reads as a living field rather
// than a cone, circle or flashlight. The broad Gaussian tails are also the mask
// feather: there is no geometric edge for the eye to find.
float organic_field(vec2 point, float reach, float width, float near_radius,
		float seed, float tail_power) {
	float amount = soft_blob(point, vec2(0.0), near_radius, 1.35);
	for (int i = 0; i < 15; i++) {
		float t = float(i) / 14.0;
		float wobble = 1.0
			+ 0.17 * sin(t * 5.1 + time_seconds * 0.22 + seed)
			+ 0.10 * sin(t * 11.7 - time_seconds * 0.14 + seed * 2.1);
		float lateral = width * (0.13 * sin(t * 3.3 + time_seconds * 0.18 + seed)
			+ 0.07 * sin(t * 8.1 - time_seconds * 0.11));
		float distance_forward = reach * (0.06 + 0.94 * t);
		float radius = width * (0.34
			+ 0.78 * pow(max(sin(3.14159265 * (0.12 + 0.88 * t)), 0.0), 0.75)) * wobble;
		float strength = 0.86 * (1.0 - pow(t, tail_power));
		amount += soft_blob(point, vec2(distance_forward, lateral), radius, strength);
	}
	return 1.0 - exp(-amount * 0.72);
}


vec3 resolve_colour(vec3 colour, float desaturation, float contrast) {
	float value = dot(colour, vec3(0.299, 0.587, 0.114));
	vec3 greyed = mix(colour, vec3(value), desaturation);
	return mix(unresolved_paper.rgb, greyed, contrast);
}


void fragment() {
	vec2 screen_px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 forward = normalize(sight_direction);
	vec2 side = vec2(-forward.y, forward.x);
	vec2 from_eye = (screen_px - sight_origin_px) / max(pixels_per_world, 0.001);
	vec2 sight_space = vec2(dot(from_eye, forward), dot(from_eye, side));

	float clear_field = organic_field(sight_space, clear_reach, clear_width,
		clear_near_radius, 0.0, 1.7);
	float peripheral_field = organic_field(sight_space, peripheral_reach, peripheral_width,
		peripheral_near_radius, 1.9, 2.9);
	float clear_mask = smoothstep(0.23, 0.72, clear_field);
	float peripheral_mask = smoothstep(0.10, 0.66, peripheral_field);

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
