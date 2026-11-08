class_name DateBowl
extends Node3D
## An old earthen bowl of dates beside Al-Khasm, and the stones he spits out of them.
##
## The bowl is wheel-thrown desert clay, unglazed and open-fired: wide and shallow, an open
## bowl a hand can reach anywhere in, on a low foot, with flaring walls
## and a rounded lip, never quite round or level, with throwing rings inside, grit in the
## body, smoky fire-clouds, a chipped rim, a hairline crack, a dark old stain where dates
## have always sat, and the table's sand blown into it and onto it.
##
## The dates are counted: there are only so many, and each one eaten is gone. Each is a
## different fruit: its own size and shape, its own shade from amber to near-black
## mahogany, its own wrinkles (the skin loose and folded over the flesh), a pale scar or a
## scrap of papery cap where it hung on the stalk, and a little dusty bloom. They are
## heaped in the bowl as real ones fall, each resting on the bowl or on the ones below.
##
## Everything is modelled in centimetres (the meshes hang under nodes scaled by CM); the
## node itself is unscaled, so the physics lives in world units.
##
## It is all solid. The dates are rigid bodies (a chain of balls along each one) lying in
## the bowl's own shape as a collision mesh: they rest on the clay and on each other, and
## when one is pushed or taken the rest shift and slump into the gap. The hand reaching in
## is solid to them too (see attach_hand: every finger bone and the palm follow the
## skeleton as kinematic bodies), and the clay is solid to the hand: hand_clear() measures
## how far the hand, the wrist and the hanging sleeve are from the clay, so a reach can be
## chosen that fits, and hand_push() keeps it out of the clay whatever it does.

const CM := 0.21
# The bowl's section (radius, height in cm) from the middle of its underside, out across
# the foot, up the outside, over the lip and down the inside to the middle of its floor.
const PROFILE := [Vector2(0.0, 0.25), Vector2(1.5, 0.24), Vector2(2.8, 0.18), Vector2(3.3, 0.06), Vector2(3.55, 0.0),
	Vector2(3.8, 0.05), Vector2(4.2, 0.25), Vector2(5.0, 0.7), Vector2(5.8, 1.35), Vector2(6.4, 2.1),
	Vector2(6.8, 2.85), Vector2(7.05, 3.45), Vector2(7.1, 3.62), Vector2(7.02, 3.82), Vector2(6.82, 3.86),
	Vector2(6.63, 3.72), Vector2(6.5, 3.35), Vector2(6.15, 2.6), Vector2(5.6, 1.85), Vector2(4.8, 1.2),
	Vector2(3.8, 0.82), Vector2(2.6, 0.66), Vector2(1.3, 0.6), Vector2(0.0, 0.58)]
const RIM_K := 13                 # index of the top of the lip in PROFILE
const INNER_R := 6.6             # inside radius at the lip
const CHIPS := [Vector2(2.1, 0.32), Vector2(4.6, 0.2)]   # (angle, depth cm) of the chips in the rim
const TILT := Vector3(0.025, 0.0, -0.018)                # it sits a little askew in the sand

var count := 14
var rng := RandomNumberGenerator.new()
var dates: Array = []             # [{node (RigidBody3D), c, b (where it was laid, bowl cm), sph: [[z, r]...] (cm)}]
var model: Node3D                 # the meshes, in cm
var hand_bodies: Array = []       # [[body, digit, segment]] (segment -1: the palm)
var hand_on: UrHand = null        # whose hand they follow
var spare_date: Node3D = null     # the date between his fingers (they close on it by pose)
var hand_solid_on := false
const LAYER := 16                 # the bowl, the dates and the hand reaching in
const MAX_SPEED := 2.5             # (world units / s) the fastest a nudged date ever goes
const FLUNG := 6.0                 # faster than this out of one step: the solver, not the hand
const DATE_GRAVITY := 2.6         # a date falls at true gravity (the game's is gentler, for the dice)
var date_shader: Shader
var bowl_mat: ShaderMaterial
var pits_out := 0

