class_name DiceGrip
extends RefCounted
## The dice in a player's hand, as solid things.
##
## While a hand gathers, rattles and casts the dice, every die it touches lives here, in
## the hand's own frame (hand-local cm). A die is either still lying in the tray (TABLE:
## an obstacle the hand must not pass through), pinched between finger pads (HELD: it
## moves exactly with the hand), or loose in the hand (LOOSE: a small rigid body that
## falls, rattles and is shoved about by the moving hand, but never passes through the
## palm, the fingers, the tray floor or another die).
##
## The hand is the solid the mesh was built from (UrHand.capsules / palm_sdf) and the die
## is its own rounded-tetrahedron distance field, so a contact is a real touch: skin on
## the die's surface, never a gap and never sunk in. Fingers that are being closed round
## the dice (drive) bend until they meet one and stop there, giving way if a die is
## pushed into them.

const CM := UrHand.CM
const TOL := 0.04              # how far skin may give under a die it presses on (cm)
const INV_I := 1.25            # a die's inverse moment of inertia per unit mass (1/cm^2)
const GRAV := 60.0 / UrHand.CM # the project's gravity (60 world units/s^2) in cm/s^2
const VMAX := 90.0             # cm/s, a die never rattles faster than this in the fist
const SQUEEZE := 1.6 * GRAV    # the most the fingers can pull a loose die toward its place (cm/s^2)

enum { TABLE, HELD, LOOSE, CARRIED }

var bodies: Array = []
var hand: UrHand = null
var floor_y := 0.0             # world height of the tray floor

# the die: g(x) = S * lse_K(n_k . x / S - H), x in die-local cm
var S := 1.0
var K := 14.0
var H := 0.4
var R := 2.5                   # centre to corner (cm)
var n0: Vector3
var n1: Vector3
var n2: Vector3
var n3: Vector3
var samples := PackedVector3Array()   # points on the die's surface (die-local cm)
var coarse := PackedVector3Array()    # fewer of them, for die against die

# per die, in hand-local cm
var mode: Array = [TABLE, TABLE, TABLE, TABLE]
var pos: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var rot: Array = [Basis(), Basis(), Basis(), Basis()]
var vel: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var spin: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var anchor: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var pull: Array = [0.0, 0.0, 0.0, 0.0]
var touching: Array = [false, false, false, false]
var carry_rel: Array = [Transform3D(), Transform3D(), Transform3D(), Transform3D()]   # CARRIED: place in the pinch
var follow: Array = [false, false, false, false]    # LOOSE but held in the pinch: drawn to it as it moves
var grip_cap: Array = [0.0, 0.0, 0.0, 0.0]         # how hard the fingers can draw it (cm/s^2)
var stirred: Array = [false, false, false, false]   # a die in the tray nudged by the hand this step
var up_l := Vector3.UP         # world up, hand-local
var tray := Transform3D()      # the tray's layout -> world, and its inner rectangle (x, z)
var tray_rect := Rect2()
var rim_top := 0.42            # world height of the rim boards' tops
var rim_t := 0.3               # their thickness (world)
var table_floor := 0.0         # tray floor height (world) before any throw has measured it
var palm_shell := PackedVector3Array()   # points over the palm's surface (hand-local cm)
var knock := 0.0               # strongest die-on-die knock this step (cm/s), for the sound
var acc_t := 0.0
const SIM_DT := 1.0 / 60.0
var moved := 0.0               # largest correction in the current solver pass (cm)

# fingers being closed round the dice: digit -> [open pose, shut pose, closure 0..1, speed /s]
var ctl := {}
var caps := {}                 # digit -> capsules of the current pose
var hand_p := Vector3.ZERO
var hand_v := Vector3.ZERO
var hand_a := Vector3.ZERO     # hand acceleration, hand-local cm/s^2
var fresh := true

# scratch results of the last contact query
var c_n := Vector3.ZERO        # unit normal, from the die toward the other thing
var c_pt := Vector3.ZERO       # contact point on the die's surface


