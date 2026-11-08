class_name UrHand
extends Node3D
## A player's right hand and robed arm: a skinned hand mesh (tools/make_hand.py) on a
## skeleton of hand, forearm, upper arm, finger and thumb bones; scruffy, sun-browned
## skin with knuckle wrinkles, dry patches, hair, veins, scratches, grimy cracked nails
## and an old faded tattoo; rings and a bracelet; and a loose desert-robe sleeve
## (white linen or black wool) that drapes from the wrist to the shoulder.
##
## The node's transform is the wrist. place() puts the hand so that its grip point
## (between thumb and fingers) lands on a world position; the elbow and shoulder are
## solved each frame so the arm always reaches back to the player's body.

const CM := 0.21                 # world units per centimetre (a board square is ~4-5 cm)
const FOREARM_CM := 25.0
const UPPERARM_CM := 30.0
const ELBOW_MIN_Y := 1.0         # world height the elbow keeps above (the table is at ~0.1)
# How far a seated player can reach. The arm opens out until it is nearly straight (the
# elbow at ~150 degrees, never locked); past that only the body can bring the hand
# further, leaning forward from the hips and pushing the shoulder blade out, which moves
# the shoulder at most a hand's length or so. Nothing reaches beyond that.
const REACH_FRAC := 0.97         # longest wrist-shoulder distance, as a part of the arm's length
const MAX_LEAN_CM := 26.0        # furthest the shoulder can travel from where he sits (the far
                                 # corner of the dice tray takes ~24, for the AI)

enum Style { WHITE, BLACK }

var style: Style
var left := false                # a left hand: the right one mirrored (thumb on the other side)
var shoulder: Vector3            # where this arm's shoulder normally is (world)
var person_right: Vector3        # the side this arm is on: the player's right for the right hand,
                                 # his left for the left (world, horizontal); the elbow goes out that way
var lean := 0.45                 # how far his shoulder follows the hand sideways

var skel: Skeleton3D
var bones := {}                  # name -> index
var bone_len := {}               # index -> length (cm)
var rest_rot := {}               # index -> Quaternion
var pose_cur := {}               # index -> Vector2(flex, yaw) degrees
var pose_tgt := {}
var pose_rate := 9.0
var shake := Vector3.ZERO        # extra wrist offset (world), e.g. rattling the dice
var aim_fwd := Vector3.FORWARD
var aim_pitch := 20.0
var aim_roll := 0.0
var grip_target := Vector3.ZERO
var move_id := 0                 # bumped by every new hand movement; older ones yield to it
var grip_override: Variant = null  # hand-local cm point to place at the target (e.g. the held stone)
var pose_cache := {}             # name -> {bone: Vector2}
var sleeve_mat: ShaderMaterial
var skin_mat: ShaderMaterial
var effort := 0.0               # how hard the game says the hand is working right now: 0 at ease or
                                 # open, ~0.4 holding something lightly, 1 squeezing (set by main.gd at
                                 # each grip and release; finger curl alone is only shape, not effort)
var tension := 0.0              # how hard the hand is gripping right now (0..1, follows effort quickly)
var pump := 0.0                 # blood the hand's work has pumped into it (0..1, builds while gripping,
                                 # ebbs over ~15 s)
const PUMP_EBB := 0.065          # how fast the pump ebbs (per second)
var low := 0.5                  # how far the hand hangs down, so blood pools in it (0 lifted .. 1 low)
var twist_rest := 0.3            # forearm twist (radians) in the arm's natural carriage
var sway := Vector3.ZERO         # how far the loose cloth trails behind (world)
var sway_v := Vector3.ZERO
var last_wrist := Vector3.ZERO
var last_vel := Vector3.ZERO
var swing_live := false
var aim_yaw := 0.0               # turn of the hand about the vertical, degrees (e.g. to line up with a die)
var solid := Callable()          # (T, hand) -> world push keeping the hand out of solid things
var bump := Vector3.ZERO         # how far the last placement was pushed out of them (world)
var bone_r := {}                 # index -> Vector2(r0, r1): radius of the finger flesh at either end (cm)
var bone_flat := {}              # index -> how much the finger is flattened (palm to back)

signal placed                    # the hand has just been put somewhere (things it holds follow)

const POSES := {
	# finger: [proximal, middle, distal] flex in degrees, plus spread (yaw) on the proximal
	"relaxed": {"index": [12, 16, 8, 2], "middle": [14, 17, 9, 0], "ring": [17, 20, 10, -2], "pinky": [20, 22, 12, -5],
		"thumb": [6, -6, 10, 8]},
	"reach": {"index": [4, 8, 4, 4], "middle": [5, 8, 4, 0], "ring": [7, 10, 5, -4], "pinky": [9, 12, 6, -9],
		"thumb": [0, 12, 4, 4]},
	"pinch": {"index": [36, 44, 24, 2], "middle": [40, 42, 22, 0], "ring": [58, 72, 40, -3], "pinky": [62, 78, 42, -6],
		"thumb": [16, -26, 24, 20]},
	"cup": {"index": [30, 38, 22, 1], "middle": [32, 40, 22, 0], "ring": [34, 42, 24, -1], "pinky": [36, 44, 26, -3],
		"thumb": [12, -14, 14, 12]},
	"cup_closed": {"index": [44, 58, 34, 1], "middle": [46, 60, 34, 0], "ring": [48, 62, 34, -1], "pinky": [50, 64, 36, -3],
		"thumb": [12, -14, 14, 12]},
	# as far as the fingers curl when closing round the dice; they stop where they meet one
	"fist": {"index": [78, 98, 66, 1], "middle": [80, 100, 66, 0], "ring": [82, 100, 66, -1], "pinky": [84, 100, 66, -3],
		"thumb": [12, -14, 14, 12]},
	"throw": {"index": [-6, -4, -2, 6], "middle": [-5, -4, -2, 0], "ring": [-3, -2, 0, -6], "pinky": [0, 0, 0, -13],
		"thumb": [-4, 18, -4, -4]},
}

# Where the thumb's pad goes in poses that need it to oppose the fingers (hand-local cm):
# [pad target, point the pad should face]. Solved once by solve_reach(), so the thumb
# comes round in front of the palm instead of folding away underneath it.
const THUMB_GOALS := {
	"pinch": [Vector3(3.6, -3.5, 9.2), Vector3(3.3, -3.5, 10.6)],
	"cup": [Vector3(4.2, -2.6, 8.6), Vector3(0.6, -2.9, 7.0)],
	"cup_closed": [Vector3(3.2, -3.4, 8.8), Vector3(0.6, -3.0, 7.0)],
	"fist": [Vector3(1.6, -4.2, 8.6), Vector3(0.4, -3.0, 7.0)],
}
# The point a stone is held at, between the thumb and the index/middle fingertips
const GRASP_C := Vector3(3.3, -3.5, 10.6)
const STONE_GRIP_R := 1.5            # half-width of a stone across the grip (cm)
const STONE_OPEN_R := 3.4             # fingers spread around it before closing
const PALM_C := Vector3(0.7, -3.35, 7.4)     # middle of the cupped palm (dice)
# The fingers that close round things, in the order they are driven
const DIGITS := ["index", "middle", "ring", "pinky", "thumb"]
const THUMB_FLAT := [0.9, 0.82, 0.78]
# The solid palm, as in tools/make_hand.py (hand-local cm): the rounded slab of the palm,
# the ball of the thumb, the heel under the little finger and the four knuckles.
const THENAR := [Vector3(2.9, -0.55, 3.0), Vector3(1.9, 1.25, 2.9)]
const HYPOTHENAR := [Vector3(-3.0, -0.45, 4.6), Vector3(1.25, 1.05, 3.0)]
const LIMITS := {
	"finger": [[-10.0, 95.0, -20.0, 20.0], [0.0, 110.0], [-5.0, 85.0]],
	"thumb": [[-35.0, 70.0, -75.0, 45.0], [-10.0, 75.0], [-15.0, 85.0]],
}

