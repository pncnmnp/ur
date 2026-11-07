extends SceneTree
# Many throws in a row, alternating hands: each must finish with a valid roll, all four
# dice back in the tray, and the hand gone. Prints worst in-hand penetration per throw.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 8
	var bad := 0
	for t in n:
		m.game.current = t % 2
		m.phase = m.Phase.BUSY
		m.roll = -1
		var e: int = m.epoch
		m.do_roll()
		var worst := 0.0
		var worst_rel := 0.0
		var waited := 0.0
		while m.roll < 0 and waited < 20.0:
			await physics_frame
			waited += 1.0 / 120.0
			var g: DiceGrip = m.grip
			var releasing: bool = g.active() and g.ctl.is_empty()
			var w0 := worst
			if g.active():
				for i in 4:
					if g.mode[i] == 0:
						continue
					for d in UrHand.DIGITS:
						for s in 3:
							worst = maxf(worst, g.cap_vs_die(g.hand.capsule(g.hand.bones["%s_%d" % [d, s]]), g.pos[i], g.rot[i]))
					for j in 4:
						if j != i:
							for s in g.samples:
								worst = maxf(worst, -g.die_eval(g.rot[j].transposed() * (g.pos[i] + g.rot[i] * s - g.pos[j])).w)
			if releasing and worst > w0:
				worst_rel = maxf(worst_rel, worst)
				worst = w0
		pass
		var inside := 0
		for b in m.dice_bodies:
			var l: Vector2 = m.tray_local(b.global_position)
			if m.TRAY.grow(0.05).has_point(l):
				inside += 1
		var ok: bool = m.roll >= 0 and m.roll <= 4 and inside == 4 and not m.grip.active()
		if not ok:
			bad += 1
		print("throw %d (%s): roll %d  dice in tray %d  worst overlap %.2f cm (at release %.2f)  %s" % [t, "human" if t % 2 == 0 else "AI", m.roll, inside, worst, worst_rel, "ok" if ok else "FAIL"])
		m.epoch += 1   # stop do_roll from going on to a move
		await create_timer(0.9).timeout
	print("failures: ", bad)
	quit()