func _init(dice: Array, corners: Array, corner_r: float, k: float, h: float) -> void:
	bodies = dice
	K = k
	H = h
	R = corner_r / CM
	var nn: Array = []
	for c in corners:
		nn.append(-(c as Vector3).normalized())
	n0 = nn[0]
	n1 = nn[1]
	n2 = nn[2]
	n3 = nn[3]
	S = 1.0
	S = R / ray(corners[0])
	# surface points: corners, along the edges and over the faces
	var cs: Array = []
	for c in corners:
		cs.append((c as Vector3).normalized())
	var dirs: Array = []
	var dirs_c: Array = []
	for a in 4:
		dirs.append(cs[a])
		dirs_c.append(cs[a])
		dirs.append(-(cs[a] as Vector3))           # face centre, opposite the corner
		dirs_c.append(-(cs[a] as Vector3))
		for b in range(a + 1, 4):
			for t in [0.25, 0.5, 0.75]:
				var d: Vector3 = (cs[a] as Vector3).lerp(cs[b], t).normalized()
				dirs.append(d)
				if t == 0.5:
					dirs_c.append(d)
	for a in 4:   # between each face centre and its corners
		for b in 4:
			if b != a:
				dirs.append((-(cs[a] as Vector3) + (cs[b] as Vector3) * 0.6).normalized())
	for d in dirs:
		samples.append(d * ray(d))
	for d in dirs_c:
		coarse.append(d * ray(d))


# ---------------------------------------------------------------- the die's shape

## Distance (cm) from a die-local point to the die's surface (w), and the outward
## direction there (xyz).
func die_eval(x: Vector3) -> Vector4:
	var q := x / S
	var a0 := K * (n0.dot(q) - H)
	var a1 := K * (n1.dot(q) - H)
	var a2 := K * (n2.dot(q) - H)
	var a3 := K * (n3.dot(q) - H)
	var m := maxf(maxf(a0, a1), maxf(a2, a3))
	var e0 := exp(a0 - m)
	var e1 := exp(a1 - m)
	var e2 := exp(a2 - m)
	var e3 := exp(a3 - m)
	var s := e0 + e1 + e2 + e3
	var g := (n0 * e0 + n1 * e1 + n2 * e2 + n3 * e3) / s
	return Vector4(g.x, g.y, g.z, S * (m + log(s)) / K)


## How far the surface is from die-local point o (inside the die) along direction d (cm).
func ray_from(o: Vector3, d: Vector3) -> float:
	var u := d.normalized()
	var lo := 0.0
	var hi := 3.0 * R
	for it in 24:
		var mid := (lo + hi) * 0.5
		if die_eval(o + u * mid).w < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## How far the surface is from the centre along a die-local direction (cm).
func ray(d: Vector3) -> float:
	var u := d.normalized()
	var lo := 0.0
	var hi := 3.0 * R
	for it in 24:
		var mid := (lo + hi) * 0.5
		if die_eval(u * mid).w < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


# ---------------------------------------------------------------- frames

## Start holding with this hand: every die is still in the tray, and frozen there so
## nothing can knock it about (only the hand moves dice now).
func begin(h: UrHand) -> void:
	hand = h
	ctl.clear()
	fresh = true
	floor_y = INF
	for i in 4:
		var b: RigidBody3D = bodies[i]
		var xf := b.global_transform
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.freeze = true
		b.global_transform = xf
		mode[i] = TABLE
		vel[i] = Vector3.ZERO
		spin[i] = Vector3.ZERO
		for s in samples:
			floor_y = minf(floor_y, (xf * (s * CM)).y)
	_refresh_table()
	if not hand.placed.is_connected(sync):
		hand.placed.connect(sync)


## Stop holding: the dice stay exactly where they are (still frozen) for the throw.
func end() -> void:
	if hand and hand.placed.is_connected(sync):
		hand.placed.disconnect(sync)
	sync()
	ctl.clear()
	hand = null
	for i in 4:
		mode[i] = TABLE


func active() -> bool:
	return hand != null


## Die i is pinched between thumb and fingers, exactly where it is, and from now on goes
## wherever the pinch goes (the fingers carry it).
func carry(i: int) -> void:
	if mode[i] == TABLE:
		_from_world(i)
	mode[i] = CARRIED
	vel[i] = Vector3.ZERO
	spin[i] = Vector3.ZERO
	carry_rel[i] = hand.pinch_frame().affine_inverse() * Transform3D(rot[i], pos[i])