const SKIN_SHADER := """
shader_type spatial;
render_mode cull_back;
// Weathered, sun-browned skin of a man who works outdoors. Patterns are placed with
// the rest-pose position (CUSTOM0, in cm) and per-vertex masks from make_hand.py:
// COLOR = nail, joint, dorsal (back of hand), nail tip; UV = (along finger, around).
// The pose feeds in too: knuckle skin bunches when a finger is straight and pulls tight
// and pale when it bends, the veins fill and stand out as the hand works, and the
// extensor tendons show on the back of the hand as the fingers straighten.
uniform vec3 skin_tone = vec3(0.4, 0.25, 0.15);
uniform int tattoo = 0;          // 0: ankh on the back of the hand; 1: dotted lozenge + wrist band;
                                 // 2: only three dots in the web of the thumb
uniform float seed = 0.0;
uniform int debug_view = 0;      // 1: show the vertex masks, 2: show the region, 3: joint flex, 4: veins/tendons
uniform float flex[18];          // each bone's current flex (degrees), by skeleton index
uniform float pump = 0.0;        // 0 drained (hand lifted) .. 1 full (hand low after hard work)
uniform vec4 extend = vec4(0.0); // index, middle, ring, pinky: how straight (tendons taut)
varying vec4 rest;
varying vec4 masks;
varying vec2 fuv;
varying float jflex;             // flex of the joint nearest this point (degrees)
varying float prox;              // how much this point rides on a proximal finger bone

const float CMW = 0.21;          // world units per cm (heights below are in cm)

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyx, p.y) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
// Distance to the nearest cell edge of a 3D Voronoi pattern: the fine criss-cross of
// furrows on the back of the hand.
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
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
float ink_line(float d, float w) {
	return 1.0 - smoothstep(w * 0.6, w * 1.4, d);
}
float tattoo_ink(vec2 q) {
	float ink = 0.0;
	if (tattoo == 0) {
		// ankh on the back of the hand, loop toward the fingers
		vec2 c = vec2(1.1, 5.9);
		float loop = abs(length((q - c) / vec2(0.62, 0.82)) - 1.0) * 0.7;
		ink = max(ink, ink_line(loop, 0.13));
		ink = max(ink, ink_line(seg(q, vec2(1.1, 2.6), vec2(1.1, 5.1)), 0.15));
		ink = max(ink, ink_line(seg(q, vec2(0.15, 5.0), vec2(2.05, 5.0)), 0.15));
		for (int i = 0; i < 3; i++) // three dots beside it
			ink = max(ink, 1.0 - smoothstep(0.1, 0.2, length(q - vec2(-0.6, 3.4 + float(i) * 0.75))));
	} else if (tattoo == 1) {
		// lozenge of dots, the old Nile way, and a band of dots round the wrist
		vec2 r = q - vec2(0.2, 4.6);
		if (abs(r.x) + abs(r.y) * 0.8 < 2.4) {
			vec2 g = r / 0.62;
			vec2 cell = fract(g + vec2(0.5 * mod(floor(g.y), 2.0), 0.0)) - 0.5;
			ink = max(ink, 1.0 - smoothstep(0.17, 0.27, length(cell)));
		}
		float diamond = abs(abs(r.x) + abs(r.y) * 0.8 - 2.55);
		ink = max(ink, ink_line(diamond, 0.1));
		if (abs(q.y + 1.3) < 0.25) {
			float gx = fract(q.x / 0.7) - 0.5;
			ink = max(ink, 1.0 - smoothstep(0.12, 0.2, length(vec2(gx * 0.7, q.y + 1.3))));
		}
	} else if (tattoo == 2) {
		// three dots in a little triangle in the web of the thumb, done long ago
		for (int i = 0; i < 3; i++) {
			vec2 c = vec2(2.6, 5.4) + vec2(float(i % 2) * 0.55 - float(i / 2) * 0.27, float(i / 2) * 0.5);
			ink = max(ink, 1.0 - smoothstep(0.12, 0.22, length(q - c)));
		}
	}
	return ink;
}


// Single hairs lying along +y of the chart q (cm), rooted in a jittered grid. Returns
// (coverage, how far along the hair, soft shadow beneath). Hairs thinner than a pixel
// fade out by the part of the pixel they cover, so at a distance they read as a haze.
vec3 hairs(vec2 q, float dens, float len, float wid, float cell, float sd) {
	vec2 cs = vec2(cell, cell * 1.9);
	vec2 id = floor(q / cs);
	float aa = max(length(fwidth(q)) * 0.7, 1e-4);
	float cov = 0.0, along = 0.0, sh = 0.0;
	for (int j = -2; j <= 0; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = id + vec2(float(i), float(j));
			vec4 h = hash4(c + sd);
			if (h.x > dens) continue;
			vec2 root = (c + vec2(h.y, fract(h.y * 7.13 + h.w * 3.1))) * cs;
			float a = (h.z - 0.5) * 0.75;
			vec2 dir = vec2(sin(a), cos(a));
			vec2 side = vec2(dir.y, -dir.x);
			float L = len * (0.5 + 0.5 * h.w);
			float bend = (fract(h.w * 13.7) - 0.5) * 0.35 * L;
			vec2 r = q - root;
			float t = clamp(dot(r, dir) / L, 0.0, 1.0);
			vec2 pt = root + dir * L * t + side * bend * t * t;
			float d = length(q - pt);
			float w = wid * (1.0 - 0.7 * t) * (0.7 + 0.6 * fract(h.y * 31.0));
			float c1 = clamp(1.0 - (d - w) / aa, 0.0, 1.0) * min(1.0, 2.0 * w / aa);
			if (c1 > cov) { cov = c1; along = t; }
			sh = max(sh, (1.0 - smoothstep(0.0, w * 6.0 + aa, d)) * (1.0 - t));
		}
	}
	return vec3(cov, along, sh);
}

float gauss(float d, float r) {
	return exp(-d * d / (r * r));
}
// Distance to a polyline of four points
float pl4(vec2 q, vec2 a, vec2 b, vec2 c, vec2 d) {
	return min(min(seg(q, a, b), seg(q, b, c)), seg(q, c, d));
}
// The veins on the back of the hand (rest x, z in cm): three metacarpal veins from the
// finger webs into the dorsal arch, which drains up the thumb side (cephalic) and the
// little-finger side (basilic), plus a few smaller ones. Returns the bulge (0..1 scale).
float vein_net(vec2 q, float fill, float wide) {
	float b = 0.0;
	float r = 0.15 * (0.7 + 0.9 * fill) * wide;
	float taper = mix(1.0, 0.75, smoothstep(6.0, 9.2, q.y));
	b = max(b, gauss(pl4(q, vec2(1.95, 9.1), vec2(1.8, 7.7), vec2(1.55, 6.4), vec2(1.5, 5.5)), r * taper));
	b = max(b, gauss(pl4(q, vec2(-0.05, 9.2), vec2(-0.15, 7.9), vec2(-0.4, 6.6), vec2(-0.6, 5.6)), r * taper));
	b = max(b, gauss(pl4(q, vec2(-2.05, 8.8), vec2(-2.25, 7.6), vec2(-2.4, 6.3), vec2(-2.5, 5.1)), r * 0.9 * taper));
	float rm = r * 1.25;
	b = max(b, gauss(pl4(q, vec2(2.4, 4.6), vec2(1.5, 5.5), vec2(0.4, 5.9), vec2(-0.6, 5.6)), rm));
	b = max(b, gauss(pl4(q, vec2(-0.6, 5.6), vec2(-1.6, 5.4), vec2(-2.5, 5.1), vec2(-3.3, 4.4)), rm));
	b = max(b, gauss(pl4(q, vec2(2.4, 4.6), vec2(2.6, 3.0), vec2(2.3, 1.3), vec2(2.0, -0.8)), rm * 1.1));
	b = max(b, gauss(pl4(q, vec2(-3.3, 4.4), vec2(-3.4, 2.8), vec2(-3.1, 0.8), vec2(-2.7, -1.5)), rm * 1.05));
	b = max(b, 0.7 * gauss(pl4(q, vec2(0.4, 5.9), vec2(0.3, 4.2), vec2(-0.4, 2.6), vec2(-0.6, 0.5)), r * 0.75));
	b = max(b, 0.6 * gauss(pl4(q, vec2(1.8, 7.7), vec2(2.3, 7.8), vec2(2.7, 7.6), vec2(3.0, 7.2)), r * 0.6));
	b = max(b, 0.6 * gauss(pl4(q, vec2(-2.25, 7.6), vec2(-2.7, 7.4), vec2(-3.1, 7.1), vec2(-3.5, 6.6)), r * 0.6));
	return b;
}
// One extensor tendon from the wrist to a knuckle: a broad ridge on its distal two thirds.
float tendon(vec2 q, vec2 a, vec2 b) {
	vec2 ba = b - a;
	float t = clamp(dot(q - a, ba) / dot(ba, ba), 0.0, 1.0);
	return gauss(length(q - a - ba * t), 0.2) * smoothstep(0.2, 0.55, t) * smoothstep(1.0, 0.88, t);
}

void vertex() {
	rest = CUSTOM0;
	masks = COLOR;
	fuv = UV;
	// the bone this point mostly rides on; past its middle the joint is the next bone's
	int mb = int(BONE_INDICES[0]);
	float mw = BONE_WEIGHTS[0];
	prox = 0.0;
	for (int k = 0; k < 4; k++) {
		int bi = int(BONE_INDICES[k]);
		if (BONE_WEIGHTS[k] > mw) { mw = BONE_WEIGHTS[k]; mb = bi; }
		if (bi == 2 || bi == 5 || bi == 8 || bi == 11) prox += BONE_WEIGHTS[k];
	}
	bool distal = mb == 4 || mb == 7 || mb == 10 || mb == 13 || mb == 16;
	jflex = 0.0;
	if (mb >= 2) jflex = (UV.x < 0.0 && !distal) ? flex[mb + 1] : flex[mb];
	// the veins swell the skin itself (model space is cm), so as the hand grips they rise
	// out of the back of the hand, change its outline and catch the light
	float bk = smoothstep(0.6, 0.9, COLOR.b) * (CUSTOM0.w < 1.5 ? 1.0 : 0.0);
	if (bk > 0.0) {
		vec3 pv = CUSTOM0.xyz + vec3(seed * 13.1);
		vec2 vq = CUSTOM0.xz + (vec2(vnoise(pv * 0.8), vnoise(pv * 0.8 + 17.0)) - 0.5) * 0.55;
		float f = clamp(pump, 0.0, 1.0);
		float vb = vein_net(vq, f, 1.35) * bk * smoothstep(-1.5, 0.5, CUSTOM0.z) * smoothstep(9.8, 8.6, CUSTOM0.z);
		// in the sun's shadow pass (orthographic) keep only a little of the swelling: the shadow
		// map is far coarser than a vein and would smear it into dark blotches
		float in_shadow = PROJECTION_MATRIX[3][3] > 0.5 ? 0.2 : 1.0;
		VERTEX += NORMAL * vb * (0.004 + 0.16 * f + 0.24 * f * f) * in_shadow;
	}
}

void fragment() {
	vec3 p = rest.xyz + vec3(seed * 13.1);
	float region = rest.w;
	float nail = masks.r;
	float jnt = masks.g;
	float dorsal = masks.b;
	float tip = masks.a;
	bool finger = region > 1.5;
	float back = smoothstep(0.6, 0.9, dorsal) * (region < 1.5 ? 1.0 : 0.0);   // back of hand / wrist
	float px = length(fwidth(rest.xyz));                                       // cm per pixel

	vec3 skin = skin_tone * (0.86 + 0.26 * vnoise(p * 1.3) + 0.08 * vnoise(p * 5.0));
	skin = mix(skin, skin * vec3(1.15, 0.9, 0.82), clamp(jnt * 0.7 + (finger ? 0.18 : 0.0), 0.0, 1.0) * 0.55);
	skin = mix(skin * vec3(1.45, 1.3, 1.18) + vec3(0.04, 0.025, 0.02), skin, smoothstep(0.15, 0.6, dorsal));
	// sun spots and freckles on the back
	float spot = smoothstep(0.66, 0.8, vnoise(p * 4.2 + 31.0)) * smoothstep(0.35, 0.75, vnoise(p * 0.9 + 5.0));
	skin = mix(skin, skin * vec3(0.78, 0.68, 0.6), spot * smoothstep(0.45, 0.8, dorsal) * 0.55);

	// knuckle wrinkles (lines across the finger at each joint, on the back): they bunch up
	// deep when the finger is straight and pull out smooth and pale over a bent knuckle
	float jf = clamp(jflex / 90.0, -0.4, 1.2);
	float tight = smoothstep(0.15, 0.9, jf);
	float slack = 1.0 + 0.7 * smoothstep(0.15, -0.2, jf);
	float wr = (0.5 + 0.5 * sin(fuv.x * 24.0 * (1.0 - 0.25 * tight) + vnoise(p * 3.0) * 5.0)) * jnt * dorsal * (finger ? 1.0 : 0.0);
	wr = smoothstep(0.55, 0.95, wr) * (1.0 - 0.8 * tight) * slack;
	float blanch = jnt * smoothstep(0.5, 0.85, dorsal) * tight;
	// creases on the palm side of each joint, folded deeper as it bends
	float fold = jnt * (1.0 - smoothstep(0.25, 0.55, dorsal)) * (finger ? 1.0 : 0.0)
		* max(1.0 - smoothstep(0.015, 0.06, abs(abs(fuv.x) - 0.08)), 0.7 * (1.0 - smoothstep(0.015, 0.05, abs(abs(fuv.x) - 0.3))))
		* (0.35 + 0.9 * clamp(jf, 0.0, 1.0));
	// big MCP knuckles: dry, ashy, wrinkled skin
	float ash = smoothstep(0.5, 0.85, vnoise(p * 5.0 + 2.0)) * dorsal * clamp(jnt + 0.25, 0.0, 1.0);
	// fine criss-cross furrows and pores; faded out where they'd shimmer below a pixel
	float relief_k = 1.0 - smoothstep(0.02, 0.05, px);
	float furrow = (1.0 - smoothstep(0.0, 0.25, cell_edge(p * vec3(12.0, 12.0, 8.0)))) * relief_k * (0.4 + 0.6 * dorsal) * (1.0 - nail);
	float pore = vnoise(p * 16.0);
	// veins over the back of the hand, filling as the hand works; tendons taut over the
	// back as the fingers straighten (and a little in a hard grip)
	vec2 vq = rest.xz + (vec2(vnoise(p * 0.8), vnoise(p * 0.8 + 17.0)) - 0.5) * 0.55;
	float fill = clamp(pump, 0.0, 1.0);
	float vb = vein_net(vq, fill, 1.0) * back * smoothstep(-1.5, 0.5, rest.z) * smoothstep(9.8, 8.6, rest.z);
	float vh = vb * (0.006 + 0.12 * fill + 0.19 * fill * fill);
	vec4 tens = clamp(extend * 0.85 + 0.15 + 0.25 * fill, 0.0, 1.2);
	float td = tens.x * tendon(rest.xz, vec2(0.9, 0.8), vec2(2.75, 9.5)) + tens.y * tendon(rest.xz, vec2(0.35, 0.8), vec2(0.9, 9.8))
		+ tens.z * tendon(rest.xz, vec2(-0.25, 0.8), vec2(-1.05, 9.4)) + tens.w * tendon(rest.xz, vec2(-0.8, 1.0), vec2(-2.9, 8.5));
	td *= back;
	// hair: on the back of the hand and wrist, lying toward the fingers and the little-finger
	// side, thickest by the wrist; short sparse hairs on the first finger joints
	vec3 hr = vec3(0.0);
	if (back > 0.01) {
		vec2 hq = mat2(vec2(0.96, 0.29), vec2(-0.29, 0.96)) * rest.xz;
		float dens = back * smoothstep(9.3, 6.5, rest.z) * (0.45 + 0.35 * smoothstep(1.5, -3.0, rest.x) + 0.2 * smoothstep(3.0, 0.0, rest.z));
		vec3 h1 = hairs(hq + seed, dens * 0.8, 0.75, 0.0045, 0.16, 3.0);
		vec3 h2 = hairs(hq * 1.13 + vec2(0.37, 0.71) + seed, dens * 0.6, 0.6, 0.004, 0.16, 11.0);
		hr = h1.x >= h2.x ? h1 : h2;
		hr.z = max(h1.z, h2.z);
	} else if (prox > 0.5 && finger) {
		float dens = smoothstep(0.65, 0.9, dorsal) * smoothstep(0.5, 0.9, prox) * smoothstep(0.45, 0.9, abs(fuv.x)) * 0.55;
		hr = hairs(rest.xz * vec2(1.0, 1.0) + seed * 2.0, dens, 0.4, 0.0035, 0.15, 23.0);
	}
	// scratches, nicks and a few healed scars from work
	float scr = (1.0 - smoothstep(0.0, 0.02, abs(vnoise(p * vec3(5.0, 1.0, 2.6) + 9.0) - 0.5)))
		* step(0.84, vnoise(p * 1.4 + 3.0)) * smoothstep(0.3, 0.7, dorsal);
	float scar = smoothstep(0.86, 0.9, vnoise(p * 1.7 + 21.0)) * dorsal;
	// grime: worked into creases and wrinkles, patchy dirt and sand dust
	float grime = smoothstep(0.45, 0.9, vnoise(p * 1.9 + 7.0));
	float dust = smoothstep(0.72, 0.9, vnoise(p * 9.0 + 4.0)) * smoothstep(0.4, 0.8, vnoise(p * 1.2 + 11.0));

	vec3 col = skin;
	col *= 1.0 - 0.08 * pore;
	col *= 1.0 - 0.3 * wr - 0.012 * furrow - 0.35 * fold;
	col = mix(col, col * 1.25 + vec3(0.05, 0.045, 0.04), ash * 0.3);
	col = mix(col, col * vec3(1.2, 1.12, 1.04) + vec3(0.02, 0.015, 0.01), blanch * 0.35);
	// blue-green blood under thin skin, a touch darker where the vein lies deep
	col = mix(col, col * vec3(0.8, 0.88, 0.98), vb * (0.03 + 0.12 * fill + 0.18 * fill * fill));
	col = mix(col, vec3(0.55, 0.24, 0.17), scr * 0.35);
	col = mix(col, col * vec3(1.18, 1.08, 1.0), scar * 0.4);
	col = mix(col, col * vec3(0.62, 0.55, 0.48), (grime * 0.25 + wr * 0.35 + furrow * 0.04 + fold * 0.3) * 0.6);
	col = mix(col, vec3(0.66, 0.55, 0.4), dust * 0.25);

	// tattoo: soot ink under the skin, blurred and faded blue-green with age
	float ink = tattoo_ink(rest.xz) * smoothstep(0.55, 0.85, dorsal) * (region < 1.5 ? 1.0 : 0.0);
	ink *= 0.75 + 0.25 * vnoise(p * 6.0);
	col = mix(col, col * vec3(0.32, 0.42, 0.46), ink * 0.8);

	// hair over everything on the skin: near-black at the root, sun-bleached at the tip
	col *= 1.0 - 0.22 * hr.z;
	vec3 hairc = mix(vec3(0.03, 0.022, 0.016), vec3(0.17, 0.11, 0.065), hr.y * hr.y);
	col = mix(col, hairc, hr.x * 0.92);

	// nails: thick, ridged, chipped, with dirt packed under the tips and ragged cuticles
	float ridges = vnoise(vec3(fuv.y * 9.0, p.y * 0.2, 0.0) + p * 0.15);
	vec3 nailc = vec3(0.47, 0.38, 0.3) * (0.8 + 0.3 * ridges);
	nailc = mix(nailc, vec3(0.5, 0.38, 0.3), smoothstep(0.6, 0.85, vnoise(p * 7.0)) * 0.5);   // stained
	float under = smoothstep(0.4, 0.85, tip);
	nailc = mix(nailc, vec3(0.12, 0.08, 0.05), under * 0.9);                                  // black dirt under the tip
	float cuticle = nail * (1.0 - nail) * 4.0;
	col = mix(col, nailc, smoothstep(0.35, 0.75, nail));
	col = mix(col, col * vec3(0.55, 0.42, 0.35), cuticle * 0.6);

	if (debug_view == 1) col = masks.rgb;
	if (debug_view == 2) col = vec3(rest.w / 3.0, fract(rest.z * 0.2), 0.0);
	if (debug_view == 3) col = vec3(clamp(jf, 0.0, 1.0), clamp(-jf * 3.0, 0.0, 1.0), prox * 0.5);
	if (debug_view == 4) col = vec3(vb, td, hr.x);
	ALBEDO = col;
	float nm = smoothstep(0.35, 0.75, nail);
	float rough = 0.58 - 0.08 * jnt + 0.15 * ash + 0.1 * dust + 0.06 * furrow - 0.1 * blanch - 0.06 * vb;
	ROUGHNESS = clamp(mix(mix(rough, 0.42, hr.x), 0.45 + 0.3 * under, nm), 0.2, 1.0);
	SPECULAR = 0.35;
	SSS_STRENGTH = 0.3 * (1.0 - nm);
	BACKLIGHT = vec3(0.35, 0.12, 0.06) * 0.6;

	float h = -wr * 0.03 - furrow * 0.00035 + pore * 0.003 - scr * 0.008 - fold * 0.012
		+ hr.x * 0.003 + ash * 0.006 + (ridges - 0.5) * 0.01 * nail - under * 0.01
		+ (vh + td * (0.03 + 0.07 * dot(extend, vec4(0.25)) + 0.03 * fill)) * CMW;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1v = cross(dpdy, NORMAL);
	vec3 r2v = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1v);
	vec3 grad = sign(det) * (dFdx(h) * r1v + dFdy(h) * r2v);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
"""

