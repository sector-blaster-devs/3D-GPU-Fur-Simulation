// Shell fur for rigged meshes. One layer of a FurCoat shell mesh (Scripts/VFX/FurCoat.gd).
//
// Godot 4 Compatibility (WebGL2) port of the shell layer and hair shading from
// github.com/sector-blaster-devs/3D-GPU-Fur-Simulation ("Mochi-Puff"):
//   MIT License, Copyright (c) 2026 Mochi-Puff Contributors (upstream revision c5d295f8).
//   The full license text and what was derived are in FUR_THIRD_PARTY.md, next to
//   this file. Keep that file with this one wherever it is copied.
//
// What changed from the original, and why:
//   - The original maps strands by the direction from the creature's centre, which only
//     works on a ball. Here strands are laid out triplanar on the BIND-POSE position
//     (CUSTOM0.xyz), so they work on any mesh, need no UVs (the Quaternius animals have
//     none) and stay glued to the skin while the skeleton animates.
//   - No GPGPU ping-pong simulation: float render targets are not dependable in the
//     Discord WebGL iframe. The original's own "WebGL mode" spring is used instead; FurCoat
//     runs it on the CPU and feeds `inertia`.
//   - Lights come from the scene (light()), not hard-coded key/rim uniforms.
//
// Vertex inputs written by FurCoat:
//   CUSTOM0 = bind-pose position (mesh space), shell height h in (0, 1]
//   CUSTOM1 = bind-pose normal, fur length multiplier (0 = bald)

shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
// How much lighter the tips are than the roots.
uniform float tip_lift : hint_range(0.0, 1.0) = 0.35;
// Mesh units. FurCoat derives both from the model's size.
uniform float fur_length = 0.05;
uniform float cell_size = 0.01;
uniform float body_scale = 1.0;
uniform float density : hint_range(0.1, 1.0) = 0.85;
uniform float clumping : hint_range(0.0, 1.0) = 0.20;
uniform float curliness : hint_range(0.0, 1.0) = 0.15;
uniform float roughness : hint_range(0.05, 0.95) = 0.6;
uniform float specular : hint_range(0.0, 2.0) = 0.35;
// Strand radius in cell units (0.5 = strands touch).
uniform float strand_width : hint_range(0.1, 0.7) = 0.36;
// Fur height allowed per texel (R). White = full coat, black = bald.
uniform sampler2D fur_mask : hint_default_white, filter_linear;
// Opt-in: texels whose brightest channel (linear) is below this stay bald. For
// single-texture models whose eyes / noses / headphones share the coat's material.
// The brightest channel, not luma: luma counts saturated dark blue as near-black.
// 0 = off.
uniform float bald_below_brightness : hint_range(0.0, 0.3) = 0.0;
// How far the coat lies down along `groom_dir` instead of standing straight out.
uniform float groom : hint_range(0.0, 1.0) = 0.35;
uniform float gravity : hint_range(0.0, 1.0) = 0.25;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.5;
// World metres per strand cell (FurCoat), for the distance fade.
uniform float cell_world = 0.01;
// Mesh space. FurCoat updates these every frame.
uniform vec3 mesh_down = vec3(0.0, -1.0, 0.0);
uniform vec3 inertia = vec3(0.0);

varying float v_h;
varying vec3 v_rest_pos;
varying vec3 v_rest_nrm;
varying vec3 v_hair;

void vertex() {
	float h = CUSTOM0.w;
	v_h = h;
	v_rest_pos = CUSTOM0.xyz;
	v_rest_nrm = CUSTOM1.xyz;

	vec3 n = normalize(NORMAL);
	float len = fur_length * CUSTOM1.w;
	float bend = pow(h, 1.55);

	// Per-vertex groom from FurCoat, packed as TANGENT so it is skinned with the body:
	// along the bones, away from the face.
	vec3 lie = TANGENT - n * dot(TANGENT, n);
	lie = length(lie) > 1e-4 ? normalize(lie) * groom : vec3(0.0);

	vec3 p = CUSTOM0.xyz * body_scale * 4.0;
	vec3 wind = vec3(
		sin(p.y * 4.2 + TIME * 2.6) * 0.08,
		cos(p.x * 3.8 + TIME * 2.1) * 0.04,
		cos(p.z * 4.0 - TIME * 2.4) * 0.08) * wind_strength;

	vec3 push = mesh_down * gravity + inertia * 0.42 + wind;
	// Hair may sweep along the skin but never into it.
	push -= n * min(0.0, dot(push, n));

	VERTEX += n * (h * len) + (lie + push) * bend * len;

	vec3 dir = n + (lie + push) * 1.55 * pow(max(0.05, h), 0.55);
	v_hair = normalize((MODELVIEW_MATRIX * vec4(dir, 0.0)).xyz);
}