func _follow_pinch() -> void:
	var F: Transform3D = Transform3D()
	var got := false
	for i in 4:
		if mode[i] == CARRIED:
			if not got:
				F = hand.pinch_frame()
				got = true
			var x: Transform3D = F * (carry_rel[i] as Transform3D)
			pos[i] = x.origin
			rot[i] = x.basis.orthonormalized()


## Die i is loose in the hand; the fingers holding it draw it toward `to` (hand-local cm).
func loosen(i: int, to: Vector3, k := 120.0) -> void:
	if mode[i] == TABLE:
		_from_world(i)
	mode[i] = LOOSE
	anchor[i] = to
	pull[i] = k
	follow[i] = false
	grip_cap[i] = SQUEEZE


## Die i is still held between thumb and fingers, but as a solid: the pinch draws it
## along firmly while the fingers move, and it is pushed by every part of the hand it
## touches instead of passing through them.
func pinch_loose(i: int) -> void:
	if mode[i] == TABLE:
		_from_world(i)
	mode[i] = LOOSE
	follow[i] = true
	pull[i] = 700.0
	grip_cap[i] = 8.0 * GRAV
	vel[i] = Vector3.ZERO


func hand_basis() -> Basis:
	return hand.global_transform.basis.orthonormalized()


func _from_world(i: int) -> void:
	var xf: Transform3D = (bodies[i] as Node3D).global_transform
	pos[i] = hand.global_transform.affine_inverse() * xf.origin
	rot[i] = (hand_basis().inverse() * xf.basis.orthonormalized()).orthonormalized()


func _refresh_table() -> void:
	if hand == null:
		return
	var inv := hand.global_transform.affine_inverse()
	var hbi := hand_basis().inverse()
	for i in 4:
		if mode[i] == TABLE:
			var xf: Transform3D = (bodies[i] as Node3D).global_transform
			pos[i] = inv * xf.origin
			rot[i] = (hbi * xf.basis.orthonormalized()).orthonormalized()


## Put the dice the hand has where the hand says they are (called whenever it moves).
func sync() -> void:
	if hand == null:
		return
	_follow_pinch()
	var T := hand.global_transform
	var hb := hand_basis()
	for i in 4:
		if mode[i] != TABLE:
			(bodies[i] as Node3D).global_transform = Transform3D(hb * (rot[i] as Basis), T * (pos[i] as Vector3))


# ---------------------------------------------------------------- contacts

## Finger capsule against die (dp, dr): how deep the flesh is in it (cm, < 0: a gap).
## Leaves the normal and the contact point in c_n / c_pt.
func cap_vs_die(cap: Array, dp: Vector3, dr: Basis) -> float:
	var a: Vector3 = cap[0]
	var ab: Vector3 = (cap[1] as Vector3) - a
	var l2 := maxf(ab.length_squared(), 1e-6)
	var t0 := clampf((dp - a).dot(ab) / l2, 0.0, 1.0)
	var r0: float = cap[2]
	if (a + ab * t0).distance_to(dp) > R + r0 + 0.3:
		return -1.0
	var ts := [0.0, 0.5, 1.0, t0]
	var best := INF
	var bt := 0.0
	var f := [0.0, 0.0, 0.0]
	for k in 4:
		var v := _cap_gap(cap, a + ab * float(ts[k]), float(ts[k]), dp, dr)
		if k < 3:
			f[k] = v
		if v < best:
			best = v
			bt = ts[k]
	# a parabola through the three samples finds the closest point between them
	var curv: float = f[2] - 2.0 * f[1] + f[0]
	if curv > 1e-5:
		var tv := clampf(0.5 - 0.25 * (f[2] - f[0]) / curv, 0.0, 1.0)
		var v := _cap_gap(cap, a + ab * tv, tv, dp, dr)
		if v < best:
			best = v
			bt = tv
	var g := _cap_gap(cap, a + ab * bt, bt, dp, dr)   # leaves c_n / c_pt at the best point
	return -g