const CLOTH_SHADER := """
shader_type spatial;
render_mode cull_back, world_vertex_coords;
// Desert robe sleeve, draped every frame. The cloth is two layers (outside and lining)
// joined by a rolled hem. Its shape is computed here from the arm bones: the top rests
// on the arm, the rest falls under real gravity into deep hanging folds, the slack
// slides down a sloping arm, bunches where the sleeve is pushed up the forearm, swings
// behind the hand's movement and lies on the table instead of passing through it.
// The arm's pose creases it as it moves: bending the elbow squeezes a fan of creases into
// the inside of the bend and pulls its point smooth, turning the forearm twists diagonal
// creases round it, and a quick pull back gathers more cloth at the cuff.
// Old, coarse hand-woven cloth (UV in cm): threads, crumpled linen (or felted wool),
// crests rubbed pale and creases holding grime, tide-marked stains, a darned repair,
// dust toward the frayed hem, sun-faded on top.
uniform vec3 base = vec3(0.8, 0.76, 0.68);
uniform float dark = 0.0;          // 1 for black wool
uniform mat4 skin_fa;              // forearm / upper arm skinning (skeleton space, cm)
uniform mat4 skin_ua;
uniform vec3 grav = vec3(0.0, -1.0, 0.0);   // gravity in skeleton space
uniform vec3 sway = vec3(0.0);     // lag of the loose cloth behind the hand (skeleton space, cm)
uniform float floor_y = 0.08;      // the table / sand under the hand (world)
uniform float seed = 0.0;
uniform float z0 = 5.5;            // the hem, measured from the wrist up the arm (cm)
uniform float elbow = 25.0;
uniform float bend = 0.0;          // elbow bend (radians, 0 = straight)
uniform vec2 e_fa = vec2(0.0, -1.0);   // the inside of the bend, round the forearm / upper arm (rest frame)
uniform vec2 e_ua = vec2(0.0, -1.0);
uniform float twist = 0.0;         // forearm turned against the upper arm (1 = well turned)
uniform float tug = 0.0;           // -1 cloth shoved toward the cuff .. 1 dragged toward the elbow
uniform int debug = 0;            // 1: lining red, hem band blue; 2: plain; 3: no relief; 4: relief only; 5: darn / stains / folds as RGB; 6/7: no backlight / rim (now unused); 8: no pose folds in the shape
varying float v_band;
varying float v_hang;
varying float v_fold;
varying float v_hem;
varying float v_inner;
varying vec3 wn;

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

mat4 skin_at(float z) {
	float wu = clamp((z - elbow + 4.0) / 8.0, 0.0, 1.0);
	return skin_fa * (1.0 - wu) + skin_ua * wu;
}

// cloth folds: rounded crests, sharp creases between them
float crease(float x) {
	return 2.0 * abs(sin(x)) - 1.0;
}

// Creases the arm's pose puts in the sleeve at (th, z); k scales their frequency (1 for the
// big folds of the drape, more for the fine creases on them). `stretch` is how hard the
// cloth is pulled taut there (over the point of a bent elbow).
float pose_folds(float th, float z, float k, float nz, out float stretch) {
	vec2 cd = vec2(-sin(th), cos(th));
	float zw = clamp((z - elbow + 3.0) / 6.0, 0.0, 1.0);
	vec2 ein = mix(e_fa, e_ua, zw);
	ein = length(ein) > 0.001 ? normalize(ein) : vec2(0.0, -1.0);
	float cin = dot(cd, ein);                     // 1 inside the bend, -1 on the point of the elbow
	float ang = acos(clamp(cin, -1.0, 1.0));
	float bw = smoothstep(0.55, 1.9, bend);   // (a straight-reaching arm is about 0.5)
	bw *= bw;
	// creases are never regular: wander their phase round and along the arm
	float wander = 2.0 * nz + 1.6 * vnoise(vec3(cos(th) * 2.2, sin(th) * 2.2, z * 0.35 + 5.0));
	float ze = z - elbow;
	float near_e = exp(-ze * ze / 48.0);
	// inside the bend: crescents squeezed together, curving toward the elbow round the sides
	float inside = smoothstep(-0.35, 0.6, cin);
	float side = ze / sqrt(ze * ze + 1.0);           // which side of the elbow (smoothly, so no seam)
	float pe = k * (ze * 0.8 - side * ang * ang * 0.85) + wander;
	float f_el = bw * near_e * inside * mix(sin(pe), crease(pe), 0.5);
	stretch = bw * near_e * smoothstep(0.0, -0.8, cin);
	// a twisted forearm: diagonal creases spiralling round it
	float tw = clamp(twist, -1.0, 1.0);
	float fore = smoothstep(z0 + 1.0, z0 + 5.0, z) * (1.0 - smoothstep(elbow - 5.0, elbow + 2.0, z));
	float pt = k * z * 0.45 + sign(tw) * floor(k * 1.5 + 0.5) * th + wander;   // (whole turns round: no seam)
	float f_tw = abs(tw) * fore * mix(sin(pt), crease(pt), 0.5);
	return f_el + 0.6 * f_tw;
}

// Point of the sleeve at material angle th (0 = top of the arm at rest) and distance z
// up the arm, `inset` cm inside the outer surface. Skeleton space.
vec3 sleeve_pos(float th, float z, float inset, out float hang, out float fold) {
	mat4 M = skin_at(z);
	vec3 g = normalize(transpose(mat3(M)) * grav);     // gravity in the arm's rest frame
	vec2 gd = vec2(g.x, g.y);
	float k = smoothstep(0.08, 0.6, length(gd));       // how much the cloth hangs sideways
	gd = length(gd) > 0.001 ? normalize(gd) : vec2(0.0, -1.0);
	vec2 cs = vec2(cos(th), sin(th));
	float n1 = vnoise(vec3(cs * 2.0, z * 0.11 + seed));
	float n2 = vnoise(vec3(cs * 3.5, z * 0.3 + seed * 2.0));

	// sizes: the arm (round enough for the drape), and the cloth's half-girth
	float ra = 3.3 + 0.03 * z;
	float bunch = exp(-(z - z0) / 7.0);                 // pushed up the forearm: gathered there
	// a bent elbow pulls the cloth taut round its point, which takes up the slack that would
	// otherwise pool into a belly under the joint
	float ze = z - elbow;
	float taut = smoothstep(0.55, 1.9, bend) * exp(-ze * ze / 50.0);
	float Rs = mix(4.75 + 0.035 * z, 4.3, bunch * 0.7);
	Rs = mix(Rs, ra * 1.22, taut * 0.8);
	float half_c = 3.14159 * Rs;

	// where this bit of cloth is, counted round from the top (the side facing away from gravity)
	vec2 up = -gd;
	float th_top = atan(-up.x, up.y);
	float phi = mod(th - th_top + 3.14159, 6.28318) - 3.14159;
	float sg = phi < 0.0 ? -1.0 : 1.0;
	float s = abs(phi) / 3.14159 * half_c;
	vec2 side = vec2(up.y, -up.x) * -sg;               // horizontal, toward this side
	// draped: over the arm, straight down the side, round under the bottom
	float pc = 1.72;
	float sc = ra * pc;
	vec2 pd;
	float h = 0.0;
	if (s <= sc) {
		float a = s / ra;
		pd = up * cos(a) * ra + side * sin(a) * ra;
	} else {
		float L = half_c - sc;
		float xs = ra * sin(pc);
		float yc = ra * cos(pc);
		float rho = min(xs, L / 1.5708);
		float hh = max(L - 1.5708 * rho, 0.0);
		float rem = s - sc;
		if (rem < hh) {
			pd = side * xs + up * (yc - rem);
		} else {
			float b = (rem - hh) / rho;
			pd = side * mix(xs, rho, smoothstep(0.0, 0.3, b)) * cos(b) + up * (yc - hh - rho * sin(b));
		}
		h = rem / L;
	}
	vec2 pr = vec2(-sin(th), cos(th)) * Rs * 0.92;     // with no sideways pull: a loose round tube
	vec2 p = mix(pr, pd, k);
	hang = h * k;

	// folds: vertical drapes in the hanging cloth, rings where it is bunched, small creases
	// hanging cloth: long ridges falling from the arm, sharp crested, rounded between
	float rh = sin(z * 0.36 + 4.0 * n1 + seed);
	float f_hang = (0.85 * (1.0 - 2.0 * abs(rh)) * 0.5 + 0.35 * rh + 0.22 * sin(z * 0.8 + 3.0 * n2)) * smoothstep(0.0, 0.45, hang);
	// pushed up the forearm: rings of gathered cloth, more of them when it is shoved back
	float gather = (1.0 + 0.9 * max(-tug, 0.0)) * (1.0 - 0.45 * max(tug, 0.0));
	float f_bunch = bunch * 0.75 * gather * sin(z * 1.3 + 1.2 * sin(2.0 * th + seed) + 3.0 * n2);
	// where it rests on the arm: long diagonal folds twisting round it
	float rd = sin(z * 0.42 + th * 2.0 + 2.5 * n1 + seed);
	float f_top = (0.38 * (1.0 - abs(rd)) - 0.2) * (1.0 - hang) * (1.0 - bunch);
	float f_gen = (n2 - 0.5) * 0.12;
	// and what the arm's pose does to it: creased inside the elbow, pulled smooth over its point
	float stretch;
	float f_pose = pose_folds(th, z, 1.0, n2, stretch);
	f_top *= 1.0 - 0.8 * stretch;
	f_hang *= 1.0 - 0.5 * stretch - 0.3 * max(tug, 0.0);
	fold = f_hang + f_bunch + f_top + f_gen + 0.8 * f_pose - 0.25 * stretch;
	if (debug == 8) fold = f_hang + f_bunch + f_top + f_gen;
	vec2 rad = normalize(p + vec2(0.0001));
	p += rad * (fold - inset);
	// never inside the (oval) forearm
	float e = length(vec2(p.x / (3.7 + 0.03 * z), p.y / (2.9 + 0.03 * z)));
	if (e < 1.1) p *= 1.1 / e;
	// the slack slides down a sloping arm
	float slide = g.z * 1.6 * hang;
	return (M * vec4(p.x, p.y, -z + slide, 1.0)).xyz;
}

void vertex() {
	float th = UV2.x;
	float z = UV2.y;
	float inner = COLOR.r;
	float band = COLOR.g;
	// frayed, uneven hem
	float hemw = 1.0 - smoothstep(0.0, 0.01, z - z0);
	z += hemw * (vnoise(vec3(cos(th) * 3.0, sin(th) * 3.0, seed)) - 0.5) * 1.6;
	float inset = inner * 0.32;
	float hang;
	float fold;
	float hg;
	float fd;
	vec3 p = sleeve_pos(th, z, inset, hang, fold);
	vec3 pa = sleeve_pos(th + 0.012, z, inset, hg, fd);
	vec3 pb = sleeve_pos(th, z + 0.06, inset, hg, fd);
	mat4 M = skin_at(z);
	vec3 axis = (M * vec4(0.0, 0.0, -z, 1.0)).xyz;
	vec3 n = normalize(cross(pa - p, pb - p));
	if (dot(n, p - axis) < 0.0) n = -n;
	if (inner > 0.5) n = -n;
	if (band > 0.5) n = normalize(mat3(M) * vec3(0.0, 0.0, 1.0));
	// the loose cloth lags behind the hand and stirs a little in the breeze
	p += sway * (0.15 + hang);
	p += (mat3(M) * vec3(1.0, 0.0, 0.0)) * sin(TIME * 2.3 + z * 0.35 + th + seed) * 0.12 * hang;
	vec3 w = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	vec3 wnm = normalize(mat3(MODEL_MATRIX) * n);
	// lies on the table rather than passing into it
	float under = floor_y - w.y;
	if (under > 0.0) {
		w.y = floor_y + under * 0.04;
		wnm = normalize(mix(wnm, vec3(0.0, 1.0, 0.0), clamp(under * 8.0, 0.0, 0.8)));
	}
	VERTEX = w;
	NORMAL = wnm;
	v_hang = hang;
	v_fold = fold;
	v_hem = clamp(1.0 - (UV2.y - z0) / 9.0, 0.0, 1.0);
	v_inner = inner;
	v_band = band;
	wn = wnm;
}

const float RF = 5.5;               // radius of the texture cylinder (cm)
const float NU = 121.0;             // threads round the sleeve (~3.5 per cm)

// Darned repair: where it is and how much (0..1) at (th, z); `edge` is its ragged border.
float darn(float th, float z, out float edge) {
	vec2 d = vec2(mod(th - 2.3 + 3.14159, 6.28318) - 3.14159, (z - 16.0) / 1.25) * vec2(RF / 1.0, 1.0);
	float r = length(d / vec2(0.85, 1.0)) + 0.18 * (vnoise(vec3(d * 2.0, 7.0)) - 0.5);
	edge = 1.0 - smoothstep(0.0, 0.18, abs(r - 1.0));
	return 1.0 - smoothstep(0.92, 1.0, r);
}

// Relief of the cloth surface (cm) at (th, z): woven threads, crumple, the fine creases of
// the arm's pose and of the gathered cuff, and the darning. Also hands back what the
// colouring needs: the crumple and crease part alone (`fold`, for wear on the crests and
// grime in the creases), how taut the cloth is, the thread slub and the darn.
float cloth_h(float th, float z, float fade, out float fold, out float stretch, out float slub, out float dm, out float de) {
	vec3 c = vec3(cos(th) * RF, sin(th) * RF, z);
	float nz = vnoise(vec3(c.xy * 0.4, z * 0.3) + seed);
	// threads, over and under, uneven in thickness
	slub = vnoise(vec3(c.xy * 0.6, z * 5.0));
	float warp = abs(sin(th * NU + 1.5 * slub));
	float weft = abs(sin(z * 22.0 + 1.5 * vnoise(vec3(c.xy * 4.0, z * 0.6))));
	float weave = (warp + weft - 1.0) * (0.6 + 0.8 * slub);
	// crumpled: linen into short sharp crinkles running every which way (along the arm,
	// round it, across it), each set only here and there; wool into soft lumps
	float crumple = 0.0;
	if (dark > 0.5) {
		crumple = (vnoise(c * 1.2 + seed) - 0.5) * 0.5;
	} else for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 dir = vec2(17.0, 0.0);                  // (per radian round the sleeve, per cm along it)
		if (i == 1) dir = vec2(9.0, 1.7);
		if (i == 2) dir = vec2(-11.0, 2.1);
		if (i == 3) dir = vec2(0.0, 2.9);
		float ph = dir.x * th + dir.y * z + 1.5 * vnoise(c * 0.65 + seed + fi * 5.0);
		float w = sin(ph);
		float patch = smoothstep(0.5, 0.78, vnoise(c * vec3(0.5, 0.5, 0.3) + seed + fi * 11.0));
		crumple += w * w * w * patch * 0.6;
	}
	// fine creases on the pose's folds, and tight little rings in the gathered cuff
	float fine = pose_folds(th, z, 1.8, nz, stretch);
	float bunch = exp(-(z - z0) / 6.0) * (1.0 + 0.9 * max(-tug, 0.0));
	float cuff = bunch * crease(z * 2.7 + 1.4 * sin(3.0 * th + seed) + 3.0 * nz);
	fold = crumple * (1.0 - 0.7 * stretch) + fine + 0.5 * cuff;
	dm = darn(th, z, de);
	// darning: a coarser grid of mending thread laid over the hole
	float dgrid = sin(th * 66.0) * sin(z * 12.0);
	return fade * 0.003 * mix(weave * (1.0 - 0.7 * dark), dgrid * 4.0, dm) + 0.11 * crumple * (1.0 - 0.7 * stretch) + 0.08 * fine + 0.06 * cuff + 0.03 * de;
}

void fragment() {
	float th = UV2.x;
	float z = UV2.y;
	// frayed hem: the weft has worn away along the edge, leaving loose warp threads
	float fr = z - z0;
	float fl = vnoise(vec3(cos(th) * 2.2, sin(th) * 2.2, seed));
	float fray = (1.0 - smoothstep(0.0, 0.08 + 0.4 * fl * fl, fr)) * (1.0 - v_inner * 0.5);

	// screen-space frame: how th and z change across the pixel (th wraps round the sleeve)
	vec2 dth = vec2(dFdx(th), dFdy(th));
	dth -= 6.28318 * round(dth / 6.28318);
	vec2 dzz = vec2(dFdx(z), dFdy(z));
	float fw = max(length(dth) * RF, length(dzz));       // cm per pixel
	float fade = 1.0 - smoothstep(0.025, 0.06, fw);         // threads too fine to draw: leave them out

	float fold, stretch, slub, dm, de;
	float h0 = cloth_h(th, z, fade, fold, stretch, slub, dm, de);

	float hem = v_hem;
	vec3 c = vec3(cos(th) * RF, sin(th) * RF, z);
	float up = clamp(normalize(wn).y, 0.0, 1.0);

	// thread colour varies thread to thread, and the dye (or the bleaching) is uneven
	float dye = vnoise(c * 0.15 + seed) * 0.6 + vnoise(c * 0.5 + seed) * 0.4;
	vec3 col = base * (0.9 + 0.06 * slub * fade * (1.0 - 0.6 * dark) + 0.14 * dye);
	// sun-faded where the folds face the sky (black wool turns brown-grey)
	col = mix(col, mix(col * 1.06, vec3(0.2, 0.17, 0.14), dark), up * 0.4);
	// rubbed pale on the crests of the crumples and creases, grime packed into the creases
	float crest = smoothstep(0.3, 0.9, fold) * 0.5;
	float crevice = smoothstep(-0.35, -0.85, fold) * 0.6 + clamp(-v_fold / 0.9, 0.0, 1.0) * 0.5;
	col = mix(col, mix(col * 1.12 + vec3(0.02), col * vec3(1.3, 1.25, 1.2), dark), crest * 0.45);
	col = mix(col, col * mix(vec3(0.72, 0.66, 0.56), vec3(0.6), dark), clamp(crevice, 0.0, 1.0) * mix(0.3, 0.3, dark));
	// worn thin over the point of the elbow and along the top of the forearm
	float rub = clamp(stretch * 1.4, 0.0, 1.0) * (0.6 + 0.4 * vnoise(c * 1.5));
	col = mix(col, col * mix(vec3(1.1), vec3(1.3, 1.25, 1.18), dark), rub * 0.6);
	// old stains with tide-lines: brown on the linen, white salt on the wool
	float sn = vnoise(c * vec3(0.7, 0.7, 0.55) + seed * 3.0) * 0.75 + vnoise(c * 2.4 + seed) * 0.25;
	sn *= smoothstep(0.3, 0.6, vnoise(c * 0.18 + seed + 40.0));   // only here and there
	float stain = smoothstep(0.66, 0.7, sn);
	float tide = smoothstep(0.65, 0.67, sn) - smoothstep(0.67, 0.71, sn);
	col = mix(col, mix(col * vec3(0.84, 0.76, 0.62), col * 1.08 + vec3(0.02, 0.019, 0.018) * tide, dark), stain * 0.35 + tide * 0.5);
	// grime and sweat toward the cuff, dust settled into it (soft, never paint-like specks)
	col = mix(col, mix(col * vec3(0.66, 0.58, 0.47), vec3(0.2, 0.17, 0.13), dark), hem * 0.55);
	float dust = (0.35 * up + 0.4 * hem + 0.3 * clamp(crevice, 0.0, 1.0)) * smoothstep(0.5, 0.9, vnoise(c * 1.7 + 11.0));
	col = mix(col, vec3(0.6, 0.5, 0.37), dust * mix(0.12, 0.06, dark));
	// the darn: mending thread a slightly different colour, stitched round the edge
	vec3 mend = mix(base * vec3(1.12, 1.08, 0.95), vec3(0.16, 0.12, 0.09), dark);
	col = mix(col, mend * (0.85 + 0.3 * slub), dm * 0.85);
	col = mix(col, col * 0.7, de * 0.5);
	// loose threads at the hem: separate, paler (dustier on the wool), the gaps between them dark
	float strand = smoothstep(0.2, 0.9, abs(sin(th * 60.0 + 3.0 * vnoise(vec3(cos(th) * 6.4, sin(th) * 6.4, 2.0)))));
	col = mix(col, mix(col * 1.15, col * 1.6 + vec3(0.02), dark) * mix(0.55, 1.0, strand), fray);

	// shade in the fold valleys and under the hanging cloth; the lining is in shadow
	float valley = clamp(-v_fold / 0.7, 0.0, 1.0);
	float ao = (1.0 - 0.6 * valley) * (1.0 - 0.25 * v_hang) * (1.0 - 0.3 * clamp(crevice, 0.0, 1.0));
	ao *= mix(1.0, 0.32, v_inner);
	if (debug == 1) {
		col = mix(col, vec3(1.0, 0.0, 0.0), v_inner);
		col = mix(col, vec3(0.0, 0.2, 1.0), v_band);
		ao = 1.0;
	}
	if (debug == 2 || debug == 4) col = base;
	if (debug == 5) col = vec3(dm + de, stain + tide, clamp(abs(fold), 0.0, 1.0));
	ALBEDO = col;
	AO = ao;
	AO_LIGHT_AFFECT = 0.55;
	// wool polishes a little where it is rubbed; linen stays matt
	ROUGHNESS = clamp(mix(0.93, 1.0, dark) - 0.22 * rub * dark - 0.05 * crest, 0.0, 1.0);
	SPECULAR = 0.2;
	// (no rim sheen or light-through glow: a lined sleeve with an arm in it lets no light
	// through, and both lit up its shaded side until it looked hazy and see-through)

	// bump the surface by the relief: its surface gradient from how it and the position
	// change across the pixel (Mikkelsen's bump mapping for unparametrised surfaces)
	vec3 N = normalize(NORMAL);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, N);
	vec3 r2 = cross(N, dpx);
	float det = dot(dpx, r1);
	float hx = dFdx(h0) * 0.21;     // relief is in cm; the world in 0.21 units per cm
	float hy = dFdy(h0) * 0.21;
	if (abs(det) > 1e-12 && debug != 2 && debug != 3)
		NORMAL = normalize(abs(det) * N - sign(det) * (hx * r1 + hy * r2));
}
"""

