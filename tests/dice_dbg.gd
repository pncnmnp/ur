extends SceneTree
# Numbers for the dice in the hand: per die mode, offset from its anchor, worst
# penetration into hand / other dice / floor (cm), and finger closures.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	m.game.current = int(OS.get_environment("PLAYER")) if OS.get_environment("PLAYER") != "" else 0
	m.phase = m.Phase.BUSY
	m.do_roll()
	var worst := 0.0
	for k in 170:
		await physics_frame
		await physics_frame
		await physics_frame
		await physics_frame
		var g: DiceGrip = m.grip
		if not g.active():
			continue
		var line := "%.2f " % (k * 4 / 120.0)
		for i in 4:
			var hp := -INF
			for d in g.hand.DIGITS:
				hp = maxf(hp, g.digit_pen(d))
			var mine := -INF
			for d in g.hand.DIGITS:
				for s in 3:
					mine = maxf(mine, g.cap_vs_die(g.hand.capsule(g.hand.bones["%s_%d" % [d, s]]), g.pos[i], g.rot[i]))
			var palm := INF
			for s in g.samples:
				palm = minf(palm, g.hand.palm_sdf(g.pos[i] + g.rot[i] * s))
			var dd := INF
			for j in 4:
				if j == i: continue
				for s in g.samples:
					dd = minf(dd, g.die_eval(g.rot[j].transposed() * (g.pos[i] + g.rot[i] * s - g.pos[j])).w)
			var off: float = (g.pos[i] - g.anchor[i]).length() if g.mode[i] == 2 else 0.0
			line += "| %d fing=%.2f palm=%.2f die=%.2f off=%.1f " % [g.mode[i], mine, -palm, -dd, off]
			if g.mode[i] != 0:
				worst = maxf(worst, maxf(mine, maxf(-palm, -dd)))
		var cl := ""
		for d in g.ctl:
			cl += "%s=%.2f " % [d.left(2), g.ctl[d][2].min()]
		print(line, " ", cl)
	print("worst penetration of a held die (cm): ", worst)
	quit()