func _cap_gap(cap: Array, x: Vector3, t: float, dp: Vector3, dr: Basis) -> float:
	var ev := die_eval(dr.transposed() * (x - dp))
	var n := dr * Vector3(ev.x, ev.y, ev.z)
	var nl := n.length()
	if nl > 1e-6:
		n /= nl
	var r: float = lerpf(cap[2], cap[3], t)
	var yy: float = n.dot(cap[4])
	var reff := r * sqrt(maxf(1.0 - float(cap[5]) * yy * yy, 0.0))
	c_n = n
	c_pt = x - n * ev.w
	return ev.w - reff


## Shove die i by `d` cm along n, as if pushed at hand-local point p: it moves and turns.
## A die lying in the tray can only slide over the leather and turn flat on it.
func _push(i: int, p: Vector3, n: Vector3, d: float) -> void:
	var arm := p - (pos[i] as Vector3)
	if mode[i] == TABLE:
		n = n - up_l * n.dot(up_l)
		if n.length() < 0.05:
			return
		stirred[i] = true
	var rn := arm.cross(n)
	var lam := d / (1.0 + rn.length_squared() * INV_I)
	pos[i] += n * lam
	moved = maxf(moved, absf(lam))
	var th := rn * (INV_I * lam * 0.7)
	if mode[i] == TABLE:
		th = up_l * th.dot(up_l)
	var ang := th.length()
	if ang > 1e-6:
		rot[i] = Basis(th / ang, ang) * (rot[i] as Basis)
	touching[i] = true


func _collide_hand(i: int) -> void:
	var dp: Vector3 = pos[i]
	for d in caps:
		for cap in caps[d]:
			var dr: Basis = rot[i]
			var pen := cap_vs_die(cap, dp, dr)
			if pen > 0.0:
				_push(i, c_pt, -c_n, pen)
				dp = pos[i]
	if hand.palm_sdf(dp) < R + 0.2:
		for s in samples:
			var p: Vector3 = (pos[i] as Vector3) + (rot[i] as Basis) * s
			var d := hand.palm_sdf(p)
			if d < 0.0:
				_push(i, p, hand.palm_grad(p), -d)


func _collide_floor(i: int, T: Transform3D, up: Vector3) -> void:
	var row := Vector3(T.basis.x.y, T.basis.y.y, T.basis.z.y)
	if T.origin.y + row.dot(pos[i]) - R * CM > floor_y:
		return
	for s in samples:
		var p: Vector3 = (pos[i] as Vector3) + (rot[i] as Basis) * s
		var wy := T.origin.y + row.dot(p)
		if wy < floor_y:
			_push(i, p, up, (floor_y - wy) / CM)


func _collide_pair(i: int, j: int) -> void:
	var pi: Vector3 = pos[i]
	var pj: Vector3 = pos[j]
	if pi.distance_to(pj) > 2.0 * R:
		return
	if mode[i] == TABLE and mode[j] == TABLE and not (stirred[i] or stirred[j]):
		return
	var wi := 0.0 if mode[i] == HELD or mode[i] == CARRIED else 1.0
	var wj := 0.0 if mode[j] == HELD or mode[j] == CARRIED else 1.0
	if wi + wj == 0.0:
		return
	var si := wi / (wi + wj)
	var sj := wj / (wi + wj)
	for pass_ in 2:
		var a := i if pass_ == 0 else j
		var b := j if pass_ == 0 else i
		var sa := si if pass_ == 0 else sj
		var sb := sj if pass_ == 0 else si
		var ra: Basis = rot[a]
		var pa: Vector3 = pos[a]
		var pb: Vector3 = pos[b]
		var rbt: Basis = (rot[b] as Basis).transposed()
		var r2 := R * R
		for s in samples:
			var p: Vector3 = pa + ra * s
			if p.distance_squared_to(pb) > r2:
				continue      # outside the other die's corners: cannot be in it
			var ev := die_eval(rbt * (p - pb))
			if ev.w < 0.0:
				var rb: Basis = rot[b]
				var n := (rb * Vector3(ev.x, ev.y, ev.z)).normalized()
				var rel: float = ((vel[a] as Vector3) - (vel[b] as Vector3)).dot(n)
				knock = maxf(knock, -rel)
				if sa > 0.0:
					_push(a, p, n, -ev.w * sa)
				if sb > 0.0:
					_push(b, p, -n, -ev.w * sb)