const CLAY_SHADER := """
shader_type spatial;
render_mode cull_back;
// Unglazed earthen clay, open-fired. Object space (cm). COLOR: r = inside of the bowl,
// g = height up the bowl (0..1), b = the lip, a = fresh clay in a chip.
uniform float seed = 0.0;
uniform vec4 chips[2];              // xy: direction of each chip round the bowl, z: its depth
varying vec3 lp;
varying vec3 ln;
varying vec4 vc;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 x) {
	return vnoise(x) * 0.55 + vnoise(x * 2.1 + 3.1) * 0.3 + vnoise(x * 4.3 + 7.7) * 0.15;
}
float line(float v, float w) { return 1.0 - smoothstep(0.0, w, abs(v - 0.5)); }

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vc = COLOR;
}

// grit in the clay: little lumps of sand and lime temper, and pits where bits burnt out
float grit(vec3 x) {
	return smoothstep(0.8, 0.88, vnoise(x * 11.0 + seed)) - 0.4 * smoothstep(0.85, 0.91, vnoise(x * 7.0 + seed + 31.0));
}

// relief (cm): the potter's throwing rings, finger-ridged inside and smoothed outside,
// the spiral on the floor, lumps of the hand-kneaded clay, grit, and the chipped lip
float relief(vec3 x, float inner) {
	float r = length(x.xz);
	float a = atan(x.z, x.x);
	float wob = 0.7 * vnoise(vec3(a * 2.0, x.y * 0.4, 1.0) + seed);
	float rings = sin(x.y * 12.5 + wob * 3.0 + a * 0.15);
	float wall = smoothstep(0.9, 1.8, x.y);
	float h = rings * mix(0.004, 0.012, inner) * wall;
	// the floor's spiral, where the potter's fingers drew the clay up from the middle
	float floor_k = inner * (1.0 - smoothstep(1.0, 1.8, x.y));
	h += floor_k * 0.012 * sin(r * 9.0 - a + wob * 2.0);
	h += 0.03 * (fbm(x * 0.9 + seed) - 0.5);
	h += 0.012 * grit(x);
	return h;
}

void fragment() {
	vec3 x = lp;
	float inner = vc.r;
	float up = vc.g;
	float lip = vc.b;
	float chip = vc.a;
	float r = length(x.xz);
	float a = atan(x.z, x.x);

	// the clay: buff to warm red-brown, unevenly fired; a red slip wiped over the inside
	float n1 = fbm(x * 0.35 + seed);
	float n2 = fbm(x * 1.6 + seed + 5.0);
	vec3 buff = vec3(0.37, 0.2, 0.09);
	vec3 red = vec3(0.28, 0.115, 0.05);
	vec3 col = mix(buff, red, smoothstep(0.3, 0.75, n1)) * (0.85 + 0.3 * n2);
	float slip = inner * smoothstep(0.35, 0.6, fbm(x * 0.5 + seed + 11.0) + 0.25);
	col = mix(col, vec3(0.27, 0.13, 0.07) * (0.85 + 0.3 * n2), slip * 0.6);
	// smoke clouds from the open fire: soft dark blotches, mostly low on the outside
	float cloud = smoothstep(0.42, 0.66, fbm(x * vec3(0.32, 0.5, 0.32) + seed + 17.0));
	cloud *= mix(1.0 - 0.6 * up, 0.45, inner);
	col = mix(col, vec3(0.055, 0.045, 0.04), cloud * 0.8);
	// temper: pale lime specks and dark grains, and the pits where bits burnt out
	float lime = smoothstep(0.86, 0.92, vnoise(x * 16.0 + seed + 3.0));
	float dark = smoothstep(0.85, 0.91, vnoise(x * 15.0 + seed + 9.0));
	float pit = smoothstep(0.85, 0.91, vnoise(x * 7.0 + seed + 31.0));
	col = mix(col, vec3(0.5, 0.44, 0.36), lime * 0.3);
	col = mix(col, vec3(0.1, 0.07, 0.05), dark * 0.3 + pit * 0.25);
	// years of use: the inside is rubbed smoother and paler on the walls where hands reach
	// in, and the floor dark and a little tacky with old date syrup
	float rub = inner * smoothstep(1.3, 2.7, x.y) * smoothstep(0.4, 0.7, fbm(x * vec3(1.2, 0.3, 1.2) + seed));
	col = mix(col, col * 1.18 + vec3(0.02, 0.012, 0.006), rub * 0.5);
	float syrup = inner * (1.0 - smoothstep(1.0, 2.4, x.y + 0.8 * (fbm(x * 0.8 + seed + 23.0) - 0.5)));
	col = mix(col, vec3(0.1, 0.045, 0.02), syrup * 0.5);
	// a hairline crack running down from the rim
	float ca = 5.3;
	float da = mod(a - ca + 3.14159, 6.28318) - 3.14159;
	float cw = da * r + 0.25 * sin(x.y * 1.7) + 0.15 * (vnoise(vec3(x.y * 3.0, seed, 2.0)) - 0.5);
	float crack = (1.0 - smoothstep(0.012, 0.035, abs(cw))) * smoothstep(1.8, 3.3, x.y);
	col = mix(col, vec3(0.03, 0.02, 0.015), crack * 0.85);
	// the lip: knocked and worn paler on its top; chips show the fresh, pinker clay inside
	col = mix(col, col * 1.15 + vec3(0.025, 0.015, 0.01), lip * 0.4 * smoothstep(0.4, 0.8, n2));
	vec3 fresh = vec3(0.52, 0.27, 0.15) * (0.9 + 0.2 * vnoise(x * 6.0));
	col = mix(col, fresh, smoothstep(0.15, 0.6, chip));
	// sand blown onto it: settled on the lip, inside on the floor, and drifted round the foot
	float grains = smoothstep(0.55, 0.85, vnoise(x * 14.0 + seed + 41.0));
	float sand = lip * 0.35 + inner * (1.0 - smoothstep(0.8, 1.8, x.y)) * 0.55 + (1.0 - inner) * (1.0 - smoothstep(0.2, 1.4, x.y)) * 0.8;
	sand *= smoothstep(0.3, 0.7, fbm(x * 0.9 + seed + 51.0)) * (0.4 + 0.6 * grains);
	col = mix(col, vec3(0.6, 0.4, 0.24), clamp(sand, 0.0, 1.0) * 0.55);

	ALBEDO = col;
	float rough = 0.88 - 0.22 * rub - 0.3 * syrup * inner - 0.08 * slip + 0.06 * sand;
	ROUGHNESS = clamp(rough, 0.35, 1.0);
	SPECULAR = 0.35;
	// the inside of a deep bowl sees little sky
	AO = mix(1.0, 0.82 + 0.18 * smoothstep(0.6, 3.0, x.y), inner);
	AO_LIGHT_AFFECT = 0.1;

	float e = 0.01;
	float h0 = relief(x, inner);
	vec3 g = vec3(relief(x + vec3(e, 0, 0), inner) - h0, relief(x + vec3(0, e, 0), inner) - h0, relief(x + vec3(0, 0, e), inner) - h0) / e;
	vec3 nn = normalize(ln);
	nn = normalize(nn - (g - dot(g, nn) * nn) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nn, 0.0)).xyz);
}
"""

