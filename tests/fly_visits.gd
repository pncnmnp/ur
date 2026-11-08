extends SceneTree
# How often flies come round in play (default settings), sped up and headless: over a
# long stretch, with him shooing them as usual, how many visits there are, how long the
# flies are about on each, and how long the quiet between. Checks that they do come, but
# only now and then: the first not before 2 minutes, visits no longer than ~1.5 minutes,
# and at least 5 minutes of quiet between. MINUTES = game minutes to watch (default 40).
func _init() -> void:
	Engine.time_scale = 10.0
	var mins := float(OS.get_environment("MINUTES")) if OS.get_environment("MINUTES") != "" else 40.0
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.epoch += 1
	m.snack_ok = false
	for i in 3:
		m.eat_instantly()
	var fl: Flies = m.flies
	var t0: float = m.fly_clock
	var visits: Array = []        # [start, end, most flies at once]
	var out := false
	while m.fly_clock - t0 < mins * 60.0:
		await process_frame
		var n := 0
		for f in fl.flies:
			if f.state != Flies.AWAY:
				n += 1
		var now: float = m.fly_clock - t0
		if n > 0 and not out:
			visits.append([now, now, n])
		if n > 0:
			visits[-1][1] = now
			visits[-1][2] = maxi(visits[-1][2], n)
		out = n > 0
	var fails := 0
	print("%d visits in %.0f minutes" % [visits.size(), mins])
	for k in visits.size():
		var v: Array = visits[k]
		var gap: float = v[0] - (visits[k - 1][1] if k > 0 else 0.0)
		print("  at %5.0f s: %3.0f s, %d fl%s  (%.0f s of quiet before)" % [v[0], v[1] - v[0], v[2], "y" if v[2] == 1 else "ies", gap])
		if k == 0 and v[0] < 115.0:
			print("FAIL: the first came after only ", v[0], " s")
			fails += 1
		if k > 0 and gap < 290.0:
			print("FAIL: only ", gap, " s of quiet")
			fails += 1
		if v[1] - v[0] > 100.0:
			print("FAIL: a visit lasted ", v[1] - v[0], " s")
			fails += 1
	if visits.size() < 2:
		print("FAIL: hardly any flies at all")
		fails += 1
	print("PASS" if fails == 0 else "FAILED %d" % fails)
	quit()
