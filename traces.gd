class_name Traces
extends Node
## The record the table keeps of what has happened on it.
##
## One small picture of the table seen from above (AREA, PPU pixels per world unit), kept
## on the graphics card and never cleared:
##   r  how far the sand has been pressed down (-) or pushed up (+) from how the wind left
##      it (world units): a date stone's bed, the heel of a hand, the trail of a sleeve
##   g  how much of the wind-blown dust on the wood has been wiped off there (0..1)
##   b  dust pushed into a little bank at the edge of a wipe (0..1)
## The sand's shader reads r (main.gd, SAND_SHADER); the dust lying on the board, the
## strips and the plates reads g and b (DUST_SHADER here, laid on by main.gd's add_dust).
##
## The wind undoes all of it slowly. About once a second the picture is blurred a little,
## mostly along the wind, and fades a little: marks in the sand soften and fill over a few
## minutes (SAND_FILL), and dust settles again on wiped wood over rather longer
## (DUST_SETTLE), so that late in a game the board is cleanest where it was played on most.
##
## A picture cannot be read while it is drawn into, so there are two: `sim` draws the new
## state from `keep`, then `keep` copies it back, a frame apart.

const AREA := Rect2(-11.5, -6.5, 20.0, 14.0)     # the part of the table that keeps marks (x, z)
const PPU := 51.2                                # pixels per world unit (~0.9 mm of table each)
const SAND_FILL := 260.0        # (s) a mark in the sand is down to a third of itself after this long
const DUST_SETTLE := 540.0      # (s) and wiped wood has two thirds of its dust back
const SOFTEN_EVERY := 1.0       # (s) between the wind's passes over it
const MAX_MARKS := 24           # new marks drawn in one pass (the rest wait for the next)

const SAND := 0                 # kinds of mark
const DUST := 1

const SIM_SHADER := """
shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D prev : filter_linear, repeat_disable;
uniform vec2 px;                // one pixel (uv)
uniform vec4 area;              // the table it covers: corner (x, z), size
uniform bool reset = false;
uniform float soften = 0.0;     // how far the wind blurs it this pass (0 = not a wind pass)
uniform float keep_sand = 1.0;  // and what is left of each mark after it
uniform float keep_dust = 1.0;
uniform vec2 wind = vec2(0.94, 0.34);
uniform int count = 0;
uniform vec4 seg[24];           // each new mark: from (x, z) to (x, z)
uniform vec4 par[24];           // its half-width, depth or strength, kind, rim
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 c = texture(prev, UV);
	if (soften > 0.0) {
		// the wind smooths along its own way more than across it
		vec2 a = wind * px * 1.5;
		vec2 b = vec2(-wind.y, wind.x) * px;
		vec4 n = 0.3 * (texture(prev, UV + a) + texture(prev, UV - a))
			+ 0.2 * (texture(prev, UV + b) + texture(prev, UV - b));
		c.r = mix(c.r, n.r, soften) * keep_sand;
		c.g = mix(c.g, n.g, soften * 0.25) * keep_dust;
		c.b = mix(c.b, n.b, soften * 0.5) * keep_dust;
	}
	if (reset) c = vec4(0.0);
	vec2 w = area.xy + UV * area.zw;
	for (int i = 0; i < 24; i++) {
		if (i >= count) break;
		vec2 p0 = seg[i].xy;
		vec2 d = seg[i].zw - p0;
		float t = clamp(dot(w - p0, d) / max(dot(d, d), 1e-8), 0.0, 1.0);
		vec2 off = w - p0 - d * t;
		float r = length(off) / par[i].x;     // 1 at the mark's edge
		if (r > 2.2) continue;
		if (par[i].z < 0.5) {
			// pressed into sand: a flat-bottomed dent, never shallower than what was there,
			// and what it pushed aside heaped just outside it (but not into an older dent).
			// Nothing presses evenly, and sand does not give evenly: its edge wanders, it is
			// deeper here than there, and the heap round it comes and goes
			r *= 1.0 + 0.3 * (vnoise(w * 6.0 + 2.0) - 0.5) + 0.2 * (vnoise(w * 2.7) - 0.5);
			float deep = par[i].y * (0.7 + 0.6 * vnoise(w * 4.3 + 9.0));
			float was = c.r;
			c.r = min(c.r, -deep * (1.0 - smoothstep(0.35, 1.0, r)));
			if (r >= 1.0 && was > -0.15 * par[i].y)
				c.r = max(c.r, par[i].w * (0.3 + 1.4 * vnoise(w * 5.0 + 31.0)) * exp(-pow((r - 1.25) / 0.22, 2.0)));
		} else {
			// wiped off wood: clean under it, less so in streaks along the way it went, and
			// the dust it pushed banked unevenly along its edge
			r *= 1.0 + 0.16 * (vnoise(w * 13.0 + 4.0) - 0.5);
			float across = dot(d, d) > 1e-6 ? dot(off, normalize(vec2(-d.y, d.x))) : length(off);
			float streak = 0.72 + 0.28 * vnoise(vec2(across * 46.0, float(i) * 7.3 + seg[i].x));
			float wipe = par[i].y * streak * (1.0 - smoothstep(0.62, 1.0, r));
			float was = c.g;
			c.g = max(c.g, wipe);
			c.b *= 1.0 - wipe;
			if (was < 0.5 * par[i].y)
				c.b = max(c.b, par[i].w * (0.25 + 1.2 * vnoise(w * 11.0 + 17.0)) * exp(-pow((r - 1.03) / 0.08, 2.0)));
		}
	}
	COLOR = c;
}
"""

