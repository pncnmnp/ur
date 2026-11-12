class_name Flies
extends Node3D
## Houseflies, drawn to Vidur's bowl of dates and to the sticky stones he spits out
## beside it.
##
## A fly is life size (about 7 mm long, a speck from where you sit): a dark grey thorax,
## a paler banded abdomen, big red-brown eyes, six thin black legs, and glassy wings that
## lie folded back over its body when it sits and are only a faint blur while it flies.
##
## It flies the way a fly does round food: short straight darts with sudden turns,
## hanging about over the bowl before it comes down, and buzzing only while it is in
## the air. It lands on top of a date, on the bowl's lip, or on one of the stones; while
## it sits it turns about and shuffles a little, then sooner or later goes up again of
## its own accord. It takes off the moment a hand comes at it, and how close a hand can
## get first depends on how fast it comes: a quick swipe sends it off from well away, a
## slow, lazy one gets much nearer. Startled, it shoots away, circles, and mostly comes
## straight back; now and then it gives up for a while and goes off out of sight.
##
## sitting() tells the game which flies are sat where, and for how long, so Vidur can
## decide whether to bother shooing them.

const CM := 0.21
enum { AWAY, FLY, LAND, SIT, FLEE }

var bowl: DateBowl
var pits: Array = []          # the date stones on the sand (shared with the game; it adds to it)
var hands: Array = []         # UrHand: everything a fly takes off from
var flies: Array = []         # [{...}] see _make_fly
var rng := RandomNumberGenerator.new()
var buzz_stream: AudioStreamWAV
var hand_prev := {}           # hand -> [points last frame]
var hand_speed := {}          # hand -> how fast it is moving now (world units / s)
var enabled := true           # (tests) false: they all stay away
# A fly is a now-and-then thing, not a fixture: one turns up once in a while (now and
# then with another), hangs about the dates for a minute or so, and goes; then none
# for a good while.
var first_visit := Vector2(120.0, 240.0)   # (s) before the first one turns up
var visit_gap := Vector2(300.0, 600.0)     # (s) from the last one leaving to the next visit
var visit_len := Vector2(30.0, 75.0)       # (s) the longest a fly stays on a visit
var pair_chance := 0.25                    # how often a second one comes along too
var next_visit := 0.0


func _init(b: DateBowl, pit_list: Array, hand_list: Array, n := 2, sd := 7331) -> void:
	bowl = b
	pits = pit_list
	hands = hand_list
	rng.seed = sd
	for i in n:
		flies.append({})


func _ready() -> void:
	next_visit = rng.randf_range(first_visit.x, first_visit.y)
	buzz_stream = _make_buzz()
	for i in flies.size():
		flies[i] = _make_fly(i)


# ---------------------------------------------------------------- the fly itself

const FLY_SHADER := """
shader_type spatial;
// One part of a housefly, drawn on a unit sphere (or a leg's cylinder) in its own space.
// part: 0 thorax, 1 abdomen, 2 head, 3 eye, 4 leg
uniform int part = 0;
uniform float shade = 1.0;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void fragment() {
	vec3 c = vec3(0.2, 0.2, 0.19);
	float rough = 0.62;
	float spec = 0.35;
	if (part == 0) {
		// ash grey, with four black stripes down the back
		float x = abs(lp.x);
		float st = 1.0 - smoothstep(0.07, 0.11, abs(x - 0.16)) ;
		st = max(st, 1.0 - smoothstep(0.08, 0.13, abs(x - 0.52)));
		st *= smoothstep(-0.1, 0.35, lp.y);
		c = mix(vec3(0.17, 0.165, 0.155), vec3(0.025), st);
		c *= mix(0.55, 1.0, smoothstep(-0.6, 0.2, lp.y));
	} else if (part == 1) {
		// yellowish grey, a dark line down the middle, darker bands across the segments,
		// and the shifting chequer of pale and dark patches
		float mid = 1.0 - smoothstep(0.06, 0.12, abs(lp.x));
		float seg = smoothstep(0.55, 0.9, fract(lp.z * 2.0 + 0.3));
		float chk = step(0.5, fract(lp.x * 1.6 + 0.25)) * 0.5 + step(0.5, fract(lp.z * 2.0)) * 0.5;
		c = vec3(0.14, 0.12, 0.085);
		c = mix(c, vec3(0.12, 0.1, 0.08), 0.35 * abs(chk - 0.5) * 2.0);
		c = mix(c, vec3(0.05), max(mid * smoothstep(-0.2, 0.4, lp.y), seg * 0.6));
		c *= mix(0.45, 1.0, smoothstep(-0.7, 0.3, lp.y));
		c = mix(c, vec3(0.03), smoothstep(0.7, 1.0, lp.z));
	} else if (part == 2) {
		// a dark head, silvery in the face between the eyes
		c = mix(vec3(0.04), vec3(0.3, 0.29, 0.26), smoothstep(0.0, -0.8, lp.z) * (1.0 - smoothstep(0.2, 0.5, abs(lp.x))));
	} else if (part == 3) {
		// the big compound eyes, dull red-brown, faceted
		float f = hash(floor(lp * 22.0));
		c = vec3(0.2, 0.04, 0.025) * (0.85 + 0.3 * f);
		rough = 0.4;
		spec = 0.6;
	} else {
		c = vec3(0.025);
		rough = 0.7;
	}
	// fine black bristles all over the body
	if (part < 3) {
		float h = hash(floor(lp * 55.0));
		c *= mix(1.0, 0.6, step(0.9, h));
	}
	// hairy, not shiny: dull and dark at the edges
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= mix(1.0, 0.55, rim * rim);
	ALBEDO = c * shade;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
"""

