extends SceneTree
# The flies round Vidur's dates, sped up (headless is fine): with a few date stones
# already spat out by the bowl and nothing else going on, watch the flies come and go and
# him shoo them. Checks that flies land both in the bowl and on the stones; that he flicks
# a fly off his dates quickly (within ~1.5 s of it sitting) but leaves one on the stones a
# long while (9 s or more); that after any shoo he leaves them be for a while (7 s or more
# before the next); that a fly sitting where his hand passes has gone by the time it
# passes; and that no fly ever goes into the sand or the clay of the bowl.
# SECONDS = game seconds to watch (default 400).
func _init() -> void:
	Engine.time_scale = 5.0
	var secs := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 400.0
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.epoch += 1                  # no game going on
	m.snack_ok = false
	for i in 4:
		m.eat_instantly()
	var fl: Flies = m.flies
	fl.often()                    # (in play they come only now and then)
	var shoos: Array = []         # [time, kind, sat]
	# how long a fly sat before he shooed it, counted from when he was free to (not still
	# letting them be after the last one, his hand not busy): main reports it
	m.shooing.connect(func(kind: String, sat: float) -> void:
		shoos.append([m.fly_clock, kind, sat, sat]))
	var landed := {"date": 0, "rim": 0, "pit": 0}
	var was := []
	for f in fl.flies:
		was.append(f.state)
	var fails := 0
	var low := 0
	var t0: float = m.fly_clock
	var touched := 0
	while m.fly_clock - t0 < secs:
		await process_frame
		for i in fl.flies.size():
			var f: Dictionary = fl.flies[i]
			if f.state == Flies.SIT and was[i] != Flies.SIT:
				landed[f.spot.kind] += 1
			was[i] = f.state
			if f.state != Flies.AWAY:
				var p: Vector3 = f.pos
				if p.y < 0.0:
					low += 1
				if m.bowl.clay_sdf(p) < -0.15:
					low += 1
			# his hand right on a sitting fly: it should have been off long before
			if f.state == Flies.SIT and m.lhand.visible and m.lhand.grip_world().distance_to(f.pos) < 0.35:
				touched += 1
	print("landings ", landed, "  shoos ", shoos.size())
	var bowl_sat: Array = []
	var pit_sat: Array = []
	for s in shoos:
		(pit_sat if s[1] == "pit" else bowl_sat).append(snappedf(s[2], 0.1))
	print("  bowl: sat ", bowl_sat, " s before he flicked")
	print("  pits: sat ", pit_sat, " s before he waved")
	var gaps: Array = []
	for k in range(1, shoos.size()):
		gaps.append(snappedf(shoos[k][0] - shoos[k - 1][0], 0.1))
	print("  gaps between shoos ", gaps)
	if landed.date + landed.rim == 0 or landed.pit == 0:
		print("FAIL: flies never landed in the bowl or never on the stones")
		fails += 1
	if bowl_sat.is_empty() or pit_sat.is_empty():
		print("FAIL: he never shooed one off the bowl, or never off the stones")
		fails += 1
	for s in bowl_sat:
		if s > 1.6 or s < 0.4:
			print("FAIL: he flicked a fly off his dates after ", s, " s")
			fails += 1
	for s in pit_sat:
		if s < 9.0:
			print("FAIL: he waved at a fly on the stones after only ", s, " s")
			fails += 1
	for g in gaps:
		if g < 7.0:
			print("FAIL: shooed again only ", g, " s after the last")
			fails += 1
	if low > 0:
		print("FAIL: a fly went into the sand or the clay (", low, " frames)")
		fails += 1
	if touched > 0:
		print("FAIL: his hand reached a fly still sitting (", touched, " frames)")
		fails += 1
	print("PASS" if fails == 0 else "FAILED %d" % fails)
	quit()