const JEWEL_SHADER := """
shader_type spatial;
// Old jewellery, worn every day for years. Metal is dented, scratched round and round,
// polished bright on its high points and dark with grime and tarnish in every crevice;
// lapis has gold flecks and pale veins; carnelian is banded and lit through; faience
// glaze is uneven, crazed and worn through to the pale core; leather cord is burnished on
// its crowns. Object space, in cm. Vertex COLOR (when use_vc): r = crevice / hidden side,
// g = a per-piece seed.
uniform int kind = 0;              // 0 metal, 1 lapis, 2 carnelian, 3 faience, 4 leather
uniform vec3 base = vec3(0.9, 0.7, 0.34);
uniform vec3 tarnish = vec3(0.1, 0.07, 0.04);
uniform float verdigris = 0.0;     // copper: green corrosion in the grime
uniform float rough = 0.35;
uniform float use_vc = 0.0;
uniform float band_r = 0.0;        // > 0: a band round the z axis (scratches run round it)
uniform float seed = 0.0;
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
float line(float v, float w) { return 1.0 - smoothstep(0.0, w, abs(v - 0.5)); }

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vc = mix(vec4(0.0, 0.0, 0.0, 1.0), COLOR, use_vc);
}

// fine scratches: on a band mostly running round it, elsewhere every which way
float scratches(vec3 x) {
	vec3 q = x;
	if (band_r > 0.0)
		q = vec3(atan(x.x, x.y) * band_r, x.z, length(x.xy));
	float s = line(vnoise(vec3(q.x * 0.5, q.y * 30.0, q.z * 4.0 + 1.0)), 0.035) * step(0.5, vnoise(vec3(q.x * 0.4, q.y * 3.0, 2.0)));
	s += 0.7 * line(vnoise(vec3(q.x * 3.0 + q.y * 11.0, q.y * 16.0 - q.x * 2.0, 3.0)), 0.03) * step(0.62, vnoise(x * 1.4 + 4.0));
	s += 0.5 * line(vnoise(x * vec3(22.0, 4.0, 9.0) + 6.0), 0.03) * step(0.7, vnoise(x * 2.0 + 8.0));
	return clamp(s, 0.0, 1.0);
}

float height(vec3 x) {
	float sd = seed + vc.g * 17.0;
	if (kind == 0)        // hammered, knocked about, scratched
		return 0.05 * vnoise(x * 2.4 + sd) + 0.016 * vnoise(x * 7.0 + sd) - 0.005 * scratches(x);
	if (kind == 1 || kind == 2)   // polished stone: gently uneven, fine scratches, the odd pit
		return 0.01 * vnoise(x * 3.0 + sd) - 0.0015 * scratches(x * 1.7) - 0.006 * smoothstep(0.86, 0.95, vnoise(x * 14.0 + sd));
	if (kind == 3)        // faience: lumpy hand-rolled bead, glaze lost in patches
		return 0.02 * vnoise(x * 5.0 + sd) + 0.008 * vnoise(x * 14.0 + sd) - 0.012 * smoothstep(0.63, 0.7, vnoise(x * 3.5 + sd * 3.0));
	// leather: grain and little cracks across the strands
	return 0.006 * vnoise(x * 18.0 + sd) - 0.008 * line(vnoise(x * 9.0 + sd), 0.06) * step(0.45, vnoise(x * 2.0 + 3.0));
}

void fragment() {
	float sd = seed + vc.g * 17.0;
	vec3 x = lp;
	float crev = vc.r;
	vec3 col;
	float metal = 0.0;
	float r = rough;
	float bump = 1.0;
	vec3 back = vec3(0.0);
	float spec = 0.5;
	if (kind == 0) {
		float scr = scratches(x);
		float low = smoothstep(0.5, 0.15, vnoise(x * 2.4 + sd));      // dents and pockets
		float grime = clamp(crev * 0.85 + low * 0.35, 0.0, 1.0) * (0.55 + 0.45 * vnoise(x * 9.0 + sd));
		float polish = (1.0 - crev) * smoothstep(0.45, 0.8, vnoise(x * 2.4 + sd));
		col = base * (0.86 + 0.18 * vnoise(x * 4.0 + sd));
		col = mix(col, col * vec3(0.92, 0.88, 0.84), scr * 0.5);
		// tarnish dulls everything a little and fills the crevices
		col = mix(col, tarnish, grime * 0.85 + 0.2);
		metal = 1.0 - grime * 0.8;
		float green = verdigris * smoothstep(0.45, 0.75, vnoise(x * 5.0 + 7.0)) * clamp(grime * 1.6, 0.0, 1.0);
		col = mix(col, vec3(0.22, 0.46, 0.36) * (0.8 + 0.4 * vnoise(x * 20.0)), green);
		metal *= 1.0 - green;
		r = rough + 0.22 * scr + 0.45 * grime - 0.14 * polish + 0.4 * green;
	} else if (kind == 1) {
		// lapis lazuli: mottled deep blue, pale calcite clouds and veins, pyrite flecks
		float m = vnoise(x * 3.0 + sd) * 0.6 + vnoise(x * 9.0 + sd) * 0.4;
		col = mix(vec3(0.015, 0.025, 0.14), vec3(0.07, 0.13, 0.44), m);
		float calc = smoothstep(0.72, 0.9, vnoise(x * 4.0 + sd + 9.0)) * 0.6 + line(vnoise(x * 6.0 + sd + 3.0), 0.025) * 0.35;
		col = mix(col, vec3(0.5, 0.53, 0.58), clamp(calc, 0.0, 1.0) * 0.4);
		float fleck = smoothstep(0.84, 0.9, vnoise(x * 34.0 + sd)) * step(0.4, vnoise(x * 6.0 + 2.0));
		col = mix(col, vec3(0.86, 0.7, 0.36), fleck);
		metal = fleck;
		float dull = smoothstep(0.5, 0.8, vnoise(x * 2.0 + 5.0));       // rubbed dull where it catches
		r = 0.34 + 0.25 * dull + 0.2 * scratches(x * 1.7) + 0.1 * fleck;
		bump = 0.6;
		spec = 0.3;
	} else if (kind == 2) {
		// carnelian: banded orange-red, cloudy, glowing where light comes through
		float b = sin(x.y * 26.0 + x.x * 8.0 + vnoise(x * 3.0 + sd) * 6.0) * 0.5 + 0.5;
		col = mix(vec3(0.32, 0.05, 0.015), vec3(0.72, 0.24, 0.07), b * 0.7 + 0.3 * vnoise(x * 7.0 + sd));
		float cloud = smoothstep(0.6, 0.85, vnoise(x * 5.0 + sd + 4.0));
		col = mix(col, vec3(0.78, 0.5, 0.36), cloud * 0.35);
		r = 0.18 + 0.25 * smoothstep(0.5, 0.8, vnoise(x * 2.0 + 1.0)) + 0.2 * scratches(x * 1.7);
		back = vec3(0.5, 0.1, 0.02);
		bump = 0.6;
	} else if (kind == 3) {
		// faience: blue-green glaze, uneven per bead, worn through to the gritty pale core
		vec3 glaze = mix(vec3(0.05, 0.36, 0.44), vec3(0.14, 0.42, 0.3), hash(vec3(sd, 1.0, 2.0)));
		glaze *= 0.8 + 0.4 * vnoise(x * 4.0 + sd);
		float thin = smoothstep(0.45, 0.75, vnoise(x * 5.0 + sd));      // thin glaze on the bumps
		glaze = mix(glaze, glaze * 1.5 + vec3(0.1, 0.1, 0.08), thin * 0.45);
		float craze = line(vnoise(x * 16.0 + sd), 0.04) * 0.6 + line(vnoise(x * 28.0 + sd + 2.0), 0.04) * 0.4;
		glaze *= 1.0 - 0.45 * craze;
		float worn = smoothstep(0.63, 0.7, vnoise(x * 3.5 + sd * 3.0));
		vec3 core = vec3(0.66, 0.58, 0.45) * (0.8 + 0.3 * vnoise(x * 30.0 + sd));
		core *= 1.0 - 0.6 * smoothstep(0.85, 0.92, vnoise(x * 40.0 + sd));   // black specks in the paste
		col = mix(glaze, core, worn);
		// a dusting of grime where it sits against the cord and in the hollows
		float dirt = clamp(crev * 0.7 + smoothstep(0.45, 0.2, vnoise(x * 5.0 + sd)) * 0.4, 0.0, 1.0);
		col = mix(col, vec3(0.2, 0.16, 0.11), dirt * 0.45);
		r = mix(0.32 + 0.2 * craze, 0.9, worn) + 0.25 * dirt;
	} else {
		// twisted leather: dark, burnished on the crowns of the strands, dry in between
		col = base * (0.8 + 0.4 * vnoise(x * 6.0 + sd));
		col = mix(col * 1.1 + vec3(0.015, 0.008, 0.0), col * 0.4, crev);
		col *= 1.0 - 0.35 * line(vnoise(x * 9.0 + sd), 0.06) * step(0.45, vnoise(x * 2.0 + 3.0));
		r = mix(0.5, 0.92, crev) + 0.1 * vnoise(x * 12.0);
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = clamp(r, 0.05, 1.0);
	SPECULAR = spec;
	BACKLIGHT = back;
	// relief from the height field, in object space
	float e = 0.004;
	float h0 = height(x);
	vec3 g = vec3(height(x + vec3(e, 0, 0)) - h0, height(x + vec3(0, e, 0)) - h0, height(x + vec3(0, 0, e)) - h0) / e;
	vec3 n = normalize(ln);
	n = normalize(n - (g - dot(g, n) * n) * bump);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
}
"""