## How deep a digit is in any die (cm; < 0: how far it is from the nearest one).
func digit_pen(d: String) -> float:
	var worst := -INF
	for s in 3:
		var cap := hand.capsule(hand.bones["%s_%d" % [d, s]])
		for i in 4:
			worst = maxf(worst, cap_vs_die(cap, pos[i], rot[i]))
	return worst


# ---------------------------------------------------------------- fingers

## Close a digit from `open` toward `shut` (pose dicts) at `speed` (whole way per second).
## It closes joint by joint, the way a hand wraps round something: a joint stops where
## the part of the finger it moves meets a die and keeps that touch, while the joints
## beyond it go on curling round the die.
func drive(d: String, open: Dictionary, shut: Dictionary, speed: float, from := 0.0) -> void:
	ctl[d] = [open, shut, [from, from, from], speed]


func let_go(d: String) -> void:
	ctl.erase(d)


func let_go_all() -> void:
	ctl.clear()


## True once each named digit has closed as far as it will go (on a die, or all the way).
func closed(ds: Array) -> bool:
	for d in ds:
		if not ctl.has(d):
			continue
		var cs: Array = ctl[d][2]
		if minf(float(cs[0]), minf(float(cs[1]), float(cs[2]))) < 0.999 and digit_pen(d) < -0.02:
			return false
	return true


func _set_joint(d: String, st: Array, k: int, c: float) -> void:
	var i: int = hand.bones["%s_%d" % [d, k]]
	hand.put_bone(i, ((st[0] as Dictionary)[i] as Vector2).lerp((st[1] as Dictionary)[i], c))


## How deep the part of a digit from segment k out to its tip is in any die (cm).
func _pen_from(d: String, k: int) -> float:
	var worst := -INF
	for s in range(k, 3):
		var cap := hand.capsule(hand.bones["%s_%d" % [d, s]])
		for i in 4:
			worst = maxf(worst, cap_vs_die(cap, pos[i], rot[i]))
	return worst


func _drive_fingers(dt: float) -> void:
	for d in ctl:
		var st: Array = ctl[d]
		var cs: Array = st[2]
		for k in 3:
			var c: float = cs[k]
			var c1 := minf(1.0, c + float(st[3]) * dt)
			if c1 > c:
				_set_joint(d, st, k, c1)
				if _pen_from(d, k) <= TOL:
					cs[k] = c1
					continue
			_set_joint(d, st, k, c)
			if _pen_from(d, k) > TOL:
				# a die is pressing into the finger here: it gives way, a little at a time
				cs[k] = maxf(0.0, c - 4.0 * dt)
				_set_joint(d, st, k, cs[k])
				continue
			if c1 <= c:
				continue
			var lo := c
			var hi := c1
			for it in 5:
				var mid := (lo + hi) * 0.5
				_set_joint(d, st, k, mid)
				if _pen_from(d, k) <= TOL:
					lo = mid
				else:
					hi = mid
			cs[k] = lo
			_set_joint(d, st, k, lo)


# ---------------------------------------------------------------- simulation