const KEEP_SHADER := """
shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D src : filter_nearest, repeat_disable;
void fragment() {
	COLOR = texture(src, UV);
}
"""

## Wind-blown sand lying on a piece of wood, drawn over it (a material_overlay): its own
## picture (dust_tex, straight alpha: tools/make_dust.py), less what has been wiped off it
## since, plus what the wiping banked up. `to_dust` takes a world point to the picture
## (x, z: -0.5..0.5 across it; y: world height above the wood's top).
const DUST_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D dust_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D marks : filter_linear, repeat_disable;
uniform vec4 area;
uniform mat4 to_dust;
const float FILM = 0.13;       // how much of the wood's colour the film hides
const float RUB = 0.13;        // and how much darker rubbed wood is
uniform float reach = 0.12;     // how far below the top it still lies (the rounded edges)
varying vec3 wpos;
varying vec3 dpos;
varying float up;
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dpos = (to_dust * vec4(wpos, 1.0)).xyz;
	up = normalize(MODEL_NORMAL_MATRIX * NORMAL).y;
}
void fragment() {
	vec2 uv = dpos.xz + 0.5;
	vec4 d = texture(dust_tex, uv);
	// it lies on what faces up: a little down the rounded edges, hardly at all on the sides
	float lies = smoothstep(0.35, 1.0, up * 0.5 + 0.5) * step(abs(dpos.y), reach)
		* step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 m = texture(marks, (wpos.xz - area.xy) / area.zw);
	// a wipe is never clean to the grain: some stays in the pores of the wood
	float grain = hash(floor(wpos.xz * 150.0));
	float wiped = clamp(m.g * (0.9 + 0.2 * grain), 0.0, 1.0);
	float bank = m.b * (0.5 + 0.5 * grain) * (1.0 - wiped);
	// besides the sand in the picture, the finest of it lies over everything as a thin
	// pale film, a little thicker in patches: it is what a wipe shows the wood through
	float film = FILM * (0.55 + 0.6 * vnoise(wpos.xz * 2.3 + 5.0) + 0.25 * vnoise(wpos.xz * 9.0)) * (0.8 + 0.4 * grain);
	float a = (d.a + film * (1.0 - d.a)) * (1.0 - wiped);
	vec3 sand = vec3(0.56, 0.38, 0.2);
	vec3 lying = mix(sand, d.rgb, d.a / max(d.a + film, 1e-4));
	// and wood that stones are pushed over is rubbed a shade darker than wood left alone
	float rub = RUB * wiped;
	ALBEDO = mix(vec3(0.05, 0.025, 0.012), mix(sand, lying, a / max(a + bank, 1e-4)), (a + bank) / max(a + bank + rub, 1e-4));
	ALPHA = clamp(a + bank + rub, 0.0, 1.0) * lies;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
}
"""

var sim: SubViewport
var keep: SubViewport
var sim_mat: ShaderMaterial
var queue: Array = []           # marks not yet drawn: [seg, par]
var stage := 0                  # 0 ready, 1 sim drawn (keep copies it next), 2 keep drawn
var since_soft := 0.0
var started := false
var made := {}                  # (tests) how many marks of each sort have been made


func _ready() -> void:
	var size := Vector2i(int(round(AREA.size.x * PPU)), int(round(AREA.size.y * PPU)))
	sim = _viewport(size, true)
	keep = _viewport(size, true)
	sim_mat = _fill(sim, SIM_SHADER)
	sim_mat.set_shader_parameter("prev", keep.get_texture())
	sim_mat.set_shader_parameter("px", Vector2.ONE / Vector2(size))
	sim_mat.set_shader_parameter("area", _area4())
	var km := _fill(keep, KEEP_SHADER)
	km.set_shader_parameter("src", sim.get_texture())


func _viewport(size: Vector2i, hdr: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.use_hdr_2d = hdr          # (half floats: the slow fading needs more than 8 bits)
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	return vp


func _fill(vp: SubViewport, code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	var r := ColorRect.new()
	r.size = Vector2(vp.size)
	r.material = m
	vp.add_child(r)
	return m


func _area4() -> Vector4:
	return Vector4(AREA.position.x, AREA.position.y, AREA.size.x, AREA.size.y)


## The picture itself, for a shader to read (see the top of this file).
func texture() -> Texture2D:
	return sim.get_texture()


## Something pressed into the sand from a to b (world): a dent `half` wide either side,
## `depth` deep, with what it pushed out heaped `rim` high round it.
func press(a: Vector3, b: Vector3, half: float, depth: float, rim := 0.0, what := "sand") -> void:
	queue.append([Vector4(a.x, a.z, b.x, b.z), Vector4(half, depth, SAND, rim)])
	made[what] = int(made.get(what, 0)) + 1


## Something drawn over dusty wood from a to b: `amount` (0..1) of the dust wiped off, in
## a streak `half` wide either side, and `bank` (0..1) of it left along the streak's edge.
func wipe(a: Vector3, b: Vector3, half: float, amount: float, bank := 0.0, what := "dust") -> void:
	queue.append([Vector4(a.x, a.z, b.x, b.z), Vector4(half, clampf(amount, 0.0, 1.0), DUST, bank)])
	made[what] = int(made.get(what, 0)) + 1


## The material that lays the dust picture `dust` over a piece of wood (as its meshes'
## material_overlay). The wood lies at `xf`; the picture covers `size` (x, z) of it,
## centred at `at` in its frame, which is also the height of its top.
func dust_material(dust: Texture2D, xf: Transform3D, at: Vector3, size: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DUST_SHADER
	m.shader = sh
	m.render_priority = 1
	m.set_shader_parameter("dust_tex", dust)
	m.set_shader_parameter("marks", sim.get_texture())
	m.set_shader_parameter("area", _area4())
	m.set_shader_parameter("to_dust", Transform3D(Basis.from_scale(Vector3(1.0 / size.x, 1.0, 1.0 / size.y)), Vector3.ZERO)
		* Transform3D(Basis(), -at) * xf.affine_inverse())
	return m


func _process(delta: float) -> void:
	since_soft += delta
	if stage == 1:
		keep.render_target_update_mode = SubViewport.UPDATE_ONCE
		stage = 2
		return
	if stage == 2:
		stage = 0
	var windy := since_soft >= SOFTEN_EVERY
	if started and queue.is_empty() and not windy:
		return
	var n := mini(queue.size(), MAX_MARKS)
	var seg: Array[Vector4] = []
	var par: Array[Vector4] = []
	for i in MAX_MARKS:
		seg.append(queue[i][0] if i < n else Vector4.ZERO)
		par.append(queue[i][1] if i < n else Vector4.ZERO)
	queue = queue.slice(n)
	sim_mat.set_shader_parameter("count", n)
	sim_mat.set_shader_parameter("seg", seg)
	sim_mat.set_shader_parameter("par", par)
	sim_mat.set_shader_parameter("reset", not started)
	sim_mat.set_shader_parameter("soften", 0.22 if windy else 0.0)
	sim_mat.set_shader_parameter("keep_sand", exp(-since_soft / SAND_FILL) if windy else 1.0)
	sim_mat.set_shader_parameter("keep_dust", exp(-since_soft / DUST_SETTLE) if windy else 1.0)
	if windy:
		since_soft = 0.0
	started = true
	sim.render_target_update_mode = SubViewport.UPDATE_ONCE
	stage = 1