func _init(s: Style, shoulder_pos: Vector3, right_dir: Vector3, is_left := false) -> void:
	style = s
	left = is_left
	shoulder = shoulder_pos
	person_right = right_dir.normalized()


func _ready() -> void:
	build_skeleton()
	build_skin()
	build_sleeve()
	build_jewellery()
	set_pose("relaxed", true)
	visible = false


# ---------------------------------------------------------------- building

func build_skeleton() -> void:
	skel = Skeleton3D.new()
	add_child(skel)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hand_mesh.json"))
	var globals: Array = []
	for b in meta.bones:
		var g := Transform3D(Basis(_v(b.x), _v(b.y), _v(b.z)), _v(b.head))
		globals.append(g)
		var i := skel.add_bone(b.name)
		bones[b.name] = i
		bone_len[i] = float(b.length)
		bone_r[i] = Vector2(float(b.get("r0", 1.0)), float(b.get("r1", 1.0)))
		var nm: String = b.name
		bone_flat[i] = THUMB_FLAT[int(nm.right(1))] if nm.begins_with("thumb") else (0.7 if nm == "forearm" else 0.86)
		if int(b.parent) >= 0:
			skel.set_bone_parent(i, int(b.parent))
			skel.set_bone_rest(i, (globals[int(b.parent)] as Transform3D).affine_inverse() * g)
		else:
			skel.set_bone_rest(i, g)
	# the upper arm continues from the elbow (not part of the hand mesh: only the sleeve uses it)
	var fa: int = bones["forearm"]
	var ua := skel.add_bone("upperarm")
	bones["upperarm"] = ua
	skel.set_bone_parent(ua, fa)
	skel.set_bone_rest(ua, Transform3D(Basis(), Vector3(0, 0, FOREARM_CM)))
	bone_len[ua] = UPPERARM_CM
	skel.reset_bone_poses()
	for i in skel.get_bone_count():
		rest_rot[i] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		pose_cur[i] = Vector2.ZERO
		pose_tgt[i] = Vector2.ZERO


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func build_skin() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hand_mesh.json"))
	var raw := FileAccess.get_file_as_bytes("res://assets/hand_mesh.bin")
	var L: Dictionary = meta.layout
	var f := func(name: String) -> PackedFloat32Array:
		var o: Array = L[name]
		return raw.slice(int(o[0]), int(o[0]) + int(o[1]) * 4).to_float32_array()
	var ii := func(name: String) -> PackedInt32Array:
		var o: Array = L[name]
		return raw.slice(int(o[0]), int(o[0]) + int(o[1]) * 4).to_int32_array()
	var n: int = meta.vertex_count
	var pos: PackedFloat32Array = f.call("pos")
	var nrm: PackedFloat32Array = f.call("nrm")
	var col: PackedFloat32Array = f.call("color")
	var uv: PackedFloat32Array = f.call("uv")
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n)
	norms.resize(n)
	cols.resize(n)
	uvs.resize(n)
	for k in n:
		verts[k] = Vector3(pos[3 * k], pos[3 * k + 1], pos[3 * k + 2])
		norms[k] = Vector3(nrm[3 * k], nrm[3 * k + 1], nrm[3 * k + 2])
		cols[k] = Color(col[4 * k], col[4 * k + 1], col[4 * k + 2], col[4 * k + 3])
		uvs[k] = Vector2(uv[2 * k], uv[2 * k + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_CUSTOM0] = f.call("custom0")
	arr[Mesh.ARRAY_BONES] = ii.call("bones")
	arr[Mesh.ARRAY_WEIGHTS] = f.call("weights")
	arr[Mesh.ARRAY_INDEX] = ii.call("index")
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKIN_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tattoo", 0 if style == Style.WHITE else (2 if left else 1))
	# the same man's other hand: the same skin, but every freckle, scar and crease elsewhere
	mat.set_shader_parameter("seed", (0.0 if style == Style.WHITE else 3.7) + (5.3 if left else 0.0))
	mat.set_shader_parameter("skin_tone", Vector3(0.33, 0.19, 0.1) if style == Style.WHITE else Vector3(0.26, 0.15, 0.08))
	skin_mat = mat
	_skinned(mesh, mat)


func _skinned(mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	mi.extra_cull_margin = 40.0
	return mi


## A loose sleeve from just behind the wrist to the shoulder, outside and lining joined by
## a rolled hem. The mesh only carries where each point is in the cloth (angle round the
## arm, distance up it); CLOTH_SHADER drapes it from the arm bones every frame.
func build_sleeve() -> void:
	var nseg := 72
	var rings := 130
	var z0 := 5.5          # hem: the sleeve is pushed up the forearm, clear of the wrist
	var z1 := FOREARM_CM + UPPERARM_CM + 30.0   # on past the shoulder, out of view
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nv := 0
	for layer in 2:
		for j in rings + 1:
			var zz := z0 + (z1 - z0) * pow(float(j) / rings, 1.35)
			for i in nseg + 1:
				var th := TAU * i / nseg
				_sleeve_vert(st, th, zz, float(layer), 0.0)
		var base := layer * (rings + 1) * (nseg + 1)
		for j in rings:
			for i in nseg:
				var a := base + j * (nseg + 1) + i
				var b := a + 1
				var c := a + nseg + 1
				var d := c + 1
				var idx := [a, b, c, b, d, c] if layer == 0 else [a, c, b, b, c, d]
				for x in idx:
					st.add_index(x)
	nv = 2 * (rings + 1) * (nseg + 1)
	# the rolled hem: a narrow band from the outside round to the lining
	for i in nseg + 1:
		var th := TAU * i / nseg
		_sleeve_vert(st, th, z0, 0.0, 1.0)
		_sleeve_vert(st, th, z0, 1.0, 1.0)
	for i in nseg:
		var a := nv + 2 * i
		for x in [a, a + 1, a + 2, a + 2, a + 1, a + 3]:
			st.add_index(x)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CLOTH_SHADER
	mat.shader = sh
	if style == Style.WHITE:
		mat.set_shader_parameter("base", Vector3(0.6, 0.56, 0.48))   # unbleached linen
		mat.set_shader_parameter("dark", 0.0)
		mat.set_shader_parameter("seed", 1.3)
	else:
		mat.set_shader_parameter("base", Vector3(0.06, 0.055, 0.05))
		mat.set_shader_parameter("dark", 1.0)
		mat.set_shader_parameter("seed", 4.6 if left else 7.9)
	mat.set_shader_parameter("z0", z0)
	mat.set_shader_parameter("elbow", FOREARM_CM)
	sleeve_mat = mat
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.extra_cull_margin = 40.0
	skel.add_child(mi)


func _sleeve_vert(st: SurfaceTool, th: float, zz: float, inner: float, band: float) -> void:
	var R := 5.0 + 0.035 * zz
	st.set_color(Color(inner, band, 0.0))
	st.set_uv(Vector2(th * R, zz))
	st.set_uv2(Vector2(th, zz))
	st.add_vertex(Vector3(-sin(th) * R, cos(th) * R, -zz))   # rest shape, only for culling


## Hand the cloth shader the arm's pose, gravity and how the loose cloth is swinging.
func _update_sleeve() -> void:
	if sleeve_mat == null:
		return
	var fa: int = bones["forearm"]
	var ua: int = bones["upperarm"]
	sleeve_mat.set_shader_parameter("skin_fa", skel.get_bone_global_pose(fa) * skel.get_bone_global_rest(fa).affine_inverse())
	sleeve_mat.set_shader_parameter("skin_ua", skel.get_bone_global_pose(ua) * skel.get_bone_global_rest(ua).affine_inverse())
	var inv := skel.global_transform.basis.inverse()
	sleeve_mat.set_shader_parameter("grav", (inv * Vector3.DOWN).normalized())
	sleeve_mat.set_shader_parameter("sway", inv * sway)
	# how the arm's pose creases the cloth: the elbow's bend and which side is its inside,
	# the forearm's twist against the upper arm, and which way the swinging cloth is tugged
	var fb := (skel.get_bone_global_pose(fa) * skel.get_bone_global_rest(fa).affine_inverse()).basis
	var ub := (skel.get_bone_global_pose(ua) * skel.get_bone_global_rest(ua).affine_inverse()).basis
	var A := (fb * Vector3(0, 0, -1)).normalized()     # wrist to elbow
	var B := (ub * Vector3(0, 0, -1)).normalized()     # elbow to shoulder
	var inside := B - A
	var efa := fb.inverse() * inside
	var eua := ub.inverse() * inside
	sleeve_mat.set_shader_parameter("bend", A.angle_to(B))
	sleeve_mat.set_shader_parameter("e_fa", Vector2(efa.x, efa.y).normalized())
	sleeve_mat.set_shader_parameter("e_ua", Vector2(eua.x, eua.y).normalized())
	var q := (ub.orthonormalized().inverse() * fb.orthonormalized()).get_rotation_quaternion()
	var tw := wrapf(2.0 * atan2(q.z, q.w), -PI, PI)
	sleeve_mat.set_shader_parameter("twist", (tw - twist_rest) / 1.5)
	sleeve_mat.set_shader_parameter("tug", clampf((inv * sway).dot(A) / 1.0, -1.0, 1.0))


## The hanging cloth is a damped pendulum: it trails behind when the hand speeds up
## and swings on a moment after it stops.
func _swing_cloth(delta: float) -> void:
	if delta <= 0.0:
		return
	var w := global_position
	var vel := (w - last_wrist) / delta
	if not swing_live or (w - last_wrist).length() > 3.0:
		vel = Vector3.ZERO
		last_vel = Vector3.ZERO
		sway = Vector3.ZERO
		sway_v = Vector3.ZERO
		swing_live = true
	var acc := (vel - last_vel) / delta
	last_wrist = w
	last_vel = vel
	sway_v += (-acc.limit_length(80.0) * 0.6 - sway * 55.0 - sway_v * 7.5) * delta
	sway += sway_v * delta
	# cloth only stretches so far: ease into the limit rather than stop dead at it
	var l := sway.length()
	if l > 0.25:
		sway *= (0.25 + 0.2 * tanh((l - 0.25) / 0.2)) / l


func _jewel(kind: int, base: Color, rough: float, opts := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = JEWEL_SHADER
	m.shader = sh
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("base", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("rough", rough)
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	return m


func _attach(bone_name: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	skel.add_child(ba)
	ba.bone_name = bone_name
	return ba


## Mesh from a grid of points (rows x cols), wrapping round in either direction. Each
## triangle is wound to face along the given normals (Godot's front faces are clockwise).
func _grid_mesh(p: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, rows: int, cols: int, wrap_r: bool, wrap_c: bool) -> ArrayMesh:
	var idx := PackedInt32Array()
	for i in (rows if wrap_r else rows - 1):
		for j in (cols if wrap_c else cols - 1):
			var a := i * cols + j
			var b := i * cols + (j + 1) % cols
			var d := ((i + 1) % rows) * cols + j
			var e := ((i + 1) % rows) * cols + (j + 1) % cols
			for t in [[a, b, d], [b, e, d]]:
				var x: int = t[0]
				var y: int = t[1]
				var z: int = t[2]
				if (p[y] - p[x]).cross(p[z] - p[x]).dot(n[x] + n[y] + n[z]) > 0.0:
					idx.append_array([x, z, y])
				else:
					idx.append_array([x, y, z])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = p
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Normals of a grid surface by central differences, turned away from `inside` (one point per row).
func _grid_normals(p: PackedVector3Array, rows: int, cols: int, inside: PackedVector3Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(p.size())
	for i in rows:
		for j in cols:
			var du := p[((i + 1) % rows) * cols + j] - p[((i - 1 + rows) % rows) * cols + j]
			var dv := p[i * cols + (j + 1) % cols] - p[i * cols + (j - 1 + cols) % cols]
			var v := du.cross(dv).normalized()
			if v.dot(p[i * cols + j] - inside[i]) < 0.0:
				v = -v
			n[i * cols + j] = v
	return n


## A hand-made finger ring round the z axis: inner radius r, width w, thickness t, a
## D-shaped section, worn thin underneath (where it rubs) and a little uneven all round.
## COLOR.r marks the inside that presses the skin and the edges beside it.
func _band_mesh(r: float, w: float, t: float, thin: float, sd: float) -> ArrayMesh:
	var na := 72
	var nb := 16
	var p := PackedVector3Array()
	var c := PackedColorArray()
	var inside := PackedVector3Array()
	for i in na:
		var a := TAU * i / na
		var wear := 1.0 - thin * pow(0.5 - 0.5 * cos(a), 2.0)
		var lump := 1.0 + 0.06 * sin(3.0 * a + sd) + 0.035 * sin(7.0 * a + 2.0 * sd)
		var radial := Vector3(sin(a), cos(a), 0.0)
		inside.append(radial * (r + 0.5 * t * wear))
		for j in nb:
			var b := TAU * j / nb
			var cb := cos(b)
			var sb := sin(b)
			var zc := 0.5 * w * wear * signf(cb) * pow(absf(cb), 0.55)
			var se := pow(absf(sb), 0.7 if sb > 0.0 else 0.25)
			var rc := r + t * wear * lump * 0.5 * (1.0 + signf(sb) * se)
			p.append(radial * rc + Vector3(0, 0, zc))
			c.append(Color(clampf(0.8 - sb, 0.0, 1.0), 0.0, 0.0))
	return _grid_mesh(p, _grid_normals(p, na, nb, inside), c, na, nb, true, true)


## An irregular, pebbly bead (lumpy, a little flattened along the string, holes at the ends).
func _bead_mesh(rad: float, rng: RandomNumberGenerator, sd: float) -> ArrayMesh:
	var rows := 11
	var cols := 16
	var p := PackedVector3Array()
	var c := PackedColorArray()
	var inside := PackedVector3Array()
	var ph := []
	for k in 6:
		ph.append(rng.randf() * TAU)
	var squash := rng.randf_range(0.7, 0.92)
	var ovl := rng.randf_range(0.9, 1.1)
	for i in rows:
		var v := lerpf(0.13, PI - 0.13, float(i) / (rows - 1))
		inside.append(Vector3(0, 0, -cos(v) * rad * squash * 0.5))
		for j in cols:
			var u := TAU * j / cols
			var d := Vector3(sin(v) * cos(u), sin(v) * sin(u), cos(v))
			var lump := 1.0 + 0.07 * sin(2.0 * u + ph[0]) * sin(v) + 0.05 * sin(3.0 * u + 2.0 * v + ph[1]) + 0.04 * sin(5.0 * u - v + ph[2]) \
				+ 0.05 * cos(2.0 * v + ph[3])
			p.append(Vector3(d.x * ovl, d.y / ovl, d.z * squash) * rad * lump)
			c.append(Color(0.25 * pow(absf(cos(v)), 3.0), sd, 0.0))
	return _grid_mesh(p, _grid_normals(p, rows, cols, inside), c, rows, cols, false, true)


## A tube of radius tr along a closed path; COLOR.r marks the side facing `crev_dir(i)`.
func _tube_mesh(path: PackedVector3Array, tr: float, crev: PackedVector3Array, sides := 7) -> ArrayMesh:
	var rows := path.size()
	var p := PackedVector3Array()
	var c := PackedColorArray()
	for i in rows:
		var tg := (path[(i + 1) % rows] - path[(i - 1 + rows) % rows]).normalized()
		var nx := tg.cross(Vector3(0, 0, 1)).normalized()
		var ny := tg.cross(nx).normalized()
		for j in sides:
			var a := TAU * j / sides
			var d := nx * cos(a) + ny * sin(a)
			p.append(path[i] + d * tr)
			c.append(Color(clampf(d.dot(crev[i]) * 0.9 + 0.2, 0.0, 1.0), 0.0, 0.0))
	return _grid_mesh(p, _grid_normals(p, rows, sides, path), c, rows, sides, true, true)


## Point on the wrist loop (forearm-bone space, cm), t in radians round the arm.
func _wrist_pt(t: float, rx: float, ry: float, dy: float, z: float) -> Vector3:
	return Vector3(sin(t) * rx, cos(t) * ry + dy, z)


## A finger ring on bone `bone_name`, `t` cm along it. Returns the attachment.
func _ring(bone_name: String, t: float, r: float, w: float, th: float, mat: Material, sd: float) -> BoneAttachment3D:
	var ba := _attach(bone_name)
	var mi := MeshInstance3D.new()
	mi.mesh = _band_mesh(r, w, th, 0.35, sd)
	mi.material_override = mat
	mi.position = Vector3(0, 0, t)
	ba.add_child(mi)
	return ba


## A bezel cup with a beaded (granulated) rim sitting on top of a ring at height y.
func _bezel(ba: BoneAttachment3D, at: Vector3, rad: float, h: float, mat: Material, grains: int) -> void:
	var setting := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = rad
	cyl.bottom_radius = rad * 0.9
	cyl.height = h
	cyl.radial_segments = 24
	setting.mesh = cyl
	setting.material_override = mat
	setting.position = at
	ba.add_child(setting)
	var gm := SphereMesh.new()
	gm.radius = 0.055
	gm.height = 0.11
	gm.radial_segments = 8
	gm.rings = 4
	for k in grains:
		var a := TAU * (k + 0.5 * (k % 2) * 0.1) / grains
		var g := MeshInstance3D.new()
		g.mesh = gm
		g.material_override = mat
		g.position = at + Vector3(cos(a) * rad * 1.02, h * 0.5, sin(a) * rad * 1.02)
		var sc := 0.85 + 0.3 * fposmod(sin(k * 12.9898) * 43758.5453, 1.0)
		g.scale = Vector3(sc, sc * 0.9, sc)
		ba.add_child(g)


func build_jewellery() -> void:
	if left:
		_left_jewellery()
		return
	if style == Style.WHITE:
		# an old gold band with a lapis cabochon in a granulated bezel, on the ring finger
		var gold := _jewel(0, Color(0.92, 0.7, 0.36), 0.38, {"tarnish": Vector3(0.12, 0.08, 0.04), "use_vc": 1.0, "band_r": 1.08, "seed": 2.0})
		var gold_b := _jewel(0, Color(0.92, 0.7, 0.36), 0.4, {"tarnish": Vector3(0.12, 0.08, 0.04), "seed": 5.0})
		var ba := _ring("ring_0", 1.3, 0.98, 0.42, 0.2, gold, 1.0)
		_bezel(ba, Vector3(0, 1.22, 1.3), 0.4, 0.2, gold_b, 18)
		var stone := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.36
		sp.height = 0.44
		sp.radial_segments = 24
		sp.rings = 12
		stone.mesh = sp
		stone.material_override = _jewel(1, Color(0.1, 0.15, 0.5), 0.2, {"seed": 3.0})
		stone.position = Vector3(0, 1.36, 1.3)
		stone.scale = Vector3(1.0, 1.0, 1.12)
		ba.add_child(stone)
		# a twisted leather cord round the wrist: three strands, knotted underneath
		var wrist := _attach("forearm")
		var leather := _jewel(4, Color(0.2, 0.12, 0.07), 0.7, {"use_vc": 1.0, "seed": 4.0})
		var n := 520
		var turns := 38.0
		for s in 3:
			var path := PackedVector3Array()
			var crev := PackedVector3Array()
			for i in n:
				var t := TAU * i / n
				var c := _wrist_pt(t, 3.12, 2.34, -0.1, 1.4)
				var out := Vector3(sin(t) / 3.12, cos(t) / 2.34, 0).normalized()
				var ph := t * turns + TAU * s / 3.0
				var off := out * cos(ph) * 0.075 + Vector3(0, 0, 1) * sin(ph) * 0.11
				path.append(c + off)
				crev.append(-off.normalized())
			var strand := MeshInstance3D.new()
			strand.mesh = _tube_mesh(path, 0.07, crev)
			strand.material_override = leather
			wrist.add_child(strand)
		var knot := MeshInstance3D.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		knot.mesh = _bead_mesh(0.26, rng, 0.3)
		knot.material_override = leather
		knot.position = _wrist_pt(PI * 0.92, 3.2, 2.42, -0.1, 1.4)
		knot.rotation = Vector3(0.4, 0.9, 0.2)
		wrist.add_child(knot)
	else:
		# a tarnished silver signet with a carnelian on the index finger, a thin copper band
		# gone green in its creases on the little finger
		var silver := _jewel(0, Color(0.66, 0.64, 0.6), 0.36, {"tarnish": Vector3(0.07, 0.065, 0.06), "use_vc": 1.0, "band_r": 1.15, "seed": 8.0})
		var silver_b := _jewel(0, Color(0.66, 0.64, 0.6), 0.4, {"tarnish": Vector3(0.07, 0.065, 0.06), "seed": 9.0})
		var ba := _ring("index_0", 1.2, 1.03, 0.5, 0.22, silver, 4.0)
		_bezel(ba, Vector3(0, 1.28, 1.2), 0.52, 0.16, silver_b, 0)
		ba.get_child(ba.get_child_count() - 1).scale = Vector3(1.0, 1.0, 1.22)
		var stone := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.48
		sp.height = 0.34
		sp.radial_segments = 24
		sp.rings = 12
		stone.mesh = sp
		stone.material_override = _jewel(2, Color(0.55, 0.12, 0.05), 0.25, {"seed": 6.0})
		stone.position = Vector3(0, 1.38, 1.2)
		stone.scale = Vector3(1.0, 1.0, 1.25)
		ba.add_child(stone)
		var copper := _jewel(0, Color(0.74, 0.43, 0.28), 0.42, {"tarnish": Vector3(0.12, 0.06, 0.035), "verdigris": 1.0, "use_vc": 1.0, "band_r": 0.9, "seed": 11.0})
		_ring("pinky_0", 1.0, 0.84, 0.26, 0.13, copper, 2.0)
		# a string of faience beads round the wrist, rolled by hand, no two alike, with a few
		# of carnelian and lapis among them, on a dark cord that shows between them
		var wrist := _attach("forearm")
		var rx := 3.15
		var ry := 2.35
		var dy := -0.2
		var z := 1.5
		# the loop, sampled finely, to space the beads along it by arc length
		var m := 720
		var acc := PackedFloat32Array([0.0])
		for i in m:
			var d := _wrist_pt(TAU * (i + 1) / m, rx, ry, dy, z) - _wrist_pt(TAU * i / m, rx, ry, dy, z)
			acc.append(acc[i] + d.length())
		var total: float = acc[m]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var radii: Array = []
		var used := 0.0
		while true:
			var rr := rng.randf_range(0.27, 0.37)
			if used + 2.0 * rr * 0.82 + 0.03 > total:
				break
			radii.append(rr)
			used += 2.0 * rr * 0.82 + 0.03
		var gap := 0.03 + (total - used) / radii.size()
		var faience := _jewel(3, Color(0.1, 0.45, 0.45), 0.35, {"use_vc": 1.0})
		var carnelian := _jewel(2, Color(0.55, 0.12, 0.05), 0.3, {"seed": 13.0})
		var lapis := _jewel(1, Color(0.1, 0.15, 0.5), 0.25, {"seed": 17.0})
		var s := 0.0
		var k := 0
		for rr in radii:
			s += rr * 0.82
			var ti := acc.bsearch(s)
			var t := TAU * clampf(float(ti) / m, 0.0, 1.0)
			var c := _wrist_pt(t, rx, ry, dy, z)
			var tg := (_wrist_pt(t + 0.01, rx, ry, dy, z) - _wrist_pt(t - 0.01, rx, ry, dy, z)).normalized()
			var up := Vector3(sin(t) / rx, cos(t) / ry, 0).normalized()
			var bead := MeshInstance3D.new()
			bead.mesh = _bead_mesh(rr, rng, rng.randf())
			bead.material_override = carnelian if k % 7 == 3 else (lapis if k % 11 == 8 else faience)
			bead.transform = Transform3D(Basis(up.cross(tg), up, tg).orthonormalized(), c + up * 0.02)
			bead.rotate_object_local(Vector3(0, 0, 1), rng.randf() * TAU)
			wrist.add_child(bead)
			s += rr * 0.82 + gap
			k += 1
		var cord_path := PackedVector3Array()
		var cord_crev := PackedVector3Array()
		for i in 240:
			var t := TAU * i / 240
			cord_path.append(_wrist_pt(t, rx, ry, dy, z))
			cord_crev.append(-Vector3(sin(t) / rx, cos(t) / ry, 0).normalized())
		var cord := MeshInstance3D.new()
		cord.mesh = _tube_mesh(cord_path, 0.05, cord_crev, 6)
		cord.material_override = _jewel(4, Color(0.09, 0.07, 0.05), 0.85, {"use_vc": 1.0, "seed": 19.0})
		wrist.add_child(cord)


## The other hand of the same man: a plain bronze band on the ring finger, worn thin and
## brown with handling, and a bangle of two silver wires twisted together, gone dark.
func _left_jewellery() -> void:
	var bronze := _jewel(0, Color(0.7, 0.5, 0.3), 0.45, {"tarnish": Vector3(0.1, 0.065, 0.035), "verdigris": 0.35, "use_vc": 1.0, "band_r": 1.0, "seed": 23.0})
	_ring("ring_0", 1.25, 0.95, 0.5, 0.17, bronze, 6.0)
	var wrist := _attach("forearm")
	var silver := _jewel(0, Color(0.66, 0.64, 0.6), 0.4, {"tarnish": Vector3(0.06, 0.055, 0.05), "use_vc": 1.0, "seed": 29.0})
	var n := 420
	var turns := 23.0
	var rx := 3.3
	var ry := 2.5
	for s in 2:
		var path := PackedVector3Array()
		var crev := PackedVector3Array()
		for i in n:
			var t := TAU * i / n
			# a bangle is a rigid ring: it hangs a little low on the wrist bone, off-centre
			var c := _wrist_pt(t, rx, ry, -0.35, 2.0)
			var out := Vector3(sin(t) / rx, cos(t) / ry, 0).normalized()
			var ph := t * turns + PI * s
			var off := out * cos(ph) * 0.07 + Vector3(0, 0, 1) * sin(ph) * 0.07
			path.append(c + off)
			crev.append(-off.normalized())
		var wire := MeshInstance3D.new()
		wire.mesh = _tube_mesh(path, 0.075, crev, 8)
		wire.material_override = silver
		wrist.add_child(wire)


# ---------------------------------------------------------------- posing

## The finger angles for a named hand shape, with the thumb solved where it must oppose.
func pose_dict(name: String) -> Dictionary:
	if pose_cache.has(name):
		return pose_cache[name]
	var p: Dictionary = POSES[name]
	var d := {}
	for fname in ["index", "middle", "ring", "pinky"]:
		var v: Array = p[fname]
		for s in 3:
			d[bones["%s_%d" % [fname, s]]] = Vector2(v[s], v[3] if s == 0 else 0.0)
	var t: Array = p["thumb"]
	d[bones["thumb_0"]] = Vector2(t[0], t[1])
	d[bones["thumb_1"]] = Vector2(t[2], 0)
	d[bones["thumb_2"]] = Vector2(t[3], 0)
	if THUMB_GOALS.has(name):
		var g: Array = THUMB_GOALS[name]
		_store(d, "thumb", solve_reach("thumb", g[0], g[1]))
	pose_cache[name] = d
	return d


## Blend toward a named hand shape (instantly if snap).
func set_pose(name: String, snap := false) -> void:
	set_pose_dict(pose_dict(name), snap)


func set_pose_dict(d: Dictionary, snap := false) -> void:
	for i in d:
		pose_tgt[i] = d[i]
	if snap:
		for i in pose_tgt:
			pose_cur[i] = pose_tgt[i]
		_apply_pose()
		_update_skin()


## Shape of the hand holding something of half-width r (cm) at GRASP_C: the index and
## middle pads press on its far side, the thumb pad on its near side, all facing it.
func grasp_pose(r: float) -> Dictionary:
	var key := "grasp_%.2f" % r
	if pose_cache.has(key):
		return pose_cache[key]
	var d: Dictionary = pose_dict("pinch").duplicate()   # ring and little finger tucked
	var fz := sqrt(maxf(r * r - 0.8, 0.25))
	_store(d, "index", solve_reach("index", GRASP_C + Vector3(0.85, 0.0, fz), GRASP_C))
	_store(d, "middle", solve_reach("middle", GRASP_C + Vector3(-0.95, 0.0, fz), GRASP_C))
	_store(d, "thumb", solve_reach("thumb", GRASP_C + Vector3(0.35, 0.0, -r), GRASP_C))
	pose_cache[key] = d
	_apply_pose()
	return d


## The same pinch as grasp_pose, but closed round a thing of half-width r at hand-local
## point c (e.g. a die being set down in the palm by thumb and fingers).
func grasp_at(c: Vector3, r: float) -> Dictionary:
	var key := "grasp_at_%.1f_%.1f_%.1f_%.2f" % [c.x, c.y, c.z, r]
	if pose_cache.has(key):
		return pose_cache[key]
	var d: Dictionary = pose_dict("pinch").duplicate()
	var fz := sqrt(maxf(r * r - 0.8, 0.25))
	_store(d, "index", solve_reach("index", c + Vector3(0.85, 0.0, fz), c))
	_store(d, "middle", solve_reach("middle", c + Vector3(-0.95, 0.0, fz), c))
	_store(d, "thumb", solve_reach("thumb", c + Vector3(0.35, 0.0, -r), c))
	pose_cache[key] = d
	_apply_pose()
	return d


## The pinch for taking something small off a flat surface, with the hand tipped down by
## `pitch` degrees: thumb and finger pads meet across it level with the surface (not
## along the tipped hand), so as they open or close they stay at its middle height and
## never dig their tips down.
func grasp_level(r: float, pitch: float) -> Dictionary:
	var key := "grasp_lv_%.2f_%.0f" % [r, pitch]
	if pose_cache.has(key):
		return pose_cache[key]
	var p := deg_to_rad(pitch)
	var a := Vector3(0.0, sin(p), cos(p))     # level and forward, in the tipped hand
	var c := GRASP_C
	var d: Dictionary = pose_dict("pinch").duplicate()
	var fz := sqrt(maxf(r * r - 0.8, 0.25))
	_store(d, "index", solve_reach("index", c + Vector3(0.85, 0.0, 0.0) + a * fz, c))
	_store(d, "middle", solve_reach("middle", c + Vector3(-0.95, 0.0, 0.0) + a * fz, c))
	_store(d, "thumb", solve_reach("thumb", c + Vector3(0.35, 0.0, 0.0) - a * r, c))
	pose_cache[key] = d
	_apply_pose()
	return d


## Where the thumb meets the index and middle fingers right now (hand-local cm): origin
## between the thumb pad and the finger pads, x from thumb toward fingers.
func pinch_frame() -> Transform3D:
	var t := _pad("thumb_2")
	var f := (_pad("index_2") + _pad("middle_2")) * 0.5
	var x := (f - t).normalized()
	var y0 := skel.get_bone_global_pose(bones["index_2"]).basis.y
	var y := (y0 - x * y0.dot(x)).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (t + f) * 0.5)


func _store(d: Dictionary, name: String, a: PackedFloat32Array) -> void:
	d[bones[name + "_0"]] = Vector2(a[0], a[1])
	d[bones[name + "_1"]] = Vector2(a[2], 0)
	d[bones[name + "_2"]] = Vector2(a[3], 0)


func _set_chain(ch: Array, a: PackedFloat32Array) -> void:
	skel.set_bone_pose_rotation(ch[0], rest_rot[ch[0]] * Quaternion(Vector3.RIGHT, deg_to_rad(a[0])) * Quaternion(Vector3.UP, deg_to_rad(a[1])))
	skel.set_bone_pose_rotation(ch[1], rest_rot[ch[1]] * Quaternion(Vector3.RIGHT, deg_to_rad(a[2])))
	skel.set_bone_pose_rotation(ch[2], rest_rot[ch[2]] * Quaternion(Vector3.RIGHT, deg_to_rad(a[3])))


## Bend a finger (or the thumb) so its pad presses on `target`, facing `center`:
## a small coordinate-descent search over its joint angles, within natural limits.
func solve_reach(name: String, target: Vector3, center: Vector3) -> PackedFloat32Array:
	var ch := [bones[name + "_0"], bones[name + "_1"], bones[name + "_2"]]
	var lim: Array = LIMITS["thumb" if name == "thumb" else "finger"]
	var lo := PackedFloat32Array([lim[0][0], lim[0][2], lim[1][0], lim[2][0]])
	var hi := PackedFloat32Array([lim[0][1], lim[0][3], lim[1][1], lim[2][1]])
	var cost := func(v: PackedFloat32Array) -> float:
		_set_chain(ch, v)
		var g := skel.get_bone_global_pose(ch[2])
		var pad := g * Vector3(0, -0.6, bone_len[ch[2]] * 0.7)
		var face := (center - pad).normalized()
		return pad.distance_to(target) + 1.5 * (1.0 - (-g.basis.y.normalized()).dot(face)) + 0.003 * (v[2] + v[3])
	var a := PackedFloat32Array([10.0, 0.0, 20.0, 10.0])
	var best: float = cost.call(a)
	var step := 16.0
	while step > 0.2:
		var improved := false
		for k in 4:
			for sgn in [1.0, -1.0]:
				var t := a.duplicate()
				t[k] = clampf(t[k] + sgn * step, lo[k], hi[k])
				var c: float = cost.call(t)
				if c < best - 0.0001:
					best = c
					a = t
					improved = true
		if not improved:
			step *= 0.5
	return a


func _apply_pose() -> void:
	for i in pose_cur:
		if i == bones["forearm"] or i == bones["upperarm"] or i == bones["hand"]:
			continue
		var v: Vector2 = pose_cur[i]
		skel.set_bone_pose_rotation(i, rest_rot[i] * Quaternion(Vector3.RIGHT, deg_to_rad(v.x)) * Quaternion(Vector3.UP, deg_to_rad(v.y)))


## Hand the skin shader the pose: every joint's bend (knuckle wrinkles), how straight each
## finger is (extensor tendons) and how full the veins on the back of the hand are.
## The veins behave like real ones: blood pools in a hand held low, so they show even at
## rest, and drains out of a lifted one within a second or two; gripping squeezes blood
## into them at once (they stand up within a fraction of a second and sink again as soon as
## the hand lets go), and sustained work leaves them a little fuller for a while, ebbing over
## ~15 s. Grip carries most of the swell so it always reads; the pump is only a baseline and
## the terms add up to at most 1, so nothing saturates. delta < 0 snaps the quick parts.
func _update_skin(delta := -1.0) -> void:
	if skin_mat == null:
		return
	var fl := PackedFloat32Array()
	fl.resize(18)
	for i in pose_cur:
		if i < 18:
			fl[i] = (pose_cur[i] as Vector2).x
	var grip := 0.0
	var ext := Vector4.ZERO
	var k := 0
	# index and middle do the gripping; the ring and little finger often just tuck away
	var weight := [0.35, 0.35, 0.15, 0.15]
	for f in ["index", "middle", "ring", "pinky"]:
		var a: float = fl[bones[f + "_0"]]
		var b: float = fl[bones[f + "_1"]]
		grip += clampf((a + b) / 170.0, 0.0, 1.0) * weight[k]
		ext[k] = 0.7 * smoothstep(18.0, -6.0, a) + 0.3 * smoothstep(14.0, -4.0, b)
		k += 1
	# effort is what the hand is doing (squeezing a die, holding a fist of dice), not the
	# shape it is in: it comes curled and pre-shaped to most things, so curl and a hard
	# stretch add only a little on top
	var spread := (ext.x + ext.y + ext.z + ext.w) / 4.0 * smoothstep(0.4, 0.9, (ext.x + ext.w) / 2.0)
	var want := clampf(effort + 0.15 * smoothstep(0.3, 0.9, grip) + 0.15 * spread, 0.0, 1.0)
	# how low the wrist is against the shoulder: down at the board the veins fill, lifted
	# (rattling and throwing the dice) they empty
	var drop_cm := (global_position.y - shoulder.y) / CM
	var want_low := smoothstep(4.0, -10.0, drop_cm)
	if delta < 0.0:
		tension = want
		low = want_low
	else:
		tension = lerpf(tension, want, 1.0 - exp(-(10.0 if want > tension else 6.0) * delta))
		low = lerpf(low, want_low, 1.0 - exp(-2.2 * delta))
		pump = clampf(pump + delta * (0.12 * tension - PUMP_EBB), 0.0, 1.0)
	# a raised hand drains even after hard work; a low one shows all of it
	var fill := 0.33 * low + 0.47 * tension + 0.2 * pump * (0.3 + 0.7 * low)
	skin_mat.set_shader_parameter("flex", fl)
	skin_mat.set_shader_parameter("extend", ext)
	skin_mat.set_shader_parameter("pump", clampf(fill, 0.0, 1.0))


## Grip point in hand-local cm: an explicit one while holding something, otherwise
## between the pads of thumb, index and middle finger in the current pose.
func grip_local() -> Vector3:
	if grip_override != null:
		return grip_override
	var it := _pad("index_2")
	var mt := _pad("middle_2")
	var tt := _pad("thumb_2")
	return it * 0.35 + mt * 0.2 + tt * 0.45 + Vector3(0, -0.4, 0)


func _pad(bname: String) -> Vector3:
	var i: int = bones[bname]
	var g := skel.get_bone_global_pose(i)
	return g * Vector3(0, -0.55, bone_len[i] * 0.85)


## Hand orientation: fingers along fwd (horizontal), tipped down by pitch degrees.
func hand_basis(fwd: Vector3, pitch: float, roll: float) -> Basis:
	var f := Vector3(fwd.x, 0, fwd.z).normalized().rotated(Vector3.UP, deg_to_rad(aim_yaw))
	var side := Vector3.UP.cross(f).normalized()     # thumb side of a right hand, palm down
	var p := deg_to_rad(pitch)
	var fz := f * cos(p) - Vector3.UP * sin(p)
	var up := fz.cross(side).normalized()
	var x := up.cross(fz).normalized()
	if left:
		# the left hand is the right one mirrored: its thumb is on the other side, and it
		# rolls thumb-up the other way
		return Basis(-x, up, fz).rotated(fz, deg_to_rad(-roll))
	return Basis(x, up, fz).rotated(fz, deg_to_rad(roll))


## Put the hand so its grip point is at `grip` (world), fingers pointing along fwd.
func place(grip: Vector3, fwd: Vector3, pitch := 20.0, roll := 0.0) -> void:
	grip_target = grip
	aim_fwd = fwd
	aim_pitch = pitch
	aim_roll = roll
	_place_now()


func _place_now() -> void:
	var b := hand_basis(aim_fwd, aim_pitch, aim_roll)
	var gl := grip_local() * CM
	var W := grip_target + shake - b * gl
	var T := Transform3D(b.scaled(Vector3(CM, CM, CM)), _reachable_wrist(W))
	# solid things in the way (the dice tray): the hand comes to rest on them, never in them
	if solid.is_valid():
		var push: Vector3 = solid.call(T, self)
		T.origin += push
		bump = push
	global_transform = T
	_solve_arm()
	_update_sleeve()
	placed.emit()


## Where the hand would be (world, scaled to cm) with grip point `gl` (hand-local cm) at `grip`.
func xf_at(grip: Vector3, fwd: Vector3, pitch: float, yaw: float, gl: Vector3, roll := 0.0) -> Transform3D:
	var y0 := aim_yaw
	aim_yaw = yaw
	var b := hand_basis(fwd, pitch, roll)
	aim_yaw = y0
	return Transform3D(b.scaled(Vector3(CM, CM, CM)), grip - b * (gl * CM))


## Where the grip point is right now (world).
func grip_world() -> Vector3:
	return global_transform * grip_local()


## Where the shoulder is with the wrist at W: the body leans in (or sits back) so the
## shoulder stays within reach, but only as far as a seated body can lean.
func _shoulder_for(W: Vector3, max_lean_cm := MAX_LEAN_CM) -> Vector3:
	var a := FOREARM_CM * CM
	var b := UPPERARM_CM * CM
	var S := shoulder
	S.x = lerpf(shoulder.x, W.x, lean)
	var to_s := S - W
	var d := clampf(to_s.length(), absf(a - b) + 0.5, (a + b) * REACH_FRAC)
	S = W + to_s.normalized() * d
	var off := S - shoulder
	if off.length() > max_lean_cm * CM:
		S = shoulder + off.normalized() * (max_lean_cm * CM)
	return S


## The nearest wrist position to W that the player can actually reach: past a nearly
## straight arm from the furthest-leaning shoulder, the hand stops.
func _reachable_wrist(W: Vector3, max_lean_cm := MAX_LEAN_CM) -> Vector3:
	var r := (FOREARM_CM + UPPERARM_CM) * CM * REACH_FRAC
	for i in 4:     # the lean depends a little on where the wrist ends up
		var S := _shoulder_for(W, max_lean_cm)
		if W.distance_to(S) <= r + 0.001:
			break
		W = S + (W - S).normalized() * r
	return W


## How far short of `grip` (at the same height, back toward the player) the hand has to
## stop: the nearest point it can bring its grip point to, held as place() would hold it
## (fingers along fwd, pitched and rolled), leaning no more than max_lean_cm.
func reachable(grip: Vector3, fwd: Vector3, pitch := 20.0, roll := 0.0, max_lean_cm := MAX_LEAN_CM) -> Vector3:
	var off := hand_basis(fwd, pitch, roll) * (grip_local() * CM)
	var ok := func(g: Vector3) -> bool:
		var W := g - off
		return _reachable_wrist(W, max_lean_cm).distance_to(W) < 0.001
	if ok.call(grip):
		return grip
	var home := Vector3(shoulder.x, grip.y, shoulder.z)
	var lo := 0.0    # fraction of the way back toward the player: lo too far, hi reachable
	var hi := 1.0
	for i in 16:
		var t := (lo + hi) * 0.5
		if ok.call(grip.lerp(home, t)):
			hi = t
		else:
			lo = t
	return grip.lerp(home, hi)


## Elbow and shoulder: two-bone IK from the wrist back to the (possibly leaning) shoulder.
func _solve_arm() -> void:
	var W := global_position
	var a := FOREARM_CM * CM
	var b := UPPERARM_CM * CM
	var S := _shoulder_for(W)
	var d := W.distance_to(S)
	var dir := (S - W).normalized()
	var pole := (person_right * 0.6 + Vector3.DOWN * 0.8).normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	var along := (d * d + a * a - b * b) / (2.0 * d)
	var h := sqrt(maxf(a * a - along * along, 0.0))
	var C := W + dir * along
	var E := C + pole * h
	# the elbow can swing anywhere round the wrist-shoulder line; a person keeps it clear of
	# the table (lifting it out to the side) rather than letting it sink into the sand, where
	# the sleeve would be crushed into a flat lump under it
	if E.y < ELBOW_MIN_Y and h > 0.01:
		var up_p := Vector3.UP - dir * dir.y
		if up_p.length() > 0.001:
			up_p = up_p.normalized()
			var lo := 0.0
			var hi := 1.0
			for i in 12:      # how far to turn the pole toward up: just enough
				var t := (lo + hi) * 0.5
				var pt := pole.slerp(up_p, t)
				if (C + pt * h).y < ELBOW_MIN_Y:
					lo = t
				else:
					hi = t
			pole = pole.slerp(up_p, hi)
			E = C + pole * h
	var inv := global_transform.basis.inverse()
	var fa: int = bones["forearm"]
	var ua: int = bones["upperarm"]
	var fb := _aim_basis((inv * (E - W)).normalized())
	skel.set_bone_pose_rotation(fa, fb.get_rotation_quaternion())
	var ub := _aim_basis((fb.inverse() * (inv * (S - E))).normalized(), fb.inverse() * Vector3.UP)
	skel.set_bone_pose_rotation(ua, ub.get_rotation_quaternion())


func _aim_basis(z: Vector3, up := Vector3.UP) -> Basis:
	var y := (up - z * up.dot(z))
	if y.length() < 0.01:
		y = Vector3.FORWARD
	y = y.normalized()
	return Basis(y.cross(z).normalized(), y, z)


func _process(delta: float) -> void:
	if not visible:
		swing_live = false
		pump = maxf(pump - PUMP_EBB * delta, 0.0)
		return
	var k := 1.0 - exp(-pose_rate * delta)
	for i in pose_tgt:
		pose_cur[i] = (pose_cur[i] as Vector2).lerp(pose_tgt[i], k)
	_apply_pose()
	_update_skin(delta)
	_place_now()
	_swing_cloth(delta)
	_update_sleeve()


# ---------------------------------------------------------------- contact
# The hand as a solid, for things it touches: each finger bone is the tapered, flattened
# capsule the mesh was built from, and the palm is its slab, pads and knuckles. All in
# hand-local cm, in the current pose.

## Set one finger bone's flex / spread now (and keep it there).
func put_bone(i: int, v: Vector2) -> void:
	pose_cur[i] = v
	pose_tgt[i] = v
	skel.set_bone_pose_rotation(i, rest_rot[i] * Quaternion(Vector3.RIGHT, deg_to_rad(v.x)) * Quaternion(Vector3.UP, deg_to_rad(v.y)))


## A finger bone as a capsule: [head, tail, r0, r1, back-of-finger axis, 1 - flat^2]
func capsule(i: int) -> Array:
	var g := skel.get_bone_global_pose(i)
	var L: float = bone_len[i]
	var r: Vector2 = bone_r[i]
	var f: float = bone_flat[i]
	return [g.origin, g * Vector3(0, 0, L), r.x, r.y, g.basis.y.normalized(), 1.0 - f * f]


## All finger and thumb capsules of the current pose, by digit name.
func capsules() -> Dictionary:
	var out := {}
	for d in DIGITS:
		var a: Array = []
		for s in 3:
			a.append(capsule(bones["%s_%d" % [d, s]]))
		out[d] = a
	return out


## Signed distance (cm) from a hand-local point to the palm (slab, thumb ball, heel, knuckles).
func palm_sdf(p: Vector3) -> float:
	var w := 3.3 + 0.95 * clampf(p.z / 9.0, 0.0, 1.0)
	var hh := 1.3 + 0.25 * clampf(1.0 - (p.x / w) * (p.x / w), 0.0, 1.0)
	var r := 1.1
	var q := Vector3(absf(p.x) - w + r, absf(p.y + 0.05) - hh + r, absf(p.z - 4.8) - 4.85 + r)
	var d := Vector3(maxf(q.x, 0), maxf(q.y, 0), maxf(q.z, 0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - r
	d = minf(d, _ellipsoid(p, THENAR[0], THENAR[1]))
	d = minf(d, _ellipsoid(p, HYPOTHENAR[0], HYPOTHENAR[1]))
	for k in KNUCKLES:
		d = minf(d, p.distance_to(k[0]) - k[1])
	return d


func palm_grad(p: Vector3) -> Vector3:
	var e := 0.04
	return Vector3(palm_sdf(p + Vector3(e, 0, 0)) - palm_sdf(p - Vector3(e, 0, 0)),
		palm_sdf(p + Vector3(0, e, 0)) - palm_sdf(p - Vector3(0, e, 0)),
		palm_sdf(p + Vector3(0, 0, e)) - palm_sdf(p - Vector3(0, 0, e))).normalized()


func _ellipsoid(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := (p - c) / r
	return (q.length() - 1.0) * minf(r.x, minf(r.y, r.z))


# knuckle balls at the base of each finger: [centre, radius]
const KNUCKLES := [[Vector3(2.85, 0.5, 9.45), 1.0], [Vector3(0.9, 0.6, 9.8), 1.03],
	[Vector3(-1.1, 0.5, 9.4), 0.95], [Vector3(-3.0, 0.3, 8.45), 0.82]]