vec3 hash23(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.xxz + p3.yxx) * p3.zyx);
}

// 1.0 where a strand of this projected grid passes through shell height h.
// `far` (0..1) rises as strands shrink below ~2 px: they then only sparkle, so they
// shorten and thicken into a closed velvet. `edge` = 0 on the strand's axis, 1 at its rim.
float strand(vec2 uv, float h, float far, out float seed, out float edge) {
	// Macro variation must not pull every strand toward a shared centre: that turns the
	// shell layers into visible radial scales. Shift each patch as a whole instead, then
	// keep the strand-level variation below independent per cell.
	vec3 cr = hash23(floor(uv * 0.24) + 71.0);
	uv += (cr.xy - 0.5) * (h * clumping * (0.20 + 0.18 * cr.z));
	vec2 cell = floor(uv);
	vec2 local = fract(uv) - 0.5;
	vec3 r = hash23(cell);
	seed = r.x;
	edge = 1.0;

	// Far away the strands shorten to a lower, narrower spread of heights: the coat
	// keeps a fibrous top and silhouette without the tall tips that sparkle.
	float max_h = mix(mix(0.32, 1.0, r.z), mix(0.3, 0.7, r.z), far) * clamp(density * 1.08, 0.22, 1.0);
	if (h > max_h) {
		return 0.0;
	}
	float angle = h * mix(1.4, 4.4, curliness) + r.x * 6.28318;
	float env = h * h * (3.0 - 2.0 * h);
	// Strands sit well off their cell centres: at 0.22 the cells' grid showed through
	// as a regular lattice of spikes.
	vec2 centre = (r.xy - 0.5) * 0.30
		+ vec2(cos(angle), sin(angle)) * (0.02 * clumping + 0.055 * curliness) * env;
	float nh = clamp(h / max(0.15, max_h), 0.0, 1.0);
	// A shaft of varied width that narrows over its upper part. The original's cone,
	// tapering from the root, turned every visible shell edge into a quill point.
	float radius = strand_width * mix(0.86, 1.10, fract(r.x * 7.13)) * (1.0 - pow(nh, 2.3));
	// Closed undercoat at the skin, so the coat reads as a volume, not bristles on skin.
	radius = max(radius, 0.9 * (1.0 - smoothstep(0.1, 0.3, h)));
	radius = mix(radius, 0.7, far);
	float d = length(local - centre);
	edge = clamp(d / max(radius, 1e-3), 0.0, 1.0);
	return step(d, radius);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * base_color.rgb;
	// Bald where the mask says so or, opt-in, where the texture is dark and grey.
	float allowed = texture(fur_mask, UV).r;
	if (bald_below_brightness > 0.0) {
		// Judged on a slightly blurred sample: a dark area a few texels wide (an atlas eye)
		// otherwise leaves a square hole in the coat.
		vec2 px = 1.2 / vec2(textureSize(albedo_tex, 0));
		vec3 soft = base * 2.0;
		soft += texture(albedo_tex, UV + vec2(px.x, px.y)).rgb * base_color.rgb;
		soft += texture(albedo_tex, UV + vec2(-px.x, px.y)).rgb * base_color.rgb;
		soft += texture(albedo_tex, UV + vec2(px.x, -px.y)).rgb * base_color.rgb;
		soft += texture(albedo_tex, UV - px).rgb * base_color.rgb;
		soft /= 6.0;
		allowed *= smoothstep(bald_below_brightness, bald_below_brightness * 1.25,
			max(soft.r, max(soft.g, soft.b)));
	}
	if (v_h > allowed) {
		discard;
	}

	vec3 w = pow(abs(normalize(v_rest_nrm)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 g = v_rest_pos / cell_size;
	// Strand cells per pixel, from distance alone. Screen derivatives also grow on
	// surfaces seen edge-on, which flattened whole patches of the coat while their
	// neighbours kept their strands.
	// abs(): Compatibility renders into a Y-flipped target, so [1][1] is negative there.
	// Orthographic cameras ([3][3] == 1) have no depth term: a pixel is the same size everywhere.
	float depth_term = PROJECTION_MATRIX[3][3] > 0.5 ? 1.0 : -VERTEX.z;
	float pixel_world = 2.0 * depth_term / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float far = smoothstep(0.35, 0.9, pixel_world / cell_world);
	float sx;
	float sy;
	float sz;
	float ex;
	float ey;
	float ez;
	float cover = w.x * strand(g.yz, v_h, far, sx, ex) + w.y * strand(g.xz + 17.0, v_h, far, sy, ey)
		+ w.z * strand(g.xy + 31.0, v_h, far, sz, ez);
	if (cover < 0.5) {
		discard;
	}
	bool x_wins = w.x > w.y && w.x > w.z;
	bool y_wins = !x_wins && w.y > w.z;
	float seed = x_wins ? sx : (y_wins ? sy : sz);
	float edge = x_wins ? ex : (y_wins ? ey : ez);

	vec3 tip = min(base * 1.3 + 0.01, vec3(1.0));
	vec3 albedo = mix(base, tip, smoothstep(0.05, 0.92, pow(v_h, 0.82)) * tip_lift);
	albedo *= mix(0.92, 1.08, seed);
	// Round shaft: darker toward the strand's rim, so strands read as hairs, not flat cards.
	albedo *= mix(1.0, 0.86, edge * edge * (1.0 - far) * (1.0 - far));
	// Follicle occlusion: the coat is dark near the skin.
	// Mild: strong root darkening made every strand a bright spike over a dark gap.
	ALBEDO = albedo * mix(0.7, 1.0, pow(v_h, 0.6));
	// Hands `far` to light() (which can't see fragment locals): sub-pixel strands get a
	// dimmer highlight instead of a sparkle.
	ROUGHNESS = mix(roughness, 0.95, far);
}

// Kajiya-Kay longitudinal lobe along the hair tangent.
float hair_lobe(vec3 t, vec3 n, vec3 v, vec3 l, float rough) {
	vec3 hv = normalize(l + v + vec3(1e-6));
	float t_h = clamp(dot(t, hv), -1.0, 1.0);
	float sin_th = sqrt(max(1e-5, 1.0 - t_h * t_h));
	float hemi = smoothstep(-0.25, 0.15, dot(n, l));
	float expo = mix(220.0, 10.0, clamp(rough * rough, 0.0, 1.0));
	return hemi * pow(sin_th, expo) * (expo + 2.0) / 8.0 * 0.095;
}

void light() {
	vec3 n = NORMAL;
	vec3 t = normalize(v_hair);
	float n_l = dot(n, LIGHT);
	vec3 lc = LIGHT_COLOR * ATTENUATION / PI;

	// Godot multiplies DIFFUSE_LIGHT by ALBEDO after this function but leaves
	// SPECULAR_LIGHT alone (checked with a controlled render, 2026-10-28), so any
	// pigment on highlights has to be applied here.

	// Wrapped diffuse through a Beer-Lambert estimate of the coat above this shell.
	float wrap = clamp((n_l + 0.45) / 1.45, 0.0, 1.0);
	float depth = (1.0 - v_h) * (0.45 + 0.55 * density) / max(0.22, n_l * 0.5 + 0.55);
	float shade = exp(-depth * 0.6);
	DIFFUSE_LIGHT += lc * wrap * shade;

	// Marschner R (shifted to the root) and TRT (shifted to the tip, pigment-tinted).
	// R is half-tinted by the coat: a pure-white R over thousands of tips bleached grey
	// coats to silver.
	// Far away the lobes keep their width and fade instead. Widening them to hide
	// sparkle spread a pale sheen over whole coats (silver wolf, banded horse).
	float far = clamp((ROUGHNESS - roughness) / max(0.95 - roughness, 1e-3), 0.0, 1.0);
	float spec_r = hair_lobe(normalize(t - n * 0.16), n, VIEW, LIGHT, roughness);
	float spec_trt = hair_lobe(normalize(t + n * 0.24), n, VIEW, LIGHT, min(1.0, roughness * 1.35)) * 0.85;
	SPECULAR_LIGHT += lc * (mix(vec3(1.0), ALBEDO, 0.5) * spec_r + ALBEDO * spec_trt * 1.65)
		* specular * shade * (0.25 + 0.75 * v_h) * (1.0 - 0.75 * far);

	// TT: light passing through the fringe when the light is behind the coat.
	float through = pow(clamp(dot(VIEW, -LIGHT + n * 0.35), 0.0, 1.0), 3.2);
	SPECULAR_LIGHT += lc * ALBEDO * through * 0.25 * (0.35 + 0.65 * v_h);
}