const WING_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never;
// A fly's wing: clear membrane, faintly smoky, with a few dark veins running out along
// it, and the thin-film shimmer of a wing in the sun. UV.x across it (0 front edge,
// 1 back), UV.y along it (0 root, 1 tip).
uniform float blur = 0.0;   // 1: beating too fast to see, only a haze
void fragment() {
	vec2 uv = UV;
	float v = 0.0;
	// the veins: the front edge, and three running out to the tip
	v = max(v, 1.0 - smoothstep(0.0, 0.08, uv.x));
	for (int k = 0; k < 3; k++) {
		float at = 0.22 + 0.2 * float(k) + 0.08 * uv.y * float(k);
		v = max(v, 1.0 - smoothstep(0.0, 0.035, abs(uv.x - at)));
	}
	v = max(v, (1.0 - smoothstep(0.0, 0.04, abs(uv.y - 0.55 - 0.1 * uv.x))) * step(0.2, uv.x) * step(uv.x, 0.65));
	v *= smoothstep(0.0, 0.08, uv.y);
	float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	vec3 film = 0.5 + 0.5 * cos(6.2832 * (rim * 1.3 + vec3(0.0, 0.33, 0.67)));
	vec3 c = mix(vec3(0.45, 0.44, 0.4), film, 0.25);
	ALBEDO = mix(c, vec3(0.1, 0.09, 0.08), v * (1.0 - blur));
	ALPHA = mix(mix(0.1, 0.75, v) + 0.12 * rim, 0.07, blur);
	ROUGHNESS = 0.3;
	SPECULAR = 0.45;
}
"""
var fly_shader: Shader
var wing_shader: Shader


func _part_mat(part: int, shade := 1.0) -> ShaderMaterial:
	if fly_shader == null:
		fly_shader = Shader.new()
		fly_shader.code = FLY_SHADER
	var m := ShaderMaterial.new()
	m.shader = fly_shader
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("shade", shade)
	return m


func _ellipsoid(r: Vector3, at: Vector3, m: Material, parent: Node3D) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 14
	s.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.scale = r
	mi.position = at
	parent.add_child(mi)
	return mi


## One leg: thin and black, out from under the thorax, up to the knee and down to the
## foot (cm, fly space).
func _leg(pts: Array, m: Material, parent: Node3D) -> void:
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var c := CylinderMesh.new()
		c.top_radius = 0.016 - 0.004 * k
		c.bottom_radius = 0.014 - 0.004 * k
		c.height = a.distance_to(b)
		c.radial_segments = 5
		c.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var y := (b - a).normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)


## A wing, root at the origin, the blade running back along +z out to side s (-1 or 1):
## a long rounded oval, widest past its middle (cm).
func _wing_mesh(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var rows: Array = []
	for k in n + 1:
		var a := PI * float(k) / n
		var z := 0.04 + 0.6 * (1.0 - cos(a)) * 0.5
		var w := 0.15 * sin(a) * (0.7 + 0.4 * (1.0 - cos(a)) * 0.5)
		rows.append([z, w])
	for k in n:
		var z0: float = rows[k][0]
		var z1: float = rows[k + 1][0]
		var w0: float = rows[k][1]
		var w1: float = rows[k + 1][1]
		var v0 := float(k) / n
		var v1 := float(k + 1) / n
		var quad := [[Vector3(0, 0, z0), Vector2(0, v0)], [Vector3(s * w0, 0, z0), Vector2(1, v0)],
			[Vector3(s * w1, 0, z1), Vector2(1, v1)], [Vector3(0, 0, z1), Vector2(0, v1)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(quad[idx][1])
			st.add_vertex(quad[idx][0])
	return st.commit()


func _make_fly(i: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Fly%d" % i
	add_child(root)
	var body := Node3D.new()           # the fly in cm, nose along -z, feet at y = 0
	body.scale = Vector3(CM, CM, CM)
	root.add_child(body)
	var shade := rng.randf_range(0.85, 1.1)
	_ellipsoid(Vector3(0.13, 0.12, 0.15), Vector3(0, 0.2, -0.05), _part_mat(0, shade), body)
	var abdo := _ellipsoid(Vector3(0.13, 0.1, 0.19), Vector3(0, 0.17, 0.19), _part_mat(1, shade), body)
	abdo.rotation.x = 0.12
	_ellipsoid(Vector3(0.12, 0.105, 0.07), Vector3(0, 0.19, -0.22), _part_mat(2, shade), body)
	var eye_m := _part_mat(3)
	var leg_m := _part_mat(4)
	for s in [-1.0, 1.0]:
		var e := _ellipsoid(Vector3(0.07, 0.095, 0.065), Vector3(0.068 * s, 0.205, -0.225), eye_m, body)
		e.rotation.y = s * 0.35
		for k in 3:
			var z := -0.11 + 0.08 * k
			var spread: float = [-0.65, 0.05, 0.75][k]
			var out := Vector3(s * cos(spread), 0, sin(spread))
			var hip := Vector3(0.04 * s, 0.12, z)
			_leg([hip, hip + out * 0.15 + Vector3(0, 0.06, 0), Vector3(hip.x, 0.0, hip.z) + out * 0.3,
				Vector3(hip.x, 0.0, hip.z) + out * 0.36], leg_m, body)
	if wing_shader == null:
		wing_shader = Shader.new()
		wing_shader.code = WING_SHADER
	var wing_m := ShaderMaterial.new()
	wing_m.shader = wing_shader
	var blur_m := ShaderMaterial.new()
	blur_m.shader = wing_shader
	blur_m.set_shader_parameter("blur", 1.0)
	var folded: Array = []
	var blur: Array = []
	for s in [-1.0, 1.0]:
		var wm := _wing_mesh(s)
		# at rest: back over the abdomen in a V, lying almost flat
		var w := MeshInstance3D.new()
		w.mesh = wm
		w.material_override = wing_m
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = Vector3(0.035 * s, 0.305, -0.06)
		w.rotation = Vector3(-0.1, s * 0.28, 0)
		body.add_child(w)
		folded.append(w)
		# in flight, beating ~200 times a second: no wing to see, only a faint haze either side
		var b := MeshInstance3D.new()
		b.mesh = wm
		b.material_override = blur_m
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = Vector3(0.05 * s, 0.3, -0.05)
		b.rotation = Vector3(0, s * 1.3, 0)
		b.scale = Vector3(1.5, 1, 1.05)
		b.visible = false
		body.add_child(b)
		blur.append(b)
	var p := AudioStreamPlayer3D.new()
	p.stream = buzz_stream
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.attenuation_filter_db = 0.0
	p.panning_strength = 0.8
	p.volume_db = -80.0
	add_child(p)
	root.visible = false
	return {"node": root, "body": body, "folded": folded, "blur": blur, "audio": p,
		"state": AWAY, "timer": INF, "stay": 0.0,
		"pos": Vector3.ZERO, "vel": Vector3.ZERO, "goal": Vector3.ZERO, "goal_t": 0.0,
		"yaw": 0.0, "yaw_to": 0.0, "spot": {}, "center": Vector3.ZERO, "loiter": 0.0,
		"sat": 0.0, "patience": 0.0, "fidget": 0.0, "pitch": 0.0, "fear": 0, "leaving": false, "descend": false}


## Fly sound: wings beating near 200 Hz, a rough buzz rich in overtones, wavering a little.
## A two-second loop (every component a whole number of cycles in it, so it never clicks).
func _make_buzz() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var ph := []
	for k in 12:
		ph.append(r.randf() * TAU)
	var noise := 0.0
	for i in n:
		var t := float(i) / rate
		# the wingbeat wanders in pitch: a slow wobble (whole cycles over the loop)
		var f0 := 196.0
		var wob := 0.9 * sin(TAU * 1.5 * t) + 0.5 * sin(TAU * 4.0 * t + 1.3)
		var phase := TAU * f0 * t + wob
		var s := 0.0
		for k in range(1, 12):
			s += sin(phase * k + ph[k]) / pow(k, 1.05) * (1.25 if k == 2 or k == 3 else 1.0)
		var am := 0.82 + 0.12 * sin(TAU * 3.0 * t + 0.4) + 0.06 * sin(TAU * 11.0 * t)
		noise = noise * 0.6 + r.randf_range(-1.0, 1.0) * 0.4
		var v := clampf((s * 0.32 + noise * 0.06) * am, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# ---------------------------------------------------------------- where they go

func _bowl_top() -> float:
	return bowl.global_position.y + 3.9 * CM


## Somewhere to land: on top of one of the dates near the top of the heap, on the bowl's
## lip, or on a date stone in the sand. Returns {kind, node, local (point in node space),
## up (world)} or {} if there is nothing to go to.
func _pick_spot(f: Dictionary) -> Dictionary:
	var choices: Array = []
	var live_pits: Array = pits.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	if not live_pits.is_empty():
		choices.append(["pit", 0.35])
	if bowl.remaining() > 0:
		choices.append(["date", 0.5])
	choices.append(["rim", 0.15 if bowl.remaining() > 0 else 0.4])
	for attempt in 8:
		var tot := 0.0
		for c in choices:
			tot += float(c[1])
		var x := rng.randf() * tot
		var kind: String = choices[choices.size() - 1][0]
		for c in choices:
			x -= float(c[1])
			if x <= 0.0:
				kind = c[0]
				break
		var spot := {}
		var node: Node3D
		var at: Vector3
		if kind == "pit":
			node = live_pits[rng.randi() % live_pits.size()]
			# on its top, near its middle (it lies on its side, ~2 cm long, 0.8 thick)
			at = node.global_position + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)) * CM
		elif kind == "date":
			var cand := bowl.candidates(Vector3.ZERO, 5)
			if cand.is_empty():
				continue
			node = cand[rng.randi() % cand.size()]
			var half: Vector2 = bowl.date_half(node)
			at = node.global_position + node.global_transform.basis.z.normalized() * rng.randf_range(-0.5, 0.5) * half.y * CM \
				+ Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)) * CM
		else:
			node = bowl
			var a := rng.randf() * TAU
			at = bowl.to_global(Vector3(cos(a) * 6.95, 3.86, sin(a) * 6.95) * CM)
		var hit: Variant = surface_at(_mesh_of(node), at)
		if hit == null or not _room_at(hit, node):
			continue
		spot = {"kind": kind, "node": node, "local": node.global_transform.affine_inverse() * (hit as Vector3)}
		# not on top of another fly
		var w := _spot_world(spot)
		var crowded := false
		for o in flies:
			if o != f and not o.is_empty() and (o.state == SIT or o.state == LAND) and (o.pos as Vector3).distance_to(w) < 0.25:
				crowded = true
		if not crowded:
			return spot
	return {}


# ---------------------------------------------------------------- solid things

var _faces := {}           # Mesh -> [faces (mesh space), longest edge]

## The mesh a fly stands on when it sits on `node`: a date's own fruit, a stone, or the
## bowl's clay.
func _mesh_of(node: Node3D) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	if node == bowl:
		for c in bowl.model.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override == bowl.bowl_mat:
				return c
	for c in node.find_children("*", "MeshInstance3D", true, false):
		return c
	return null


## Where a line straight down through `at` first meets the mesh's surface (world), or
## null if it misses it.
func surface_at(mi: MeshInstance3D, at: Vector3) -> Variant:
	if mi == null or mi.mesh == null:
		return null
	if not _faces.has(mi.mesh):
		var fs := mi.mesh.get_faces()
		var longest := 0.0
		for k in range(0, fs.size(), 3):
			longest = maxf(longest, maxf(fs[k].distance_to(fs[k + 1]), maxf(fs[k + 1].distance_to(fs[k + 2]), fs[k].distance_to(fs[k + 2]))))
		_faces[mi.mesh] = [fs, longest]
	var fs: PackedVector3Array = _faces[mi.mesh][0]
	var reach: float = _faces[mi.mesh][1]
	var inv := mi.global_transform.affine_inverse()
	var o := inv * (at + Vector3(0, 3.0, 0))
	var d := (inv.basis * Vector3.DOWN).normalized()
	var best: Variant = null
	var best_t := INF
	for k in range(0, fs.size(), 3):
		var v := fs[k] - o
		var t := v.dot(d)
		if v.length_squared() - t * t > reach * reach:
			continue
		var h: Variant = Geometry3D.ray_intersects_triangle(o, d, fs[k], fs[k + 1], fs[k + 2])
		if h != null:
			var tt := ((h as Vector3) - o).dot(d)
			if tt < best_t:
				best_t = tt
				best = h
	if best == null:
		return null
	return mi.global_transform * (best as Vector3)


## Is there room for a fly standing at `feet` on `own` (nothing else in its body, and a
## clear way straight down to it from above)?
func _room_at(feet: Vector3, own: Node3D) -> bool:
	for k in 8:
		var q := feet + Vector3(0, 0.25 * CM + k * 0.05, 0)
		# right down by its feet it may come close to things; higher up, where it hangs
		# before dropping onto the spot, it must be as clear as anywhere it flies
		var need := 0.12 * CM if k < 4 else (BODY_R + 0.05) * CM
		if bowl.clay_sdf(q) < need:
			return false
		if _date_clear(q, own if k < 4 else null) < need:
			return false
	return true


## How far a point is from the nearest date in the bowl, other than `skip` (world, < 0
## inside one), and the way out of it.
func _date_clear(w: Vector3, skip: Node3D, out := []) -> float:
	var c := bowl.global_transform.affine_inverse() * w / CM
	var best := INF
	for d in bowl.dates:
		if d.node == skip:
			continue
		var lv := bowl.live(d)
		for b in bowl._balls(lv[0], lv[1], d.sph):
			var dv: Vector3 = c - (b[0] as Vector3)
			var gap := dv.length() - float(b[1])
			if gap < best:
				best = gap
				if out.size() > 0:
					out[0] = bowl.global_transform.basis * (dv.normalized() if dv.length() > 1e-5 else Vector3.UP)
	return best * CM


## Keep a flying fly's body out of the clay, the dates, the date stones and the sand: it
## slides along whatever it meets, and loses the speed it had into it.
const BODY_R := 0.4             # (cm) round a fly's middle, wings and all
func _keep_clear(f: Dictionary, p: Vector3) -> Vector3:
	var m := BODY_R * CM
	for it in 2:
		var sd := bowl.clay_sdf(p)
		if sd < m:
			var g := bowl._clay_grad(p)
			p += g * (m - sd)
			_lose(f, g)
		var out := [Vector3.UP]
		var dc := _date_clear(p, null, out)
		if dc < m:
			p += (out[0] as Vector3) * (m - dc)
			_lose(f, out[0])
	for pit in pits:
		if not is_instance_valid(pit):
			continue
		var pc: Vector3 = (pit as Node3D).global_position
		var flat := Vector2(p.x - pc.x, p.z - pc.z).length()
		var top := pc.y + 0.45 * CM + m
		if flat < 1.3 * CM and p.y < top:
			p.y = top
			_lose(f, Vector3.UP)
	if p.y < 0.03 + m:
		p.y = 0.03 + m
		_lose(f, Vector3.UP)
	return p


func _lose(f: Dictionary, n: Vector3) -> void:
	var vn: float = (f.vel as Vector3).dot(n)
	if vn < 0.0:
		f.vel -= n * vn


## Fly by `step` (world), a little at a time so that nothing thin (the bowl's wall is
## half a centimetre) can be passed through between one frame and the next.
func _move(f: Dictionary, step: Vector3) -> void:
	var n := maxi(1, ceili(step.length() / (0.15 * CM)))
	var p: Vector3 = f.pos
	for k in n:
		p = _keep_clear(f, p + step / n)
	f.pos = p


func _spot_world(spot: Dictionary) -> Vector3:
	var n: Node3D = spot.node
	if not is_instance_valid(n):
		return Vector3.ZERO
	return n.global_transform * (spot.local as Vector3)


func _spot_valid(spot: Dictionary) -> bool:
	if spot.is_empty() or not is_instance_valid(spot.node):
		return false
	if spot.kind == "date":
		# taken out of the bowl (in his fingers, or eaten): not a date to sit on any more
		for d in bowl.dates:
			if d.node == spot.node:
				return true
		return false
	return true


## A point to dart to while hanging about over `c`: off to one side, a little above.
func _wander(c: Vector3, wide := 1.0) -> Vector3:
	var a := rng.randf() * TAU
	var r := rng.randf_range(0.4, 1.6) * wide
	var y := maxf(c.y, _bowl_top()) + rng.randf_range(0.35, 1.6) * wide
	return Vector3(c.x + cos(a) * r, y, c.z + sin(a) * r * 0.8)


## Where a fly comes from, or goes when it gives up: off past the bowl, out of view.
func _offstage() -> Vector3:
	var a := rng.randf_range(-1.2, 1.8)
	return bowl.global_position + Vector3(cos(a) * 9.0, rng.randf_range(3.0, 6.0), -absf(sin(a)) * 7.0 - 2.0)


# ---------------------------------------------------------------- each frame

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_track_hands(delta)
	_schedule(delta)
	for f in flies:
		_step(f, delta)
		_show(f, delta)


## How fast each hand is moving, and the points of it a fly would see coming.
func _hand_points(h: UrHand) -> Array:
	return [h.global_position, h.grip_world(), h.global_transform * Vector3(0, 0, 6.0)]


func _track_hands(delta: float) -> void:
	for h in hands:
		if not is_instance_valid(h) or not h.visible:
			hand_prev.erase(h)
			hand_speed[h] = 0.0
			continue
		var pts := _hand_points(h)
		var v := 0.0
		if hand_prev.has(h):
			for k in pts.size():
				v = maxf(v, (pts[k] as Vector3).distance_to(hand_prev[h][k]) / delta)
		# (a hand appearing from out of view has no speed to judge yet)
		hand_speed[h] = lerpf(float(hand_speed.get(h, 0.0)), minf(v, 30.0), 1.0 - exp(-20.0 * delta))
		hand_prev[h] = pts


## The nearest hand that is too close for comfort, or null. A fly lets a slow hand come
## much nearer than a fast one.
func _threat(at: Vector3) -> Variant:
	for h in hands:
		if not is_instance_valid(h) or not h.visible:
			continue
		var reach := 0.45 + 0.24 * float(hand_speed.get(h, 0.0))
		reach = minf(reach, 2.8)
		for q in _hand_points(h):
			if (q as Vector3).distance_to(at) < reach:
				return h
	return null


func _take_off(f: Dictionary, away_from: Variant) -> void:
	f.descend = false
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	if away_from != null:
		var hp: Vector3 = (away_from as UrHand).global_position
		dir = f.pos - hp
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
		f.fear += 1
		f.state = FLEE
		f.timer = rng.randf_range(0.35, 0.6)
		f.vel = (dir + Vector3(0, 1.1, 0)).normalized() * rng.randf_range(9.0, 13.0)
	else:
		f.state = FLY
		f.vel = (dir * 0.6 + Vector3(0, 1.0, 0)).normalized() * 3.0
		f.loiter = rng.randf_range(2.0, 7.0)
		f.goal = _wander(f.pos)
		f.goal_t = rng.randf_range(0.3, 0.8)
	f.spot = {}
	f.sat = 0.0


func _step(f: Dictionary, dt: float) -> void:
	if f.state != AWAY:
		f.stay -= dt
		if f.stay <= 0.0 and f.state == FLY and not f.leaving:
			# its visit is over: off it goes
			f.loiter = 99.0
			f.goal = _offstage()
			f.goal_t = 3.0
			f.leaving = true
	match f.state:
		AWAY:
			f.timer -= dt
			if f.timer > 0.0:
				return
			if not enabled:
				f.timer = 1.0
				return
			# in from out of view, toward the dates, for a while
			f.timer = INF
			if f != flies[0] and flies.all(func(o: Dictionary) -> bool: return o.state == AWAY):
				return              # (it only comes along with the other, not after it has gone)
			f.stay = rng.randf_range(visit_len.x, visit_len.y)
			f.pos = _offstage()
			f.center = bowl.global_position
			f.vel = (f.center - f.pos).normalized() * 6.0
			f.goal = _wander(f.center)
			f.goal_t = 1.5
			f.loiter = rng.randf_range(3.0, 8.0)
			f.state = FLY
		FLY:
			if not enabled:
				f.goal = _offstage()
				f.loiter = 99.0
			var t = _threat(f.pos)
			if t != null and (f.pos as Vector3).distance_to((t as UrHand).global_position) < 1.0:
				f.vel += ((f.pos as Vector3) - (t as UrHand).global_position).normalized() * 40.0 * dt
			f.loiter -= dt
			f.goal_t -= dt
			if f.goal_t <= 0.0 or (f.pos as Vector3).distance_to(f.goal) < 0.25:
				if not enabled and (f.pos as Vector3).distance_to(f.goal) < 0.5:
					_go_away(f, rng.randf_range(2.0, 5.0))
					return
				if f.loiter <= 0.0 and enabled:
					var spot := _pick_spot(f)
					if spot.is_empty():
						_go_away(f, rng.randf_range(10.0, 30.0))
						return
					f.spot = spot
					f.descend = false
					f.timer = 4.0                   # (if it cannot get down onto it by then, it gives up)
					f.state = LAND
				elif f.leaving:
					f.goal_t = 3.0                  # (on its way off: it keeps going)
				else:
					# a dart off somewhere else nearby, often at a sharp angle to the last
					f.goal = _wander(f.center, 1.0 + 0.3 * mini(f.fear, 3))
					f.goal_t = rng.randf_range(0.25, 0.9)
			_fly_toward(f, f.goal, rng.randf_range(3.0, 5.5), 9.0, dt)
		LAND:
			if not _spot_valid(f.spot):
				_take_off(f, null)
				return
			var w := _spot_world(f.spot)
			var t = _threat(w)
			if t != null:
				_take_off(f, t)
				return
			var above := w + Vector3(0, 0.3, 0)
			f.timer -= dt
			if f.timer <= 0.0 and not f.descend:
				_take_off(f, null)
				return
			if not f.descend:
				var d := (f.pos as Vector3).distance_to(above)
				_fly_toward(f, above, clampf(d * 3.0, 1.0, 5.0), 10.0, dt)
				# over it: from here it comes straight down (the way down is clear: see _room_at)
				f.descend = (f.pos as Vector3).distance_to(above) < 0.1
			else:
				if not _room_at(w, f.spot.node):
					_take_off(f, null)
					return
				# the last little way: slow, straight down onto it
				var to: Vector3 = w - f.pos
				var step := minf(to.length(), (0.2 + to.length() * 2.5) * dt)
				f.vel = to.normalized() * step / dt
				f.pos += to.normalized() * step
				if to.length() < 0.012:
					f.pos = w
					f.vel = Vector3.ZERO
					f.state = SIT
					f.center = w
					f.sat = 0.0
					f.timer = rng.randf_range(6.0, 40.0)      # how long it means to stay
					f.fidget = rng.randf_range(0.8, 3.0)
					f.patience = rng.randf_range(0.45, 1.3) if f.spot.kind != "pit" else rng.randf_range(9.0, 22.0)
		SIT:
			if not _spot_valid(f.spot):
				_take_off(f, null)
				return
			f.pos = _spot_world(f.spot)
			if not _room_at(f.pos, f.spot.node):
				_take_off(f, null)          # something slid onto it
				return
			var t = _threat(f.pos)
			if t != null:
				_take_off(f, t)
				return
			f.sat += dt
			f.timer -= dt
			if f.timer <= 0.0 or (f.stay <= 0.0 and f.sat > 4.0):
				# had enough of this one: up, round, and down somewhere else (or off)
				if rng.randf() < 0.2 or f.stay <= 0.0:
					_take_off(f, null)
					f.loiter = 99.0
					f.goal = _offstage()
					f.goal_t = 3.0
					f.state = FLY
					f.leaving = true
				else:
					_take_off(f, null)
				return
			f.fidget -= dt
			if f.fidget <= 0.0:
				f.fidget = rng.randf_range(0.7, 3.5)
				f.yaw_to = float(f.yaw) + rng.randf_range(-1.3, 1.3)
				if rng.randf() < 0.45:
					# a step or two across the top of it
					var dir := Vector3(sin(f.yaw_to), 0, cos(f.yaw_to)) * rng.randf_range(0.08, 0.2) * CM
					var n: Node3D = f.spot.node
					var lim := 0.35 if f.spot.kind == "pit" else 0.6
					var base: Vector3 = f.spot.get("base", f.spot.local)
					f.spot["base"] = base
					var hit: Variant = surface_at(_mesh_of(n), f.pos + dir)
					if hit != null and absf((hit as Vector3).y - f.pos.y) < 0.15 * CM and _room_at(hit, n):
						var moved: Vector3 = n.global_transform.affine_inverse() * (hit as Vector3)
						if (n.global_transform.basis * (moved - base)).length() < lim * CM:
							f.spot.local = moved
		FLEE:
			f.timer -= dt
			f.vel *= exp(-2.0 * dt)
			_move(f, f.vel * dt)
			if f.timer <= 0.0:
				# shaken off: mostly it comes straight back round; sometimes it gives up a while
				if rng.randf() < 0.3 + 0.15 * mini(f.fear, 4) or f.stay <= 0.0:
					f.fear = 0
					f.state = FLY
					f.loiter = 99.0
					f.goal = _offstage()
					f.goal_t = 3.0
					f.leaving = true
				else:
					f.state = FLY
					f.loiter = rng.randf_range(2.5, 9.0)
					f.goal = _wander(f.center, 1.4)
					f.goal_t = rng.randf_range(0.4, 1.0)
	if f.state == FLY and f.leaving:
		if (f.pos as Vector3).distance_to(f.goal) < 0.6:
			f.leaving = false
			_go_away(f, rng.randf_range(12.0, 45.0))


## Visits: when every fly is gone, wait out the gap, then send one in (and perhaps a
## second a little after it).
func _schedule(dt: float) -> void:
	for f in flies:
		if f.state != AWAY or f.timer < INF:
			return
	next_visit -= dt
	if next_visit > 0.0 or not enabled:
		return
	next_visit = rng.randf_range(visit_gap.x, visit_gap.y)
	for i in flies.size():
		if i == 0 or rng.randf() < pair_chance:
			flies[i].timer = 0.0 if i == 0 else rng.randf_range(4.0, 20.0)


## (Tests) Flies about nearly all the time, as many as there are.
func often() -> void:
	first_visit = Vector2(1.0, 3.0)
	visit_gap = Vector2(2.0, 6.0)
	visit_len = Vector2(80.0, 160.0)
	pair_chance = 1.0
	next_visit = 1.0


## Off out of view; its visit is over (the next one is _schedule's to send).
func _go_away(f: Dictionary, _wait := 0.0) -> void:
	f.state = AWAY
	f.timer = INF
	f.spot = {}
	f.leaving = false
	f.fear = 0


## Steer toward `to` at about `speed`, turning hard (a fly changes course almost at once).
func _fly_toward(f: Dictionary, to: Vector3, speed: float, agility: float, dt: float) -> void:
	var want: Vector3 = to - f.pos
	if want.length() > 0.001:
		want = want.normalized() * speed
	var k := 1.0 - exp(-agility * dt)
	f.vel = (f.vel as Vector3).lerp(want, k)
	# the little jinks of a fly's flight
	f.vel += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)) * 6.0 * dt
	_move(f, f.vel * dt)


func _show(f: Dictionary, dt: float) -> void:
	var node: Node3D = f.node
	var p: AudioStreamPlayer3D = f.audio
	if f.state == AWAY:
		node.visible = false
		if p.playing:
			p.stop()
		return
	node.visible = true
	var flying: bool = f.state != SIT
	var v: Vector3 = f.vel
	if flying and Vector2(v.x, v.z).length() > 0.3:
		f.yaw_to = atan2(-v.x, -v.z)
	f.yaw = lerp_angle(f.yaw, f.yaw_to, 1.0 - exp(-(14.0 if flying else 9.0) * dt))
	var pitch_to := clampf(-v.y * 0.08, -0.4, 0.4) + (0.15 if flying else 0.0)
	f.pitch = lerpf(f.pitch, pitch_to, 1.0 - exp(-10.0 * dt))
	node.global_transform = Transform3D(Basis(Vector3.UP, f.yaw) * Basis(Vector3.RIGHT, f.pitch), f.pos)
	for w in f.folded:
		(w as Node3D).visible = not flying
	for w in f.blur:
		(w as Node3D).visible = flying
		if flying:
			(w as Node3D).rotation.x = rng.randf_range(-0.35, 0.35)
	# the buzz: only in the air, louder as it works harder, nearer the ear
	if flying:
		if not p.playing:
			p.play(rng.randf() * 1.9)
		p.global_position = f.pos
		var cam := get_viewport().get_camera_3d()
		var dist := cam.global_position.distance_to(f.pos) if cam else 17.0
		var effort := clampf(v.length() / 8.0, 0.0, 1.0)
		var db := -24.0 + 6.0 * effort - 20.0 * log(maxf(dist, 1.0) / 17.0) / log(10.0)
		p.volume_db = lerpf(p.volume_db, db, 1.0 - exp(-25.0 * dt))
		p.pitch_scale = lerpf(p.pitch_scale, 0.94 + 0.14 * effort + 0.03 * sin(Time.get_ticks_msec() * 0.007 + float(f.goal_t)), 1.0 - exp(-12.0 * dt))
	elif p.playing:
		# it stops dead the moment it lands
		p.volume_db -= 400.0 * dt
		if p.volume_db < -60.0:
			p.stop()


# ---------------------------------------------------------------- for the game

## The flies sitting where he might mind: [{pos, kind ("date", "rim", "pit"), sat (s),
## patience (s: how long he lets this one sit before he bothers)}].
## Whether any fly is on the wing (flying about, landing or fleeing), not sitting or away.
func airborne() -> bool:
	for f in flies:
		if f.state == FLY or f.state == LAND or f.state == FLEE:
			return true
	return false


func sitting() -> Array:
	var out: Array = []
	for f in flies:
		if f.state == SIT:
			out.append({"pos": f.pos, "kind": f.spot.kind, "sat": f.sat, "patience": f.patience})
	return out


## (Tests) Fly i sits down now on a spot of the given kind ("date", "rim" or "pit").
func sit_on(i: int, kind: String) -> void:
	var f: Dictionary = flies[i]
	for k in 40:
		var s := _pick_spot(f)
		if not s.is_empty() and s.kind == kind:
			f.spot = s
			f.pos = _spot_world(s)
			f.center = f.pos
			f.vel = Vector3.ZERO
			f.state = SIT
			f.sat = 0.0
			f.timer = 1e9
			f.stay = 1e9
			f.fidget = 1e9
			f.patience = 0.8 if kind != "pit" else 12.0
			return
