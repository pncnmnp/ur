extends SceneTree
# Al-Khasm's bowl as solid things (headless is fine). The dates settle at the start without
# flying about; then he eats EAT dates (default 6), one after another (stones and all),
# and every physics step checks: no part of his hand or sleeve inside the clay; no date
# squeezed into the clay or into another more than soft fruit gives under a finger, and
# none at all once they lie still; none fallen out of the bowl. Also prints how far the
# dates left behind move each time (the fingers nudge them, they slump into the gap).
# PLAN_LOG=1 prints each reach he chose.
func _init() -> void:
	var n_eat := int(OS.get_environment("EAT")) if OS.get_environment("EAT") != "" else 6
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.snack_ok = false
	m.epoch += 1
	m.chew = Vector2(0.3, 0.3)       # (no need to wait for him to chew)
	var bowl: DateBowl = m.bowl
	var fails := 0
	for d in bowl.dates:
		(d.node as RigidBody3D).contact_monitor = true
		(d.node as RigidBody3D).max_contacts_reported = 8
	# settling
	var start := {}
	for d in bowl.dates:
		start[d.node] = d.node.global_position
	for i in 240:
		await physics_frame
	var settle := 0.0
	for d in bowl.dates:
		settle = maxf(settle, (d.node.global_position - start[d.node]).length() / DateBowl.CM)
	print("settling: the most any date moved %.2f cm" % settle)
	if settle > 1.5:
		print("FAIL: the heap moved too much as it settled")
		fails += 1
	var worst_hand := 1e9
	var clay_what := ""
	var pair_what := ""
	var worst_what := ""
	var worst_clay := 1e9
	var worst_pair := 0.0
	var fell := 0
	for k in n_eat:
		var before := {}
		for d in bowl.dates:
			before[d.node] = d.node.global_position
		m.eat_date()
		var fast := 0.0
		var fast_at := ""
		var t0 := Time.get_ticks_msec()
		while m.eating:
			await process_frame       # (what is drawn)
			for d in bowl.dates:
				var v: float = (d.node as RigidBody3D).linear_velocity.length()
				if v > fast:
					fast = v
					fast_at = "%d ms in, hand %s" % [Time.get_ticks_msec() - t0, "out" if m.lhand.visible else "hidden"]
			if m.lhand.visible:
				var hb := bowl.hand_balls(m.lhand.global_transform, m.lhand)
				for i in hb.size():
					var cl := bowl.clay_sdf(hb[i][0]) - float(hb[i][1])
					if cl < worst_hand:
						worst_hand = cl
						var q: Vector3 = bowl.global_transform.affine_inverse() * (hb[i][0] as Vector3) / DateBowl.CM
						worst_what = "ball %d at r=%.1f y=%.1f, %d ms into date %d; solid %s, bump %.2f cm, push now %.2f cm, grip y %.2f" % [i, Vector2(q.x, q.z).length(), q.y, Time.get_ticks_msec() - t0, k + 1,
							m.lhand.solid.is_valid(), m.lhand.bump.length() / DateBowl.CM, bowl.hand_push(m.lhand.global_transform, m.lhand).length() / DateBowl.CM, m.lhand.grip_target.y / DateBowl.CM]
			for d in bowl.dates:
				var lw: Array = bowl.live(d)
				var mine: Array = bowl._balls(lw[0], lw[1], d.sph)
				for b in mine:
					var cl: float = bowl.clay_sdf(bowl.global_transform * (b[0] * DateBowl.CM)) / DateBowl.CM - float(b[1])
					if cl < worst_clay:
						worst_clay = cl
						var bq: Vector3 = b[0]
						var bw: Vector3 = bowl.global_transform * (bq * DateBowl.CM)
						var near := ""
						for o in (d.node as RigidBody3D).get_colliding_bodies():
							var tag := "bowl" if o is StaticBody3D else ("date" if o is RigidBody3D else "?")
							for e in bowl.hand_bodies:
								if e[0] == o:
									tag = "%s%d" % [e[1], e[2]]
							near += " " + tag
						near += "; speed %.2f, frozen %s" % [(d.node as RigidBody3D).linear_velocity.length(), (d.node as RigidBody3D).freeze]
						clay_what = "%d ms into date %d, hand %s, at r=%.1f y=%.1f; touching:%s" % [Time.get_ticks_msec() - t0, k + 1, "out" if m.lhand.visible else "hidden", Vector2(bq.x, bq.z).length(), bq.y, near]
				for e in bowl.dates:
					if e == d:
						continue
					var le: Array = bowl.live(e)
					for b in mine:
						for q in bowl._balls(le[0], le[1], e.sph):
							var pp: float = float(b[1]) + float(q[1]) - (b[0] as Vector3).distance_to(q[0])
							if pp > worst_pair:
								worst_pair = pp
								pair_what = "%d ms into date %d, hand %s" % [Time.get_ticks_msec() - t0, k + 1, "out" if m.lhand.visible else "hidden"]
		while m.left_busy:
			await physics_frame
		for i in 60:
			await physics_frame
		var moved := 0.0
		for d in bowl.dates:
			if before.has(d.node):
				moved = maxf(moved, (d.node.global_position - before[d.node]).length() / DateBowl.CM)
			if bowl.live(d)[0].y < -0.5:
				fell += 1
		print("date %d: %d left, the most another moved %.2f cm; fastest %.2f u/s (%s)" % [k + 1, bowl.remaining(), moved, fast, fast_at])
		while m.left_busy:          # the stone goes down beside the bowl
			await physics_frame
		m.last_eat = -100.0
	print("hand vs clay: closest %.2f cm (%s; balls: 5 per digit index,middle,ring,pinky,thumb x6, palm 30-38, wrist/sleeve 39-42)" % [worst_hand / DateBowl.CM, worst_what])
	print("dates vs clay: deepest %.2f cm (%s)" % [-worst_clay, clay_what])
	print("date vs date: deepest %.2f cm (%s)" % [worst_pair, pair_what])
	# and where they come to rest
	var rest_clay := 1e9
	var rest_pair := 0.0
	for d in bowl.dates:
		var lw: Array = bowl.live(d)
		var mine: Array = bowl._balls(lw[0], lw[1], d.sph)
		for b in mine:
			rest_clay = minf(rest_clay, bowl.clay_sdf(bowl.global_transform * (b[0] * DateBowl.CM)) / DateBowl.CM - float(b[1]))
		for e in bowl.dates:
			if e != d:
				var le: Array = bowl.live(e)
				for b in mine:
					for q in bowl._balls(le[0], le[1], e.sph):
						rest_pair = maxf(rest_pair, float(b[1]) + float(q[1]) - (b[0] as Vector3).distance_to(q[0]))
	print("at rest: deepest into the clay %.2f cm, into each other %.2f cm" % [-rest_clay, rest_pair])
	if worst_hand < -0.15 * DateBowl.CM:
		print("FAIL: the hand went into the clay")
		fails += 1
	if worst_clay < -1.0:
		print("FAIL: a date was squeezed into the clay")
		fails += 1
	if worst_pair > 1.0:
		print("FAIL: dates were squeezed into each other")
		fails += 1
	if rest_clay < -0.15 or rest_pair > 0.15:
		print("FAIL: dates lie in the clay or in each other")
		fails += 1
	if fell > 0:
		print("FAIL: dates fell out")
		fails += 1
	print("PASS" if fails == 0 else "FAILED %d" % fails)
	quit()