func step(dt: float) -> void:
	if hand == null or dt <= 0.0:
		return
	# the hand only moves once a frame: simulate at about that rate
	acc_t += dt
	if acc_t < SIM_DT - 1e-4:
		return
	dt = minf(acc_t, 2.0 * SIM_DT)
	acc_t = 0.0
	var T := hand.global_transform
	var hb := hand_basis()
	var hbi := hb.inverse()
	# how the hand is moving: in its frame, a loose die feels that as a push the other way
	var hv := (T.origin - hand_p) / dt
	if fresh:
		hv = Vector3.ZERO
		hand_v = Vector3.ZERO
		fresh = false
	var ha := (hv - hand_v) / dt
	hand_p = T.origin
	hand_v = hv
	hand_a = hand_a.lerp((hbi * ha / CM).limit_length(4000.0), 0.5)
	var g := hbi * Vector3.DOWN * GRAV
	var up := hbi * Vector3.UP
	up_l = up
	_refresh_table()
	_drive_fingers(dt)
	_follow_pinch()
	caps = hand.capsules()
	var loose := []
	var near := []      # dice in the tray within reach of the hand
	for i in 4:
		touching[i] = false
		stirred[i] = false
		if mode[i] == LOOSE:
			loose.append(i)
		elif mode[i] == TABLE and (pos[i] as Vector3).distance_to(UrHand.PALM_C) < 16.0:
			near.append(i)
	knock = 0.0
	if loose.is_empty() and near.is_empty():
		sync()
		return
	var p0 := {}
	var r0 := {}
	var pf := Vector3.INF
	for i in loose:
		if follow[i]:
			if pf == Vector3.INF:
				pf = hand.pinch_frame().origin
			anchor[i] = pf
		var to: Vector3 = (anchor[i] as Vector3) - (pos[i] as Vector3)
		var k: float = pull[i]
		# the fingers draw it in, but only so hard
		var acc: Vector3 = g - hand_a + (to * k).limit_length(grip_cap[i]) - (vel[i] as Vector3) * (2.0 * sqrt(k) * 0.6)
		vel[i] = ((vel[i] as Vector3) + acc * dt).limit_length(VMAX)
		p0[i] = pos[i]
		r0[i] = rot[i]
		pos[i] = (pos[i] as Vector3) + (vel[i] as Vector3) * dt
		var w: Vector3 = spin[i]
		if w.length() > 1e-4:
			rot[i] = Basis(w.normalized(), w.length() * dt) * (rot[i] as Basis)
	for it in 4:
		moved = 0.0
		for i in loose:
			_collide_hand(i)
			_collide_floor(i, T, up)
		for i in near:
			_collide_hand(i)
		for a in 4:
			for b in range(a + 1, 4):
				_collide_pair(a, b)
		if it == 3 or moved < 0.002:
			# dice last: pushed apart, they must not have been pushed into the hand
			for i in loose:
				_collide_hand(i)
			break
		for i in near:
			if stirred[i]:
				_keep_in_tray(i, T, hb)
	# nudged dice in the tray: put them where they slid to
	for i in near:
		if stirred[i]:
			var b: RigidBody3D = bodies[i]
			b.global_transform = Transform3D(hb * (rot[i] as Basis).orthonormalized(), T * (pos[i] as Vector3))
	for i in loose:
		var v: Vector3 = ((pos[i] as Vector3) - (p0[i] as Vector3)) / dt
		var q := ((rot[i] as Basis) * (r0[i] as Basis).inverse()).get_rotation_quaternion()
		var w := q.get_axis() * q.get_angle() / dt if q.get_angle() > 1e-5 else Vector3.ZERO
		if touching[i]:
			v *= 0.9      # skin and bone: rough, and soaks up the knocks
			w *= 0.8
		vel[i] = v.limit_length(VMAX)
		spin[i] = w.limit_length(40.0)
		rot[i] = (rot[i] as Basis).orthonormalized()
	sync()


## A die slid by the hand stops against the tray's rim boards.
func _keep_in_tray(i: int, T: Transform3D, hb: Basis) -> void:
	var ti := tray.affine_inverse()
	var w := T * (pos[i] as Vector3)
	var rb: Basis = hb * (rot[i] as Basis)
	var over := Vector3.ZERO
	for s in coarse:
		var l := ti * (w + rb * (s * CM))
		over.x = maxf(over.x, l.x - tray_rect.end.x) if l.x > tray_rect.end.x else minf(over.x, l.x - tray_rect.position.x) if l.x < tray_rect.position.x else over.x
		over.z = maxf(over.z, l.z - tray_rect.end.y) if l.z > tray_rect.end.y else minf(over.z, l.z - tray_rect.position.y) if l.z < tray_rect.position.y else over.z
	if over != Vector3.ZERO:
		var back := tray.basis * (-over)
		pos[i] = (pos[i] as Vector3) + hb.inverse() * back / CM


# ---------------------------------------------------------------- the tray as a solid
# The hand is as solid as the dice: the leather floor and the four rim boards stop it.
# Whatever the hand is doing (reaching, pinching, closing round the dice, rattling them),
# its fingers, palm, knuckles and wrist, and the dice it holds, rest on the leather and
# ride over the wood instead of sinking into them.

