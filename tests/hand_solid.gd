extends SceneTree
# Does the throwing hand stay out of the dice tray's solid parts? Many throws, alternating
# hands; every physics frame the whole hand (finger capsules, palm, bare wrist, sleeved
# forearm) is checked against the tray floor and the four rim boards. Prints, per throw,
# the worst penetration (cm) into each and which part and moment it was, and fails if any
# goes deeper than TOL. N = number of throws (default 10), SEED = rng seed.
const TOL := 0.15      # cm: skin may press this far into wood / leather before it shows

var m
var palm_pts := PackedVector3Array()
var trace := false


func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	if OS.get_environment("SEED") != "":
		seed(int(OS.get_environment("SEED")))
	# the palm's surface (hand-local cm), sampled once: it does not change with the pose
	for x in range(-24, 25):
		for y in range(-14, 10):
			for z in range(-6, 30):
				var p := Vector3(x, y, z) * 0.4
				if absf(m.hands[0].palm_sdf(p)) < 0.22:
					palm_pts.append(p)
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 10
	var fails := 0
	trace = OS.get_environment("TRACE") != ""
	var all_floor := 0.0
	var all_rim := 0.0
	for t in n:
		m.game.current = t % 2
		m.phase = m.Phase.BUSY
		m.roll = -1
		m.do_roll()
		var h: UrHand = m.hands[t % 2]
		var wf := [0.0, ""]
		var wr := [0.0, ""]
		var t0 := Time.get_ticks_msec()
		# checked every time the hand is placed (that is what gets drawn: the push out of
		# the tray has just been applied)
		var check := func() -> void:
			if not h.visible:
				return
			var at := (Time.get_ticks_msec() - t0) / 1000.0
			var r := probe(h)
			var phase := "fist" if h.grip_override == UrHand.PALM_C else "held %d" % held_count()
			if trace and h.bump.y < -0.05:
				var T0 := h.global_transform
				T0.origin -= h.bump
				for c in m.grip.solid_contacts(T0, h, h.capsules(), true):
					if (c[0] as Vector3).y < -0.2:
						print("    DOWN n=%s pen=%.3f" % [c[0], c[1]])
				print("    held modes %s" % [m.grip.mode])
			if trace and (r[0] > 0.3 or r[2] > 0.3):
				print("  %.2f %s floor %.2f %s  rim %.2f %s  grip %s pitch %.0f yaw %.0f bump %s" % [at, phase, r[0], r[1], r[2], r[3], h.grip_target, h.aim_pitch, h.aim_yaw, h.bump])
			if r[0] > wf[0]:
				wf[0] = r[0]
				wf[1] = "%s %s @%.2fs" % [r[1], phase, at]
			if r[2] > wr[0]:
				wr[0] = r[2]
				wr[1] = "%s %s @%.2fs" % [r[3], phase, at]
		h.placed.connect(check)
		var waited := 0.0
		while m.roll < 0 and waited < 20.0:
			await physics_frame
			waited += 1.0 / 120.0
		h.placed.disconnect(check)
		var ok: bool = wf[0] <= TOL and wr[0] <= TOL and m.roll >= 0
		if not ok:
			fails += 1
		all_floor = maxf(all_floor, wf[0])
		all_rim = maxf(all_rim, wr[0])
		print("throw %d (%s) roll %d  floor %.2f cm [%s]  rim %.2f cm [%s]  %s" % [t, "human" if t % 2 == 0 else "AI",
			m.roll, wf[0], wf[1], wr[0], wr[1], "ok" if ok else "FAIL"])
		m.epoch += 1
		await create_timer(0.9).timeout
	print("worst floor %.2f cm, worst rim %.2f cm, failures %d / %d" % [all_floor, all_rim, fails, n])
	quit()


func held_count() -> int:
	var k := 0
	for i in 4:
		if m.grip.mode[i] != 0:
			k += 1
	return k


## Signed distance (world) from a world point to the rim boards, and to the floor plane.
func rim_sd(q: Vector3) -> float:
	var l: Vector3 = m.tray_xf().affine_inverse() * q
	var R: Rect2 = m.TRAY
	var c := R.get_center()
	var top := 0.42
	var t := 0.3
	var px := absf(l.x - c.x)
	var pz := absf(l.z - c.y)
	# outer box (with height), minus the inner well (open upward)
	var ob := Vector3(px - (R.size.x / 2 + t), absf(l.y - top / 2) - top / 2, pz - (R.size.y / 2 + t))
	var outer := Vector3(maxf(ob.x, 0), maxf(ob.y, 0), maxf(ob.z, 0)).length() + minf(maxf(ob.x, maxf(ob.y, ob.z)), 0.0)
	var ib := Vector2(px - R.size.x / 2, pz - R.size.y / 2)
	var inner := Vector2(maxf(ib.x, 0), maxf(ib.y, 0)).length() + minf(maxf(ib.x, ib.y), 0.0)
	return maxf(outer, -inner)


## [floor pen cm, part, rim pen cm, part]
func probe(h: UrHand) -> Array:
	var T := h.global_transform
	var fy: float = m.grip.floor_y if m.grip.floor_y < INF else 0.012
	var down_l := (T.basis.inverse() * Vector3.DOWN).normalized()
	var best := [0.0, "", 0.0, ""]
	var test := func(p: Vector3, r_cm: float, part: String) -> void:
		var w := T * p
		var lt: Vector2 = m.tray_local(w)
		if m.TRAY.has_point(lt):
			var f: float = (fy - (w.y - r_cm * UrHand.CM)) / UrHand.CM
			if f > best[0]:
				best[0] = f
				best[1] = part
		var rp: float = (r_cm * UrHand.CM - rim_sd(w)) / UrHand.CM
		if rp > best[2]:
			best[2] = rp
			best[3] = part
	var caps := h.capsules()
	for d in caps:
		var s := 0
		for cap in caps[d]:
			for k in 5:
				var u := k / 4.0
				var p: Vector3 = (cap[0] as Vector3).lerp(cap[1], u)
				var r: float = lerpf(cap[2], cap[3], u)
				# flattened palm to back: thinner toward whichever surface is nearest
				var w := T * p
				var nl: Vector3 = (T.basis.inverse() * (m.grip.tray_n(w) as Vector3)).normalized()
				var yy: float = nl.dot(cap[4])
				test.call(p, r * sqrt(maxf(1.0 - float(cap[5]) * yy * yy, 0.0)), "%s_%d" % [d, s])
			s += 1
	for p in palm_pts:
		test.call(p, 0.0, "palm")
	# forearm: bare wrist then sleeve (radius ~5 cm, cloth hangs a bit lower)
	var fa: int = h.bones["forearm"]
	var ua: int = h.bones["upperarm"]
	var a := h.skel.get_bone_global_pose(fa).origin
	var e := h.skel.get_bone_global_pose(ua).origin
	for k in 13:
		var z := k * 2.0
		var p := a + (e - a).normalized() * z
		if z < 5.5:
			test.call(p, 2.6, "wrist")
		else:
			test.call(p, 5.0 + 0.035 * z, "sleeve")
	return best