const DATE_SHADER := """
shader_type spatial;
render_mode cull_back;
// A dried date (kind 0) or its stone (kind 1). Object space, in cm; the long axis is z,
// the stalk end at -z. The date's skin is loose over the flesh and folds into a network of
// creases with puffy, glossy, sticky skin between them; the folds are real geometry,
// pushed out in the vertex shader, so they catch the low sun and shade one another. Finer
// creases and the skin's grain are bump-mapped on top.
uniform int kind = 0;
uniform float seed = 0.0;
uniform vec3 tint = vec3(0.13, 0.045, 0.016);   // the date's own colour (linear)
uniform float wrinkly = 1.0;
uniform float half_len = 2.3;                   // half its length (cm)
uniform float cap = 0.0;                        // 1: a scrap of the papery cap still on it
uniform float bloom = 0.3;                      // dusty bloom on the skin
varying vec3 rp;
varying float crease_v;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
// distance to the nearest cell edge of a 3D Voronoi pattern
float cell_edge(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	float f1 = 8.0, f2 = 8.0;
	for (int k = 0; k < 27; k++) {
		vec3 o = vec3(float(k % 3), float((k / 3) % 3), float(k / 9)) - 1.0;
		vec3 c = i + o;
		vec3 r = o + vec3(hash(c), hash(c + 17.31), hash(c + 41.7)) - f;
		float d = dot(r, r);
		if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
	}
	return sqrt(f2) - sqrt(f1);
}

// The folds of the skin (cm, + out). A dried date's skin has come loose from the shrunken
// flesh and lies over it in folds: soft, rounded ridges of puffed skin with narrow creases
// between them, mostly running round the fruit and wandering, forking and crossing, a
// few running lengthwise; plus the soft dents of a date that lay under others. `w` widens
// the creases (the mesh can only carry the broad ones; the fine ones are bump-mapped).
float folds(vec3 p, float w, out float cr) {
	float ends = smoothstep(half_len, half_len - 0.6, abs(p.z));   // pulled smooth over the ends
	vec3 wp = p + 0.95 * (vec3(vnoise(p * 0.7 + seed), vnoise(p * 0.7 + seed + 7.0), vnoise(p * 0.7 + seed + 13.0)) - 0.5)
		+ 0.3 * (vec3(vnoise(p * 1.9 + seed + 2.0), vnoise(p * 1.9 + seed + 4.0), vnoise(p * 1.9 + seed + 6.0)) - 0.5);
	float l1 = abs(vnoise(wp * vec3(1.15, 1.15, 1.5) + seed * 3.0) - 0.5);        // mostly round the fruit
	float l2 = abs(vnoise(wp * vec3(2.0, 2.0, 2.3) + seed * 5.0 + 9.0) - 0.5);    // smaller ones every which way
	float l3 = abs(vnoise(wp * vec3(1.7, 1.7, 0.5) + seed * 2.0 + 21.0) - 0.5);   // along it
	float c1 = exp(-l1 * l1 / (w * w));
	float c2 = exp(-l2 * l2 / (w * w * 0.7)) * smoothstep(0.3, 0.6, vnoise(p * 0.9 + seed * 4.0));
	float c3 = exp(-l3 * l3 / (w * w * 0.8)) * smoothstep(0.45, 0.7, vnoise(p * 0.6 + seed * 6.0));
	cr = clamp(max(c1, max(0.8 * c2, 0.7 * c3)) * (0.3 + 0.7 * ends), 0.0, 1.0);
	// the puffs between: highest midway between creases
	float puff = smoothstep(0.0, 0.22, min(l1, l2 + 0.08));
	float lump = vnoise(p * 0.5 + seed * 11.0) - 0.5;
	return wrinkly * (-0.11 * c1 - 0.07 * c2 - 0.06 * c3 + 0.04 * puff) * (0.25 + 0.75 * ends) + 0.06 * lump;
}

// the stone: a deep groove down one side, fine lengthwise fibres, a little pore on the back
float pit_relief(vec3 p) {
	float fib = vnoise(vec3(atan(p.y, p.x) * 14.0, p.z * 1.2, seed));
	return 0.012 * fib + 0.004 * vnoise(p * 9.0 + seed);
}

void vertex() {
	rp = VERTEX;
	crease_v = 0.0;
	if (kind == 0) {
		vec3 N = normalize(NORMAL);
		vec3 a = abs(N.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 T = normalize(cross(N, a));
		vec3 B = cross(N, T);
		float e = 0.04;
		float cr;
		float h0 = folds(VERTEX, 0.075, cr);
		float c2;
		float ht = folds(VERTEX + T * e, 0.075, c2);
		float hb = folds(VERTEX + B * e, 0.075, c2);
		VERTEX += N * h0;
		NORMAL = normalize(N - ((ht - h0) / e) * T - ((hb - h0) / e) * B);
		crease_v = cr;
	}
}

void fragment() {
	vec3 p = rp;
	vec3 col;
	float rough;
	float h;
	float sss = 0.0;
	vec3 back = vec3(0.0);
	if (kind == 0) {
		// the creases at full sharpness, for their colour and fine relief
		float cr;
		float big = folds(p, 0.05, cr);
		float crw;
		folds(p, 0.075, crw);
		float sharp = clamp(cr - 0.6 * crw, 0.0, 1.0);    // the part the mesh could not carry
		// the skin's own fine crinkle and grain
		vec3 fq = p * vec3(3.4, 3.4, 6.5) + 0.35 * vec3(vnoise(p * 2.6 + seed), vnoise(p * 2.6 + seed + 3.0), vnoise(p * 2.6 + seed + 5.0));
		float lf = abs(vnoise(fq + seed * 13.0) - 0.5);
		float fine = exp(-lf * lf / 0.0012) * smoothstep(0.35, 0.65, vnoise(p * 1.8 + seed * 9.0)) * (1.0 - cr);
		float grain = vnoise(p * 24.0 + seed);
		// the colour: deep and red-black down in the creases, the puffs a shade more amber
		// where the low sun comes through their thin skin; uneven along the fruit
		float shade = vnoise(p * 0.45 + seed * 2.0);
		vec3 c = tint * (0.8 + 0.4 * shade);
		float puff = smoothstep(0.0, 0.05, big);
		c = mix(c, c * vec3(1.2, 1.08, 0.95), puff * 0.45);
		c = mix(c, c * vec3(0.42, 0.3, 0.26), cr * 0.7);
		c *= 1.0 - 0.2 * fine;
		// the dusty bloom on the skin, lightest on the puffs
		float bl = bloom * smoothstep(0.45, 0.8, vnoise(p * 1.3 + seed * 17.0)) * (1.0 - cr);
		c = mix(c, c * vec3(1.35, 1.3, 1.2) + vec3(0.012, 0.006, 0.002), bl * 0.35);
		// sugar has come out on the odd one in pale specks
		float sugar = smoothstep(0.9, 0.95, vnoise(p * 6.0 + seed * 19.0)) * step(0.75, fract(seed * 7.31)) * (1.0 - cr);
		c = mix(c, vec3(0.32, 0.22, 0.13), sugar * 0.35);
		// where it hung on the stalk: a pale, rough, round scar with a dark heart, or a scrap
		// of the dry papery cap
		float d = length(p.xy);
		float stalk = smoothstep(-half_len + 0.7, -half_len + 0.15, p.z);
		float scar = stalk * (1.0 - smoothstep(0.18, 0.3 + 0.06 * sin(atan(p.y, p.x) * 5.0 + seed), d));
		c = mix(c, vec3(0.22, 0.12, 0.055) * (0.8 + 0.4 * grain), scar * 0.7);
		c = mix(c, c * 0.6, stalk * (1.0 - smoothstep(0.04, 0.09, d)) * 0.7);
		float ang = atan(p.y, p.x);
		float lobes = 0.55 + 0.12 * sin(ang * 3.0 + seed * 5.0);
		float calyx = cap * stalk * (1.0 - smoothstep(lobes - 0.05, lobes + 0.03, d));
		c = mix(c, vec3(0.36, 0.22, 0.1) * (0.75 + 0.5 * vnoise(vec3(ang * 8.0, d * 10.0, seed))), calyx * 0.9);
		col = c;
		// satin, a little sticky on the puffs, dull in the creases, the bloom and the scar
		rough = 0.42 + 0.3 * cr + 0.1 * fine + 0.25 * bl + 0.4 * max(scar, calyx) + 0.08 * grain;
		sss = 0.2;
		back = vec3(0.2, 0.05, 0.012);
		h = -0.03 * sharp - 0.015 * fine + 0.003 * grain + 0.01 * calyx;
	} else {
		// the stone: grey-buff, fibrous, still a little wet, with flesh clinging in places
		float fib = vnoise(vec3(atan(p.y, p.x) * 14.0, p.z * 1.2, seed));
		vec3 c = mix(vec3(0.16, 0.1, 0.055), vec3(0.26, 0.17, 0.1), vnoise(p * 2.5 + seed));
		c *= 0.85 + 0.25 * fib;
		float groove = 1.0 - smoothstep(0.05, 0.2, abs(atan(p.x, p.y)) * length(p.xy));
		c = mix(c, c * 0.5, groove * smoothstep(0.1, 0.25, length(p.xy)) * 0.0);
		float flesh = smoothstep(0.72, 0.85, vnoise(p * 3.0 + seed * 3.0));
		c = mix(c, vec3(0.1, 0.04, 0.015), flesh * 0.5);
		// fine ridges along it
		c *= 0.88 + 0.12 * vnoise(vec3(atan(p.y, p.x) * 22.0, p.z * 2.0, seed));
		float pore = 1.0 - smoothstep(0.04, 0.08, length(vec2(p.x, p.z - 0.1)) ) ;
		pore *= step(p.y, 0.0);
		c = mix(c, vec3(0.08, 0.05, 0.03), pore * 0.8);
		col = c;
		rough = 0.62 - 0.15 * flesh;
		h = pit_relief(p);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.15, 1.0);
	SPECULAR = 0.42;
	if (kind == 0) {
		SSS_STRENGTH = sss;
		BACKLIGHT = back;
	}
	// fine relief, bump-mapped from how it changes across the pixel
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	float hs = h * length(MODEL_MATRIX[0].xyz);    // cm to world
	vec3 grad = sign(det) * (dFdx(hs) * r1 + dFdy(hs) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
"""


func _init(n := 14, sd := 20251107) -> void:
	count = n
	rng.seed = sd


func _ready() -> void:
	rotation = TILT
	model = Node3D.new()
	model.scale = Vector3(CM, CM, CM)
	add_child(model)
	date_shader = Shader.new()
	date_shader.code = DATE_SHADER
	build_bowl()
	build_dates()


# ---------------------------------------------------------------- the bowl