## Signed distance (world) from a world point to the tray's solid parts: the floor slab
## (below the leather, as far as the rim's outer edge) and the rim boards round it.
func tray_sd(q: Vector3) -> float:
	var l := tray.affine_inverse() * q
	var c := tray_rect.get_center()
	var px := absf(l.x - c.x)
	var pz := absf(l.z - c.y)
	var fy := floor_y if floor_y < INF else table_floor
	var hx := tray_rect.size.x * 0.5
	var hz := tray_rect.size.y * 0.5
	# outer block: the rim's outer edge, from far below the floor to the rim's top
	var oy0 := fy - 40.0     # (deep: its underside is never the nearest way out)
	var ob := Vector3(px - hx - rim_t, absf(l.y - (oy0 + rim_top) * 0.5) - (rim_top - oy0) * 0.5, pz - hz - rim_t)
	var outer := Vector3(maxf(ob.x, 0.0), maxf(ob.y, 0.0), maxf(ob.z, 0.0)).length() + minf(maxf(ob.x, maxf(ob.y, ob.z)), 0.0)
	# minus the well the dice lie in: the inner rectangle, open upward from the leather
	var ib := Vector3(px - hx, fy - l.y, pz - hz)
	var inner := Vector3(maxf(ib.x, 0.0), maxf(ib.y, 0.0), maxf(ib.z, 0.0)).length() + minf(maxf(ib.x, maxf(ib.y, ib.z)), 0.0)
	return maxf(outer, -inner)


## Outward direction of the tray's surface nearest world point q.
func tray_n(q: Vector3) -> Vector3:
	var e := 0.004
	var n := Vector3(tray_sd(q + Vector3(e, 0, 0)) - tray_sd(q - Vector3(e, 0, 0)),
		tray_sd(q + Vector3(0, e, 0)) - tray_sd(q - Vector3(0, e, 0)),
		tray_sd(q + Vector3(0, 0, e)) - tray_sd(q - Vector3(0, 0, e)))
	return n.normalized() if n.length() > 1e-6 else Vector3.UP


func _ensure_palm_shell(h: UrHand) -> void:
	if not palm_shell.is_empty():
		return
	for x in range(-9, 10):
		for y in range(-6, 4):
			for z in range(-2, 17):
				var p := Vector3(x, y, z) * 0.6
				if absf(h.palm_sdf(p)) < 0.3:
					palm_shell.append(p)


## Where hand h, placed at T with finger capsules cs, is in the tray's wood or leather:
## [[outward normal (world), depth (world)], ...]. With held, the dice it holds count too.
func solid_contacts(T: Transform3D, h: UrHand, cs: Dictionary, held: bool) -> Array:
	var out: Array = []
	# nothing of the hand reaches the tray: done
	if tray_sd(T * Vector3(0.0, -1.0, 6.0)) > 16.0 * CM:
		return out
	_ensure_palm_shell(h)
	var bi := T.basis.inverse()
	for d in cs:
		for cap in cs[d]:
			for u: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var p: Vector3 = (cap[0] as Vector3).lerp(cap[1], u)
				var r: float = lerpf(cap[2], cap[3], u)
				var w := T * p
				var sd := tray_sd(w)
				if sd >= r * CM:
					continue
				var n := tray_n(w)
				# the finger is flattened palm to back: thinner that way
				var yy: float = (bi * n).normalized().dot(cap[4])
				var pen := r * sqrt(maxf(1.0 - float(cap[5]) * yy * yy, 0.0)) * CM - sd
				if pen > 0.0:
					out.append([n, pen])
	for p in palm_shell:
		var w := T * p
		var sd := tray_sd(w)
		if sd < 0.0:
			out.append([tray_n(w), -sd])
	# the bare wrist, up to the sleeve's hem
	var fa: int = h.bones["forearm"]
	var ua: int = h.bones["upperarm"]
	var a := h.skel.get_bone_global_pose(fa).origin
	var ax := (h.skel.get_bone_global_pose(ua).origin - a).normalized()
	for z: float in [0.0, 2.5, 5.0]:
		var w := T * (a + ax * z)
		var sd := tray_sd(w)
		if sd < 2.6 * CM:
			out.append([tray_n(w), 2.6 * CM - sd])
	if held and hand == h:
		for j in 4:
			if mode[j] == TABLE:
				continue
			for s in coarse:
				var w := T * ((pos[j] as Vector3) + (rot[j] as Basis) * s)
				var sd := tray_sd(w)
				if sd < 0.0:
					out.append([tray_n(w), -sd])
	return out