## A smooth curve through PROFILE (Catmull-Rom), sampled evenly along its length.
## Returns [points, which point is the top of the lip].
func _profile(samples: int) -> Array:
	var fine := PackedVector2Array()
	var marks := PackedInt32Array()
	var P := PROFILE
	for k in P.size() - 1:
		var p0: Vector2 = P[maxi(k - 1, 0)]
		var p1: Vector2 = P[k]
		var p2: Vector2 = P[k + 1]
		var p3: Vector2 = P[mini(k + 2, P.size() - 1)]
		marks.append(fine.size())
		for s in 12:
			var t := s / 12.0
			fine.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	fine.append(P[P.size() - 1])
	var acc := PackedFloat32Array([0.0])
	for i in range(1, fine.size()):
		acc.append(acc[i - 1] + fine[i].distance_to(fine[i - 1]))
	var total: float = acc[acc.size() - 1]
	var rim_s: float = acc[marks[RIM_K]]
	var out := PackedVector2Array()
	var rim_i := 0
	var j := 0
	for i in samples:
		var s := total * i / (samples - 1)
		while j < acc.size() - 2 and acc[j + 1] < s:
			j += 1
		var f := clampf((s - acc[j]) / maxf(acc[j + 1] - acc[j], 1e-6), 0.0, 1.0)
		out.append(fine[j].lerp(fine[j + 1], f))
		if s <= rim_s:
			rim_i = i
	return [out, rim_i]


## Where a point of the section lands round the bowl at angle a: out of round, the lip
## wavy and not quite level, and chipped.
func _bowl_point(v: Vector2, a: float, inner: bool) -> Array:
	var r := v.x * (1.0 + 0.013 * sin(2.0 * a + 0.7) + 0.008 * sin(3.0 * a + 2.1) + 0.004 * sin(5.0 * a + 4.0))
	var y := v.y
	var hi := smoothstep(0.8, 3.8, y)
	y += hi * (0.11 * sin(2.0 * a + 1.3) + 0.05 * sin(3.0 * a + 0.4) + 0.025 * sin(7.0 * a + 2.0))
	var chip := 0.0
	for c in CHIPS:
		var da := absf(wrapf(a - c.x, -PI, PI)) * v.x
		# a chip is a shallow scallop, deepest off-centre, its edge broken unevenly
		var jag := 0.12 * sin(a * 37.0 + c.x * 5.0) + 0.08 * sin(a * 71.0)
		var k := (1.0 - smoothstep(0.15, 0.7 + jag, da)) * smoothstep(2.9, 3.7, v.y)
		k *= 0.75 + 0.25 * sin((a - c.x) * 9.0 + 1.0)
		chip = maxf(chip, k)
		y -= c.y * k
		# the break goes into the wall too: the lip loses its rounded edge
		r -= (0.12 if not inner else -0.08) * k
	return [Vector3(cos(a) * r, y, sin(a) * r), chip]


func build_bowl() -> void:
	var prof: Array = _profile(140)
	var pts: PackedVector2Array = prof[0]
	var rim_i: int = prof[1]
	var rows := pts.size()
	var cols := 128
	var p := PackedVector3Array()
	var c := PackedColorArray()
	for i in rows:
		var v: Vector2 = pts[i]
		var inner := i > rim_i
		var lip := exp(-pow(float(i - rim_i) / 6.0, 2.0))
		for j in cols:
			var a := TAU * j / cols
			var bp: Array = _bowl_point(v, a, inner)
			p.append(bp[0])
			c.append(Color(1.0 if inner else 0.0, clampf(v.y / 3.9, 0.0, 1.0), lip, bp[1]))
	# normals by central differences across the surface; at the two middles (where every
	# point of the row is the same one) straight down under the foot and up off the floor
	var n := PackedVector3Array()
	n.resize(p.size())
	for i in rows:
		for j in cols:
			var k := i * cols + j
			if pts[i].x < 0.05:
				n[k] = Vector3.DOWN if i == 0 else Vector3.UP
				continue
			var du := p[mini(i + 1, rows - 1) * cols + j] - p[maxi(i - 1, 0) * cols + j]
			var dv := p[i * cols + (j + 1) % cols] - p[i * cols + (j - 1 + cols) % cols]
			var nv := dv.cross(du).normalized()
			# outward on the outside (and down under the foot), into the bowl on the inside
			var t2 := (pts[mini(i + 1, rows - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var n2 := Vector2(t2.y, -t2.x)
			var want := Vector3(cos(TAU * j / cols) * n2.x, n2.y, sin(TAU * j / cols) * n2.x)
			if nv.dot(want) < 0.0:
				nv = -nv
			n[k] = nv
	var idx := PackedInt32Array()
	for i in rows - 1:
		for j in cols:
			var a0 := i * cols + j
			var b0 := i * cols + (j + 1) % cols
			var d0 := (i + 1) * cols + j
			var e0 := (i + 1) * cols + (j + 1) % cols
			for t in [[a0, b0, d0], [b0, e0, d0]]:
				var x: int = t[0]
				var y: int = t[1]
				var z: int = t[2]
				var face := (p[y] - p[x]).cross(p[z] - p[x])
				if face.length_squared() < 1e-12:
					continue
				if face.dot(n[x] + n[y] + n[z]) > 0.0:
					idx.append_array([x, z, y])
				else:
					idx.append_array([x, y, z])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = p
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	bowl_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CLAY_SHADER
	bowl_mat.shader = sh
	bowl_mat.set_shader_parameter("seed", 3.3)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = bowl_mat
	model.add_child(mi)
	# the clay as a solid, in world units, for the dates to lie against: the inside of the
	# bowl (and the top of the lip) in thick wedges, one for each patch of the surface, so
	# that nothing pressed against it can slip through (a surface alone has no thickness)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.0
	body.physics_material_override = pm
	var P := PROFILE
	var sectors := 32
	for k in range(RIM_K - 1, P.size() - 1):
		var a: Vector2 = P[k]
		var bb: Vector2 = P[k + 1]
		var t := (bb - a).normalized()
		var out := Vector2(-t.y, t.x)            # away from the open side, into the clay
		if k < RIM_K:
			out = Vector2(0.0, -1.0)              # (the top of the lip: down into it)
		var thick := 1.2
		for j in sectors:
			var wedge := PackedVector3Array()
			for th in [TAU * j / sectors, TAU * (j + 1) / sectors]:
				for v in [a, bb]:
					for o in [0.0, thick]:
						var q: Vector2 = v + out * o
						wedge.append(Vector3(cos(th) * q.x, q.y, sin(th) * q.x) * CM)
			var cs := CollisionShape3D.new()
			var hull := ConvexPolygonShape3D.new()
			hull.points = wedge
			cs.shape = hull
			body.add_child(cs)
	add_child(body)


## Height of the inside of the bowl at radius r (cm), from the section.
func inner_floor(r: float) -> float:
	var P := PROFILE
	for k in range(RIM_K + 2, P.size() - 1):
		var a: Vector2 = P[k]
		var b: Vector2 = P[k + 1]
		if r <= a.x and r >= b.x:
			return lerpf(a.y, b.y, (a.x - r) / maxf(a.x - b.x, 1e-6))
	return P[P.size() - 1].y


## Signed clearance of a ball (centre q, radius rad) from the inside of the bowl: < 0 if
## it would push into the clay.
func _bowl_clear(q: Vector3, rad: float) -> float:
	var r := Vector2(q.x, q.z).length()
	var best := 1e6
	var P := PROFILE
	for k in range(RIM_K + 1, P.size() - 1):
		var a: Vector2 = P[k]
		var b: Vector2 = P[k + 1]
		var ab := b - a
		var t := clampf((Vector2(r, q.y) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, (Vector2(r, q.y) - (a + ab * t)).length())
	var inside := q.y >= inner_floor(r) and r < INNER_R
	return (best if inside else -best) - rad


# ---------------------------------------------------------------- the dates

## The date's surface before its skin is folded (cm): a blunt ellipsoid along z, flatter on
## one side, thicker at one end and a little bent. u along (0 = stalk end), v round.
func _date_point(u: float, v: float, d: Dictionary) -> Vector3:
	var s := 2.0 * u - 1.0
	var k: float = d.k0 if s < 0.0 else d.k1
	var r: float = pow(maxf(1.0 - pow(absf(s), k), 0.0), 1.0 / k) * d.R * (1.0 + d.taper * s)
	var x := cos(v) * r
	var y: float = sin(v) * r * (float(d.flat) if sin(v) < 0.0 else 1.0)
	y += d.bend * (1.0 - s * s) * d.R
	return Vector3(x, y, s * d.L * 0.5)


func _date_mesh(d: Dictionary) -> ArrayMesh:
	var nu := 70
	var nv := 60
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	for i in nu + 1:
		# packed closer toward the ends, where the surface turns fastest
		var u := 0.5 - 0.5 * cos(PI * i / nu)
		for j in nv:
			var v := TAU * j / nv
			p.append(_date_point(u, v, d))
			var e := 0.002
			var du := _date_point(minf(u + e, 1.0), v, d) - _date_point(maxf(u - e, 0.0), v, d)
			var dv := _date_point(u, v + 0.01, d) - _date_point(u, v - 0.01, d)
			var nn := dv.cross(du)          # outward
			if i == 0:
				nn = Vector3(0, 0, -1)
			elif i == nu:
				nn = Vector3(0, 0, 1)
			n.append(nn.normalized())
	# at the poles the rows close up on one point: point those normals straight out
	var idx := PackedInt32Array()
	for i in nu:
		for j in nv:
			var a0 := i * nv + j
			var b0 := i * nv + (j + 1) % nv
			var d0 := (i + 1) * nv + j
			var e0 := (i + 1) * nv + (j + 1) % nv
			for t in [[a0, b0, d0], [b0, e0, d0]]:
				var x: int = t[0]
				var y: int = t[1]
				var z: int = t[2]
				var face := (p[y] - p[x]).cross(p[z] - p[x])
				if face.length_squared() < 1e-14:
					continue
				if face.dot(n[x] + n[y] + n[z]) > 0.0:
					idx.append_array([x, z, y])
				else:
					idx.append_array([x, y, z])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = p
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A new, different date: [mesh instance, its shape].
func _make_date(i: int) -> Array:
	var d := {
		"L": rng.randf_range(3.9, 4.8), "R": rng.randf_range(0.92, 1.08),
		"k0": rng.randf_range(2.1, 2.6), "k1": rng.randf_range(1.8, 2.3),
		"taper": rng.randf_range(-0.08, 0.1), "flat": rng.randf_range(0.72, 0.92),
		"bend": rng.randf_range(-0.12, 0.12),
	}
	var mi := MeshInstance3D.new()
	mi.mesh = _date_mesh(d)
	var m := ShaderMaterial.new()
	m.shader = date_shader
	# from deep amber through red-brown to almost black mahogany
	var shade := clampf(rng.randfn(0.55, 0.3), 0.0, 1.0)
	var tint := Vector3(0.15, 0.042, 0.012).lerp(Vector3(0.095, 0.03, 0.011), smoothstep(0.0, 0.5, shade)) \
		.lerp(Vector3(0.035, 0.012, 0.007), smoothstep(0.5, 1.0, shade))
	tint *= rng.randf_range(0.9, 1.1)
	tint.x *= rng.randf_range(0.93, 1.07)
	m.set_shader_parameter("kind", 0)
	m.set_shader_parameter("seed", float(i) * 1.37 + rng.randf() * 10.0)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("wrinkly", rng.randf_range(0.6, 1.35))
	m.set_shader_parameter("half_len", d.L * 0.5)
	m.set_shader_parameter("cap", 1.0 if rng.randf() < 0.3 else 0.0)
	m.set_shader_parameter("bloom", rng.randf_range(0.25, 0.85))
	mi.material_override = m
	mi.extra_cull_margin = 0.5
	# balls along its length, for heaping them up
	var sph: Array = []
	for k in 5:
		var s := lerpf(-0.78, 0.78, k / 4.0)
		var kk: float = d.k0 if s < 0.0 else d.k1
		var r: float = pow(maxf(1.0 - pow(absf(s), kk), 0.0), 1.0 / kk) * d.R * (1.0 + d.taper * s) * 0.92
		sph.append([s * d.L * 0.5, r])
	return [mi, sph]


## Fill the bowl: each date is dropped in turn and comes to rest as low as it can, on the
## clay or on the dates already there, lying however it happened to fall.
func build_dates() -> void:
	for i in count:
		var md: Array = _make_date(i)
		var mi: MeshInstance3D = md[0]
		var sph: Array = md[1]
		var best := {}
		for tries in 48:
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * 4.6
			var xz := Vector2(cos(a), sin(a)) * rr
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)) \
				* Basis(Vector3.BACK, rng.randf() * TAU)
			var lo := 0.3
			var hi := 12.0
			if not _fits(Vector3(xz.x, hi, xz.y), b, sph):
				continue
			for it in 16:
				var mid := (lo + hi) * 0.5
				if _fits(Vector3(xz.x, mid, xz.y), b, sph):
					hi = mid
				else:
					lo = mid
			# toward the middle and low: a heap, not a ring round the wall
			var score := hi + 0.05 * rr
			if best.is_empty() or score < float(best.score):
				best = {"score": score, "c": Vector3(xz.x, hi, xz.y), "b": b}
		if best.is_empty():
			mi.queue_free()
			continue
		dates.append({"node": _date_body(mi, sph, best.b, best.c), "c": best.c, "b": best.b, "sph": sph})


## A date as a rigid body: soft, sticky fruit, so it does not bounce or roll far.
func _date_body(mi: MeshInstance3D, sph: Array, b: Basis, c: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.transform = Transform3D(b, c * CM)
	rb.mass = 0.02
	rb.gravity_scale = DATE_GRAVITY
	rb.linear_damp = 1.5
	rb.angular_damp = 4.0
	rb.continuous_cd = true
	rb.collision_layer = LAYER
	rb.collision_mask = LAYER | 1
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.0
	pm.rough = true
	rb.physics_material_override = pm
	for sp in sph:
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = float(sp[1]) * CM
		cs.shape = ss
		cs.position = Vector3(0, 0, float(sp[0]) * CM)
		rb.add_child(cs)
	mi.scale = Vector3(CM, CM, CM)
	rb.add_child(mi)
	add_child(rb)
	return rb


func _balls(c: Vector3, b: Basis, sph: Array) -> Array:
	var out: Array = []
	for s in sph:
		out.append([c + b.z * float(s[0]), float(s[1])])
	return out


func _fits(c: Vector3, b: Basis, sph: Array) -> bool:
	var mine := _balls(c, b, sph)
	for m in mine:
		if _bowl_clear(m[0], m[1]) < 0.0:
			return false
	for o in dates:
		if (o.c as Vector3).distance_to(c) > 7.0:
			continue
		for q in _balls(o.c, o.b, o.sph):
			for m in mine:
				if (m[0] as Vector3).distance_to(q[0]) < float(m[1]) + float(q[1]):
					return false
	return true


func remaining() -> int:
	return dates.size()


## Where a date lies now (bowl cm): [centre, basis].
func live(d: Dictionary) -> Array:
	var x: Transform3D = global_transform.affine_inverse() * (d.node as Node3D).global_transform
	return [x.origin / CM, x.basis.orthonormalized()]


## The dates he could take now, likeliest first: ones near the top that nothing else is
## lying on (so the heap never hangs in the air), on his side of the bowl (`reach` is the
## way his hand comes in, world), since his fingers reach on past the one they take.
func candidates(reach := Vector3.ZERO, n := 4) -> Array:
	var where: Array = []
	for d in dates:
		where.append(live(d))
	var scored: Array = []
	for i in dates.size():
		var di: Array = _balls(where[i][0], where[i][1], dates[i].sph)
		var free := true
		for j in dates.size():
			if j == i or float(where[j][0].y) <= float(where[i][0].y):
				continue
			for q in _balls(where[j][0], where[j][1], dates[j].sph):
				for m in di:
					if (m[0] as Vector3).distance_to(q[0]) < float(m[1]) + float(q[1]) + 0.25:
						free = false
		if not free:
			continue
		var c: Vector3 = where[i][0]
		var room := Vector2(c.x, c.z).dot(Vector2(reach.x, reach.z).normalized()) if reach != Vector3.ZERO else 0.0
		scored.append([c.y - 0.9 * room + rng.randf() * 0.6, dates[i].node])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array = []
	for k in mini(n, scored.size()):
		out.append(scored[k][1])
	if out.is_empty() and not dates.is_empty():
		out.append(dates[0].node)
	return out


## Half a date's width and half its length (cm), from its balls.
func date_half(node: Node3D) -> Vector2:
	for d in dates:
		if d.node == node:
			var w := 0.0
			for sp in d.sph:
				w = maxf(w, float(sp[1]))
			var last: Array = d.sph[d.sph.size() - 1]
			return Vector2(w, float(last[0]) + float(last[1]))
	return Vector2(1.0, 2.2)


## Out of the bowl's count: it is his now. It stops being pushed about (held fast by the
## fingers, or gone), and stops holding the others up: drawn up out of the heap it leaves
## a gap the ones that leant on it slump into (it does not shove them down as it goes).
func remove(node: Node3D) -> void:
	for i in dates.size():
		if dates[i].node == node:
			dates.remove_at(i)
			break
	var rb := node as RigidBody3D
	if rb:
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
	stir()


## (Tests) the likeliest date, taken.
func take_date(reach := Vector3.ZERO) -> Node3D:
	var c := candidates(reach, 1)
	if c.is_empty():
		return null
	remove(c[0])
	return c[0]


## Hold one date still where it lies (while fingers come down round it), or let it go.
func hold_still(node: Node3D, on: bool) -> void:
	var rb := node as RigidBody3D
	if rb:
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = on


## Wake every date: something has moved among them.
func stir() -> void:
	for d in dates:
		(d.node as RigidBody3D).sleeping = false


# ---------------------------------------------------------------- the clay against the hand

## The bowl as a solid for the hand (bowl cm, r and height): everything under the inside
## surface and within the outside wall, down into the sand. (The clay of the floor is only
## a few millimetres thick: a finger must not be able to slip through it and count as
## being clear of the bowl underneath.)
var _solid_poly := PackedVector2Array()
func _solid() -> PackedVector2Array:
	if _solid_poly.is_empty():
		var P := PROFILE
		for k in range(7, P.size()):           # up the outside from the foot, over the lip, down the inside
			_solid_poly.append(P[k])
		_solid_poly.append(Vector2(0.0, -6.0))  # down the middle into the ground
		_solid_poly.append(Vector2((P[7] as Vector2).x, -6.0))
	return _solid_poly


## Signed distance (world units) from a world point to the bowl: < 0 in it. The turned
## section (its small out-of-roundness and wavy, chipped lip are a millimetre or two).
func clay_sdf(w: Vector3) -> float:
	var q := global_transform.affine_inverse() * w / CM
	var pt := Vector2(Vector2(q.x, q.z).length(), q.y)
	var P := _solid()
	var best := 1e9
	var inside := false
	var n := P.size()
	for k in n:
		var a: Vector2 = P[k]
		var b: Vector2 = P[(k + 1) % n]
		if k != n - 3:                         # (the axis is not a surface)
			var ab := b - a
			var t := clampf((pt - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, pt.distance_to(a + ab * t))
		if (a.y > pt.y) != (b.y > pt.y) and pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
	return (-best if inside else best) * CM


## Signed distance (world units) from a world point to the inside surface of the bowl,
## > 0 on the bowl's open side (where the dates lie).
func cavity_sdf(w: Vector3) -> float:
	var q := global_transform.affine_inverse() * w / CM
	var pt := Vector2(Vector2(q.x, q.z).length(), q.y)
	var P := PROFILE
	var best := 1e9
	var bt := 0.0
	var ba := Vector2.ZERO
	var bb := Vector2.ZERO
	for k in range(RIM_K, P.size() - 1):
		var a: Vector2 = P[k]
		var b: Vector2 = P[k + 1]
		var ab := b - a
		var t := clampf((pt - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var dd := pt.distance_to(a + ab * t)
		if dd < best:
			best = dd
			ba = a
			bb = b
	# which side: the open side is to the left going down the inside (rim to middle)
	var side := (bb - ba).x * (pt - ba).y - (bb - ba).y * (pt - ba).x
	return (best if side <= 0.0 else -best) * CM


func _cavity_grad(w: Vector3) -> Vector3:
	var e := 0.02
	var g := Vector3(cavity_sdf(w + Vector3(e, 0, 0)) - cavity_sdf(w - Vector3(e, 0, 0)),
		cavity_sdf(w + Vector3(0, e, 0)) - cavity_sdf(w - Vector3(0, e, 0)),
		cavity_sdf(w + Vector3(0, 0, e)) - cavity_sdf(w - Vector3(0, 0, e)))
	return g.normalized() if g.length() > 1e-6 else Vector3.UP


## Whether a hand gripping at world point g is reaching into the bowl (from above, over
## the open side), not round its outside.
func reaching_in(g: Vector3) -> bool:
	var q := global_transform.affine_inverse() * g / CM
	return Vector2(q.x, q.z).length() < INNER_R and cavity_sdf(g) > -0.2 * CM


func _clay_grad(w: Vector3) -> Vector3:
	var e := 0.02
	var g := Vector3(clay_sdf(w + Vector3(e, 0, 0)) - clay_sdf(w - Vector3(e, 0, 0)),
		clay_sdf(w + Vector3(0, e, 0)) - clay_sdf(w - Vector3(0, e, 0)),
		clay_sdf(w + Vector3(0, 0, e)) - clay_sdf(w - Vector3(0, 0, e)))
	return g.normalized() if g.length() > 1e-6 else Vector3.UP


## The hand as balls (world: [point, radius]), if it were at T in its present pose: along
## every finger and the thumb, over the palm, and up the wrist into the hanging sleeve.
func hand_balls(T: Transform3D, h: UrHand, fingers_only := false) -> Array:
	var out: Array = []
	var cs := h.capsules()
	for dg in cs:
		for cap in cs[dg]:
			var a: Vector3 = cap[0]
			var b: Vector3 = cap[1]
			out.append([T * a.lerp(b, 0.5), (float(cap[2]) + float(cap[3])) * 0.5 * CM])
			out.append([T * b, float(cap[3]) * CM])
	if fingers_only:
		return out
	for x in [-2.9, 0.0, 2.9]:
		for z in [1.2, 5.0, 8.6]:
			out.append([T * Vector3(x, 0.0, z), 1.35 * CM])
	# the wrist, then the sleeve hanging loose round the forearm
	var fa := h.skel.get_bone_global_pose(h.bones["forearm"])
	var up := fa.basis.z.normalized()
	for t in [1.5, 4.5, 8.0, 12.0]:
		out.append([T * (fa.origin + up * t), (3.2 if t < 5.0 else 5.2) * CM])
	return out


## How clear of the clay the hand would be at T (world units; < 0: it would be in it).
func hand_clear(T: Transform3D, h: UrHand) -> float:
	if T.origin.distance_to(global_position) > 30.0 * CM + 2.0:
		return 1e9
	var m := 1e9
	for bl in hand_balls(T, h):
		m = minf(m, clay_sdf(bl[0]) - float(bl[1]))
	return m


## How far one finger (or the thumb) at T is into the clay, or pressing down into a date
## (world units, 0 if clear): a finger can nudge a date aside, but one coming down on it
## from above only presses it into what it lies on, so to the finger it is solid.
func _digit_pen(T: Transform3D, h: UrHand, dg: String, grounded: Array) -> float:
	var worst := 0.0
	for sg in 3:
		var cap: Array = h.capsule(h.bones["%s_%d" % [dg, sg]])
		var a: Vector3 = cap[0]
		var b: Vector3 = cap[1]
		for f in [0.5, 1.0]:
			var r := lerpf(float(cap[2]), float(cap[3]), f) * CM
			var p := T * a.lerp(b, f)
			worst = maxf(worst, r + 0.03 * CM - clay_sdf(p))
			for g in grounded:
				var pen := r + float(g[1]) - p.distance_to(g[0])
				if pen > 0.0 and _pinned(p, r, g):
					worst = maxf(worst, pen)
	return worst


## Whether a date ball g ([centre, radius], world) touched by a bit of hand at p (radius r)
## cannot get out of its way: the hand comes down on it, or the clay is right behind it.
func _pinned(p: Vector3, r: float, g: Array) -> bool:
	var c: Vector3 = g[0]
	if c.y < p.y - 0.3 * r:
		return true
	var away := (c - p).normalized()
	return clay_sdf(c + away * (float(g[1]) + 0.25 * CM)) < 0.1 * CM


## The balls (world: [centre, radius]) of the dates in the bowl (the one being taken left
## out), worked out once a frame.
var _grounded_frame := -1
var _grounded_cache: Array = []
func _grounded() -> Array:
	var f := Engine.get_process_frames() * 1000 + Engine.get_physics_frames()
	if f == _grounded_frame:
		return _grounded_cache
	_grounded_frame = f
	_grounded_cache = []
	for d in dates:
		if d.node == spare_date:
			continue
		var lw: Array = live(d)
		for b in _balls(lw[0], lw[1], d.sph):
			_grounded_cache.append([global_transform * ((b[0] as Vector3) * CM), float(b[1]) * CM])
	return _grounded_cache


## A finger that meets the clay gives way, as a real one does: it curls its tip in, or
## lifts at the knuckle, by as little as clears it (the most it can, if nothing does).
## Bends the hand's present pose (h.pose_cur): the pose it is heading for is untouched, so
## the finger straightens again as the hand comes away. Returns how much was bent.
func conform(T: Transform3D, h: UrHand) -> float:
	var total := 0.0
	var grounded := _grounded()
	for dg in UrHand.DIGITS:
		var pen := _digit_pen(T, h, dg, grounded)
		if pen <= 0.0:
			continue
		var ids: Array = []
		var base: Array = []
		for sg in 3:
			var i: int = h.bones["%s_%d" % [dg, sg]]
			ids.append(i)
			base.append(h.pose_cur[i])
		var lim: Array = UrHand.LIMITS["thumb" if dg == "thumb" else "finger"]
		var best := [pen, 0.0, 0]
		for k in range(1, 11):
			var amt := 7.0 * k
			for mode in 2:
				for sg in 3:
					var v: Vector2 = base[sg]
					if mode == 0:                     # curl the tip in
						v.x += amt * [0.25, 0.45, 0.6][sg]
					elif sg == 0:                     # lift at the knuckle
						v.x -= amt * 0.6
					var l: Array = lim[sg]
					v.x = clampf(v.x, l[0], l[1])
					h.put_bone(ids[sg], v)
				var p := _digit_pen(T, h, dg, grounded)
				if p < float(best[0]) - 1e-6:
					best = [p, amt, mode]
			if float(best[0]) <= 0.0:
				break
		for sg in 3:
			var v: Vector2 = base[sg]
			if int(best[2]) == 0:
				v.x += float(best[1]) * [0.25, 0.45, 0.6][sg]
			elif sg == 0:
				v.x -= float(best[1]) * 0.6
			var l: Array = lim[sg]
			v.x = clampf(v.x, l[0], l[1])
			# (the present pose only: put_bone would make it the target too)
			h.pose_cur[ids[sg]] = v
			h.skel.set_bone_pose_rotation(ids[sg], h.rest_rot[ids[sg]] * Quaternion(Vector3.RIGHT, deg_to_rad(v.x)) * Quaternion(Vector3.UP, deg_to_rad(v.y)))
		total += float(best[1])
	return total


## How clear of the clay (world units) the parts of the fingers that can bend out of its
## way are (the outer two joints), and the rest of the hand, which cannot (the first
## joint of each finger, the palm, the wrist, the sleeve), if it were at T as it is.
func hand_clear_parts(T: Transform3D, h: UrHand) -> Vector2:
	var hb := hand_balls(T, h)
	var out := Vector2(1e9, 1e9)
	for i in hb.size():
		var c := clay_sdf(hb[i][0]) - float(hb[i][1])
		if i < 30 and i % 6 >= 2:
			out.x = minf(out.x, c)
		else:
			out.y = minf(out.y, c)
	return out


## (UrHand.solid) The clay is solid: however the hand is put, its fingers give way where
## they meet it, and whatever still would be in it (the palm, the wrist, the sleeve, a
## finger that cannot bend further) is pushed out the shortest way, never into it.
func hand_push(T: Transform3D, h: UrHand) -> Vector3:
	if T.origin.distance_to(global_position) > 30.0 * CM + 2.0:
		return Vector3.ZERO
	conform(T, h)
	# the deepest contact first, straight out of the clay, until nothing is in it: back into
	# the bowl if the hand is reaching into it (never on through the wall), else outward.
	# A date that cannot get out of the way is as solid: the hand comes to rest on it.
	var inward := reaching_in(T * h.grip_local())
	var grounded := _grounded() if hand_solid_on else []
	var d := Vector3.ZERO
	for it in 8:
		var T2 := T
		T2.origin += d
		var worst := 0.0
		var at := Vector3.ZERO
		var dir := Vector3.ZERO
		var hb := hand_balls(T2, h)
		for bl in hb:
			var pen := float(bl[1]) + 0.05 * CM - clay_sdf(bl[0])
			if pen > worst:
				worst = pen
				at = bl[0]
				dir = Vector3.ZERO
		for i in mini(hb.size(), 39):          # (fingers and palm, not the sleeve)
			var p: Vector3 = hb[i][0]
			var r := float(hb[i][1])
			for g in grounded:
				var pen := r + float(g[1]) - p.distance_to(g[0])
				if pen > worst and _pinned(p, r, g):
					worst = pen
					at = p
					dir = (p - (g[0] as Vector3)).normalized()
		if worst <= 0.0:
			break
		if dir != Vector3.ZERO:
			d += dir * worst
			continue
		var q := global_transform.affine_inverse() * at / CM
		var in_rim := Vector2(q.x, q.z).length() < 7.3
		if inward and in_rim:
			d += _cavity_grad(at) * maxf(worst, float(0.0) - cavity_sdf(at))
		else:
			d += _clay_grad(at) * worst
	return d


## How far the fingers and palm at T would have to push into the other dates (cm), the
## ones underneath counting more (they cannot get out of the way).
func date_crowding(T: Transform3D, h: UrHand, skip: Node3D, below_y: float) -> float:
	var hb := hand_balls(T, h, false)
	var sum := 0.0
	for d in dates:
		if d.node == skip:
			continue
		var lw: Array = live(d)
		var under: bool = float(lw[0].y) < below_y
		for q in _balls(lw[0], lw[1], d.sph):
			var qw: Vector3 = global_transform * (q[0] * CM)
			for bl in hb:
				var pen := float(bl[1]) + float(q[1]) * CM - (bl[0] as Vector3).distance_to(qw)
				if pen > 0.0:
					sum += pen / CM * (3.0 if under else 1.0)
	return sum


# ---------------------------------------------------------------- the hand among the dates

## Make a hand solid to the dates: a kinematic capsule on each finger and thumb bone and a
## slab for the palm, following the skeleton every physics step. They only push while
## set_hand_solid() has them on.
func attach_hand(h: UrHand) -> void:
	hand_on = h
	for dg in UrHand.DIGITS:
		for sg in 3:
			_hand_body(dg, sg)
	for x in [-2.9, 0.0, 2.9]:
		for z in [1.2, 5.0, 8.6]:
			_hand_body("palm", -1, Vector3(x, 0.0, z))
	set_hand_solid(false)


func _hand_body(dg: String, sg: int, at := Vector3.ZERO) -> void:
	var b := AnimatableBody3D.new()
	b.sync_to_physics = false
	b.top_level = true
	b.collision_layer = 0
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	if sg < 0:
		# the palm as the same balls the reach was worked out with
		var sp := SphereShape3D.new()
		sp.radius = 1.35 * CM
		cs.shape = sp
	else:
		# a finger bone is the same length and girth whatever the pose: sized once
		var i: int = hand_on.bones["%s_%d" % [dg, sg]]
		var r: Vector2 = hand_on.bone_r[i]
		var cp := CapsuleShape3D.new()
		cp.radius = (r.x + r.y) * 0.5 * CM
		cp.height = float(hand_on.bone_len[i]) * CM + 2.0 * cp.radius
		cs.shape = cp
	b.add_child(cs)
	add_child(b)
	hand_bodies.append([b, dg, sg, at])


## Whether the hand's bodies push the dates now; `spare` is a date they leave alone (the
## one between the fingers: the fingers close on it by pose, not by shoving).
func set_hand_solid(on: bool, spare: Node3D = null) -> void:
	spare_date = spare if on else null
	hand_solid_on = on
	for e in hand_bodies:
		var b: AnimatableBody3D = e[0]
		b.collision_layer = LAYER if on else 0
		for d in dates:
			var rb: RigidBody3D = d.node
			rb.remove_collision_exception_with(b)
		if spare is RigidBody3D:
			(spare as RigidBody3D).add_collision_exception_with(b)
	if on:
		stir()


func _physics_process(_dt: float) -> void:
	_unfling()
	if hand_on == null or not hand_on.visible:
		return
	_sync_hand()


## (Also after the frame's physics, before it is drawn: nothing flung is ever seen.)
func _process(_dt: float) -> void:
	_unfling()


## Soft, sticky fruit: nothing a hand does sends it flying. One caught between a finger
## and the clay is squeezed, not shot out: if the physics flung one, it is put back where
## it last lay, still (that is the solver's answer to a body pinched tight, not a motion).
func _unfling() -> void:
	for d in dates:
		var rb: RigidBody3D = d.node
		if rb.freeze:
			continue
		if rb.linear_velocity.length() > FLUNG or rb.angular_velocity.length() > 40.0:
			if d.has("last"):
				rb.global_transform = d.last
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
		else:
			if rb.linear_velocity.length() > MAX_SPEED:
				rb.linear_velocity = rb.linear_velocity.normalized() * MAX_SPEED
			if rb.angular_velocity.length() > 12.0:
				rb.angular_velocity = rb.angular_velocity.normalized() * 12.0
			d["last"] = rb.global_transform


func _sync_hand() -> void:
	var h := hand_on
	var T := h.global_transform
	var R := T.basis.orthonormalized()
	if R.determinant() < 0.0:
		R.x = -R.x            # (the left hand is the right mirrored)
	for e in hand_bodies:
		var b: AnimatableBody3D = e[0]
		var sg: int = e[2]
		var cs: CollisionShape3D = b.get_child(0)
		if sg < 0:
			b.global_transform = Transform3D(R, T * (e[3] as Vector3))
			continue
		var cap: Array = h.capsule(h.bones["%s_%d" % [e[1], sg]])
		var A: Vector3 = T * (cap[0] as Vector3)
		var B: Vector3 = T * (cap[1] as Vector3)
		var y := (B - A).normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		b.global_transform = Transform3D(Basis(x, y, x.cross(y)), (A + B) * 0.5)


## A date's stone, as it comes out of his mouth (cm, under a node scaled by CM).
func make_pit() -> MeshInstance3D:
	var L := rng.randf_range(1.9, 2.4)
	var R := rng.randf_range(0.36, 0.42)
	var nu := 28
	var nv := 24
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	var pt := func(u: float, v: float) -> Vector3:
		var s := 2.0 * u - 1.0
		var r := pow(maxf(1.0 - pow(absf(s), 1.7), 0.0), 0.62) * R
		# the deep groove down its belly
		var g := exp(-pow(wrapf(v - PI * 0.5, -PI, PI) / 0.28, 2.0))
		r *= 1.0 - 0.55 * g * (1.0 - s * s * s * s)
		return Vector3(cos(v) * r, sin(v) * r * 0.9, s * L * 0.5)
	for i in nu + 1:
		var u := 0.5 - 0.5 * cos(PI * i / nu)
		for j in nv:
			var v := TAU * j / nv
			p.append(pt.call(u, v))
			var du: Vector3 = pt.call(minf(u + 0.003, 1.0), v) - pt.call(maxf(u - 0.003, 0.0), v)
			var dv: Vector3 = pt.call(u, v + 0.02) - pt.call(u, v - 0.02)
			var nn := dv.cross(du)          # outward
			if i == 0:
				nn = Vector3(0, 0, -1)
			elif i == nu:
				nn = Vector3(0, 0, 1)
			n.append(nn.normalized())
	var idx := PackedInt32Array()
	for i in nu:
		for j in nv:
			var a0 := i * nv + j
			var b0 := i * nv + (j + 1) % nv
			var d0 := (i + 1) * nv + j
			var e0 := (i + 1) * nv + (j + 1) % nv
			for t in [[a0, b0, d0], [b0, e0, d0]]:
				var x: int = t[0]
				var y: int = t[1]
				var z: int = t[2]
				var face := (p[y] - p[x]).cross(p[z] - p[x])
				if face.length_squared() < 1e-14:
					continue
				if face.dot(n[x] + n[y] + n[z]) > 0.0:
					idx.append_array([x, z, y])
				else:
					idx.append_array([x, y, z])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = p
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = date_shader
	mat.set_shader_parameter("kind", 1)
	mat.set_shader_parameter("seed", rng.randf() * 20.0)
	mi.material_override = mat
	mi.set_meta("half_h", R * 0.85)
	return mi


## Where the next stone he spits out goes (world): on the sand just beside the bowl, on
## the side of the hand that puts it there, the stones gathering in a loose little scatter.
func pit_spot() -> Vector3:
	var c := global_position + Vector3(2.0, 0.0, 0.45)
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * 0.4 + 0.08 * pits_out
	pits_out += 1
	return c + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.7)