## The smallest move (world) that takes everything in `contacts` out of the tray.
func solve_push(contacts: Array) -> Vector3:
	var d := Vector3.ZERO
	if contacts.is_empty():
		return d
	for it in 6:
		var worst := 0.0
		for c in contacts:
			var v: float = float(c[1]) - (c[0] as Vector3).dot(d)
			if v > 1e-5:
				d += (c[0] as Vector3) * v
				worst = maxf(worst, v)
		if worst < 1e-4:
			break
	return d


## How far hand h, about to be placed at T in its current pose, must move to stay out of
## the tray's floor and rim (world). UrHand calls this every time it is placed.
func hand_push(T: Transform3D, h: UrHand) -> Vector3:
	var cs := h.capsules()
	var d := Vector3.ZERO
	# the surface turns as the hand moves off it (round edges, a corner of floor and
	# rim): look again from where it was pushed to, until nothing is in the wood
	for it in 5:
		var T2 := T
		T2.origin += d
		var step := solve_push(solid_contacts(T2, h, cs, true))
		d += step
		if step.length() < 0.002 * CM:
			break
	return d


# ---------------------------------------------------------------- planning

## Die i in hand-local cm as it would be if the hand had transform T.
func local_under(T: Transform3D, i: int) -> Array:
	var xf: Transform3D = (bodies[i] as Node3D).global_transform
	var hb := T.basis.orthonormalized()
	return [T.affine_inverse() * xf.origin, (hb.inverse() * xf.basis.orthonormalized()).orthonormalized()]


## How badly a hand placed at T, its fingers in `pose`, would run into the dice, the
## floor and the world (world_pen: the rim): 0 when everything is clear. Digits in
## `skip` are left out (their touch is solved separately). i_target is the die about to
## be taken; dice already in the hand ride along and must clear the floor and the dice
## still lying in the tray.
func clash(T: Transform3D, pose: Dictionary, skip: Array, i_target: int) -> float:
	var cs := pose_caps(pose)
	for d in skip:
		cs.erase(d)
	var bad := 0.0
	for j in 4:
		if mode[j] != TABLE:
			continue      # held: rides along in the hand (checked against the tray below)
		var lr := local_under(T, j)
		var dp: Vector3 = lr[0]
		var dr: Basis = lr[1]
		var margin := 0.35 if j == i_target else 0.25
		for d in cs:
			for cap in cs[d]:
				bad += maxf(0.0, cap_vs_die(cap, dp, dr) + margin)
		if hand.palm_sdf(dp) < R + margin:
			for s in samples:
				bad += maxf(0.0, -hand.palm_sdf(dp + dr * s) + margin)
		for h in 4:
			if mode[h] == TABLE:
				continue
			for s in coarse:
				var ev := die_eval(dr.transposed() * ((pos[h] as Vector3) + (rot[h] as Basis) * s - dp))
				bad += maxf(0.0, -ev.w + 0.15)
	# the whole hand, and the dice it holds, clear of the tray's floor and rim
	for c in solid_contacts(T, hand, cs, true):
		bad += float(c[1]) / CM
	return bad


## The finger and thumb capsules the hand would have in `pose` (its pose is left as it is).
func pose_caps(pose: Dictionary) -> Dictionary:
	for d in UrHand.DIGITS:
		for k in 3:
			var i: int = hand.bones["%s_%d" % [d, k]]
			if pose.has(i):
				hand.skel.set_bone_pose_rotation(i, hand.rest_rot[i] * Quaternion(Vector3.RIGHT, deg_to_rad(pose[i].x)) * Quaternion(Vector3.UP, deg_to_rad(pose[i].y)))
	var cs := hand.capsules()
	hand._apply_pose()
	return cs


## How far (world) a hand at T in `pose` must rise to clear the tray's floor (and rim).
func lift_needed(T: Transform3D, pose: Dictionary) -> float:
	var d := solve_push(solid_contacts(T, hand, pose_caps(pose), true))
	return maxf(d.y, 0.0) + Vector2(d.x, d.z).length()
